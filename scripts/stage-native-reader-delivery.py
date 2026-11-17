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


def inventory(root):
    root = Path(root).absolute()
    result = []
    for p in sorted(root.rglob('*')):
        rel = relative(p.relative_to(root).as_posix())
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
    paths = ['apps/macos/sources.json', 'scripts/flow-app.py', 'scripts/stage-native-reader-delivery.py', 'scripts/verify-native-reader-app.py',
             'scripts/prepare-native-reader-runtime.mjs', 'assets/branding/lagrangian.png', 'docs/tinymist/flow-app.typ',
             *[str(RUNTIME_POLICY / n) for n in ['node-distribution.json', 'backend-delivery.json', 'package.json', 'package-lock.json', 'THIRD-PARTY-NOTICES.md']],
             *['apps/macos/' + n for section in ('core', 'native', 'app') for n in sources[section]]]
    return {name: sha(root / name) for name in sorted(paths)}


def integrated_sources(root):
    """Bind immutable upstream owners and the one transferred collection fix."""
    capabilities = read(root / RUNTIME_POLICY / 'backend-delivery.json')['capabilities']
    core, pages = capabilities['coreSource'], capabilities['originalPagesSource']
    gui, published = capabilities['guiPreparationSource'], capabilities['publishedReaderSource']
    base = '9b2dc87651eb16a809bb48dbe4539614cfe30d6a'
    for ancestor, descendant in [(base, core), (core, pages), (pages, 'HEAD'),
                                  (gui, 'HEAD'), (published, 'HEAD')]:
        run(['git', '-C', root, 'merge-base', '--is-ancestor', ancestor, descendant])
    def changed(before, after):
        return run(['git', '-C', root, 'diff', '--name-only', before, after]).splitlines()
    revisions = {name:core for name in changed(base, core)}
    revisions.update({name:pages for name in changed(core, pages)})
    revisions.update({name:gui for name in changed(gui + '^', gui)})
    revisions.update({name:published for name in changed('5d71618e7ee320edbe759511fe634024fc8104a6', published)})
    # Explicit PM transfer C-TEST-COLLECT-01. No C implementation is overridden.
    transferred = 'tests/flow-app/native-reader-app/test_original_pages.py'
    revisions[transferred] = 'HEAD'
    records = {}
    for name, revision in sorted(revisions.items()):
        blob = subprocess.check_output(['git', '-C', str(root), 'show', revision + ':' + name])
        digest = hashlib.sha256(blob).hexdigest()
        require(sha(root / name) == digest, 'integrated owner source drift: ' + name)
        records[name] = digest
    return {'coreRevision':core, 'pageRevision':pages, 'guiRevision':gui,
            'publishedReaderRevision':published, 'deliveryOwnedOverrides':[transferred], 'files':records}


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
        require(rm['source']['sourceSHA'] == m['sourceRevision'] and not rm['source']['dirty'], 'stale runtime sourceRevision')
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
    output.parent.mkdir(parents=True, exist_ok=True)
    require(output.parent.resolve() == output.parent and not output.is_symlink(), 'output path/symlink')
    if output.exists():
        verify(output)
        libc = ctypes.CDLL(None, use_errno=True)
        result = libc.renamex_np(os.fsencode(candidate), os.fsencode(output), 2)
        require(result == 0, 'atomic stage exchange failed: ' + str(ctypes.get_errno()))
    else:
        os.replace(candidate, output)


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
    require(rm['source']['sourceSHA'] == expected['sourceRevision'] and not rm['source']['dirty'], 'stale runtime sourceRevision')
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
