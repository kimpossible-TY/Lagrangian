#!/usr/bin/env python3
"""Build, install, update, roll back, and migrate the personal macOS app."""
from __future__ import annotations
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'io.github.kimpossible-ty.lagrangian'
ENGINE_WORKFLOW = 'flow-engine.yml'
ENGINE_ARTIFACT = 'flow-engine-darwin-arm64'
ENGINE_TARGET = 'aarch64-apple-darwin'
ENGINE_PROFILE = 'flow-release'
APP_NAME = 'Lagrangian'
APP_BUNDLE = 'Lagrangian.app'
APP_EXECUTABLE = 'Lagrangian'
DEFAULT_APP = Path.home() / 'Applications/Lagrangian.app'
LEGACY_APP = Path.home() / 'Applications/tinymist-flow.app'
DATA = Path.home() / 'Library/Application Support/Lagrangian'
LEGACY_DATA = Path.home() / 'Library/Application Support/tinymist-flow'

def swift_sources(include_app=True):
    """Use one explicit source manifest for app builds and isolated core tests."""
    directory = ROOT / 'apps/macos'
    manifest = json.loads((directory / 'sources.json').read_text())
    sections = ('core', 'app') if include_app else ('core',)
    return [directory / name for section in sections for name in manifest[section]]

def run(args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)

def capture(args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, indent=2, ensure_ascii=False); f.write('\n')
        os.replace(tmp, path)
    finally:
        Path(tmp).unlink(missing_ok=True)

def executable(app):
    return app / 'Contents/MacOS' / APP_EXECUTABLE

def signing_data_directory():
    """Use the existing data root until the new app migrates it on first launch."""
    return DATA if DATA.exists() or not LEGACY_DATA.exists() else LEGACY_DATA

def signing_identities():
    output = capture(['/usr/bin/security', 'find-identity', '-p', 'codesigning'])
    return dict(re.findall(r'\)\s+([0-9A-F]{40})\s+"([^"]+)"', output))

def resolve_signing_identity(requested=None):
    override = requested or os.environ.get('FLOW_SIGN_IDENTITY')
    if override: return override
    path = signing_data_directory() / 'signing.json'
    if not path.exists(): return '-'
    config = json.loads(path.read_text())
    if not isinstance(config, dict):
        raise ValueError('Invalid signing configuration: ' + str(path))
    identity = config.get('identity', '')
    if config.get('schemaVersion') != 1 or not isinstance(identity, str) or not re.fullmatch('[0-9A-F]{40}', identity):
        raise ValueError('Invalid signing configuration: ' + str(path))
    if identity not in signing_identities():
        raise ValueError('Configured signing certificate is unavailable. Restore its Keychain identity '
                         'or explicitly run configure-signing; refusing ad-hoc fallback.')
    return identity

def signing_certificate(path):
    """Return public certificate fingerprints without exporting its private key."""
    with tempfile.TemporaryDirectory(prefix='flow-cert-') as tmp:
        prefix = Path(tmp) / 'certificate'
        run(['/usr/bin/codesign', '--display', '--extract-certificates=' + str(prefix), path], capture_output=True)
        leaf = Path(str(prefix) + '0')
        if not leaf.exists(): return None
        data = leaf.read_bytes()
        return {'sha1': hashlib.sha1(data).hexdigest().upper(), 'sha256': hashlib.sha256(data).hexdigest()}

def configure_signing(args):
    """Save a verified existing Keychain identity for subsequent local builds."""
    identities = signing_identities()
    matches = [sha for sha, name in identities.items() if args.identity.upper() == sha or args.identity == name]
    if len(matches) != 1:
        raise ValueError('Select exactly one available Keychain code-signing identity by name or SHA-1.')
    identity = matches[0]
    with tempfile.TemporaryDirectory(prefix='flow-signing-check-') as tmp:
        probe = Path(tmp) / 'probe'; shutil.copyfile('/usr/bin/true', probe); probe.chmod(0o755)
        run(['/usr/bin/codesign', '--force', '--sign', identity, '--identifier', APP_ID, probe], capture_output=True)
        run(['/usr/bin/codesign', '--verify', '--strict', probe], capture_output=True)
        certificate = signing_certificate(probe)
        if not certificate or certificate['sha1'] != identity:
            raise ValueError('Signing probe did not use the selected certificate')
    path = signing_data_directory() / 'signing.json'
    write_json(path, {'schemaVersion': 1, 'identity': identity, 'name': identities[identity]})
    path.chmod(0o600)
    print('Signing identity saved: ' + identities[identity] + ' (' + identity + ')')

def validate(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != APP_ID or info.get('CFBundleExecutable') != APP_EXECUTABLE:
        raise ValueError('Not a Lagrangian app bundle')
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app], capture_output=True)
    manifest = json.loads((app / 'Contents/Resources/release.json').read_text())
    certificate_hash = manifest.get('signingCertificateSHA256')
    if certificate_hash:
        for path in (app, app / 'Contents/MacOS/flow-engine'):
            certificate = signing_certificate(path)
            if not certificate or certificate['sha256'] != certificate_hash:
                raise ValueError('Signing certificate mismatch: ' + str(path))
    if digest(app / 'Contents/MacOS/flow-engine') != manifest['engineSHA256']:
        raise ValueError('Bundled engine hash mismatch')
    if capture([executable(app), '--version']) != APP_NAME + ' ' + manifest['version']:
        raise ValueError('Version mismatch')
    run([app / 'Contents/MacOS/flow-engine', '--version'], stdout=subprocess.DEVNULL)
    return manifest

def resolve_engine(requested=None):
    selected = requested or os.environ.get('FLOW_ENGINE_PATH')
    if selected is None:
        preferred = DEFAULT_APP / 'Contents/MacOS/flow-engine'
        legacy = LEGACY_APP / 'Contents/MacOS/flow-engine'
        selected = preferred if preferred.is_file() or not legacy.is_file() else legacy
    engine = Path(selected).expanduser().resolve()
    if not engine.is_file() or not os.access(engine, os.X_OK):
        raise ValueError('A compatible external engine is required. Pass --engine /path/to/flow-engine '
                         'or set FLOW_ENGINE_PATH; the installed Flow engine is the default.')
    version = capture([engine, '--version'])
    if '--follow-system-theme' not in capture([engine, 'preview', '--help']):
        raise ValueError('The external engine must support Flow preview features, including '
                         '--follow-system-theme. Reuse a compatible installed Flow engine.')
    return engine, version

def build(args):
    engine_build = None
    if getattr(args, 'build_engine', False):
        args.engine, engine_build = build_native_engine(args.jobs)
    engine, engine_version = resolve_engine(args.engine)
    app = args.output.expanduser().resolve()
    if app.name != APP_BUNDLE: raise ValueError('Unexpected output app name')
    app.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.flow-build-', dir=app.parent) as tmp:
        staged = Path(tmp) / app.name
        manifest = build_bundle(args, staged, engine, engine_version, engine_build)
        if app.exists(): shutil.rmtree(app)
        os.replace(staged, app)
    write_json(app.parent / 'release.json', {**manifest, 'appExecutableSHA256': digest(executable(app))})
    print(app)

def build_bundle(args, app, engine, engine_version, engine_build=None):
    identity = resolve_signing_identity(getattr(args, 'identity', None))
    mac = app / 'Contents/MacOS'; resources = app / 'Contents/Resources'
    mac.mkdir(parents=True); resources.mkdir()
    engine_input_hash = digest(engine)
    shutil.copy2(engine, mac / 'flow-engine')
    run(['/usr/bin/swiftc', '-swift-version', '5', '-warnings-as-errors', '-O',
         *swift_sources(), '-o', mac / APP_EXECUTABLE])
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / 'Flow.iconset'; iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                filename = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
                run(['/usr/bin/sips', '-z', size * scale, size * scale, ROOT / 'assets/branding/lagrangian.png', '--out', iconset / filename], stdout=subprocess.DEVNULL)
        run(['/usr/bin/iconutil', '-c', 'icns', iconset, '-o', resources / 'Flow.icns'])
    version = args.version
    if not __import__('re').fullmatch(r'\d+\.\d+\.\d+', version): raise ValueError('Version must be X.Y.Z')
    info = {
        'CFBundleIdentifier': APP_ID, 'CFBundleName': APP_NAME, 'CFBundleDisplayName': APP_NAME,
        'CFBundleExecutable': APP_EXECUTABLE, 'CFBundleIconFile': 'Flow', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': version, 'CFBundleVersion': version, 'LSMinimumSystemVersion': '13.0',
        'LSUIElement': True, 'NSHighResolutionCapable': True,
        'NSDocumentsFolderUsageDescription': '선택한 Typst 프로젝트와 글꼴을 읽고 실시간 프리뷰를 제공합니다.',
        'NSDesktopFolderUsageDescription': '선택한 Typst 프로젝트를 읽고 실시간 프리뷰를 제공합니다.',
        'NSDownloadsFolderUsageDescription': '선택한 Typst 프로젝트를 읽고 실시간 프리뷰를 제공합니다.',
        'NSHumanReadableCopyright': 'Tinymist contributors and Lagrangian contributors. Apache License 2.0.',
    }
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE')
    guide = ROOT / 'docs/tinymist/flow-app.typ'
    if guide.exists():
        run([engine, 'compile', guide, resources / 'UserGuide.pdf', '--root', ROOT])
    run(['/usr/bin/codesign', '--force', '--sign', identity, '--identifier', APP_ID + '.engine', mac / 'flow-engine'])
    manifest = {'version': version, 'sourceRevision': capture(['git', '-C', ROOT, 'rev-parse', 'HEAD']),
                'sourceDirty': bool(capture(['git', '-C', ROOT, 'status', '--porcelain'])),
                'engineSource': 'native' if engine_build is not None else 'external', 'engineVersion': engine_version,
                'engineInputSHA256': engine_input_hash,
                'engineSHA256': digest(mac / 'flow-engine'), 'signing': 'ad-hoc' if identity == '-' else identity,
                'builtAt': dt.datetime.now(dt.timezone.utc).isoformat()}
    if identity != '-':
        certificate = signing_certificate(mac / 'flow-engine')
        if not certificate: raise ValueError('Certificate signing produced no certificate')
        manifest['signingCertificateSHA256'] = certificate['sha256']
    if engine_build is not None:
        manifest['engineBuild'] = engine_build
    write_json(resources / 'release.json', manifest)
    # Files created by Finder, sync providers, or this build may carry
    # provenance metadata that macOS refuses to sign.
    run(['/usr/bin/xattr', '-cr', app])
    run(['/usr/bin/codesign', '--force', '--sign', identity, '--identifier', APP_ID, app])
    validate(app)
    return manifest

def cargo_metadata():
    return json.loads(capture(['cargo', 'metadata', '--locked', '--format-version=1', '--no-deps',
                               '--manifest-path', ROOT / 'Cargo.toml'], cwd=ROOT))

def flow_release_engine_path(target_directory, target):
    return Path(target_directory) / target / 'flow-release' / 'tinymist'

def build_native_engine(jobs):
    """Build a portable native Mac engine with a recorded ThinLTO profile."""
    if sys.platform != 'darwin':
        raise ValueError('The macOS app must be built on macOS')
    if jobs < 1:
        raise ValueError('Build jobs must be positive')
    machine = platform.machine()
    if machine == 'x86_64':
        translated = subprocess.run(['/usr/sbin/sysctl', '-in', 'sysctl.proc_translated'],
                                    capture_output=True, text=True)
        if translated.stdout.strip() == '1':
            raise ValueError('Run the build with a native ARM Python or terminal on Apple Silicon')
    target = {'arm64': ENGINE_TARGET, 'x86_64': 'x86_64-apple-darwin'}.get(machine)
    if target is None:
        raise ValueError('Unsupported macOS host architecture')
    metadata = cargo_metadata()
    run(['cargo', 'build', '--locked', '--profile', ENGINE_PROFILE, '--target', target,
         '--bin', 'tinymist', '--jobs', str(jobs)], cwd=ROOT)
    path = flow_release_engine_path(metadata['target_directory'], target)
    settings = {'profile': ENGINE_PROFILE, 'target': target, 'configuredLto': 'thin',
                'rustflags': os.environ.get('RUSTFLAGS', ''),
                'encodedRustflags': os.environ.get('CARGO_ENCODED_RUSTFLAGS', '')}
    if 'CARGO_PROFILE_FLOW_RELEASE_LTO' in os.environ:
        settings['profileLtoOverride'] = os.environ['CARGO_PROFILE_FLOW_RELEASE_LTO']
    return path, settings

def stage_engine_artifact(args):
    """Collect the unsigned Apple Silicon engine, checksum, manifest, and app for upload."""
    app = args.app.expanduser().resolve()
    manifest_path = (args.manifest or (app.parent / 'release.json')).expanduser().resolve()
    manifest = json.loads(manifest_path.read_text())
    build = manifest.get('engineBuild')
    if not isinstance(build, dict) or build.get('target') != ENGINE_TARGET or build.get('profile') != ENGINE_PROFILE:
        raise ValueError('Engine artifact requires an aarch64-apple-darwin flow-release engineBuild')
    if not app.is_dir():
        raise ValueError('App bundle is missing: ' + str(app))
    engine = flow_release_engine_path(cargo_metadata()['target_directory'], ENGINE_TARGET)
    if not engine.is_file():
        raise ValueError('Native engine output is missing: ' + str(engine))
    actual = digest(engine)
    if actual != manifest.get('engineInputSHA256'):
        raise ValueError('Unsigned engine hash does not match release.json engineInputSHA256')
    version = capture([engine, '--version'])
    if not version:
        raise ValueError('Engine --version produced no output')
    if '--follow-system-theme' not in capture([engine, 'preview', '--help']):
        raise ValueError('The engine must support Flow preview features, including --follow-system-theme')
    output = args.output.expanduser().resolve()
    if output.exists(): shutil.rmtree(output)
    output.mkdir(parents=True)
    shutil.copy2(engine, output / 'flow-engine')
    (output / 'flow-engine').chmod(0o755)
    (output / 'flow-engine.sha256').write_text(actual + '  flow-engine\n')
    shutil.copy2(manifest_path, output / 'release.json')
    shutil.copytree(app, output / app.name, symlinks=True)
    print(output)

def path_inside(child, parent):
    resolved = child.expanduser().resolve()
    root = parent.resolve()
    return resolved == root or root in resolved.parents

def ensure_outside_target(path):
    if path_inside(path, ROOT / 'target'):
        raise ValueError('Refusing to store the engine inside the repository target directory. '
                         'The download is the built executable; choose a path outside target/.')

def engine_cache_dir(run_id):
    base = Path.home() / 'Library/Caches/Lagrangian/engines' if sys.platform == 'darwin' else Path.home() / '.cache/lagrangian/engines'
    return base / str(run_id)

def github_repo():
    return capture(['gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner'], cwd=ROOT).strip().strip('"')

def latest_engine_run(repo, branch):
    # A workflow_dispatch run is listed under the ref it was started with.
    # --branch main therefore finds `gh workflow run flow-engine.yml --ref main`.
    # Do not add --event; that would hide a successful run of another event.
    raw = capture(['gh', 'run', 'list', '--repo', repo, '--workflow', ENGINE_WORKFLOW,
                   '--branch', branch, '--status', 'success', '--limit', '1',
                   '--json', 'databaseId,url,headSha,conclusion'], cwd=ROOT)
    try:
        runs = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError('gh run list did not return JSON') from error
    if not isinstance(runs, list) or not runs or not runs[0].get('databaseId'):
        raise ValueError('No successful ' + ENGINE_WORKFLOW + ' run for branch ' + branch + '. '
                         'Dispatch one with: gh workflow run ' + ENGINE_WORKFLOW + ' --ref ' + branch)
    return str(runs[0]['databaseId'])

def parse_engine_checksum(text):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) != 1:
        raise ValueError('Engine checksum file must contain one SHA-256 line')
    token = lines[0].split()[0]
    if not re.fullmatch(r'[0-9a-fA-F]{64}', token):
        raise ValueError('Engine checksum file does not contain a SHA-256 digest')
    return token.lower()

def engine_payload_dir(download):
    candidates = []
    for checksum in download.rglob('flow-engine.sha256'):
        if (checksum.parent / 'flow-engine').is_file() and (checksum.parent / 'release.json').is_file():
            candidates.append(checksum.parent)
    if len(candidates) != 1:
        raise ValueError('The downloaded artifact must contain one flow-engine, flow-engine.sha256, and release.json')
    return candidates[0]

def verify_engine_payload(payload):
    engine = payload / 'flow-engine'
    actual = digest(engine)
    expected = parse_engine_checksum((payload / 'flow-engine.sha256').read_text())
    if actual != expected:
        raise ValueError('Engine SHA-256 mismatch: expected ' + expected + ', got ' + actual)
    manifest = json.loads((payload / 'release.json').read_text())
    recorded = str(manifest.get('engineInputSHA256', '')).lower()
    if recorded != actual:
        raise ValueError('Engine SHA-256 does not match release.json engineInputSHA256')
    build = manifest.get('engineBuild')
    if not isinstance(build, dict) or build.get('target') != ENGINE_TARGET or build.get('profile') != ENGINE_PROFILE:
        raise ValueError('release.json must record an aarch64-apple-darwin flow-release engineBuild')
    return actual

def clear_quarantine(path):
    if sys.platform != 'darwin':
        return
    try:
        run(['/usr/bin/xattr', '-dr', 'com.apple.quarantine', path])
    except subprocess.CalledProcessError as error:
        if error.returncode != 1:
            raise

def install_engine_payload(repo, run_id, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    incoming = dest.parent / ('.incoming-' + dest.name)
    if incoming.exists(): shutil.rmtree(incoming)
    installed = False
    try:
        with tempfile.TemporaryDirectory(prefix='flow-engine-download-') as tmp:
            download = Path(tmp) / 'artifact'
            download.mkdir()
            run(['gh', 'run', 'download', run_id, '--repo', repo, '--name', ENGINE_ARTIFACT, '--dir', download])
            payload = engine_payload_dir(download)
            verify_engine_payload(payload)
            shutil.copytree(payload, incoming, symlinks=True)
        engine = incoming / 'flow-engine'
        engine.chmod(0o755)
        clear_quarantine(incoming)
        if sys.platform == 'darwin':
            resolve_engine(engine)
        if dest.exists(): shutil.rmtree(dest)
        os.replace(incoming, dest)
        installed = True
    finally:
        if not installed and incoming.exists(): shutil.rmtree(incoming, ignore_errors=True)

def fetch_engine(args):
    """Download a verified macOS arm64 engine artifact. This does not compile Rust."""
    if shutil.which('gh') is None:
        raise ValueError('gh is required to download the macOS engine from GitHub Actions. '
                         'Authenticate it for this repository. This command does not compile Rust.')
    if args.dest is not None:
        ensure_outside_target(args.dest)
    run_id = str(args.run_id) if args.run_id else None
    if run_id is not None and not re.fullmatch(r'\d+', run_id):
        raise ValueError('Run id must be the numeric GitHub Actions run id')
    repo = github_repo()
    if run_id is None:
        branch = (args.branch or '').strip()
        if not branch:
            raise ValueError('Pass --branch or --run-id')
        run_id = latest_engine_run(repo, branch)
    dest = (args.dest or engine_cache_dir(run_id)).expanduser()
    ensure_outside_target(dest)
    install_engine_payload(repo, run_id, dest)
    engine = dest / 'flow-engine'
    print('Verified flow-engine run ' + run_id + ' SHA-256 ' + digest(engine), file=sys.stderr)
    print(engine)

def profiles(app):
    if not executable(app).exists(): return []
    return json.loads(capture([executable(app), '--profiles']))['profiles']

def running(app):
    active = []
    for p in profiles(app):
        state = json.loads(capture([executable(app), '--status', p['id']]))
        if state['running'] and state.get('managedByApp', False): active.append(p['id'])
    return active

def wait_stopped(app, ids, timeout=10):
    """Wait for asynchronous launchd bootout before replacing or restarting an app."""
    pending = set(ids)
    deadline = time.monotonic() + timeout
    while pending and time.monotonic() < deadline:
        for pid in list(pending):
            state = json.loads(capture([executable(app), '--status', pid]))
            if not state['running']: pending.remove(pid)
        if pending: time.sleep(.1)
    if pending: raise RuntimeError('Preview did not stop before update: ' + ', '.join(sorted(pending)))

def healthy(app, ids, timeout=30):
    if not ids: return
    by_id = {p['id']: p for p in profiles(app)}
    deadline = time.monotonic() + timeout
    pending = set(ids)
    while pending and time.monotonic() < deadline:
        for pid in list(pending):
            try:
                state = json.loads(capture([executable(app), '--status', pid]))
                with urllib.request.urlopen(f'http://127.0.0.1:{by_id[pid]["port"]}/', timeout=1) as response:
                    if state['running'] and response.status == 200: pending.remove(pid)
            except Exception: pass
        if pending: time.sleep(.5)
    if pending: raise RuntimeError('Preview startup failed; inspect Documents consent and logs: ' + ', '.join(pending))

def replace_app(source, destination, data_dir=None, check_health=True):
    if data_dir is None:
        # Validate before touching user data, then let the candidate's native,
        # tested migration owner move legacy directories before recovery files
        # create the new data root.
        validate(source)
        run([executable(source), '--migrate-data'])
        data_dir = DATA
    data_dir.mkdir(parents=True, exist_ok=True)
    with (data_dir / 'install.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return _replace_app(source, destination, data_dir, check_health)

def _replace_app(source, destination, data_dir, check_health):
    """Validate before stopping services; restore the old bundle on a failed update."""
    validate(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    releases = data_dir / 'releases'; releases.mkdir(parents=True, exist_ok=True)
    backup = releases / stamp / APP_BUNDLE
    active = running(destination)
    stage = Path(tempfile.mkdtemp(prefix='.lagrangian-install-', dir=destination.parent)) / APP_BUNDLE
    shutil.copytree(source, stage, symlinks=True)
    validate(stage)
    stopped = []
    had_previous = destination.exists()
    swapped = False
    try:
        for pid in active:
            run([executable(destination), '--control', 'stop', pid]); stopped.append(pid)
        wait_stopped(destination, stopped)
        if had_previous:
            backup.parent.mkdir(); os.replace(destination, backup)
        os.replace(stage, destination); swapped = True
        for pid in active: run([executable(destination), '--control', 'start', pid])
        if check_health: healthy(destination, active)
    except Exception:
        for pid in stopped:
            if executable(destination).exists(): subprocess.run([str(executable(destination)), '--control', 'stop', pid], capture_output=True)
        if executable(destination).exists(): wait_stopped(destination, stopped)
        if swapped and destination.exists():
            failed = releases / (stamp + '-failed'); failed.mkdir(); os.replace(destination, failed / destination.name)
        if backup.exists(): os.replace(backup, destination)
        for pid in stopped: subprocess.run([str(executable(destination)), '--control', 'start', pid], capture_output=True)
        raise
    finally:
        shutil.rmtree(stage.parent, ignore_errors=True)
    if had_previous: write_json(data_dir / 'previous-release.json', {'app': str(backup), 'replacedAt': stamp})
    write_json(data_dir / 'installed-release.json', validate(destination))
    print(destination)

def install(args):
    deferred = getattr(args, 'defer_health_check', False)
    replace_app(args.source.resolve(), args.app.expanduser().resolve(), check_health=not deferred)
    if deferred:
        print('Live preview health verification deferred; complete any macOS consent prompt, then verify document delivery.')

def rollback(args):
    previous = Path(json.loads((DATA / 'previous-release.json').read_text())['app'])
    replace_app(previous, args.app.expanduser().resolve())

def canonical_data_root(path):
    """Resolve parent symlinks (such as /var -> /private/var) while keeping a leaf symlink intact."""
    expanded = Path(path).expanduser()
    return expanded.parent.resolve() / expanded.name

def flow_env(data_dir=None):
    env = dict(os.environ)
    env['HOME'] = str(Path.home())
    env.setdefault('FLOW_DATA_DIR', str(canonical_data_root(data_dir or DATA)))
    env.setdefault('FLOW_LOG_DIR', str(canonical_data_root(Path.home() / 'Library/Logs/Lagrangian')))
    return env

def copy_verified(src, dst):
    src = Path(src); dst = Path(dst)
    if not src.is_file():
        raise ValueError('Missing source file for verified copy: ' + str(src))
    expected = digest(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and os.path.samefile(src, dst):
        if digest(dst) != expected:
            raise ValueError('SHA-256 verification failed for ' + str(dst))
        return expected
    fd, tmp = tempfile.mkstemp(dir=dst.parent, prefix='.' + dst.name)
    os.close(fd)
    try:
        shutil.copy2(src, tmp)
        if digest(tmp) != expected:
            raise ValueError('SHA-256 mismatch while copying ' + str(src) + ' to ' + str(dst))
        os.replace(tmp, dst)
    finally:
        Path(tmp).unlink(missing_ok=True)
    if digest(dst) != expected:
        raise ValueError('SHA-256 verification failed for ' + str(dst))
    return expected

def check_data_migration_preflight(app, has_reader=False):
    data_root = canonical_data_root(DATA)
    legacy_path = Path(LEGACY_DATA).expanduser()
    cmd = f'{executable(app)} --migrate-data'
    if legacy_path.is_symlink():
        if not data_root.is_dir() or legacy_path.resolve() != data_root.resolve():
            raise ValueError(
                f'Legacy data symlink {legacy_path} does not point to {data_root}; '
                f'run `{cmd}` first.'
            )
        return
    if legacy_path.exists():
        raise ValueError(
            f'Legacy data directory {legacy_path} has not been migrated to {data_root}; '
            f'run `{cmd}` first.'
        )
    if has_reader and not data_root.is_dir():
        raise ValueError(
            f'Lagrangian data directory {data_root} is missing; '
            f'run `{cmd}` first.'
        )

def listening_pids(port):
    result = subprocess.run(['/usr/sbin/lsof', '-nP', f'-iTCP:{port}', '-sTCP:LISTEN', '-Fp'],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return []
    return [int(line[1:]) for line in result.stdout.splitlines() if line.startswith('p') and line[1:].isdigit()]

def launchd_job_pid(label):
    result = subprocess.run(['/bin/launchctl', 'print', f'gui/{os.getuid()}/{label}'],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return None
    match = re.search(r'\bpid = (\d+)\b', result.stdout)
    return int(match.group(1)) if match else None

def pid_belongs_to_reader_service(pid, sid, expected_job_pid):
    if expected_job_pid is not None and pid == expected_job_pid:
        return True
    result = subprocess.run(['/bin/ps', '-o', 'ppid=,command=', '-p', str(pid)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        return False
    line = result.stdout.strip()
    if not line:
        return False
    parts = line.split(None, 1)
    if expected_job_pid is not None and parts[0].isdigit() and int(parts[0]) == expected_job_pid:
        return True
    command = parts[1] if len(parts) > 1 else ''
    return f'--serve {sid}' in command and ('flow-reader' in command or 'manage.py' in command)

def check_reader_ports(reader_services, all_services, preview_profiles, plan=None):
    seen_ports = {}
    for s in all_services:
        backend = s.get('backend') or {}
        port = backend.get('port')
        sid = s.get('id', '')
        if port is None:
            continue
        if port in seen_ports and seen_ports[port] != sid:
            raise ValueError(f'Port conflict on {port} for {sid}: already assigned to {seen_ports[port]}')
        seen_ports[port] = sid
    for p in preview_profiles:
        port = p.get('port')
        pid = p.get('id', '')
        if port in seen_ports and seen_ports[port] != pid:
            raise ValueError(f'Port conflict on {port} for {pid}: already assigned to {seen_ports[port]}')
    for s in reader_services:
        sid = s['id']
        port = int(s['backend']['port'])
        label = s['launchAgentLabel']
        pids = listening_pids(port)
        expected_pid = launchd_job_pid(label)
        conflicting = [pid for pid in pids if not pid_belongs_to_reader_service(pid, sid, expected_pid)]
        if conflicting:
            raise ValueError(f'Port conflict on {port} for {sid}: conflicting listener PID {conflicting}')
        if plan is not None:
            status = f'owned by {label} (pid {pids[0]})' if pids else 'free'
            plan.append(f'port-check {sid} tcp/{port}: {status}')

def verify_reader_artifacts(reader_root, reader_cfg):
    reader_root = Path(reader_root)
    engines_root = reader_root / 'engines'
    releases_root = reader_root / 'releases'
    if not engines_root.is_dir():
        raise ValueError('Reader engines directory is missing: ' + str(engines_root))
    if not releases_root.is_dir():
        raise ValueError('Reader releases directory is missing: ' + str(releases_root))
    engine_path = Path(str(reader_cfg.get('engine', '')))
    if not engine_path.is_file() or not os.access(engine_path, os.X_OK):
        raise ValueError('Configured reader engine is missing or not executable: ' + str(engine_path))
    verified_engines = 0
    for candidate in sorted(engines_root.glob('*/flow-engine')):
        if not candidate.is_file() or not os.access(candidate, os.X_OK):
            raise ValueError('Reader engine is not executable: ' + str(candidate))
        parent_name = candidate.parent.name
        if re.fullmatch(r'[0-9a-fA-F]{64}', parent_name) and digest(candidate) != parent_name.lower():
            raise ValueError('Reader engine SHA-256 mismatch: ' + str(candidate))
        verified_engines += 1
    if verified_engines < 1:
        raise ValueError('No verified reader engine found in ' + str(engines_root))
    compiler_path = Path(str(reader_cfg.get('browserCompiler', '')))
    compiler_manifest_path = compiler_path / 'manifest.json'
    if not compiler_manifest_path.is_file():
        raise ValueError('Reader browserCompiler manifest is missing: ' + str(compiler_manifest_path))
    compiler_manifest = json.loads(compiler_manifest_path.read_text())
    for rel, expected_sha in (compiler_manifest.get('files') or {}).items():
        asset = compiler_path / rel
        if not asset.is_file() or digest(asset) != str(expected_sha).lower():
            raise ValueError('Reader browserCompiler asset SHA-256 mismatch: ' + str(asset))
    manage_candidates = [compiler_path.parent / 'manage.py']
    if len(compiler_path.parents) > 2:
        manage_candidates.append(compiler_path.parents[2] / 'tools/flow-reader/manage.py')
    manage_py = next((p for p in manage_candidates if p.is_file()), None)
    if manage_py is None:
        raise ValueError('Reader release manage.py is missing under ' + str(compiler_path))
    verified_releases = 0
    for release_json in sorted(releases_root.glob('*/release.json')):
        release_dir = release_json.parent
        rel_manifest = json.loads(release_json.read_text())
        files = rel_manifest.get('files') or {}
        if not files:
            raise ValueError('Reader release manifest has no file hashes: ' + str(release_json))
        for rel, expected_sha in files.items():
            member = release_dir / rel
            if not member.is_file() or digest(member) != str(expected_sha).lower():
                raise ValueError('Reader release file SHA-256 mismatch: ' + str(member))
        verified_releases += 1
    if verified_releases < 1:
        raise ValueError('No verified reader release found in ' + str(releases_root))
    return {'engines': verified_engines, 'releases': verified_releases, 'managePy': manage_py}

TAIL_HOSTING_PATCH_SPECS = [
    (
        'tail-hosting.patch',
        False,
        {'bin/tail-hosting': ['Flow app lifecycle adapter']},
        'Flow app lifecycle adapter',
    ),
    (
        'tail-hosting-reader.patch',
        True,
        {
            'bin/tail-hosting': [
                "if s.get('kind') == 'typst-reader':",
                "if s.get('kind')=='typst-reader' and s.get('managerBinary') and s.get('registration')=='managed':",
            ],
            'scripts/test-management.py': [
                'def test_reader_compile_state_comes_from_compiler_not_http_success',
                'def test_reader_control_delegates_only_to_its_manager',
            ],
        },
        'typst_reader_service_p',
    ),
    (
        'tail-hosting-reader-focus.patch',
        True,
        {
            'bin/tail-hosting': ['def read_document_focus(previews):'],
            'AGENTS.md': ['needs_preview_selection', 'context_read_errors'],
            'scripts/test-management.py': ['1000+86400*30'],
        },
        'typst_service_focus_file',
    ),
    (
        'tail-hosting-reader-mobile.patch',
        True,
        {
            'bin/tail-hosting': ['semanticCanvases', 'observedAt'],
            'scripts/test-management.py': [
                'def test_reader_observation_time_and_native_mode_are_explicit',
                'def test_document_role_and_entrypoint_reach_the_status_report',
            ],
            'docs/architecture.md': ['compile.observedAt'],
        },
        'Allow mobile tap propagation into PDF Canvas',
    ),
]

def split_patch_file_sections(raw_patch):
    chunks = re.split(r'(?=^diff --git a/|^--- a/)', raw_patch, flags=re.M)
    sections = []
    pending_header = ''
    for chunk in chunks:
        if not chunk.strip():
            continue
        if chunk.startswith('diff --git ') and '\n--- a/' not in chunk:
            pending_header = chunk
            continue
        full_chunk = pending_header + chunk
        pending_header = ''
        match = re.search(r'^--- a/([^\n\t]+)', full_chunk, flags=re.M)
        if not match:
            continue
        rel_path = match.group(1).strip()
        if rel_path == 'config/services.json':
            continue
        sections.append((rel_path, full_chunk))
    return sections

def run_patch_cmd(section_text, work_root, reverse=False, dry_run=True):
    with tempfile.NamedTemporaryFile('w', suffix='.patch', delete=False) as f:
        f.write(section_text)
        temp_patch = Path(f.name)
    try:
        cmd = ['/usr/bin/patch', '-p1', '-f']
        if dry_run:
            cmd.append('--dry-run')
        if reverse:
            cmd.append('-R')
        cmd.extend(['-i', str(temp_patch)])
        return subprocess.run(cmd, cwd=work_root, capture_output=True, text=True)
    finally:
        temp_patch.unlink(missing_ok=True)

def is_patch_section_applied(section_text, rel_path, markers_by_file, legacy_marker, work_root):
    target_file = work_root / rel_path
    if not target_file.is_file():
        return False
    if run_patch_cmd(section_text, work_root, reverse=True, dry_run=True).returncode == 0:
        return True
    text = target_file.read_text()
    markers = markers_by_file.get(rel_path) or []
    if markers and all(m in text for m in markers):
        return True
    if rel_path == 'bin/tail-hosting' and legacy_marker and legacy_marker in text:
        return True
    return False

def check_tail_hosting_patches(script, root, has_reader, plan=None):
    if not script.is_file():
        raise ValueError('Missing tail-hosting script: ' + str(script))
    specs = [spec for spec in TAIL_HOSTING_PATCH_SPECS if not spec[1] or has_reader]
    candidate_rels = {'bin/tail-hosting'}
    for patch_name, _, _, _ in specs:
        patch_path = ROOT / 'apps/macos' / patch_name
        if patch_path.is_file():
            for rel_path, _ in split_patch_file_sections(patch_path.read_text()):
                if (root / rel_path).is_file():
                    candidate_rels.add(rel_path)
    pending_sections = []
    with tempfile.TemporaryDirectory(prefix='flow-patch-preflight-') as tmp:
        stage_root = Path(tmp)
        for rel_path in sorted(candidate_rels):
            src = root / rel_path
            if src.is_file():
                dst = stage_root / rel_path
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
        for patch_name, _, markers_by_file, legacy_marker in specs:
            patch_path = ROOT / 'apps/macos' / patch_name
            if not patch_path.is_file():
                continue
            sections = [
                (rel_path, section_text)
                for rel_path, section_text in split_patch_file_sections(patch_path.read_text())
                if rel_path == 'bin/tail-hosting' or (root / rel_path).is_file()
            ]
            patch_needed = []
            for rel_path, section_text in sections:
                if is_patch_section_applied(section_text, rel_path, markers_by_file, legacy_marker, stage_root):
                    continue
                forward = run_patch_cmd(section_text, stage_root, reverse=False, dry_run=True)
                if forward.returncode != 0:
                    detail = (forward.stdout or forward.stderr).strip()
                    raise ValueError(f'Patch {patch_name} failed pre-flight check for {rel_path}: {detail}')
                applied = run_patch_cmd(section_text, stage_root, reverse=False, dry_run=False)
                if applied.returncode != 0:
                    detail = (applied.stdout or applied.stderr).strip()
                    raise ValueError(f'Patch {patch_name} failed staging for {rel_path}: {detail}')
                patch_needed.append((patch_name, rel_path, section_text))
            if patch_needed:
                pending_sections.extend(patch_needed)
                if plan is not None:
                    plan.append(f'patch {script} with {patch_name}: apply')
            else:
                if plan is not None:
                    plan.append(f'patch {script} with {patch_name}: already applied (skip)')
    return pending_sections

def apply_tail_hosting_patches(pending_sections, root):
    for patch_name, rel_path, section_text in pending_sections:
        res = run_patch_cmd(section_text, root, reverse=False, dry_run=False)
        if res.returncode != 0:
            detail = (res.stdout or res.stderr).strip()
            raise ValueError(f'Patch {patch_name} failed for {rel_path}: {detail}')

def restore_patched_files(backup, root, patched_rels):
    if (backup / 'tail-hosting').is_file():
        copy_verified(backup / 'tail-hosting', root / 'bin/tail-hosting')
    for rel_path in patched_rels:
        src_patched = backup / 'patched-files' / rel_path
        if src_patched.is_file():
            copy_verified(src_patched, root / rel_path)

def reconstruct_legacy_services_backup(data, app):
    snapshot = json.loads(json.dumps(data))
    agents_dir = Path.home() / 'Library/LaunchAgents'
    for service in snapshot.get('services', []):
        if service.get('kind') != 'typst-always-preview':
            continue
        plist = agents_dir / (service['launchAgentLabel'] + '.plist')
        if not plist.is_file():
            continue
        agent = plistlib.loads(plist.read_bytes())
        prog = (agent.get('ProgramArguments') or [''])[0]
        if 'tinymist-flow.app' in prog and service.get('managerBinary') == str(executable(app)):
            service['managerBinary'] = prog
            service['enginePath'] = str(Path(prog).parent / 'flow-engine')
            service['focusFile'] = str(canonical_data_root(LEGACY_DATA) / 'focus' / (service['id'] + '.json'))
    return snapshot

def should_refresh_migration_backup(backup, data, has_reader):
    if has_reader and (backup / 'services.json').exists():
        saved_services = json.loads((backup / 'services.json').read_text()).get('services', [])
        saved_reader_ids = {s.get('id') for s in saved_services if s.get('kind') == 'typst-reader'}
        current_reader_ids = {s.get('id') for s in data.get('services', []) if s.get('kind') == 'typst-reader'}
        if not current_reader_ids.issubset(saved_reader_ids) or not (backup / 'reader/config.json').exists():
            return True
    return False

def prepare_migration_backup(backup, data, registry, script, root, config_path, app, has_reader, patched_rels=(), dry_run=False, plan=None):
    refresh = should_refresh_migration_backup(backup, data, has_reader)
    if refresh:
        archive = backup / 'pre-reader-backup'
        if plan is not None:
            plan.append(f'backup-archive stale pre-reader backup -> {archive}')
        if not dry_run:
            archive.mkdir(parents=True, exist_ok=True)
            for existing in sorted(backup.iterdir()):
                if existing.name in {'pre-reader-backup', 'patched-files'}:
                    continue
                if existing.is_file():
                    copy_verified(existing, archive / existing.name)
    if dry_run:
        if plan is not None:
            plan.append(f'backup {registry} -> {backup / "services.json"}')
            plan.append(f'backup {script} -> {backup / "tail-hosting"}')
            if config_path.exists():
                plan.append(f'backup {config_path} -> {backup / "profiles.json"}')
        return refresh
    backup.mkdir(parents=True, exist_ok=True)
    if refresh or not (backup / 'services.json').exists():
        snapshot = reconstruct_legacy_services_backup(data, app) if refresh else data
        write_json(backup / 'services.json', snapshot)
        if not refresh:
            copy_verified(registry, backup / 'services.json')
    if refresh or not (backup / 'tail-hosting').exists():
        copy_verified(script, backup / 'tail-hosting')
    for rel_path in patched_rels:
        if rel_path == 'bin/tail-hosting':
            continue
        src_file = root / rel_path
        dst_file = backup / 'patched-files' / rel_path
        if src_file.is_file() and (refresh or not dst_file.exists()):
            copy_verified(src_file, dst_file)
    if config_path.exists() and (refresh or not (backup / 'profiles.json').exists()):
        copy_verified(config_path, backup / 'profiles.json')
    return refresh

def migrate_always_preview(service, data, config, app, backup, refresh_backup=False, dry_run=False, plan=None):
    sid = service['id']; label = service['launchAgentLabel']
    plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    if plist.exists() and (refresh_backup or not (backup / plist.name).exists()):
        if dry_run:
            if plan is not None:
                plan.append(f'backup-plist {plist} -> {backup / plist.name}')
        else:
            copy_verified(plist, backup / plist.name)
    ingress = service['ingress']; host = data['host']['dnsName']
    public = f'https://{host}:{ingress["port"]}{ingress.get("path", "/")}'
    profile = {'id': sid, 'name': service['name'], 'root': service['projectRoot'], 'entry': service.get('entrypoint', 'main.typ'),
               'fonts': service.get('fontPaths', []), 'packages': str(Path.home() / 'Library/Application Support/typst/packages'),
               'port': service['backend']['port'], 'publicURL': public, 'label': label}
    if not any(p['id'] == sid for p in config['profiles']): config['profiles'].append(profile)
    if not config['selectedID']: config['selectedID'] = sid
    service['managerBinary'] = str(executable(app))
    service['enginePath'] = str(app / 'Contents/MacOS/flow-engine')
    service['focusFile'] = str(canonical_data_root(DATA) / 'focus' / (sid + '.json'))
    if plan is not None:
        plan.append(f'migrate typst-always-preview {sid}: managerBinary={service["managerBinary"]} enginePath={service["enginePath"]}')

def preflight_reader_environment(app, plan=None):
    target_reader = canonical_data_root(DATA) / 'reader'
    if not target_reader.exists() or not (target_reader / 'config.json').is_file():
        raise ValueError('Reader configuration is missing: ' + str(target_reader / 'config.json'))
    source_cfg = json.loads((target_reader / 'config.json').read_text())
    source_stats = verify_reader_artifacts(target_reader, source_cfg)
    if plan is not None:
        plan.append(
            f'reader-config {target_reader / "config.json"}: flowManager={executable(app)} '
            f'engines={source_stats["engines"]} releases={source_stats["releases"]}'
        )
    return {
        'target_reader': target_reader,
        'source_stats': source_stats,
        'config': source_cfg,
    }

def backup_reader_environment(reader_info, backup, refresh_backup=False, dry_run=False, plan=None):
    target_reader = reader_info['target_reader']
    reader_backup = backup / 'reader'
    for rel in ('config.json', 'config.previous.json', 'bin/flow-reader'):
        src_file = target_reader / rel
        if not src_file.is_file():
            continue
        if refresh_backup or not (reader_backup / rel).exists():
            if dry_run:
                _ = digest(src_file)
                if plan is not None:
                    plan.append(f'backup-reader {src_file} -> {reader_backup / rel}')
            else:
                copy_verified(src_file, reader_backup / rel)

def migrate_reader_service(service, data, reader_cfg, backup, refresh_backup=False, dry_run=False, plan=None):
    sid = service['id']; label = service['launchAgentLabel']
    plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    if plist.exists() and (refresh_backup or not (backup / plist.name).exists()):
        if dry_run:
            if plan is not None:
                plan.append(f'backup-plist {plist} -> {backup / plist.name}')
        else:
            copy_verified(plist, backup / plist.name)
    target_reader = canonical_data_root(DATA) / 'reader'
    service['managerBinary'] = str(target_reader / 'bin/flow-reader')
    service['focusFile'] = str(target_reader / 'documents' / sid / 'focus.json')
    ingress = service['ingress']; host = data['host']['dnsName']
    public = f'https://{host}:{ingress["port"]}{ingress.get("path", "/")}'
    existing = next((p for p in reader_cfg.get('services', []) if p.get('id') == sid), None)
    if existing is None:
        reader_cfg.setdefault('services', []).append({
            'id': sid,
            'parentID': reader_service_parent_id(service, data, reader_cfg),
            'port': service['backend']['port'],
            'publicURL': public,
            'development': False,
            'semanticCanvases': True,
            'extraFonts': [],
        })
    if plan is not None:
        plan.append(
            f'migrate typst-reader {sid} (port {service["backend"]["port"]}): '
            f'managerBinary={service["managerBinary"]} focusFile={service["focusFile"]}'
        )

def reader_service_parent_id(service, data, reader_cfg):
    """install.py names the reader `<profile>-reader`; the Tail Hosting id must match."""
    sid = service['id']
    existing = next((p for p in reader_cfg.get('services', []) if p.get('id') == sid), None)
    if existing is not None:
        parent_id = existing.get('parentID') or ''
    else:
        parent_id = next(
            (
                s['id'] for s in data.get('services', [])
                if s.get('kind') == 'typst-always-preview'
                and s.get('projectRoot') == service.get('projectRoot')
                and s.get('entrypoint', 'main.typ') == service.get('entrypoint', 'main.typ')
            ),
            '',
        )
    if parent_id + '-reader' != sid:
        raise ValueError(f'Reader service {sid} must be named {parent_id}-reader to match install.py')
    return parent_id

def reader_launcher_path():
    return canonical_data_root(DATA) / 'reader/bin/flow-reader'

# Same choice as ReaderManager.reader_label: the legacy plist keeps its launchd label.
LEGACY_READER_LABEL_PREFIX = 'io.github.kimpossible-ty.tinymist-flow.reader.'
CURRENT_READER_LABEL_PREFIX = 'io.github.kimpossible-ty.lagrangian.reader.'

def reader_launchd_label(identifier):
    agents = Path.home() / 'Library/LaunchAgents'
    legacy = LEGACY_READER_LABEL_PREFIX + identifier
    if (agents / f'{legacy}.plist').is_file():
        return legacy
    return CURRENT_READER_LABEL_PREFIX + identifier

def reader_plist_owned(plist, sid, launcher):
    """Own a job whose arguments serve this id and whose launcher resolves to flow-reader."""
    if not Path(plist).is_file():
        return False
    try:
        agent = plistlib.loads(Path(plist).read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return False
    arguments = agent.get('ProgramArguments') if isinstance(agent, dict) else None
    if (not isinstance(arguments, list) or not arguments or arguments[1:] != ['--serve', sid]
            or not isinstance(arguments[0], str)):
        return False
    try:
        return Path(arguments[0]).resolve() == Path(launcher).resolve()
    except (OSError, RuntimeError):
        return False

def reader_jobs(reader_cfg):
    """Running jobs install.py sees: reader config services, labeled like ReaderManager."""
    launcher = reader_launcher_path()
    jobs = []
    for service in reader_cfg.get('services') or []:
        sid = service.get('id')
        if not isinstance(sid, str) or not sid:
            continue
        label = reader_launchd_label(sid)
        plist = Path.home() / 'Library/LaunchAgents' / f'{label}.plist'
        jobs.append({
            'id': sid,
            'label': label,
            'plist': plist,
            'running': launchd_job_pid(label) is not None,
            'owned': reader_plist_owned(plist, sid, launcher),
        })
    return jobs

def check_reader_install_preconditions(reader_services, reader_cfg, data, plan=None):
    """Same gates as tools/flow-reader/install.py, evaluated before it runs."""
    status = subprocess.run(
        ['git', '-C', str(ROOT), 'status', '--porcelain'],
        capture_output=True, text=True,
    )
    if status.returncode != 0:
        raise ValueError(status.stderr.strip() or 'Unable to verify the Reader checkout')
    if status.stdout.strip():
        raise ValueError('Install Reader from a clean commit')
    if plan is not None:
        plan.append('install-preflight: clean checkout')
    launcher = reader_launcher_path()
    jobs = reader_jobs(reader_cfg)
    for job in jobs:
        if not job['running']:
            continue
        if not launcher.is_file():
            raise ValueError('Reader is running but the launcher is missing: ' + str(launcher))
        if not job['owned']:
            raise ValueError(
                f'Reader {job["id"]} is running but flow-reader does not own its LaunchAgent {job["plist"]}'
            )
    by_id = {job['id']: job for job in jobs}
    for service in reader_services:
        sid = service['id']
        parent_id = reader_service_parent_id(service, data, reader_cfg)
        job = by_id.get(sid)
        running = bool(job and job['running'])
        if plan is not None:
            if running:
                disposition = f'will stop via launchctl bootout {launchd_target(job["label"])}'
            else:
                disposition = 'stopped'
            plan.append(f'install-preflight {sid}: parentID {parent_id}, {disposition}')
    return [job for job in jobs if job['running']]

def reader_job_state(job):
    pid = launchd_job_pid(job['label'])
    status = f'running pid={pid}' if pid is not None else 'stopped'
    launcher = ''
    plist = Path(job['plist'])
    if plist.is_file():
        try:
            agent = plistlib.loads(plist.read_bytes())
            arguments = agent.get('ProgramArguments') if isinstance(agent, dict) else None
            if isinstance(arguments, list) and arguments:
                launcher = ' launcher=' + str(arguments[0])
        except (OSError, plistlib.InvalidFileException):
            launcher = ' launcher=unreadable'
    return f'{status} label={job["label"]}{launcher}'

def restart_migrated_readers(jobs):
    launcher = reader_launcher_path()
    try:
        for job in jobs:
            run([launcher, '--control', 'restart', job['id']], env=flow_env())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Reader restart failed: {error}')
        for job in jobs:
            print(f'Restart reader {job["id"]}: {launcher} --control restart {job["id"]}')
            print(f'Reader {job["id"]} state: {reader_job_state(job)}')

def finalize_reader_migration(reader_services, reader_cfg, target_reader, app, dry_run=False, plan=None):
    install_script = ROOT / 'tools/flow-reader/install.py'
    python_bin = reader_cfg.get('python') or sys.executable
    compiler_bin = reader_cfg.get('compiler') or shutil.which('typst') or '/missing/typst'
    for service in reader_services:
        sid = service['id']
        entry = next((p for p in reader_cfg.get('services', []) if p.get('id') == sid), None)
        if entry is None:
            raise ValueError('Missing reader service configuration for ' + sid)
        cmd = [
            str(python_bin),
            str(install_script),
            '--data', str(target_reader),
            '--flow-manager', str(executable(app)),
            '--python', str(python_bin),
            '--compiler', str(compiler_bin),
            '--profile', str(entry['parentID']),
            '--port', str(entry['port']),
            '--public-url', str(entry.get('publicURL', '')),
        ]
        if reader_cfg.get('engine'):
            cmd.extend(['--engine', str(reader_cfg['engine'])])
        if reader_cfg.get('browserCompiler'):
            cmd.extend(['--browser-compiler', str(reader_cfg['browserCompiler'])])
        if entry.get('development'):
            cmd.append('--development')
        if 'semanticCanvases' in entry:
            cmd.append('--semantic-canvases' if entry['semanticCanvases'] else '--no-semantic-canvases')
        for font in entry.get('extraFonts') or []:
            cmd.extend(['--font-path', str(font)])
        if dry_run:
            if plan is not None:
                plan.append(f'install-reader {sid}: {" ".join(cmd)}')
            continue
        run(cmd, env=flow_env())

def prepare_background_manager(app, backup, refresh_backup=False, dry_run=False, plan=None):
    agents_dir = Path.home() / 'Library/LaunchAgents'
    legacy_login = agents_dir / 'io.github.kimpossible-ty.tinymist-flow.login.plist'
    current_login = agents_dir / f'{APP_ID}.login.plist'
    login_plist = legacy_login if legacy_login.exists() or not current_login.exists() else current_login
    existed = login_plist.exists()
    if existed and (refresh_backup or not (backup / login_plist.name).exists()):
        if dry_run:
            if plan is not None:
                plan.append(f'backup-login-plist {login_plist} -> {backup / login_plist.name}')
        else:
            copy_verified(login_plist, backup / login_plist.name)
    if plan is not None:
        if existed:
            plan.append(f'migrate background-manager {login_plist}: {executable(app)} --login on')
        else:
            plan.append('migrate background-manager: no existing login LaunchAgent (skip)')
    return {'loginPlist': login_plist, 'meta': {'loginPlistName': login_plist.name, 'loginPlistExisted': existed}}

def migrate(args):
    dry_run = getattr(args, 'dry_run', False)
    root = args.root.resolve(); app = args.app.expanduser().resolve(); validate(app)
    registry = root / 'config/services.json'; script = root / 'bin/tail-hosting'
    data = json.loads(registry.read_text())
    reader_services = [s for s in data.get('services', []) if s.get('kind') == 'typst-reader']
    check_data_migration_preflight(app, has_reader=bool(reader_services))
    backup = canonical_data_root(DATA) / 'migration-backup'
    config_path = canonical_data_root(DATA) / 'profiles.json'
    profiles_existed = config_path.exists()
    config = json.loads(config_path.read_text()) if profiles_existed else {'schemaVersion': 1, 'selectedID': '', 'profiles': []}
    plan = []
    # Pre-flight phase: validate ports, patches, and reader artifacts before mutating anything.
    check_reader_ports(reader_services, data.get('services', []), config.get('profiles', []), plan=plan)
    pending_patches = check_tail_hosting_patches(script, root, bool(reader_services), plan=plan)
    patched_rels = sorted({rel for _, rel, _ in pending_patches if rel != 'bin/tail-hosting'})
    reader_info = preflight_reader_environment(app, plan=plan) if reader_services else None
    reader_cfg = reader_info['config'] if reader_info is not None else None
    running_readers = []
    if reader_info is not None:
        running_readers = check_reader_install_preconditions(reader_services, reader_cfg, data, plan=plan)
    agents_dir = Path.home() / 'Library/LaunchAgents'
    existing_plists = {
        s['launchAgentLabel'] + '.plist': (agents_dir / (s['launchAgentLabel'] + '.plist')).exists()
        for s in data.get('services', [])
        if s.get('kind') in {'typst-always-preview', 'typst-reader'} and s.get('launchAgentLabel')
    }
    if dry_run:
        refresh_backup = prepare_migration_backup(
            backup, data, registry, script, root, config_path, app, bool(reader_services),
            patched_rels=patched_rels, dry_run=True, plan=plan,
        )
        if reader_info is not None:
            backup_reader_environment(reader_info, backup, refresh_backup=refresh_backup, dry_run=True, plan=plan)
        for service in data['services']:
            kind = service.get('kind')
            if kind == 'typst-always-preview':
                migrate_always_preview(service, data, config, app, backup, refresh_backup=refresh_backup, dry_run=True, plan=plan)
            elif kind == 'typst-reader':
                migrate_reader_service(service, data, reader_cfg, backup, refresh_backup=refresh_backup, dry_run=True, plan=plan)
        prepare_background_manager(app, backup, refresh_backup=refresh_backup, dry_run=True, plan=plan)
        if reader_info is not None:
            finalize_reader_migration(
                reader_services, reader_cfg, reader_info['target_reader'], app,
                dry_run=True, plan=plan,
            )
        for line in plan:
            print('[dry-run] ' + line)
        print('Dry run complete; no files or services were modified.')
        return

    prior_meta = json.loads((backup / 'migration.json').read_text()) if (backup / 'migration.json').is_file() else {}
    refresh_backup = prepare_migration_backup(
        backup, data, registry, script, root, config_path, app, bool(reader_services),
        patched_rels=patched_rels, dry_run=False, plan=plan,
    )
    if reader_info is not None:
        backup_reader_environment(reader_info, backup, refresh_backup=refresh_backup, dry_run=False, plan=plan)
    for service in data['services']:
        kind = service.get('kind')
        if kind == 'typst-always-preview':
            migrate_always_preview(service, data, config, app, backup, refresh_backup=refresh_backup, dry_run=False, plan=plan)
        elif kind == 'typst-reader':
            migrate_reader_service(service, data, reader_cfg, backup, refresh_backup=refresh_backup, dry_run=False, plan=plan)
    login_bundle = prepare_background_manager(app, backup, refresh_backup=refresh_backup, dry_run=False, plan=plan)
    login_meta = login_bundle['meta']
    if not refresh_backup and prior_meta.get('schemaVersion') == 2:
        profiles_existed = prior_meta.get('profilesExisted', profiles_existed)
        existing_plists = prior_meta.get('existingPlists', existing_plists)
        patched_rels = sorted(set(prior_meta.get('patchedFiles', [])) | set(patched_rels))
        if 'loginPlistExisted' in prior_meta:
            login_meta['loginPlistExisted'] = prior_meta['loginPlistExisted']
    write_json(backup / 'migration.json', {
        'schemaVersion': 2,
        'hostingRoot': str(root),
        'app': str(app),
        'legacyApp': str(LEGACY_APP),
        'profilesExisted': profiles_existed,
        'existingPlists': existing_plists,
        'patchedFiles': patched_rels,
        **login_meta,
    })
    # install.py refuses to replace a release while any reader job is running, and the
    # legacy launcher rejects a compatibility-symlink plist. Stop owned jobs here with
    # launchctl, install, then restart. A failed install bootstraps those plists again.
    undo_steps = []
    try:
        if profiles_existed:
            undo_steps.append(lambda: copy_verified(backup / 'profiles.json', config_path))
        else:
            undo_steps.append(lambda: config_path.unlink(missing_ok=True))
        write_json(config_path, config)
        run([executable(app), '--check-config'], env=flow_env())
        if reader_info is not None:
            undo_steps.append(lambda: restore_reader_environment(backup))
            for job in running_readers:
                stop_reader_job(job['label'])
                label, plist = job['label'], job['plist']
                undo_steps.append(lambda label=label, plist=plist: bootstrap_restored_reader(label, plist))
            finalize_reader_migration(
                reader_services, reader_cfg, reader_info['target_reader'], app,
                dry_run=False, plan=plan,
            )
        if login_meta['loginPlistExisted']:
            undo_steps.append(lambda: restore_background_manager(backup, login_meta))
            run([executable(app), '--login', 'on'], env=flow_env())
        if pending_patches:
            undo_steps.append(lambda: restore_patched_files(backup, root, patched_rels))
        apply_tail_hosting_patches(pending_patches, root)
        undo_steps.append(lambda: copy_verified(backup / 'services.json', registry))
        write_json(registry, data)
    except Exception as original:
        undo_errors = []
        for undo in reversed(undo_steps):
            try:
                undo()
            except Exception as error:
                undo_errors.append(error)
        if undo_errors:
            detail = '; '.join(str(error) for error in undo_errors)
            raise RuntimeError('Migration rollback encountered errors: ' + detail) from original
        raise
    if running_readers:
        restart_migrated_readers(running_readers)
    print('Profiles imported; ingress preserved. Activate with the app Restart control.')
    for s in reader_services:
        launcher = reader_launcher_path()
        print(f'Restart reader {s["id"]}: {launcher} --control restart {s["id"]}')
    print('Recovery files:', backup)

def restore_always_preview(service, app, backup, saved=None, dry_run=False, plan=None):
    sid = service['id']; label = service['launchAgentLabel']
    plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    backup_plist = backup / plist.name
    if plan is not None:
        plan.append(f'restore typst-always-preview {sid}: stop via {executable(app)} and restore {plist}')
    if dry_run:
        if backup_plist.exists():
            _ = digest(backup_plist)
        return
    if executable(app).exists():
        run([executable(app), '--control', 'stop', sid], env=flow_env())
    if backup_plist.exists():
        copy_verified(backup_plist, plist)
    elif saved and saved.get('existingPlists', {}).get(plist.name) is False and plist.exists():
        plist.unlink(missing_ok=True)

def launchd_target(label):
    return f'gui/{os.getuid()}/{label}'

def wait_launchd_unloaded(label):
    """bootout can return while launchd still reports the terminating job."""
    target = launchd_target(label)
    deadline = time.monotonic() + 10
    while True:
        status = subprocess.run(['/bin/launchctl', 'print', target], capture_output=True, text=True)
        if status.returncode != 0 or not status.stdout.strip():
            return
        if time.monotonic() >= deadline:
            raise ValueError('The Reader job has not finished stopping')
        time.sleep(0.1)

def stop_reader_job(label):
    """Unload a reader job without disabling it, so rollback can bootstrap the same plist."""
    subprocess.run(['/bin/launchctl', 'bootout', launchd_target(label)], capture_output=True, text=True)
    wait_launchd_unloaded(label)

def bootstrap_restored_reader(label, plist):
    """Load a restored plist directly.

    The restored release matches its launcher path by string equality, so a compatibility
    symlink has to be loaded here. Retry once; launchd can refuse the first bootstrap.
    """
    last_error = None
    for _attempt in range(2):
        try:
            target = launchd_target(label)
            subprocess.run(['/bin/launchctl', 'bootout', target], capture_output=True, text=True)
            wait_launchd_unloaded(label)
            run(['/bin/launchctl', 'enable', target])
            run(['/bin/launchctl', 'bootstrap', f'gui/{os.getuid()}', plist])
            return
        except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
            last_error = error
    raise last_error

def restore_reader_service(service, backup, saved=None, dry_run=False, plan=None):
    sid = service['id']; label = service['launchAgentLabel']
    plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
    backup_plist = backup / plist.name
    if plan is not None:
        plan.append(
            f'restore typst-reader {sid}: restore {plist} and bootstrap via launchctl '
            f'{launchd_target(label)}'
        )
    if dry_run:
        if backup_plist.exists():
            _ = digest(backup_plist)
        return
    if backup_plist.exists():
        copy_verified(backup_plist, plist)
    elif saved and saved.get('existingPlists', {}).get(plist.name) is False and plist.exists():
        plist.unlink(missing_ok=True)

def restore_reader_environment(backup, dry_run=False, plan=None):
    reader_backup = backup / 'reader'
    if not reader_backup.exists():
        return
    target_reader = canonical_data_root(DATA) / 'reader'
    for rel in ('config.json', 'config.previous.json', 'bin/flow-reader'):
        src = reader_backup / rel
        if not src.is_file():
            continue
        if plan is not None:
            plan.append(f'restore-reader {src} -> {target_reader / rel}')
        if dry_run:
            _ = digest(src)
            continue
        copy_verified(src, target_reader / rel)
        if rel == 'bin/flow-reader':
            (target_reader / rel).chmod(0o755)

def restore_background_manager(backup, saved, dry_run=False, plan=None):
    login_name = saved.get('loginPlistName', 'io.github.kimpossible-ty.tinymist-flow.login.plist')
    login_plist = Path.home() / 'Library/LaunchAgents' / login_name
    backup_login = backup / login_name
    if backup_login.is_file():
        if plan is not None:
            plan.append(f'restore background-manager {backup_login} -> {login_plist}')
        if dry_run:
            _ = digest(backup_login)
        else:
            copy_verified(backup_login, login_plist)
    elif 'loginPlistExisted' in saved and not saved['loginPlistExisted'] and login_plist.exists():
        if plan is not None:
            plan.append(f'remove newly-created background-manager {login_plist}')
        if not dry_run:
            login_plist.unlink(missing_ok=True)

def restore_hosting(args):
    dry_run = getattr(args, 'dry_run', False)
    backup = canonical_data_root(DATA) / 'migration-backup'
    saved = json.loads((backup / 'migration.json').read_text()); root = Path(saved['hostingRoot'])
    app = Path(saved['app'])
    original = json.loads((backup / 'services.json').read_text())
    plan = []
    for s in original['services']:
        kind = s.get('kind')
        if kind == 'typst-always-preview':
            restore_always_preview(s, app, backup, saved=saved, dry_run=dry_run, plan=plan)
        elif kind == 'typst-reader':
            restore_reader_service(s, backup, saved=saved, dry_run=dry_run, plan=plan)
    restore_reader_environment(backup, dry_run=dry_run, plan=plan)
    profiles_path = canonical_data_root(DATA) / 'profiles.json'
    if (backup / 'profiles.json').is_file():
        if plan is not None:
            plan.append(f'restore {backup / "profiles.json"} -> {profiles_path}')
        if dry_run:
            _ = digest(backup / 'profiles.json')
        else:
            copy_verified(backup / 'profiles.json', profiles_path)
    elif saved.get('profilesExisted') is False and profiles_path.exists():
        if plan is not None:
            plan.append(f'remove newly-created {profiles_path}')
        if not dry_run:
            profiles_path.unlink(missing_ok=True)
    restore_background_manager(backup, saved, dry_run=dry_run, plan=plan)
    restore_pairs = [(backup / 'services.json', root / 'config/services.json'), (backup / 'tail-hosting', root / 'bin/tail-hosting')]
    for rel_path in saved.get('patchedFiles', []):
        src_patched = backup / 'patched-files' / rel_path
        if src_patched.is_file():
            restore_pairs.append((src_patched, root / rel_path))
    for src, dst in restore_pairs:
        plan.append(f'restore {src} -> {dst}')
        if dry_run:
            _ = digest(src)
        else:
            copy_verified(src, dst)
    if dry_run:
        for line in plan:
            print('[dry-run] ' + line)
        print('Dry run complete; no files or services were modified.')
        return
    for s in original['services']:
        kind = s.get('kind')
        if kind == 'typst-always-preview' and s.get('desiredState') == 'running':
            run([root / 'bin/tail-hosting', 'start', s['id']])
        elif kind == 'typst-reader':
            label = s['launchAgentLabel']
            plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
            if s.get('desiredState') == 'running' and plist.is_file():
                bootstrap_restored_reader(label, plist)
            print(f'Restart reader {s["id"]}: launchctl bootout {launchd_target(label)}; enable; bootstrap {plist}')
    print('Previous Tail Hosting configuration restored.')

def main():
    parser = argparse.ArgumentParser(description=__doc__); sub = parser.add_subparsers(dest='command', required=True)
    b = sub.add_parser('build'); b.add_argument('--engine', type=Path, help='External Flow-compatible engine (FLOW_ENGINE_PATH or installed Lagrangian app by default; legacy Flow app accepted during migration)'); b.add_argument('--output', type=Path, default=ROOT / 'dist/Lagrangian.app'); b.add_argument('--version', default='0.1.0'); b.add_argument('--identity', help='Existing signing identity (FLOW_SIGN_IDENTITY or saved configuration by default)'); b.add_argument('--build-engine', action='store_true', help='Build the native engine with ThinLTO before packaging'); b.add_argument('--jobs', type=int, default=2); b.set_defaults(func=build)
    fetch = sub.add_parser('fetch-engine', help='Download a macOS arm64 engine built by GitHub Actions without compiling Rust')
    fetch.add_argument('--branch', default='main', help='Branch whose latest successful flow-engine run is downloaded')
    fetch.add_argument('--run-id', help='Download this workflow run instead of the latest successful branch run')
    fetch.add_argument('--dest', type=Path, help='Directory outside the repository target/ (default: a small user cache keyed by run id)')
    fetch.set_defaults(func=fetch_engine)
    stage = sub.add_parser('stage-engine-artifact', help='Collect the unsigned Apple Silicon engine and app manifest for upload')
    stage.add_argument('--app', type=Path, required=True)
    stage.add_argument('--manifest', type=Path)
    stage.add_argument('--output', type=Path, required=True)
    stage.set_defaults(func=stage_engine_artifact)
    s = sub.add_parser('configure-signing'); s.add_argument('--identity', required=True, help='Existing Keychain code-signing certificate name or SHA-1'); s.set_defaults(func=configure_signing)
    i = sub.add_parser('install'); i.add_argument('source', type=Path); i.add_argument('--app', type=Path, default=DEFAULT_APP); i.add_argument('--defer-health-check', action='store_true', help='Defer the live HTTP deadline while macOS consent is pending; keep bundle validation and backup'); i.set_defaults(func=install)
    r = sub.add_parser('rollback'); r.add_argument('--app', type=Path, default=DEFAULT_APP); r.set_defaults(func=rollback)
    m = sub.add_parser('migrate-tail-hosting'); m.add_argument('root', type=Path); m.add_argument('--app', type=Path, default=DEFAULT_APP); m.add_argument('--dry-run', action='store_true', help='Print planned migration changes without modifying files or services'); m.set_defaults(func=migrate)
    restore = sub.add_parser('restore-tail-hosting'); restore.add_argument('--dry-run', action='store_true', help='Print planned restore changes without modifying files or services'); restore.set_defaults(func=restore_hosting)
    v = sub.add_parser('verify'); v.add_argument('app', type=Path); v.set_defaults(func=lambda a: print(json.dumps(validate(a.app), indent=2)))
    args = parser.parse_args()
    try: args.func(args)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as e: print(str(e), file=sys.stderr); sys.exit(1)

if __name__ == '__main__': main()
