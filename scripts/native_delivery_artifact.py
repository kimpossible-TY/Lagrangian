"""Current-run native artifact transport; archive/inventory/publication owners reused.

GitHub zip permissions apply only to two transport files, never the signed tree.
This is not GitHub authority: callers authenticate R/H with flow_engine_runs.
"""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile

import reader_bundle

ARCHIVE = 'native-delivery-artifact.tar'
MANIFEST = 'native-delivery-artifact.json'
CACHE = '.native-transport'
CONTEXT = 'native-delivery-context.json'
FORMAT = 'lagrangian-native-delivery-tar-v1'
MAX_ENTRIES = 30000
MAX_ARCHIVE = 2 * 1024**3
MAX_ENTRY = 256 * 1024**2
MAX_TOTAL = 2 * 1024**3
MAX_MANIFEST = 16 * 1024**2
FIELDS = {'schemaVersion', 'format', 'repository', 'runId', 'sourceRevision', 'archive',
          'archiveSHA256', 'inventorySHA256', 'inventory'}


def owner():
    path = Path(__file__).with_name('stage-native-reader-delivery.py')
    spec = importlib.util.spec_from_file_location('artifact_inventory_owner', path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def checksum(records):
    return hashlib.sha256(owner().encoded(records)).hexdigest()


def inventory(root, *, cached=False):
    """Retain the delivery inventory's exact file/link policy, plus directories."""
    root = Path(root).absolute()
    if root.resolve() != root or root.is_symlink():
        raise ValueError('Artifact root must be canonical')
    excluded = (CACHE, CONTEXT) if cached else ()
    paths = []
    for p in root.rglob('*'):
        if p.relative_to(root).parts[0] in excluded: continue
        if len(paths) >= MAX_ENTRIES: raise ValueError('Artifact inventory entry budget')
        if p.lstat().st_mode & 0o7000: raise ValueError('Special artifact input mode')
        paths.append(p)
    total = 0
    for p in paths:
        if p.is_file() and not p.is_symlink():
            size = p.stat().st_size; total += size
            if size > MAX_ENTRY or total > MAX_TOTAL: raise ValueError('Artifact inventory byte budget')
    records = []
    for item in owner().inventory(root, excluded=excluded):
        if cached and (item['path'] == CONTEXT or item['path'].split('/')[0] == CACHE):
            continue
        item = dict(item)
        item['kind'] = 'symlink' if 'link' in item else 'file'
        if item['kind'] == 'symlink': item['mode'] = 0o777
        records.append(item)
    for path in root.rglob('*'):
        if cached and path.relative_to(root).parts[0] == CACHE:
            continue
        if path.is_dir() and not path.is_symlink():
            records.append(dict(path=path.relative_to(root).as_posix(), kind='directory', mode=path.stat().st_mode & 0o7777))
    return sorted(records, key=lambda r:r['path'])


def checked_manifest(path, *, repository=None, run_id=None, head=None):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_MANIFEST:
        raise ValueError('Invalid native transport manifest path/size')
    raw = path.read_bytes(); m = json.loads(raw)
    if (not isinstance(m, dict) or set(m) != FIELDS or type(m['schemaVersion']) is not int
            or m['schemaVersion'] != 1 or m['format'] != FORMAT or m['archive'] != ARCHIVE
            or any(not isinstance(m[k], str) for k in ['sourceRevision', 'runId', 'repository'])
            or not re.fullmatch(r'[0-9a-f]{40}', m['sourceRevision'])
            or not re.fullmatch(r'[1-9][0-9]*', m['runId'])
            or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', m['repository'])):
        raise ValueError('Unknown native transport schema/identity')
    for key in ['archiveSHA256', 'inventorySHA256']:
        reader_bundle.parse_digest(m[key], key)
    for actual, expected in [(m['repository'], repository), (m['runId'], str(run_id) if run_id is not None else None), (m['sourceRevision'], head)]:
        if expected is not None and actual != expected:
            raise ValueError('Native transport R/H/repository mismatch')
    records = m['inventory']
    if not isinstance(records, list) or not records or len(records) > MAX_ENTRIES or checksum(records) != m['inventorySHA256']:
        raise ValueError('Native transport inventory digest/count mismatch')
    names, total = set(), 0
    for r in records:
        if not isinstance(r, dict): raise ValueError('Invalid artifact inventory record')
        name = reader_bundle.archive_path(r.get('path')); mode = r.get('mode'); kind = r.get('kind')
        if name in names or name.split('/')[0] not in {'flow-engine', 'flow-engine.sha256', 'release.json', 'Lagrangian.app'}:
            raise ValueError('Duplicate or unknown artifact root path')
        names.add(name)
        if type(mode) is not int or not 0 <= mode <= 0o777:
            raise ValueError('Special artifact mode')
        keys = {'path', 'kind', 'mode'}
        if kind == 'file':
            keys |= {'sha256', 'bytes'}
            if type(r.get('bytes')) is not int or not 0 <= r['bytes'] <= MAX_ENTRY:
                raise ValueError('Artifact entry byte budget')
            total += r['bytes']; reader_bundle.parse_digest(r.get('sha256'), name)
        elif kind == 'symlink':
            keys |= {'sha256', 'link'}
            reader_bundle.link_stays_inside(name, r.get('link'))
            if hashlib.sha256(os.fsencode(r['link'])).hexdigest() != r.get('sha256'):
                raise ValueError('Artifact link digest mismatch')
        elif kind != 'directory': raise ValueError('Unknown artifact inventory type')
        if set(r) != keys or total > MAX_TOTAL: raise ValueError('Artifact record fields/total budget')
    roots = {r['path']:r for r in records}
    if any(roots.get(p, {}).get('kind') != 'file' for p in ['flow-engine', 'flow-engine.sha256', 'release.json']):
        raise ValueError('Artifact missing engine contract files')
    if roots.get('Lagrangian.app', {}).get('kind') != 'directory':
        raise ValueError('Artifact missing application directory')
    return m, hashlib.sha256(raw).hexdigest()


def normalized(records):
    # The old fetch contract normalizes only the authenticated external engine.
    return [{**r, 'mode':0o755} if r['path'] == 'flow-engine' else r for r in records]


def binding(root, *, repository=None, run_id=None, head=None, engine_normalized=True):
    root = Path(root)
    stored = root / CACHE
    if stored.is_symlink() or not stored.is_dir() or {p.name for p in stored.iterdir()} != {ARCHIVE, MANIFEST}:
        raise ValueError('Native transport cache missing/ambiguous')
    m, manifest_sha = checked_manifest(stored / MANIFEST, repository=repository, run_id=run_id, head=head)
    archive = stored / ARCHIVE
    if archive.is_symlink() or not archive.is_file() or archive.stat().st_size > MAX_ARCHIVE:
        raise ValueError('Invalid raw native archive')
    if reader_bundle.file_digest(archive) != m['archiveSHA256']:
        raise ValueError('Raw native archive digest drift')
    expected = normalized(m['inventory']) if engine_normalized else m['inventory']
    if inventory(root, cached=True) != expected:
        raise ValueError('Native transport payload inventory drift')
    engine_record = next(r for r in m['inventory'] if r['path'] == 'flow-engine')
    return dict(format=FORMAT, manifestSHA256=manifest_sha, archiveSHA256=m['archiveSHA256'],
                rawInventorySHA256=m['inventorySHA256'], normalizedInventorySHA256=checksum(normalized(m['inventory'])),
                engineBeforeNormalization=engine_record,
                engineAfterNormalization={**engine_record, 'mode':0o755},
                repository=m['repository'], runId=m['runId'], sourceRevision=m['sourceRevision'])


def unpack(download, dest, *, repository=None, run_id=None, head=None):
    """Never fall back to a flat payload when archive input is absent or invalid."""
    # Ancestor symlinks of the download (macOS /var -> /private/var, and /tmp)
    # are canonicalized. The final component stays unresolved, so a symlink
    # wrapper still fails wrapper.resolve() != wrapper. Dest parent
    # canonicalization belongs to extract_verified_tar; resolving all of dest
    # would follow a final-component symlink.
    download = Path(download).absolute()
    download = download.parent.resolve() / download.name
    dest = Path(dest).absolute()
    entries = []
    for p in download.rglob('*'):
        if len(entries) >= 64: raise ValueError('Transport wrapper entry budget')
        entries.append(p)
    manifests = [p for p in entries if p.name == MANIFEST]; archives = [p for p in entries if p.name == ARCHIVE]
    if len(manifests) != 1 or len(archives) != 1 or manifests[0].parent != archives[0].parent:
        raise ValueError('Native transport archive missing/ambiguous (legacy flat format rejected)')
    wrapper = manifests[0].parent
    if {p for p in entries if not (p.is_dir() and not p.is_symlink())} != {manifests[0], archives[0]}:
        raise ValueError('Native transport has unexpected flat/mixed files')
    if wrapper.resolve() != wrapper:
        raise ValueError('Native transport wrapper path escapes')
    m, _ = checked_manifest(manifests[0], repository=repository, run_id=run_id, head=head)
    dest = reader_bundle.extract_verified_tar(archives[0], dest, m['inventory'], m['archiveSHA256'],
        max_archive_bytes=MAX_ARCHIVE, max_entry_bytes=MAX_ENTRY, max_total_bytes=MAX_TOTAL, max_entries=MAX_ENTRIES)
    stored = dest / CACHE; stored.mkdir()
    shutil.copy2(manifests[0], stored / MANIFEST); shutil.copy2(archives[0], stored / ARCHIVE)
    binding(dest, repository=repository, run_id=run_id, head=head, engine_normalized=False)
    return dest


def verify_transport(root):
    """Validate a published wrapper through the same bounded extraction owner."""
    with tempfile.TemporaryDirectory(prefix='.transport-check-', dir=Path(root).parent) as tmp:
        unpack(root, Path(tmp) / 'payload')


def pack(payload, output, *, repository, run_id, head):
    """Publish a verified transport wrapper atomically; preserve prior valid output."""
    payload, output = Path(payload).absolute(), Path(output).absolute()
    o = owner(); records = inventory(payload)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.is_symlink() or output.parent.resolve() != output.parent:
        raise ValueError('Invalid transport publication path')
    if output == payload or output.is_relative_to(payload) or payload.is_relative_to(output):
        raise ValueError('Overlapping transport input/output')
    with tempfile.TemporaryDirectory(prefix='.transport-pack-', dir=output.parent) as tmp:
        candidate = Path(tmp) / 'candidate'; candidate.mkdir(); archive = candidate / ARCHIVE
        with tarfile.open(archive, 'w', format=tarfile.PAX_FORMAT) as tar:
            for r in records:
                info = tarfile.TarInfo(r['path']); info.uid = info.gid = info.mtime = 0; info.mode = r['mode']
                if r['kind'] == 'directory': info.type = tarfile.DIRTYPE; tar.addfile(info)
                elif r['kind'] == 'symlink': info.type = tarfile.SYMTYPE; info.linkname = r['link']; tar.addfile(info)
                else:
                    info.size = r['bytes']
                    with (payload / r['path']).open('rb') as stream:tar.addfile(info, stream)
        m = dict(schemaVersion=1, format=FORMAT, repository=repository, runId=str(run_id), sourceRevision=head,
                 archive=ARCHIVE, archiveSHA256=reader_bundle.file_digest(archive), inventorySHA256=checksum(records), inventory=records)
        o.write(candidate / MANIFEST, m)
        verify_transport(candidate)
        if inventory(payload) != records: raise ValueError('Producer input changed during archive creation')
        o.publish_verified(candidate, output, verify_transport)
    return output


@contextmanager
def reuse_payload(download, *, repository, run_id, head=None):
    """Old flat artifacts may contribute engine-only bytes, never an application."""
    download = Path(download)
    if list(download.rglob(MANIFEST)) or list(download.rglob(ARCHIVE)):
        with tempfile.TemporaryDirectory(prefix='.reuse-archive-', dir=download.parent) as tmp:
            yield unpack(download, Path(tmp) / 'payload', repository=repository, run_id=run_id, head=head)
        return
    candidates = [p.parent for p in download.rglob('flow-engine.sha256') if (p.parent/'flow-engine').is_file() and (p.parent/'release.json').is_file()]
    if len(candidates) != 1: raise ValueError('Legacy engine payload ambiguous')
    payload = candidates[0]
    if payload.resolve() != payload or any((payload/p).is_symlink() for p in ['flow-engine','flow-engine.sha256','release.json']):
        raise ValueError('Legacy engine path/symlink escape')
    if head is not None and json.loads((payload/'release.json').read_text()).get('sourceRevision') != head:
        raise ValueError('Legacy engine run head mismatch')
    yield payload
