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

def migrate(args):
    root = args.root.resolve(); app = args.app.expanduser().resolve(); validate(app)
    registry = root / 'config/services.json'; script = root / 'bin/tail-hosting'
    backup = DATA / 'migration-backup'
    backup.mkdir(parents=True, exist_ok=True)
    # Never overwrite the original pre-migration recovery files.
    for path, name in [(registry, 'services.json'), (script, 'tail-hosting')]:
        if not (backup / name).exists(): shutil.copy2(path, backup / name)
    config_path = DATA / 'profiles.json'
    if config_path.exists() and not (backup / 'profiles.json').exists(): shutil.copy2(config_path, backup / 'profiles.json')
    config = json.loads(config_path.read_text()) if config_path.exists() else {'schemaVersion': 1, 'selectedID': '', 'profiles': []}
    data = json.loads(registry.read_text())
    for service in data['services']:
        if service.get('kind') != 'typst-always-preview': continue
        sid = service['id']; label = service['launchAgentLabel']
        plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
        if plist.exists() and not (backup / plist.name).exists(): shutil.copy2(plist, backup / plist.name)
        ingress = service['ingress']; host = data['host']['dnsName']
        public = f'https://{host}:{ingress["port"]}{ingress.get("path", "/")}'
        profile = {'id': sid, 'name': service['name'], 'root': service['projectRoot'], 'entry': service.get('entrypoint', 'main.typ'),
                   'fonts': service.get('fontPaths', []), 'packages': str(Path.home() / 'Library/Application Support/typst/packages'),
                   'port': service['backend']['port'], 'publicURL': public, 'label': label}
        if not any(p['id'] == sid for p in config['profiles']): config['profiles'].append(profile)
        if not config['selectedID']: config['selectedID'] = sid
        service['managerBinary'] = str(executable(app))
        service['enginePath'] = str(app / 'Contents/MacOS/flow-engine')
        service['focusFile'] = str(DATA / 'focus' / (sid + '.json'))
    write_json(config_path, config)
    run([executable(app), '--check-config'])
    patch = ROOT / 'apps/macos/tail-hosting.patch'
    if 'Flow app lifecycle adapter' not in script.read_text():
        run(['/usr/bin/patch', '--dry-run', '-p1', '-i', patch], cwd=root)
        run(['/usr/bin/patch', '-p1', '-i', patch], cwd=root)
    write_json(registry, data)
    write_json(backup / 'migration.json', {'hostingRoot': str(root), 'app': str(app)})
    print('Profiles imported; ingress preserved. Activate with the app Restart control.')
    print('Recovery files:', backup)

def restore_hosting(args):
    backup = DATA / 'migration-backup'
    saved = json.loads((backup / 'migration.json').read_text()); root = Path(saved['hostingRoot'])
    app = Path(saved['app'])
    original = json.loads((backup / 'services.json').read_text())
    for s in original['services']:
        if s.get('kind') != 'typst-always-preview': continue
        subprocess.run([str(executable(app)), '--control', 'stop', s['id']], capture_output=True)
        label = s['launchAgentLabel']; plist = Path.home() / 'Library/LaunchAgents' / (label + '.plist')
        shutil.copy2(backup / plist.name, plist)
    shutil.copy2(backup / 'services.json', root / 'config/services.json')
    shutil.copy2(backup / 'tail-hosting', root / 'bin/tail-hosting')
    for s in original['services']:
        if s.get('kind') == 'typst-always-preview' and s.get('desiredState') == 'running': run([root / 'bin/tail-hosting', 'start', s['id']])
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
    m = sub.add_parser('migrate-tail-hosting'); m.add_argument('root', type=Path); m.add_argument('--app', type=Path, default=DEFAULT_APP); m.set_defaults(func=migrate)
    restore = sub.add_parser('restore-tail-hosting'); restore.set_defaults(func=restore_hosting)
    v = sub.add_parser('verify'); v.add_argument('app', type=Path); v.set_defaults(func=lambda a: print(json.dumps(validate(a.app), indent=2)))
    args = parser.parse_args()
    try: args.func(args)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as e: print(str(e), file=sys.stderr); sys.exit(1)

if __name__ == '__main__': main()
