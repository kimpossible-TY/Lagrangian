#!/usr/bin/env python3
"""Stage/verify portable native delivery. Never installs or controls user services."""
from __future__ import annotations
import argparse
import base64
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'delivery-manifest.json'
RUNTIME_POLICY = Path('tools/flow-reader/native/runtime')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode()


def read(path):
    return json.loads(Path(path).read_text())


def write(path, value):
    Path(path).write_bytes(encoded(value))


def require(ok, diagnostic):
    if not ok:
        raise ValueError(diagnostic)


def run(argv, **kwargs):
    started = time.monotonic()
    result = subprocess.run(list(map(str, argv)), capture_output=True, text=True, timeout=120, **kwargs)
    if log := os.environ.get('NATIVE_DELIVERY_EVIDENCE'):
        with Path(log).open('a') as f:
            f.write(json.dumps({'argv': list(map(str, argv)), 'cwd': str(kwargs.get('cwd', Path.cwd())),
                'exit': result.returncode, 'seconds': time.monotonic() - started,
                'stdout': result.stdout, 'stderr': result.stderr}) + '\n')
    require(result.returncode == 0, 'command failed: ' + str(argv[0]) + ': ' + result.stderr[-2000:])
    return result.stdout


def relative(name):
    require(isinstance(name, str) and name and '\\' not in name and '\x00' not in name and
            not name.startswith('/') and all(x not in ('', '.', '..') for x in name.split('/')), 'unsafe relative path')
    return name


def inventory(root, *, excluded=()):
    root = Path(root).absolute()
    result = []
    for p in sorted(root.rglob('*')):
        rel = relative(p.relative_to(root).as_posix())
        if rel.split('/')[0] in excluded:
            continue
        if p.is_symlink():
            target = os.readlink(p)
            require(not Path(target).is_absolute() and p.resolve().is_relative_to(root) and p.exists(), 'escaping or missing symlink: ' + rel)
            result.append({'path': rel, 'link': target, 'sha256': hashlib.sha256(os.fsencode(target)).hexdigest()})
        elif p.is_file():
            result.append({'path': rel, 'bytes': p.stat().st_size, 'mode': p.stat().st_mode & 0o777, 'sha256': sha(p)})
        else:
            require(p.is_dir(), 'non-regular payload: ' + rel)
    return result


def payload_files(root):
    return [f for f in inventory(root) if f['path'] != MANIFEST]


def macho(p):
    if p.is_symlink() or not p.is_file():
        return False
    with p.open('rb') as f:
        return f.read(4) in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf')


def system_library(name):
    return name.startswith(('/usr/lib/', '/System/Library/'))


def image_info(image, root):
    """Check every arm64 load/rpath, including libraries not loaded by the smoke probe."""
    loads = run(['/usr/bin/otool', '-arch', 'arm64', '-l', image])
    deps = [s.strip().split(' (compatibility')[0] for s in run(['/usr/bin/otool', '-arch', 'arm64', '-L', image]).splitlines()[1:] if s.strip()]
    minimum = re.search(r'\bminos (\d+(?:\.\d+)+)', loads) or re.search(r'\bversion (\d+(?:\.\d+)+)', loads)
    require(minimum is not None, 'missing deployment target: ' + str(image))
    require(tuple(map(int, minimum[1].split('.'))) <= (13, 0, 0), 'macOS target exceeds 13: ' + str(image))
    rpaths = re.findall(r'\bpath (.+) \(offset \d+\)', loads)
    def expand(s):
        return Path(s.replace('@loader_path', str(image.parent)))
    for rpath in rpaths:
        require(system_library(rpath) or (rpath.startswith('@loader_path') and expand(rpath).resolve().is_relative_to(root)), 'external rpath: ' + rpath)
    resolved = []
    for dep in deps:
        if system_library(dep):
            continue
        if dep.startswith('@loader_path/'):
            candidate = expand(dep)
        elif dep.startswith('@rpath/'):
            choices = [expand(r) / dep[7:] for r in rpaths]
            candidate = next((p for p in choices if p.is_file()), None)
        else:
            candidate = None
        require(candidate is not None and candidate.is_file() and candidate.resolve().is_relative_to(root), 'external/missing dylib: ' + dep)
        resolved.append(candidate.resolve().relative_to(root).as_posix())
    return {'path': image.relative_to(root).as_posix(), 'sha256': sha(image), 'minOS': minimum[1], 'dependencies': deps, 'resolved': resolved, 'rpaths': rpaths}


def sign_images(root, identity):
    images = [p for p in sorted(root.rglob('*')) if macho(p)]
    python_library = root / 'python/Python'
    for p in images:
        if p == python_library:
            continue
        if p.relative_to(root).parts[0] == 'runtime':
            run(['/usr/bin/codesign', '--verify', '--strict', p])
        else:
            run(['/usr/bin/codesign', '--force', '--sign', identity, p])
    # Seal actual nested bundles after their internal executables/libraries.
    bundles = sorted([p for p in root.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ('.app', '.framework')], key=lambda p: len(p.parts), reverse=True)
    for p in bundles:
        run(['/usr/bin/codesign', '--force', '--sign', identity, p])
    if python_library.exists():
        run(['/usr/bin/codesign', '--force', '--sign', identity, python_library])
    return [image_info(p, root) for p in images]


def relocate_python(root):
    original = '/Library/Frameworks/Python.framework/Versions/3.13/'
    for image in sorted(root.rglob('*')):
        if not macho(image):
            continue
        deps = run(['/usr/bin/otool', '-L', image])
        for dep in dict.fromkeys(re.findall(r'^\s+(/Library/Frameworks/Python\.framework/Versions/3\.13/.*?) \(compatibility', deps, re.M)):
            target = root / dep[len(original):]
            require(target.is_file(), 'Python framework closure missing: ' + dep)
            replacement = '@loader_path/' + os.path.relpath(target, image.parent)
            run(['/usr/bin/install_name_tool', '-change', dep, replacement, image])
        # A dylib's ID is also listed by otool -L. Give it a relocatable ID.
        ids = run(['/usr/bin/otool', '-D', image]).splitlines()
        if any(line.startswith(original) for line in ids):
            run(['/usr/bin/install_name_tool', '-id', '@loader_path/' + image.name, image])


def source_binding(root):
    sources = read(root / 'apps/macos/sources.json')
    paths = ['apps/macos/sources.json', 'scripts/flow-app.py', 'scripts/native_delivery_consumer.py', 'scripts/native_delivery_artifact.py', 'scripts/reader_bundle.py', 'scripts/stage-native-reader-delivery.py', 'scripts/verify-native-reader-app.py',
             'scripts/prepare-native-reader-runtime.mjs', 'assets/branding/lagrangian.png', 'docs/tinymist/flow-app.typ',
             *[str(RUNTIME_POLICY / n) for n in ['node-distribution.json', 'backend-delivery.json', 'package.json', 'package-lock.json', 'THIRD-PARTY-NOTICES.md']],
             *['apps/macos/' + n for section in ('core', 'native', 'app') for n in sources[section]]]
    return {name: sha(root / name) for name in sorted(paths)}


# Exact delivery-owned paths; extending this list requires an owner-reviewed edit.
# No native source/test/doc prefix is delegated to HEAD.
DELIVERY_SOURCE_PATHS = (
    '.github/workflows/flow-engine.yml',
    'AGENTS.md',
    'apps/macos/sources.json',
    'docs/dev-guide.md',
    'docs/tinymist/dev/development.typ',
    'docs/tinymist/dev/native-reader-delivery.typ',
    'docs/tinymist/flow-app.md',
    'docs/tinymist/flow-app.typ',
    'openspec/changes/deliver-native-reader-app/design.md',
    'openspec/changes/deliver-native-reader-app/proposal.md',
    'openspec/changes/deliver-native-reader-app/specs/flow-macos-app/spec.md',
    'openspec/changes/deliver-native-reader-app/specs/native-reader-delivery/spec.md',
    'openspec/changes/deliver-native-reader-app/specs/reader-bundle/spec.md',
    'openspec/changes/deliver-native-reader-app/tasks.md',
    'scripts/flow-app.py',
    'scripts/native_delivery_artifact.py',
    'scripts/native_delivery_consumer.py',
    'scripts/reader_bundle.py',
    'scripts/reuse-engine-artifact.py',
    'scripts/stage-native-reader-delivery.py',
    'tests/flow-app/test_bundle.py',
    'tests/flow-app/test_engine_artifact_cache.py',
    'tests/flow-app/test_native_delivery_artifact.py',
    'tests/flow-app/test_native_delivery_consumer.py',
    'tests/flow-app/test_native_source_binding.py',
    'tests/flow-app/test_reader_bundle.py',
    'tools/flow-reader/native/runtime/backend-delivery.json',
)

# NA20 integrates only these fixed reviewed source bytes; future edits still fail closed.
FIXED_APPLICATION_SOURCES = {'baseRevision': '72bd0b385d8d71ef4ad7f30d5067e9171493bc05',
 'revision': '4bd6e0da0d529dafa9993ff8467cac4652bfa2ac',
 'files': [{'path': 'apps/macos/CommandRunner.swift',
            'baseSHA256': '719cbc91ca3bc189cabec569ce4ff2bdf5ff3bdde4f14565c35f2c75886bc911',
            'sha256': '217a33f7d894c397c28b02e98a52262ed893626cf3eff4f16f750fe9f5411dca'},
           {'path': 'apps/macos/FlowApp.swift',
            'baseSHA256': '5e0ac86c3f68cdab67983188b23677218a92aed93e1960951f2d9077b4a6c102',
            'sha256': 'da4e4fee8b831d87a8859b69226e374e777ef5612658e24850bf20516be3a775'},
           {'path': 'apps/macos/NativeAppDesign.swift',
            'baseSHA256': None,
            'sha256': '3ab00cd1ef9341c43aebc1218863ed83e687fb0d99070cad3d11c6b2c4b41f5d'},
           {'path': 'apps/macos/NativeBrandMark.swift',
            'baseSHA256': None,
            'sha256': 'd1b3931963a73866f0880bc8dd9410929f950816ee93255d305c8513f627ffee'},
           {'path': 'apps/macos/NativeFloatingCapsule.swift',
            'baseSHA256': None,
            'sha256': '55533a0a600a5eb1c39f664f17300556b86fb1ad4ace2e821304f758ecd1cefb'},
           {'path': 'apps/macos/NativeReaderChatView.swift',
            'baseSHA256': 'f149260d01d094e7cd1c56abee2aeb169d2ef4c3d64ef5802beec5b36b49d31d',
            'sha256': 'f986905413cd43fb1c5a46a43272b5bf535b5fd8406971ab9da80c74db448561'},
           {'path': 'apps/macos/NativeReaderTextView.swift',
            'baseSHA256': 'e29e2e7a467b93cadabd1be53f3c2948dc88481cded68d9ad7fc0fc411eff8ed',
            'sha256': '9b9c53929d36f3259ed4f585f316c9e3be37ad052039a35c76045ca3488aa8d3'},
           {'path': 'apps/macos/NativeReaderTransport.swift',
            'baseSHA256': '28d2d7273fc1e64ff2b67ec593c9cdfd4cdbfabb1106374283eb7584ab6d9e9c',
            'sha256': 'e5f047781253c5ca7fdfcf67b690942f31f33523fee41077299df2e0790c69ab'},
           {'path': 'apps/macos/NativeReaderWindowController.swift',
            'baseSHA256': '34c1a4c00b444d6d4e1565fdb201e9c890df6cb08c96de1df882e4e765c7e139',
            'sha256': '11391d5bf7a4f29fa33e7a02f1e58808d128f99a8ce2816e07ec5f9b8cf48e9c'},
           {'path': 'docs/tinymist/dev/native-cream-design.typ',
            'baseSHA256': None,
            'sha256': 'a7e68a2fd8d4fae3fc7d483394506bf22a2e5aad73184f65e6dc7837b41ccb47'},
           {'path': 'docs/tinymist/dev/native-reader-app-contract.typ',
            'baseSHA256': 'd40f13f03f14c72454d91d8b158a0f99ff77bd15bf2c0a710b2382e72dd51355',
            'sha256': 'e3bf11756f353b2d6c8c4cfc8d8290daac1d4180ad7d8f3c6d3e2920bb90287b'},
           {'path': 'docs/tinymist/dev/native-reader-editor-actions.typ',
            'baseSHA256': '225b783a04c32b7e51be7164e2cc85c60b1f829748a350ba7c159bf5fb2303a3',
            'sha256': 'fc433a1b4c4112543990f0d376913eb96a40dc044d248b27eab2740cc6c7e12d'},
           {'path': 'docs/tinymist/dev/reader-architecture.typ',
            'baseSHA256': '16b9aafd54bb499935de6ececc4c7d9e6b69aeb793b176c228c5a7982296b5ea',
            'sha256': '08bfa63635709e67abd20fb7e8aacbfdc549d7da1d9fc43db1fe32cf67fea4ac'},
           {'path': 'openspec/changes/implement-native-reader-app/design.md',
            'baseSHA256': '6a40be085bf1f54d002b19e4906e01ddd6d331e2eca4915a979d8019659eed94',
            'sha256': '151aabcc0d7fe48db9818fc683d3b1338b7b5dc43ce8dcf2b640f000dca7acf8'},
           {'path': 'openspec/changes/implement-native-reader-app/specs/flow-macos-app/spec.md',
            'baseSHA256': 'f1eb7c23afcab32395f3c0319bffec77d3404c8a3d034c5426892c0860de2197',
            'sha256': 'f0b0a74391605c0fe622e5566164d5a0bd7d9b632f08b8e66f56ffa87ad796fe'},
           {'path': 'openspec/changes/implement-native-reader-app/specs/native-reader/spec.md',
            'baseSHA256': '3ba36189a925d438e2f25bef5c674a683b1c8de55d81334e02c7445ccfd3cde3',
            'sha256': '4b72dcbcf84a076ef94dcf60dff66fc91015d094f9259a3cdd8422c821bc8a2e'},
           {'path': 'openspec/changes/implement-native-reader-app/tasks.md',
            'baseSHA256': '8b2532af989ce599a57ae06b2f0220750dd2d484130e2c4947ba89b03a74f064',
            'sha256': '73dddfd8eca306ca7887affbf99f74677e975ade8c2fe35e2b0e7e37c7f2e17a'},
           {'path': 'openspec/changes/refine-native-cream-design/.openspec.yaml',
            'baseSHA256': None,
            'sha256': '277c3c07d7ab9927f15fff0d9c08afbbb9cc808d563ada95016a72a464a761e0'},
           {'path': 'openspec/changes/refine-native-cream-design/design.md',
            'baseSHA256': None,
            'sha256': 'e5214ca0029e9c63129c3633b4ddfd6983da1f202b296096fa17503f35930af3'},
           {'path': 'openspec/changes/refine-native-cream-design/proposal.md',
            'baseSHA256': None,
            'sha256': '2fd739e81e98f4672bd6a908c77bea09b8e3fe4d54d03d587c72a2b45988d0b1'},
           {'path': 'openspec/changes/refine-native-cream-design/specs/flow-macos-app/spec.md',
            'baseSHA256': None,
            'sha256': '53fae5e8b0864b1ab235c0921bfed4883a0fb9898d0363d066c1a2cb94699546'},
           {'path': 'openspec/changes/refine-native-cream-design/specs/native-reader/spec.md',
            'baseSHA256': None,
            'sha256': 'eb09b61a71f080850d4e54c40df43307d83a94a5916a6c33285af546becd6279'},
           {'path': 'openspec/changes/refine-native-cream-design/tasks.md',
            'baseSHA256': None,
            'sha256': '6d927e158abab7083e0338658f7b5917b3806a2849428df317eff4d2ec1d4e83'},
           {'path': 'tests/flow-app/native-reader-app/NativeCreamDesignTests.swift',
            'baseSHA256': None,
            'sha256': '91e3e315541fe2dfbd5c0e6edb634daecc325fc7e5a021ff5127bbe4cf895231'},
           {'path': 'tests/flow-app/native-reader-app/NativeEditorActionTests.swift',
            'baseSHA256': '241094b3c76214a28d4352108ae690d3de320b46e379cbe2fd8cf173f567ad09',
            'sha256': 'b3f0840ca7cbe282f128fd62517c4c929cf07d957eedc54efd1ffa8adcca0723'},
           {'path': 'tests/flow-app/native-reader-app/NativeFloatingCapsuleTests.swift',
            'baseSHA256': None,
            'sha256': '5d6132a90eacdece221fbc85964ee61ec8b08c963d17ff15437e04d3bd440a10'},
           {'path': 'tests/flow-app/native-reader-app/NativeReaderUIRefinementTests.swift',
            'baseSHA256': None,
            'sha256': 'e75599b1d030cfee87e7ee9c569b50fcdc61df3896f5e6cf45fdf03de6a80f41'},
           {'path': 'tests/flow-app/native-reader-app/OriginalPageTests.swift',
            'baseSHA256': 'acca0f73f907bf8144e27c292285f2532fe5ce8ff60868a0f26560a6b0ba90c9',
            'sha256': '665bd614c9efc2e3256f2719e03e8a11e91aeb215315e3fb996adfaa12009388'},
           {'path': 'tests/flow-app/native-reader-app/test_app_integration.py',
            'baseSHA256': '479a4e7f487b3b9be3c05ad8fd822970f30ebce97fafb77adc252e9ea9438735',
            'sha256': 'd6de3c6e030ea42314ce0b22dbc34561ca5c25b0fc2a769483ceb404d396f7c3'},
           {'path': 'tests/flow-app/native-reader-app/test_native_cream_design.py',
            'baseSHA256': None,
            'sha256': 'efe0d5bfc97f91404c9329dc5b3dfd66ecebbc0331146069ecf6e323b1f1f6c3'},
           {'path': 'tests/flow-app/native-reader-app/test_native_editor_actions.py',
            'baseSHA256': '2e838a5d31acc2ac26ad63a28e7cd1a78537eaab2c08b8eb6473f9582a773810',
            'sha256': '91cf77053e1ab595b38db6c529ba80bfe2c9b2c8f0c2b0ef5fbddcb47616f463'},
           {'path': 'tests/flow-app/native-reader-app/test_native_floating_capsule.py',
            'baseSHA256': None,
            'sha256': '200216dc613f048ef3591d30582057ff03d3ca83b89bddadb691d4b2656df24a'},
           {'path': 'tests/flow-app/native-reader-app/test_native_ui_refinement.py',
            'baseSHA256': None,
            'sha256': '09dae6f45000e2e567560a40d6519ef1c74cb103f5847d960d37dc4353b36ead'},
           {'path': 'tests/flow-app/native-reader-app/test_original_pages.py',
            'baseSHA256': '876339f49b2b316bf53e8387de75a2d97d4358afadb0114ba5dea03ef29e2140',
            'sha256': 'f67d975a6f785cd5f8e527b90711ddcaa0810dfb332bf5c1cf34f7869991c927'},
           {'path': 'tools/flow-reader/flow_reader/services/editor_sync.py',
            'baseSHA256': '3e3d122cb0bd4fffd6cbe5114134816115ac15442c5ef98ac1f2fad6e7affe7f',
            'sha256': 'c37814499be02a196347e20edc6a1bf2a77848f624b7e3a29b1b45db8b2062e6'},
           {'path': 'tools/flow-reader/flow_reader/services/manager.py',
            'baseSHA256': '7c230bdaed78dbe2ae98d178325f824f22f1b2275c28b61882b444ae1f3c25b6',
            'sha256': 'e7eed01246d329dcfb0af24d20aad9d36e10113d9f0527ff64d9b49318ac007c'},
           {'path': 'tools/flow-reader/tests/test_native_editor_dispatch.py',
            'baseSHA256': 'b66899520e7b9981049dff9e77c65976a6846dc57029c131d521bce9022783fd',
            'sha256': '28d4b9e57e858fbc687ebabbcd3bb04a77d99c8e414e39917b3556b1c2b9f16c'},
           {'path': 'tools/flow-reader/tests/test_native_manager_identity.py',
            'baseSHA256': None,
            'sha256': 'eea1f8198566b566de4391bac3552de433107a6b56b1c1d1d528f57fddde958a'}]}

# Byte-preserving reuse: the original producer revision and manifest remain intact.
RETAINED_RUNTIME_MANIFEST = 'aa824a56c4d310a9977cdcc1f7a65dd718b92fcba46605347cad20dd431623fc'
RETAINED_RUNTIME_SOURCE = {'sourceSHA': 'd7cd069f2249a405061bf220cfd7e0184f75c7fe',
 'dirty': '',
 'sourceFiles': [{'path': 'scripts/prepare-native-reader-runtime.mjs',
                  'sha256': '2f7c0220ef0a23c79b3b8d1dd657914e6bf8cb3ff87ba9befcf0994f6c272ee6'},
                 {'path': 'tools/flow-reader/native/runtime/package.json',
                  'sha256': 'a56a3b0df96e9310a679aa59f2617f4b9c790903c992474891cb525322e2d3f7'},
                 {'path': 'tools/flow-reader/native/runtime/package-lock.json',
                  'sha256': '11e30c2d0c3fd1f1d722042b28b0648f0d37d45850a9e4a3925d9d0c75a6b828'},
                 {'path': 'tools/flow-reader/native/runtime/THIRD-PARTY-NOTICES.md',
                  'sha256': '825f737592cda4aa3579d4a9d3abe1cf66da95cd8caa4a3d65f3524530bd1c75'},
                 {'path': 'tests/flow-app/native-reader-app/test_runtime.py',
                  'sha256': 'f01bc89317fd17b45594465f12c49d41980b6ad48cdacee4af43e8520a083ed2'},
                 {'path': 'tests/flow-app/native-reader-app/RuntimeTests.mjs',
                  'sha256': '6ac7fd74cd18803cb72594abaea115f6052e5a82fae2e331d7e6a3c7b5ff2ef3'},
                 {'path': 'docs/tinymist/dev/native-reader-runtime.typ',
                  'sha256': 'a8c09043dc587f5e071d1360a5416397f84cd766a1696c7355a2bd6e9f6c1f26'}],
 'baseline': 'cc790bc1778dd7560984eafca93f0d6c052805d4'}


def runtime_source_binding(manifest, manifest_sha, revision, repo=None):
    source = manifest['source']
    require(not source['dirty'], 'dirty runtime source')
    if source['sourceSHA'] == revision:
        return
    require(manifest_sha == RETAINED_RUNTIME_MANIFEST and source == RETAINED_RUNTIME_SOURCE,
            'stale runtime sourceRevision: unregistered retained runtime')
    if repo is not None:
        run(['git', '-C', repo, 'merge-base', '--is-ancestor', source['sourceSHA'], revision])
        require(sha(repo / 'tools/flow-reader/native/runtime/node-distribution.json') == manifest['node']['distributionSHA256'],
                'retained runtime node distribution drift')
        for item in source['sourceFiles']:
            require(sha(repo / relative(item['path'])) == item['sha256'], 'retained runtime producer input drift')
        require(sha(repo / RUNTIME_POLICY / 'node-distribution.json') == manifest['node']['distributionSHA256'],
                'retained runtime distribution drift')
        require(sha(repo / 'tools/flow-reader/native/math_layout.mjs') == manifest['helperSHA256'],
                'retained runtime helper drift')


def runtime_signing_policy(manifest, revision, identity):
    require(identity == '-' or manifest['source']['sourceSHA'] == revision,
            'retained runtime requires ad-hoc development; certificate signing requires a current-source runtime')


def bundle_runtime_policy(manifest, revision, identity, *, development=False):
    """Bundle consumer decision; staging alone does not grant production use."""
    runtime_signing_policy(manifest, revision, identity)
    require(manifest['source']['sourceSHA'] == revision or (development and identity == '-'),
            'production bundle requires a current-source runtime; retained runtime is development-only')


def integrated_sources(root):
    """Bind historical owners, explicit fixed corrections and current delivery bytes."""
    root = Path(root).resolve(strict=True)
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args])
    def revision(value):
        require(isinstance(value, str) and re.fullmatch('[0-9a-f]{40}', value), 'full fixed source revision required')
        require(git('rev-parse', value + '^{commit}').decode().strip() == value, 'source revision is not a commit')
        return value
    def ancestor(before, after):
        run(['git', '-C', root, 'merge-base', '--is-ancestor', before, after])
    def changed(before, after):
        return set(git('diff', '--no-renames', '--name-only', '-z', before, after).decode().split('\0')) - {''}
    def blob(rev, name, absent=False):
        relative(name)
        require(all(ord(c) >= 32 and ord(c) != 127 for c in name), 'unsafe owner path')
        entry = git('ls-tree', '-z', rev, '--', name).decode().split('\0')
        if absent and entry == ['']:
            return None
        require(len(entry) == 2 and entry[1] == '' and entry[0].split('\t')[-1] == name
                and entry[0].split()[0] in ('100644', '100755'), 'owner source must be one regular tracked file: ' + name)
        return hashlib.sha256(git('show', rev + ':' + name)).hexdigest()
    def current(name, rev):
        path = root / name
        require(path.is_file() and not path.is_symlink() and path.resolve() == path, 'missing/escaping owner source: ' + name)
        digest = blob(rev, name)
        require(sha(path) == digest, 'integrated owner source drift: ' + name)
        return digest

    head = revision(git('rev-parse', 'HEAD').decode().strip())
    require(not git('status', '--porcelain', '--untracked-files=all').strip(), 'integrated source requires a clean checkout')
    metadata = read(root / RUNTIME_POLICY / 'backend-delivery.json')
    capabilities = metadata['capabilities']
    core, pages = revision(capabilities['coreSource']), revision(capabilities['originalPagesSource'])
    gui, published = revision(capabilities['guiPreparationSource']), revision(capabilities['publishedReaderSource'])
    base = '9b2dc87651eb16a809bb48dbe4539614cfe30d6a'
    baseline = '09c5186bff1850b17f6e85fe2f3115153520bc94'
    for before, after in [(base, core), (core, pages), (pages, baseline), (gui, baseline),
                          (published, baseline), (baseline, head)]:
        ancestor(before, after)
    history, originals, revisions = [], {}, {}
    for role, before, rev in [('core', base, core), ('pages', core, pages),
                             ('gui', gui + '^', gui),
                             ('published', '5d71618e7ee320edbe759511fe634024fc8104a6', published)]:
        files = {name:blob(rev, name) for name in sorted(changed(before, rev))}
        history.append({'role':role, 'revision':rev, 'files':files})
        for name, digest in files.items():
            originals.setdefault(name, []).append({'revision':rev, 'sha256':digest})
            revisions[name] = rev

    provenance = metadata.get('sourceProvenance')
    require(isinstance(provenance, dict) and set(provenance) == {'schemaVersion', 'baselineRevision', 'ownerCorrections'}
            and type(provenance['schemaVersion']) is int and provenance['schemaVersion'] == 1
            and provenance['baselineRevision'] == baseline, 'source provenance schema/baseline mismatch')
    corrections = provenance['ownerCorrections']
    require(isinstance(corrections, list) and corrections, 'fixed owner correction inventory missing')
    approved, seen_revisions, corrected_paths = [], set(), set()
    def apply_correction(correction, previous, *, split_delivery=False):
        require(isinstance(correction, dict) and set(correction) == {'revision', 'baseRevision', 'files'}, 'owner correction fields')
        rev, before = revision(correction['revision']), revision(correction['baseRevision'])
        require(rev not in seen_revisions and rev != before, 'duplicate/empty owner correction')
        seen_revisions.add(rev)
        for first, second in [(baseline, before), (before, rev), (rev, head)]: ancestor(first, second)
        ancestor(previous, before)
        files = correction['files']
        require(isinstance(files, list) and files, 'owner correction files missing')
        records, seen_paths = [], set()
        for item in files:
            require(isinstance(item, dict) and set(item) == {'path', 'baseSHA256', 'sha256'}, 'owner correction file fields')
            name = relative(item['path'])
            require(name not in seen_paths and name not in DELIVERY_SOURCE_PATHS, 'duplicate or delivery-owned correction path')
            seen_paths.add(name)
            original, corrected = blob(before, name, absent=True), blob(rev, name)
            require(item['baseSHA256'] == original and item['sha256'] == corrected and original != corrected,
                    'owner correction original/corrected digest mismatch: ' + name)
            records.append({**item, 'overrides':originals.get(name, [])})
            revisions[name] = rev
        # Post-H19 native snapshots exclude only existing delivery-owned paths;
        # those remain separately checked against exact HEAD blobs below.
        expected_paths = changed(before, rev)
        if split_delivery: expected_paths -= set(DELIVERY_SOURCE_PATHS)
        require(seen_paths == expected_paths, 'owner correction exact path inventory mismatch')
        corrected_paths.update(seen_paths)
        approved.append({'revision':rev, 'baseRevision':before, 'files':records})
        return rev

    fixed = FIXED_APPLICATION_SOURCES
    fixed_base, fixed_rev = revision(fixed['baseRevision']), revision(fixed['revision'])
    ancestor(fixed_base, fixed_rev); ancestor(fixed_rev, head)
    original_provenance = json.loads(git('show', fixed_rev + ':' + str(RUNTIME_POLICY / 'backend-delivery.json')))
    original_corrections = original_provenance['sourceProvenance']['ownerCorrections']
    previous = baseline
    for correction in corrections[:len(original_corrections)]:
        previous = apply_correction(correction, previous)
    require(corrections[:len(original_corrections)] == original_corrections,
            'unregistered source changes / owner source drift in historical correction chain')
    ancestor(previous, fixed_base)
    require({f['path'] for f in fixed['files']} == changed(fixed_base, fixed_rev) - set(DELIVERY_SOURCE_PATHS),
            'fixed application exact path inventory mismatch')
    for item in fixed['files']:
        name = relative(item['path'])
        require(item['baseSHA256'] == blob(fixed_base, name, absent=True)
                and item['sha256'] == blob(fixed_rev, name), 'fixed application source digest mismatch')
        revisions[name] = fixed_rev
        corrected_paths.add(name)

    previous = fixed_rev
    for correction in corrections[len(original_corrections):]:
        previous = apply_correction(correction, previous, split_delivery=True)

    # Current delivery edits are bounded by exact owner paths, never a prefix.
    require(not (changed(baseline, head) - corrected_paths - set(DELIVERY_SOURCE_PATHS)),
            'unregistered source changes require a fixed owner correction inventory')
    for name in DELIVERY_SOURCE_PATHS:
        revisions[name] = head
    records = {name:current(name, rev) for name, rev in sorted(revisions.items())}
    require(head == git('rev-parse', 'HEAD').decode().strip()
            and not git('status', '--porcelain', '--untracked-files=all').strip(), 'source changed during owner binding')
    return {'coreRevision':core, 'pageRevision':pages, 'guiRevision':gui,
            'publishedReaderRevision':published, 'historicalBaseRevision':base,
            'correctionBaselineRevision':baseline, 'historicalSources':history,
            'ownerCorrections':approved, 'fixedApplicationSources':fixed,
            'deliveryOwnedOverrides':list(DELIVERY_SOURCE_PATHS),
            'files':records}


def verify(root, expected=None, signatures=True):
    root = Path(root).absolute()
    require(root.resolve() == root and not root.is_symlink(), 'delivery root must be canonical')
    m = read(root / MANIFEST)
    require(m.get('schema') == 1 and re.fullmatch('[0-9a-f]{40}', m.get('sourceRevision', '')), 'delivery schema/sourceRevision')
    files = payload_files(root)
    require(files == m['files'], 'delivery inventory mismatch/tamper/missing')
    require(hashlib.sha256(encoded(files)).hexdigest() == m['payloadSHA256'], 'delivery payload digest')
    for name in ('node', 'helper', 'runtime', 'python', 'compiler', 'manager', 'server'):
        require(relative(m['entrypoints'][name]) == m['entrypoints'][name] and (root / m['entrypoints'][name]).exists(), 'missing entrypoint: ' + name)
    runtime = root / m['entrypoints']['runtime']
    rm = read(runtime / 'runtime-manifest.json')
    require(sha(runtime / 'runtime-manifest.json') == m['runtimeManifestSHA256'] and rm['helperSHA256'] == m['helperSHA256'], 'runtime/helper binding')
    require(sha(root / m['entrypoints']['helper']) == m['helperSHA256'], 'stale helper')
    if m['capabilities'].get('guiPreparationSource'):
        runtime_source_binding(rm, m['runtimeManifestSHA256'], m['sourceRevision'])
    require(m['distribution'] == read(root / 'backend-delivery.json'), 'backend distribution manifest drift')
    if trust := m['distribution'].get('trustStore'):
        require(m['entrypoints'].get('trustStore') == 'certificates/cacert.pem' and sha(root / 'certificates/cacert.pem') == trust['sha256'], 'missing or modified trust data')
    reader = read(root / 'reader-bundle.json')
    require(reader['headSha'] == m['sourceRevision'] and reader['bundleChecksum'] == m['readerBundleChecksum'], 'stale reader source')
    if expected:
        for key in ('sourceRevision', 'sourceFiles', 'integratedSources', 'engineInputSHA256', 'helperSHA256', 'runtimeManifestSHA256', 'readerBundleChecksum'):
            require(m.get(key) == expected.get(key), 'stale input binding: ' + key)
    if signatures:
        for image in m['images']:
            p = root / relative(image['path'])
            require(image_info(p, root) == image, 'image dependency/identity drift')
            run(['/usr/bin/codesign', '--verify', '--strict', p])
        run([root / m['entrypoints']['node'], runtime / 'verify-runtime.mjs', '--verify', runtime, '--node', root / m['entrypoints']['node']])
    return m


def replace_verified(candidate, output):
    publish_verified(candidate, output, verify)


def publish_verified(candidate, output, verifier):
    """Exchange a verified candidate without a remove/rename interruption gap."""
    output.parent.mkdir(parents=True, exist_ok=True)
    require(output.parent.resolve() == output.parent and not output.is_symlink(), 'output path/symlink')
    if output.exists():
        verifier(output)
        libc = ctypes.CDLL(None, use_errno=True)
        result = libc.renamex_np(os.fsencode(candidate), os.fsencode(output), 2)
        require(result == 0, 'atomic stage exchange failed: ' + str(ctypes.get_errno()))
    else:
        os.replace(candidate, output)


def copy_signed(source, output, identity, *, development=False):
    """Re-sign only a private app candidate, then rebind post-sign inventories.

    Distribution/proof/source provenance remains unchanged. Runtime policy and
    inventory verification still belong to its shipped producer/verifier.
    """
    original = verify(source)
    bundle_runtime_policy(read(Path(source) / original['entrypoints']['runtime'] / 'runtime-manifest.json'),
                          original['sourceRevision'], identity, development=development)
    shutil.copytree(source, output, symlinks=True)
    m = dict(original)
    if m['signing'] != ('ad-hoc' if identity == '-' else identity):
        runtime = output / m['entrypoints']['runtime']
        node = output / m['entrypoints']['node']
        run(['/usr/bin/codesign', '--force', '--sign', identity, node])
        script = """import fs from 'node:fs';
import {inventory,sha,nodePolicy,verify} from MODULE;
const root=process.argv[1], exe=process.argv[2];
const encode=x=>JSON.stringify(x,null,2)+'\\n';
const read=p=>JSON.parse(fs.readFileSync(p));
const m=read(root+'/runtime-manifest.json');
m.files=inventory(root).filter(f=>f.path!=='runtime-manifest.json');
m.payloadSHA256=sha(encode(m.files));
m.node=nodePolicy(exe,read(root+'/node-distribution.json'));
const report={schema:1,status:'verified',fileCount:m.files.length,packages:m.packages.length,
payloadSHA256:m.payloadSHA256,helperSHA256:m.helperSHA256,lockSHA256:m.lockSHA256,nodeSHA256:m.node.sha256};
m.verifyReportSHA256=sha(encode(report));
fs.writeFileSync(root+'/runtime-manifest.json',encode(m));
verify(root,exe);
""".replace('MODULE', json.dumps((runtime / 'verify-runtime.mjs').as_uri()))
        run([node, '--input-type=module', '-e', script, runtime, node])
        m['runtimeManifestSHA256'] = sha(runtime / 'runtime-manifest.json')
        m['images'] = sign_images(output, identity)
        m['signing'] = 'ad-hoc' if identity == '-' else identity
        m['files'] = payload_files(output)
        m['payloadSHA256'] = hashlib.sha256(encoded(m['files'])).hexdigest()
        write(output / MANIFEST, m)
    return verify(output)


def stage(args):
    output = args.output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    require(output.parent.resolve() == output.parent and not output.is_symlink(), 'output path/symlink')
    guard = Path(str(output) + '.lock')
    guard.mkdir()
    try:
        return stage_candidate(args)
    finally:
        guard.rmdir()


def stage_candidate(args):
    import reader_bundle
    repo = args.backend.resolve()
    expected = read(args.manifest)
    require(expected['sourceRevision'] == run(['git', '-C', repo, 'rev-parse', 'HEAD']).strip(), 'stale sourceRevision')
    require(expected['sourceFiles'] == source_binding(repo), 'stale current source')
    require(sha(args.engine) == expected['engineInputSHA256'], 'engine input mismatch')
    require(sha(args.helper) == expected['helperSHA256'] == sha(repo / 'tools/flow-reader/native/math_layout.mjs'), 'old helper mismatch')
    runtime = args.runtime_source.resolve()
    require(sha(runtime / 'runtime-manifest.json') == expected['runtimeManifestSHA256'], 'runtime input mismatch')
    rm = read(runtime / 'runtime-manifest.json')
    require(rm['helperSHA256'] == expected['helperSHA256'], 'runtime has old helper')
    runtime_source_binding(rm, expected['runtimeManifestSHA256'], expected['sourceRevision'], repo)
    runtime_signing_policy(rm, expected['sourceRevision'], args.identity)
    require(sha(runtime / 'node/bin/node') == rm['node']['sha256'], 'runtime node pre-execution hash mismatch')
    require(sha(runtime / 'verify-runtime.mjs') == sha(repo / 'scripts/prepare-native-reader-runtime.mjs'),
            'runtime verifier pre-execution hash mismatch')
    run(['/usr/bin/codesign', '--verify', '--strict', runtime / 'node/bin/node'])
    run([runtime / 'node/bin/node', runtime / 'verify-runtime.mjs', '--verify', runtime, '--node', runtime / 'node/bin/node'])
    reader_bundle.check_manifest(read(args.reader_bundle / 'reader-bundle.json'), expected_head_sha=expected['sourceRevision'])
    reader_bundle.verify_unpacked_tree(args.reader_bundle)
    rb = read(args.reader_bundle / 'reader-bundle.json')
    require(rb['bundleChecksum'] == expected['readerBundleChecksum'], 'reader bundle input mismatch')
    current = reader_bundle.manifest_files(reader_bundle.collect_entries(repo, worktree=True))
    require(reader_bundle.bundle_checksum(expected['sourceRevision'], current) == rb['bundleChecksum'], 'stale current backend/resources')
    policy = read(repo / RUNTIME_POLICY / 'backend-delivery.json')
    require(expected['integratedSources'] == integrated_sources(repo), 'integrated owner binding mismatch')
    require(sha(args.python_archive) == policy['python']['archive']['sha256'], 'Python distribution hash')
    signature = run(['/usr/sbin/pkgutil', '--check-signature', args.python_archive])
    require('Python Software Foundation (' + policy['python']['signature']['team'] + ')' in signature and 'Status: signed' in signature, 'Python installer signature')
    require(sha(args.compiler) == policy['compiler']['executableSHA256'], 'compiler distribution hash')
    require(sha(args.compiler.parent / 'LICENSE') == policy['compiler']['licenseSHA256'], 'compiler license')
    output = args.output.absolute()
    output.parent.mkdir(parents=True, exist_ok=True)
    for source in (repo, runtime, args.reader_bundle.resolve()):
        require(not output.resolve().is_relative_to(source) and not source.is_relative_to(output.resolve()), 'overlapping delivery input/output')
    with tempfile.TemporaryDirectory(prefix='.delivery-', dir=output.parent) as work:
        work = Path(work); candidate = work / 'payload'; candidate.mkdir()
        shutil.copytree(runtime, candidate / 'runtime', symlinks=True)
        shutil.copytree(args.reader_bundle / 'tools', candidate / 'tools', symlinks=True)
        shutil.copytree(args.reader_bundle / 'scripts', candidate / 'scripts', symlinks=True)
        shutil.copy2(args.reader_bundle / 'reader-bundle.json', candidate / 'reader-bundle.json')
        expanded = work / 'python-expanded'
        run(['/usr/sbin/pkgutil', '--expand-full', args.python_archive, expanded])
        shutil.copytree(expanded / policy['python']['payload'], candidate / 'python', symlinks=True)
        (candidate / 'licenses').mkdir()
        for name, expected_notice in policy['python']['installerNotices'].items():
            notice = expanded / 'Resources' / relative(name)
            require(sha(notice) == expected_notice, 'Python installer notice')
            shutil.copy2(notice, candidate / 'licenses' / ('Python-' + name))
        trust = policy['trustStore']
        require(sha(args.certifi_wheel) == trust['archive']['sha256'], 'certifi distribution hash')
        (candidate / 'certificates').mkdir()
        with zipfile.ZipFile(args.certifi_wheel) as wheel:
            for member, dest, expected_hash in [(trust['file'], 'cacert.pem', trust['sha256']), (trust['license'], 'LICENSE', trust['licenseSHA256'])]:
                content = wheel.read(relative(member))
                require(hashlib.sha256(content).hexdigest() == expected_hash, 'certifi data/license hash')
                (candidate / 'certificates' / dest).write_bytes(content)
        require(sha(candidate / 'python' / policy['python']['license']) == policy['python']['licenseSHA256'], 'Python license')
        # Backend uses console CPython, not the optional Tk/IDLE GUI runtime.
        for name in policy['python']['excludedComponents']:
            target = candidate / 'python' / relative(name)
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink(missing_ok=True)
        for target in (candidate / 'python').rglob('*'):
            if target.is_symlink() and not target.exists():
                target.unlink()
        relocate_python(candidate / 'python')
        (candidate / 'compiler').mkdir()
        shutil.copy2(args.compiler, candidate / 'compiler/typst')
        shutil.copy2(args.compiler.parent / 'LICENSE', candidate / 'compiler/LICENSE')
        for package in policy['typstPackages']:
            archive = args.typst_packages / package['archive']['url'].rsplit('/', 1)[1]
            require(sha(archive) == package['archive']['sha256'], 'Typst package archive mismatch')
            target = candidate / 'typst-packages' / relative(package['path'])
            unpack_official(archive, target)
            require(any(p.is_file() for p in target.glob('LICENSE*')), 'Typst package license missing')
        shutil.copy2(repo / RUNTIME_POLICY / 'backend-delivery.json', candidate / 'backend-delivery.json')
        shutil.copy2(__file__, candidate / 'delivery.py')
        # -s excludes user site; PYTHONHOME is set to the copied standard library.
        launcher = '#!/bin/sh\nset -eu\nSELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)\nunset PYTHONPATH PYTHONSTARTUP PYTHONUSERBASE NODE_PATH NODE_OPTIONS DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH\nexport PYTHONHOME="$SELF_DIR/python" PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1\nexec "$SELF_DIR/python/bin/python3.13" -s -B "$SELF_DIR/delivery.py" manager "$@"\n'
        (candidate / 'reader-manager').write_text(launcher); (candidate / 'reader-manager').chmod(0o755)
        # Preserve package/archive provenance; only copied images are rewritten/signed.
        images = sign_images(candidate, args.identity)
        ep = {'node':'runtime/node/bin/node', 'helper':'runtime/helper.mjs', 'runtime':'runtime',
              'python':'python/bin/python3.13', 'compiler':'compiler/typst', 'manager':'reader-manager', 'server':'tools/flow-reader/serve.py', 'trustStore':'certificates/cacert.pem'}
        # Runtime executable bytes were signed before their inventory by the producer.
        run([candidate / ep['node'], '-e', "import(process.argv[1]).then(m=>m.verify(process.argv[2],process.argv[3]))", (candidate / 'runtime/verify-runtime.mjs').as_uri(), candidate / 'runtime', candidate / ep['node']])
        m = {**expected, 'schema':1, 'entrypoints':ep, 'images':images,
             'signing': 'ad-hoc' if args.identity == '-' else args.identity,
             'distribution':policy, 'stageArgv':sys.argv, 'capabilities':{**policy['capabilities'], 'sourceRevision':expected['sourceRevision']},
             'integratedSources':expected['integratedSources']}
        m['files'] = payload_files(candidate); m['payloadSHA256'] = hashlib.sha256(encoded(m['files'])).hexdigest()
        write(candidate / MANIFEST, m)
        verify(candidate, expected)
        require(expected['sourceFiles'] == source_binding(repo), 'source changed during staging')
        replace_verified(candidate, output)
    return {'status':'verified', 'output':str(output), 'manifestSHA256':sha(output / MANIFEST)}


def bundled_manager():
    """Authenticate this app before constructing concrete manager operations."""
    root = Path(__file__).resolve().parent
    contents = root.parents[1]
    require(root == contents / 'Resources/native-reader' and contents.name == 'Contents', 'not an app delivery layout')
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', contents.parent])
    m = verify(root, signatures=False)
    release = read(contents / 'Resources/release.json')
    require(release.get('nativeDeliverySHA256') == sha(root / MANIFEST)
            and release.get('sourceRevision') == m['sourceRevision']
            and release.get('engineInputSHA256') == m['engineInputSHA256'], 'app/delivery binding mismatch')
    require(sha(contents / 'MacOS/flow-engine') == release.get('engineSHA256'), 'app/engine binding mismatch')
    require(Path(sys.executable).resolve() == (root / m['entrypoints']['python']).resolve(), 'external Python interpreter')
    os.environ['PATH'] = str(root / 'runtime/node/bin') + ':/usr/bin:/bin'
    os.environ['TYPST_PACKAGE_CACHE_PATH'] = str(root / 'typst-packages')
    os.environ['SSL_CERT_FILE'] = str(root / 'certificates/cacert.pem')
    os.environ['SSL_CERT_DIR'] = str(root / 'certificates')
    os.environ['PYTHONNOUSERSITE'] = '1'
    os.environ['FLOW_ENGINE_PATH'] = str(contents / 'MacOS/flow-engine')
    sys.path[:] = [str(root / 'tools/flow-reader'), *[p for p in sys.path if p and Path(p).resolve().is_relative_to(root / 'python')]]
    from flow_reader.services.manager import ReaderManager, ReaderExecutables
    return ReaderManager(executables=ReaderExecutables(
        python=str(root / m['entrypoints']['python']), compiler=str(root / m['entrypoints']['compiler']),
        flow_manager=str(contents / 'MacOS/Lagrangian'), engine=str(contents / 'MacOS/flow-engine'),
        manager=str(root / m['entrypoints']['manager'])))


def launch_manager(arguments):
    manager = bundled_manager()
    if arguments[:1] == ['--backend']:
        from functools import partial
        from flow_reader.services.manager import ReaderManager
        from flow_reader.server.cli import main
        return main(arguments[1:], manager_factory=partial(ReaderManager, executables=manager.executables))
    from flow_reader.services.manager import cli
    return cli(arguments, manager=manager)


def fetch(record, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists():
        with urllib.request.urlopen(record['url'], timeout=120) as response:
            data = response.read()
        require(hashlib.sha256(data).hexdigest() == record['sha256'], 'official download checksum: ' + record['url'])
        output.write_bytes(data)
    require(sha(output) == record['sha256'], 'cached dependency checksum: ' + str(output))
    return output


def unpack_official(archive, output):
    output.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tar:
        for member in tar:
            if member.isdir() and member.name.rstrip('/') == '.':
                continue
            name = relative(member.name.rstrip('/'))
            target = output / name
            require(target.resolve().is_relative_to(output.resolve()), 'archive escapes output')
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            elif member.isfile():
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as dest:
                    shutil.copyfileobj(source, dest)
                target.chmod(member.mode & 0o755)
            elif member.issym():
                require(not Path(member.linkname).is_absolute() and (target.parent / member.linkname).resolve().is_relative_to(output.resolve()), 'archive symlink escape')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.symlink_to(member.linkname)
            else:
                raise ValueError('unsupported archive member')


def acquire(args):
    """Explicit network preparation; consumption never invokes this operation."""
    repo = args.backend.resolve(); output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    node = read(repo / RUNTIME_POLICY / 'node-distribution.json')
    backend = read(repo / RUNTIME_POLICY / 'backend-delivery.json')
    n = output / 'portable-node'; n.mkdir(exist_ok=True)
    for key in ('archive','checksums','signature','key','license'):
        fetch(node[key], n / node[key]['url'].rsplit('/',1)[1])
    keyring = n / 'release-key.gpg'
    if not keyring.exists():
        run(['gpg', '--homedir', n, '--batch', '--yes', '--no-options', '--dearmor', '--output', keyring, n / node['key']['url'].rsplit('/',1)[1]])
    status = run(['gpgv', '--homedir', n, '--status-fd', '1', '--keyring', keyring, n / 'SHASUMS256.txt.sig', n / 'SHASUMS256.txt'])
    require('VALIDSIG ' + node['signerFingerprint'] + ' ' in status, 'Node release signer')
    archive = n / node['archive']['url'].rsplit('/',1)[1]
    require(any(line.split() == [node['archive']['sha256'], archive.name] for line in (n/'SHASUMS256.txt').read_text().splitlines()), 'signed archive checksum mismatch')
    node_root = n / ('node-' + node['version'] + '-darwin-arm64')
    if not node_root.exists():
        unpack_official(archive, n)
    for key in ('python','compiler'):
        record = backend[key]['archive']; target = output / key / record['url'].rsplit('/',1)[1]
        fetch(record, target)
        if key == 'compiler' and not (target.parent / 'typst-aarch64-apple-darwin').exists():
            unpack_official(target, target.parent)
    for package in backend['typstPackages']:
        record = package['archive']
        fetch(record, output / 'compiler/packages' / record['url'].rsplit('/', 1)[1])
    trust = backend['trustStore']['archive']
    fetch(trust, output / 'python' / trust['url'].rsplit('/', 1)[1])
    source = output / 'runtime-source'; source.mkdir(exist_ok=True)
    for name in ('package.json','package-lock.json','THIRD-PARTY-NOTICES.md'):
        shutil.copy2(repo / RUNTIME_POLICY / name, source / name)
    lock = read(source / 'package-lock.json'); acquisition = []
    for key, value in lock['packages'].items():
        if not key:
            continue
        relative(key); require(key.startswith('node_modules/'), 'lock path')
        archive_name = value['resolved'].rsplit('/',1)[1]
        target = source / 'archives' / archive_name; target.parent.mkdir(exist_ok=True)
        if not target.exists():
            require(value['resolved'].startswith('https://registry.npmjs.org/'), 'registry authority')
            with urllib.request.urlopen(value['resolved'], timeout=120) as response:
                data = response.read()
            require('sha512-' + base64.b64encode(hashlib.sha512(data).digest()).decode() == value['integrity'], 'package SRI')
            target.write_bytes(data)
        require('sha512-' + base64.b64encode(hashlib.sha512(target.read_bytes()).digest()).decode() == value['integrity'], 'cached package SRI')
        package = source / key
        if not package.exists():
            with tempfile.TemporaryDirectory(dir=output) as temp:
                unpack_official(target, Path(temp))
                package.parent.mkdir(parents=True, exist_ok=True); shutil.move(str(Path(temp)/'package'), package)
        acquisition.append({'package':key, 'url':value['resolved'], 'file':'archives/'+archive_name})
        for name, destination in value.get('bin',{}).items():
            relative(name); relative(destination)
            link = source / 'node_modules/.bin' / name; link.parent.mkdir(exist_ok=True)
            if not link.exists():
                link.symlink_to(os.path.relpath(package / destination, link.parent))
    write(source / 'acquisition.json', acquisition)
    return {'node':str(node_root/'bin/node'), 'runtimeSource':str(source),
            'pythonArchive':str(output/'python'/backend['python']['archive']['url'].rsplit('/',1)[1]),
            'compiler':str(output/'compiler/typst-aarch64-apple-darwin/typst'),
            'certifiWheel':str(output/'python'/trust['url'].rsplit('/',1)[1])}


def main():
    if sys.argv[1:2] == ['manager']:
        return launch_manager(sys.argv[2:])
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    v = sub.add_parser('verify', help='Verify installed payload, signed images and exact optional input binding')
    v.add_argument('--output', type=Path, required=True); v.add_argument('--manifest', type=Path)
    s = sub.add_parser('stage', help='Stage explicit verified inputs; preserve any previously valid output')
    for name in ['manifest','engine','runtime-source','helper','backend','reader-bundle','python-archive','compiler','typst-packages','certifi-wheel','output']:
        s.add_argument('--' + name, type=Path, required=True)
    s.add_argument('--identity', default='-')
    a = sub.add_parser('acquire', help='Acquire pinned official prebuilt distributions and SRI-locked packages into an isolated directory')
    a.add_argument('--backend', type=Path, required=True); a.add_argument('--output', type=Path, required=True)
    u = sub.add_parser('unpack-reader', help='Materialize the verified current reader artifact without installing it')
    u.add_argument('--bundle', type=Path, required=True); u.add_argument('--output', type=Path, required=True)
    b = sub.add_parser('binding', help='Capture current exact source and dependency binding before staging')
    for name in ['backend','engine','runtime-source','helper','reader-bundle','output']:
        b.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'acquire':
        report = acquire(args)
    elif args.command == 'unpack-reader':
        import reader_bundle
        m = reader_bundle.load_manifest(args.bundle / 'reader-bundle.json')
        reader_bundle.materialize(m, args.bundle / 'reader-bundle.tar', args.output)
        report = {'status':'verified', 'headSha':m['headSha'], 'output':str(args.output)}
    elif args.command == 'stage':
        report = stage(args)
    elif args.command == 'binding':
        rb = read(args.reader_bundle / 'reader-bundle.json')
        value = {'schema':1, 'sourceRevision':run(['git','-C',args.backend,'rev-parse','HEAD']).strip(),
                 'integratedSources':integrated_sources(args.backend),
                 'sourceFiles':source_binding(args.backend), 'engineInputSHA256':sha(args.engine),
                 'helperSHA256':sha(args.helper), 'runtimeManifestSHA256':sha(args.runtime_source / 'runtime-manifest.json'),
                 'readerBundleChecksum':rb['bundleChecksum']}
        write(args.output, value); report = value
    else:
        m = verify(args.output, read(args.manifest) if args.manifest else None)
        report = {'status':'verified', 'sourceRevision':m['sourceRevision'], 'payloadSHA256':m['payloadSHA256']}
    print(json.dumps(report, indent=2)); return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print('native-delivery: ' + str(error), file=sys.stderr); sys.exit(1)
