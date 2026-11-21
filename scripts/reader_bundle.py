#!/usr/bin/env python3
"""Package and verify the HTML Reader bundle published beside the flow engine.

The flow-engine workflow uploads this bundle on an engine cache hit and on a
miss. ``scripts/engine-input-hash.py`` does not hash reader sources, so a
web-only change stays an engine cache hit and still gets a new bundle.

The artifact directory contains ``reader-bundle.json`` and
``reader-bundle.tar``. The tar holds the tracked ``tools/flow-reader`` and
``tools/reader-common`` trees (what ``install.py`` archives, including
``web/``, ``install.py``, ``manage.py``, and the ``web/reader-common``
symlink) plus this verifier. ``bundleChecksum`` is the SHA-256 of the
canonical headSha and per-file records. ``archiveSHA256`` is the SHA-256 of
the tar. Fetching checks the run head SHA, both digests, and every file,
then prints a staging directory. It does not install or restart the reader.
"""

import argparse
import hashlib
import io
import json
import os
import posixpath
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

SCHEMA_VERSION = 1
MANIFEST_NAME = 'reader-bundle.json'
ARCHIVE_NAME = 'reader-bundle.tar'
STABLE_ARTIFACT = 'flow-reader-bundle'
SHA_ARTIFACT_PREFIX = 'reader-bundle-'
BUNDLE_TREES = ('tools/flow-reader', 'tools/reader-common')
VERIFIER_PATH = 'scripts/reader_bundle.py'
REQUIRED_PATHS = (
    'tools/flow-reader/install.py',
    'tools/flow-reader/manage.py',
    VERIFIER_PATH,
)
MAX_FILES = 10000
MAX_ARCHIVE_BYTES = 200 * 1024 * 1024
FILE_MODES = ('100644', '100755', '120000')


def parse_sha(value):
    """Return a 40-character lowercase commit SHA or raise ValueError."""
    text = str(value or '').strip().lower()
    if len(text) != 40 or any(char not in '0123456789abcdef' for char in text):
        raise ValueError('headSha must be 40 lowercase hex characters')
    return text


def parse_digest(value, label):
    text = str(value or '').strip().lower()
    if len(text) != 64 or any(char not in '0123456789abcdef' for char in text):
        raise ValueError(label + ' must be 64 lowercase hex characters')
    return text


def _git(root, args, text=True):
    completed = subprocess.run(
        ['git', '-C', str(root), *args],
        check=False, capture_output=True, text=text,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() if text else completed.stderr.decode(errors='replace').strip()
        raise RuntimeError('git ' + ' '.join(args[:3]) + ' failed: ' + detail)
    return completed.stdout


def validate_rel_path(path):
    """Reject absolute paths, empty parts, and paths outside the bundle trees."""
    if not isinstance(path, str) or not path or path.startswith('/') or '\\' in path:
        raise ValueError('Reader bundle path is not a relative repo path')
    parts = path.split('/')
    if any(part in ('', '.', '..') for part in parts):
        raise ValueError('Reader bundle path is not a relative repo path: ' + path)
    if path == VERIFIER_PATH:
        return path
    if any(path.startswith(tree + '/') for tree in BUNDLE_TREES):
        return path
    raise ValueError('Reader bundle path is outside the reader trees: ' + path)


def link_stays_inside(path, target):
    """Return the normalized link target, or raise if it leaves the bundle."""
    if not isinstance(target, str) or not target or '\x00' in target or '\\' in target or '\n' in target:
        raise ValueError('Unsafe symlink target for ' + path)
    if posixpath.isabs(target):
        raise ValueError('Symlink escapes the reader bundle: ' + path + ' -> ' + target)
    joined = posixpath.normpath(posixpath.join(posixpath.dirname(path), target))
    if joined == '..' or joined.startswith('../') or joined.startswith('/'):
        raise ValueError('Symlink escapes the reader bundle: ' + path + ' -> ' + target)
    return joined


def canonical_bytes(head_sha, files):
    """Bytes whose SHA-256 is ``bundleChecksum``. Order is path order."""
    lines = ['schemaVersion ' + str(SCHEMA_VERSION), 'headSha ' + head_sha]
    ordered = sorted(files, key=lambda item: item['path'])
    seen = set()
    for entry in ordered:
        path = entry['path']
        if path in seen:
            raise ValueError('Reader bundle lists ' + path + ' more than once')
        seen.add(path)
        target = entry.get('target', '')
        lines.append('\t'.join((path, entry['mode'], entry['sha256'], target)))
    return ('\n'.join(lines) + '\n').encode()


def bundle_checksum(head_sha, files):
    return hashlib.sha256(canonical_bytes(head_sha, files)).hexdigest()


def _file_entry(path, mode, blob):
    validate_rel_path(path)
    if mode not in FILE_MODES:
        raise ValueError('Unsupported git mode ' + mode + ' for ' + path)
    digest = hashlib.sha256(blob).hexdigest()
    entry = {'path': path, 'mode': mode, 'sha256': digest, 'bytes': blob}
    if mode == '120000':
        try:
            target = blob.decode('utf-8')
        except UnicodeError as error:
            raise ValueError('Symlink target is not UTF-8: ' + path) from error
        link_stays_inside(path, target)
        entry['target'] = target
    return entry


def collect_entries(root, worktree=False):
    """Read the tracked bundle files from HEAD, not from a dirty worktree."""
    listed = _git(root, ['ls-files', '-s', '-z', '--', *BUNDLE_TREES, VERIFIER_PATH], text=False)
    records = []
    for record in listed.split(b'\0'):
        if not record:
            continue
        meta, separator, raw_path = record.partition(b'\t')
        if not separator:
            raise ValueError('git ls-files returned a record without a path')
        mode, oid, stage = meta.decode().split()
        if stage != '0':
            raise ValueError('Reader bundle requires a fully merged index')
        records.append((mode, oid, raw_path.decode()))
    if len(records) > MAX_FILES:
        raise ValueError('Reader bundle has too many files')
    blobs = _read_blobs(root, [oid for _, oid, _ in records])
    entries = [_file_entry(path, mode, blobs[oid]) for mode, oid, path in records]
    if worktree:
        entries = [_file_entry(item['path'], item['mode'],
            os.fsencode(os.readlink(Path(root) / item['path'])) if item['mode'] == '120000' else (Path(root) / item['path']).read_bytes()) for item in entries]
    entries.sort(key=lambda item: item['path'])
    paths = [entry['path'] for entry in entries]
    if len(paths) != len(set(paths)):
        raise ValueError('Reader bundle lists a path more than once')
    missing = [path for path in REQUIRED_PATHS if path not in paths]
    if missing:
        raise ValueError('Reader bundle is missing ' + ', '.join(missing))
    if not any(path.startswith('tools/flow-reader/web/') for path in paths):
        raise ValueError('Reader bundle is missing tools/flow-reader/web')
    if not any(path.startswith('tools/reader-common/') for path in paths):
        raise ValueError('Reader bundle is missing tools/reader-common')
    return entries


def _read_blobs(root, oids):
    if not oids:
        return {}
    payload = ''.join(oid + '\n' for oid in oids).encode()
    completed = subprocess.run(
        ['git', '-C', str(root), 'cat-file', '--batch'],
        input=payload, capture_output=True, check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.decode(errors='replace').strip()
        raise RuntimeError('git cat-file failed: ' + detail)
    data = completed.stdout
    found = {}
    offset = 0
    for oid in oids:
        newline = data.find(b'\n', offset)
        if newline < 0:
            raise ValueError('git cat-file batch ended early')
        header = data[offset:newline].decode()
        offset = newline + 1
        parts = header.split()
        if len(parts) < 3 or parts[0] != oid or parts[1] != 'blob':
            raise ValueError('Unexpected git object for ' + oid + ': ' + header)
        size = int(parts[2])
        blob = data[offset:offset + size]
        offset += size
        if data[offset:offset + 1] != b'\n':
            raise ValueError('git cat-file batch framing failed')
        offset += 1
        if len(blob) != size:
            raise ValueError('git cat-file returned a short blob for ' + oid)
        found[oid] = blob
    if offset != len(data):
        raise ValueError('git cat-file batch had trailing bytes')
    return found


def manifest_files(entries):
    files = []
    for entry in entries:
        item = {'mode': entry['mode'], 'path': entry['path'], 'sha256': entry['sha256']}
        if entry['mode'] == '120000':
            item['target'] = entry['target']
        files.append(item)
    return files


def write_tar(entries, dest):
    with tarfile.open(dest, 'w', format=tarfile.PAX_FORMAT) as tar:
        for entry in entries:
            info = tarfile.TarInfo(entry['path'])
            info.mtime = 0
            info.uid = 0
            info.gid = 0
            info.uname = ''
            info.gname = ''
            if entry['mode'] == '120000':
                info.type = tarfile.SYMTYPE
                info.linkname = entry['target']
                info.mode = 0o777
                tar.addfile(info)
            else:
                payload = entry['bytes']
                info.type = tarfile.REGTYPE
                info.mode = 0o755 if entry['mode'] == '100755' else 0o644
                info.size = len(payload)
                tar.addfile(info, io.BytesIO(payload))


def dump_manifest(manifest):
    return json.dumps(manifest, indent=2, sort_keys=True) + '\n'


def check_manifest(manifest, expected_head_sha=None):
    """Check the manifest against itself. This does not read the archive."""
    if not isinstance(manifest, dict):
        raise ValueError('Reader bundle manifest must be a JSON object')
    if manifest.get('schemaVersion') != SCHEMA_VERSION:
        raise ValueError('Unsupported reader bundle schema')
    if manifest.get('archive') != ARCHIVE_NAME:
        raise ValueError('Reader bundle archive must be named ' + ARCHIVE_NAME)
    head_sha = parse_sha(manifest.get('headSha'))
    if expected_head_sha is not None and head_sha != parse_sha(expected_head_sha):
        raise ValueError(
            'headSha mismatch: expected ' + parse_sha(expected_head_sha) + ', manifest says ' + head_sha
        )
    archive_sha = parse_digest(manifest.get('archiveSHA256'), 'archiveSHA256')
    files = manifest.get('files')
    if not isinstance(files, list) or not files or len(files) > MAX_FILES:
        raise ValueError('Reader bundle manifest has no usable file list')
    normalized = []
    for item in files:
        if not isinstance(item, dict):
            raise ValueError('Reader bundle file record must be an object')
        allowed = {'mode', 'path', 'sha256', 'target'}
        if not set(item).issubset(allowed):
            raise ValueError('Reader bundle file record has an unknown field')
        path = validate_rel_path(item.get('path'))
        mode = item.get('mode')
        if mode not in FILE_MODES:
            raise ValueError('Unsupported mode for ' + path)
        digest = parse_digest(item.get('sha256'), 'sha256 for ' + path)
        record = {'mode': mode, 'path': path, 'sha256': digest}
        if mode == '120000':
            if 'target' not in item:
                raise ValueError('Symlink record is missing its target: ' + path)
            link_stays_inside(path, item['target'])
            record['target'] = item['target']
        elif 'target' in item:
            raise ValueError('Regular file record must not include a symlink target: ' + path)
        normalized.append(record)
    paths = [item['path'] for item in normalized]
    if len(paths) != len(set(paths)):
        raise ValueError('Reader bundle lists a path more than once')
    for required in REQUIRED_PATHS:
        if required not in paths:
            raise ValueError('Reader bundle is missing ' + required)
    checksum = bundle_checksum(head_sha, normalized)
    recorded = parse_digest(manifest.get('bundleChecksum'), 'bundleChecksum')
    if checksum != recorded:
        raise ValueError('bundleChecksum mismatch: expected ' + checksum + ', manifest says ' + recorded)
    checked = dict(manifest)
    checked['headSha'] = head_sha
    checked['archiveSHA256'] = archive_sha
    checked['bundleChecksum'] = checksum
    checked['files'] = normalized
    return checked


def _member_mode(member):
    if member.issym():
        return '120000'
    if not member.isreg():
        raise ValueError('Reader bundle archive member must be a file or symlink: ' + member.name)
    return '100755' if member.mode & 0o111 else '100644'


def archive_path(name):
    """Canonical relative member path shared by reader and native transport."""
    if (not isinstance(name, str) or not name or name.startswith('/') or '\\' in name
            or any(ord(c) < 32 or ord(c) == 127 for c in name)
            or any(p in ('', '.', '..') for p in name.split('/'))):
        raise ValueError('Unsafe archive path: ' + repr(name))
    return name


def file_digest(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(data)
    return digest.hexdigest()


def _bounded_tar_headers(path, max_entries, max_entry_bytes):
    """Bound even PAX metadata before tarfile can allocate its declared size."""
    with Path(path).open('rb') as stream:
        count = 0
        while True:
            header = stream.read(512)
            if len(header) != 512:
                raise ValueError('Truncated tar header')
            if header == b'\0' * 512:
                if stream.read(512) != b'\0' * 512:
                    raise ValueError('Missing tar end marker')
                if any(any(data) for data in iter(lambda: stream.read(1024 * 1024), b'')):
                    raise ValueError('Trailing nonzero tar data')
                return
            count += 1
            if count > max_entries * 2:
                raise ValueError('Too many archive headers')
            try:
                info = tarfile.TarInfo.frombuf(header, 'utf-8', 'surrogateescape')
            except tarfile.HeaderError as error:
                raise ValueError('Invalid tar header') from error
            if info.type not in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.DIRTYPE,
                                 tarfile.SYMTYPE, tarfile.XHDTYPE):
                raise ValueError('Unsupported archive entry type')
            limit = min(max_entry_bytes, 65536) if info.type == tarfile.XHDTYPE else max_entry_bytes
            if info.size < 0 or info.size > limit:
                raise ValueError('Archive entry exceeds budget')
            stream.seek((info.size + 511) // 512 * 512, 1)


def extract_verified_tar(archive, dest, records, archive_sha256, *, max_archive_bytes,
                         max_entry_bytes, max_total_bytes, max_entries):
    """One bounded archive owner; callers own schemas and atomic publication.

    No extractall/chown, special modes, links-as-parents or pre-existing output.
    Reader records and native transport records share this exact extraction path.
    """
    archive, dest = Path(archive), Path(dest).absolute()
    if archive.is_symlink() or not archive.is_file() or archive.stat().st_size > max_archive_bytes:
        raise ValueError('Invalid archive path or archive budget')
    if file_digest(archive) != archive_sha256:
        raise ValueError('archiveSHA256 mismatch')
    if not records or len(records) > max_entries:
        raise ValueError('Archive inventory count exceeds budget')
    expected = {}
    for record in records:
        name = archive_path(record['path'])
        mode = record['mode']
        if name in expected or type(mode) is not int or not 0 <= mode <= 0o777:
            raise ValueError('Duplicate path or special archive mode')
        if record['kind'] not in ('file', 'directory', 'symlink'):
            raise ValueError('Unknown archive inventory kind')
        if record['kind'] == 'symlink':
            link_stays_inside(name, record['link'])
        expected[name] = record
    for name in expected:
        parents = Path(name).parents
        if any(str(p) in expected and expected[str(p)]['kind'] != 'directory' for p in parents):
            raise ValueError('Archive link/file used as parent')
    _bounded_tar_headers(archive, max_entries, max_entry_bytes)
    # Callers resolve symlinked parents first (macOS /var -> /private/var).
    # This still rejects a dest whose final component is a symlink or otherwise non-canonical.
    if dest.resolve() != dest or dest.is_symlink() or (dest.exists() and any(dest.iterdir())):
        raise ValueError('Archive extraction requires a canonical empty owned output')
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:') as tar:
        members, seen, total = [], set(), 0
        for member in tar:
            name = archive_path(member.name.rstrip('/') if member.isdir() else member.name)
            if name not in expected or name in seen or len(seen) >= max_entries:
                raise ValueError('Archive members differ from inventory or duplicate')
            seen.add(name); record = expected[name]
            kind = 'directory' if member.isdir() else 'symlink' if member.issym() else 'file' if member.isreg() else None
            if (kind != record['kind'] or member.sparse is not None
                    or set(member.pax_headers) - {'path', 'linkpath'}
                    or member.mode != record['mode']):
                raise ValueError('Archive type/mode/header mismatch: ' + name)
            if member.size < 0 or member.size > max_entry_bytes or (kind != 'file' and member.size):
                raise ValueError('Archive entry exceeds budget')
            if kind == 'file':
                total += member.size
                if total > max_total_bytes or ('bytes' in record and member.size != record['bytes']):
                    raise ValueError('Archive total/entry byte budget or size mismatch')
            if kind == 'symlink' and member.linkname != record['link']:
                raise ValueError('Archive symlink mismatch')
            members.append((member, name, record))
        if seen != set(expected):
            raise ValueError('Archive inventory members missing')
        # All files/directories precede symlink creation, including forward links.
        for member, name, record in members:
            path = dest / name
            if record['kind'] == 'directory':
                path.mkdir(parents=True, exist_ok=True)
            elif record['kind'] == 'file':
                path.parent.mkdir(parents=True, exist_ok=True)
                digest, count = hashlib.sha256(), 0
                with tar.extractfile(member) as source, path.open('xb') as output:
                    for data in iter(lambda: source.read(1024 * 1024), b''):
                        count += len(data); digest.update(data); output.write(data)
                if count != member.size or digest.hexdigest() != record['sha256']:
                    raise ValueError('Archive file digest/size mismatch: ' + name)
                path.chmod(record['mode'])
        for member, name, record in members:
            if record['kind'] == 'symlink':
                path = dest / name; path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(record['link'])
        for member, name, record in members:
            if record['kind'] == 'symlink':
                try:
                    resolved = (dest / name).resolve(strict=True)
                except (OSError, RuntimeError) as error:
                    raise ValueError('Missing/cyclic archive symlink') from error
                if not resolved.is_relative_to(dest):
                    raise ValueError('Archive symlink escapes output')
        for member, name, record in reversed(members):
            if record['kind'] == 'directory':
                (dest / name).chmod(record['mode'])
    if file_digest(archive) != archive_sha256:
        raise ValueError('Archive changed after hash/extraction')
    return dest


def extract_archive(archive_path, dest, manifest):
    """Reader schema adapter over the shared bounded tar owner."""
    records = []
    for item in manifest['files']:
        record = {'path':item['path'], 'sha256':item['sha256'],
                  'kind':'symlink' if item['mode'] == '120000' else 'file',
                  'mode':0o777 if item['mode'] == '120000' else 0o755 if item['mode'] == '100755' else 0o644}
        if item['mode'] == '120000':
            record['link'] = item['target']
        records.append(record)
    return extract_verified_tar(archive_path, dest, records, manifest['archiveSHA256'],
        max_archive_bytes=MAX_ARCHIVE_BYTES, max_entry_bytes=MAX_ARCHIVE_BYTES,
        max_total_bytes=MAX_ARCHIVE_BYTES, max_entries=MAX_FILES)

def _walk_files(root):
    found = set()
    root = Path(root)
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        current = Path(dirpath)
        kept = []
        for name in dirnames:
            path = current / name
            if path.is_symlink():
                found.add(path.relative_to(root).as_posix())
            else:
                kept.append(name)
        dirnames[:] = kept
        for name in filenames:
            found.add((current / name).relative_to(root).as_posix())
    return found


def _check_disk_entry(disk, entry):
    path = entry['path']
    if entry['mode'] == '120000':
        if not disk.is_symlink():
            raise ValueError('Reader bundle expected a symlink: ' + path)
        target = os.readlink(disk)
        if target != entry['target']:
            raise ValueError('Symlink target mismatch for ' + path)
        digest = hashlib.sha256(target.encode()).hexdigest()
    else:
        if disk.is_symlink() or not disk.is_file():
            raise ValueError('Reader bundle expected a regular file: ' + path)
        mode = '100755' if disk.stat().st_mode & 0o111 else '100644'
        if mode != entry['mode']:
            raise ValueError('File mode mismatch for ' + path)
        digest = hashlib.sha256(disk.read_bytes()).hexdigest()
    if digest != entry['sha256']:
        raise ValueError('Reader file SHA-256 mismatch for ' + path)


def _entries_under(manifest, trees):
    return {
        item['path']: item for item in manifest['files']
        if any(item['path'] == tree or item['path'].startswith(tree + '/') for tree in trees)
    }


def verify_unpacked_tree(root, manifest=None):
    """Recompute every file hash. ``root`` contains the manifest and the tar files."""
    root = Path(root)
    if manifest is None:
        manifest = load_manifest(root / MANIFEST_NAME)
    manifest = check_manifest(manifest)
    expected = {item['path']: item for item in manifest['files']}
    present = _walk_files(root)
    allowed = set(expected) | {MANIFEST_NAME}
    extra = sorted(present - allowed)
    missing = sorted(set(expected) - present)
    if extra:
        raise ValueError('Reader bundle has an unexpected file: ' + extra[0])
    if missing:
        raise ValueError('Reader bundle is missing ' + missing[0])
    for path, entry in expected.items():
        _check_disk_entry(root / path, entry)
    return manifest


def verify_copied_trees(root, manifest, trees=BUNDLE_TREES):
    """Check a copy of the reader trees against the manifest, including extra files."""
    root = Path(root)
    manifest = check_manifest(manifest)
    expected = _entries_under(manifest, trees)
    if not expected:
        raise ValueError('Reader bundle manifest has no files in the copied trees')
    present = {
        path for path in _walk_files(root)
        if any(path == tree or path.startswith(tree + '/') for tree in trees)
    }
    extra = sorted(present - set(expected))
    missing = sorted(set(expected) - present)
    if extra:
        raise ValueError('Copied reader tree has an unexpected file: ' + extra[0])
    if missing:
        raise ValueError('Copied reader tree is missing ' + missing[0])
    for path, entry in expected.items():
        _check_disk_entry(root / path, entry)
    return manifest


def materialize(manifest, archive_path, dest):
    """Extract a checked manifest into ``dest`` and verify the tree."""
    manifest = check_manifest(manifest)
    dest = Path(dest)
    # Parent components may have been reached through a symlink (macOS /var -> /private/var).
    # Resolve those before extraction. The final component stays unchanged, so a symlink
    # dest is still rejected as non-canonical.
    dest = dest.parent.resolve() / dest.name
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    extract_archive(archive_path, dest, manifest)
    (dest / MANIFEST_NAME).write_text(dump_manifest(manifest))
    return verify_unpacked_tree(dest, manifest)


def load_manifest(path):
    try:
        manifest = json.loads(Path(path).read_text())
    except json.JSONDecodeError as error:
        raise ValueError('Reader bundle manifest is not JSON') from error
    return check_manifest(manifest)


def package_reader_bundle(root, head_sha, output, worktree=False):
    """Write the artifact directory for ``head_sha`` and self-check it."""
    root = Path(root)
    output = Path(output)
    head_sha = parse_sha(head_sha)
    actual = _git(root, ['rev-parse', 'HEAD']).strip()
    if actual != head_sha:
        raise ValueError('HEAD ' + actual + ' does not match headSha ' + head_sha)
    entries = collect_entries(root, worktree=worktree)
    files = manifest_files(entries)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    archive = output / ARCHIVE_NAME
    try:
        write_tar(entries, archive)
        archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        manifest = {
            'archive': ARCHIVE_NAME,
            'archiveSHA256': archive_sha,
            'bundleChecksum': bundle_checksum(head_sha, files),
            'files': files,
            'headSha': head_sha,
            'schemaVersion': SCHEMA_VERSION,
        }
        (output / MANIFEST_NAME).write_text(dump_manifest(manifest))
        with tempfile.TemporaryDirectory(prefix='reader-bundle-check-') as temporary:
            # Resolve the temp directory (macOS /var -> /private/var). 'tree' is a real
            # final component, so the canonical-output check still sees a non-symlink dest.
            materialize(load_manifest(output / MANIFEST_NAME), archive, Path(temporary).resolve() / 'tree')
    except Exception:
        shutil.rmtree(output, ignore_errors=True)
        raise
    _summarize(manifest, len(files))
    return manifest


def _summarize(manifest, count):
    print(
        'reader-bundle: ' + manifest['headSha']
        + ' files ' + str(count)
        + ' bundleChecksum ' + manifest['bundleChecksum']
        + ' archiveSHA256 ' + manifest['archiveSHA256'],
        file=sys.stderr,
    )
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if not path:
        return
    with open(path, 'a', encoding='utf-8') as handle:
        handle.write('### flow-reader-bundle\n\n')
        handle.write('- Artifact: `reader-bundle-' + manifest['headSha'] + '` and `flow-reader-bundle`\n')
        handle.write('- headSha: `' + manifest['headSha'] + '`\n')
        handle.write('- bundleChecksum: `' + manifest['bundleChecksum'] + '`\n')
        handle.write('- archiveSHA256: `' + manifest['archiveSHA256'] + '`\n')
        handle.write('- Files: ' + str(count) + '\n\n')


def default_staging(head_sha, home=None, platform=None):
    home = Path.home() if home is None else Path(home)
    platform = sys.platform if platform is None else platform
    if platform == 'darwin':
        base = home / 'Library/Caches/Lagrangian/reader-bundles'
    else:
        base = home / '.cache/lagrangian/reader-bundles'
    return base / parse_sha(head_sha)


def assert_not_installed_reader(dest, home=None):
    """Refuse to unpack into the installed app, its data, or the legacy app data."""
    # Resolve home first so a symlinked parent (macOS /var -> /private/var) still matches dest.
    home = (Path.home() if home is None else Path(home)).resolve()
    resolved = Path(dest).expanduser().resolve()
    roots = (
        home / 'Library/Application Support/Lagrangian',
        home / 'Library/Application Support/tinymist-flow',
        home / 'Applications',
    )
    for root in roots:
        if resolved == root or root in resolved.parents:
            raise ValueError('Refusing to unpack a reader bundle into installed application data: ' + str(resolved))
    return resolved


def _flow_runs():
    """Load the shared run selector from this file's directory, including a staged copy."""
    scripts = Path(__file__).resolve().parent
    if str(scripts) not in sys.path:
        sys.path.insert(0, str(scripts))
    import flow_engine_runs
    return flow_engine_runs


def default_gh(args):
    return _flow_runs().invoke_gh(args)


def select_run(gh, repo, run_id=None, head_sha=None, branch=None):
    """Resolve a run with the shared flow-engine selector."""
    return _flow_runs().select_run(repo, run_id=run_id, head_sha=head_sha, branch=branch, runner=gh)


def locate_bundle(download):
    manifests = [path for path in Path(download).rglob(MANIFEST_NAME) if path.is_file()]
    if len(manifests) != 1:
        raise ValueError('The downloaded artifact must contain one ' + MANIFEST_NAME)
    archive = manifests[0].parent / ARCHIVE_NAME
    if not archive.is_file():
        raise ValueError('The downloaded artifact must contain ' + ARCHIVE_NAME + ' beside the manifest')
    return manifests[0], archive


def download_bundle(gh, repo, run_id, head_sha):
    """Download the sha-named artifact, then the stable name if that name is absent."""
    errors = []
    for name in (SHA_ARTIFACT_PREFIX + head_sha, STABLE_ARTIFACT):
        # mkdtemp inherits a symlinked TMPDIR on macOS (/var -> /private/var).
        temporary = Path(tempfile.mkdtemp(prefix='reader-bundle-download-')).resolve()
        try:
            gh(['run', 'download', str(run_id), '--repo', repo, '--name', name, '--dir', str(temporary)])
            return temporary, name
        except (RuntimeError, OSError, ValueError) as error:
            errors.append(name + ': ' + str(error))
            shutil.rmtree(temporary, ignore_errors=True)
    raise RuntimeError('Could not download a reader bundle for run ' + str(run_id) + ': ' + '; '.join(errors))


def assert_staging_replaceable(dest):
    """Allow a missing, empty, or previous-bundle directory. Leave anything else alone."""
    dest = Path(dest)
    if not dest.exists():
        return
    if not dest.is_dir():
        raise ValueError('Refusing to replace ' + str(dest) + ': not a directory')
    if not any(dest.iterdir()):
        return
    if (dest / MANIFEST_NAME).is_file():
        return
    raise ValueError(
        'Refusing to replace ' + str(dest) + ': it is not empty and has no ' + MANIFEST_NAME
    )


def _replace_staging(incoming, final):
    """Publish ``incoming`` as ``final`` without dropping a previous tree on failure."""
    backup = final.with_name(final.name + '.previous')
    moved = False
    try:
        if backup.exists():
            shutil.rmtree(backup)
        if final.exists():
            os.replace(final, backup)
            moved = True
        os.replace(incoming, final)
    except Exception:
        if moved and backup.exists() and not final.exists():
            os.replace(backup, final)
        raise
    if backup.exists():
        shutil.rmtree(backup, ignore_errors=True)


def fetch_reader_bundle(repo=None, run_id=None, head_sha=None, branch=None, dest=None, gh=None, home=None):
    """Download, verify, and unpack a bundle. Return the staging directory.

    On failure the installed reader is left untouched and ``dest`` is left as
    it was. Stdout is not used; callers print the returned path.
    """
    home = Path.home() if home is None else Path(home)
    if gh is None:
        if shutil.which('gh') is None:
            raise ValueError('gh is required to download the reader bundle. This command does not install the reader.')
        gh = default_gh
    if dest is not None:
        assert_not_installed_reader(dest, home)
    if repo is None:
        described = _flow_runs().json_gh(['repo', 'view', '--json', 'nameWithOwner'], gh)
        if not isinstance(described, dict) or not described.get('nameWithOwner'):
            raise ValueError('gh repo view did not return a repository')
        repo = described['nameWithOwner']
    record = select_run(gh, repo, run_id=run_id, head_sha=head_sha, branch=branch)
    download = None
    incoming = None
    try:
        download, artifact_name = download_bundle(gh, repo, record['databaseId'], record['headSha'])
        manifest_path, archive_path = locate_bundle(download)
        manifest = load_manifest(manifest_path)
        manifest = check_manifest(manifest, expected_head_sha=record['headSha'])
        final = Path(dest).expanduser() if dest is not None else default_staging(record['headSha'], home)
        final = assert_not_installed_reader(final, home)
        final.parent.mkdir(parents=True, exist_ok=True)
        incoming = Path(tempfile.mkdtemp(prefix='.incoming-', dir=final.parent)).resolve()
        materialize(manifest, archive_path, incoming)
        assert_staging_replaceable(final)
        _replace_staging(incoming, final)
        incoming = None
    except Exception:
        if incoming is not None and incoming.exists():
            shutil.rmtree(incoming, ignore_errors=True)
        raise
    finally:
        if download is not None:
            shutil.rmtree(download, ignore_errors=True)
    print(
        'reader-bundle: verified ' + record['headSha'] + ' from run ' + str(record['databaseId'])
        + ' (' + artifact_name + ')',
        file=sys.stderr,
    )
    return final


def detect_failure_message(error):
    return 'reader-bundle: ' + str(error)


def main_package(argv=None):
    parser = argparse.ArgumentParser(description='Package the HTML Reader bundle for the flow-engine workflow.')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--head-sha', required=True)
    parser.add_argument('--worktree', action='store_true', help='Bind current tracked checkout bytes, including local modifications')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        package_reader_bundle(args.root.resolve(), args.head_sha, args.output, worktree=args.worktree)
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as error:
        print(detect_failure_message(error), file=sys.stderr)
        return 1
    print(args.output.expanduser().resolve())
    return 0


def main_fetch(argv=None, gh=None):
    parser = argparse.ArgumentParser(
        description='Download a flow-engine reader bundle, verify it, and print a staging directory. '
                    'Does not install or restart the reader.',
    )
    parser.add_argument(
        '--run-id',
        help='GitHub Actions run id of a successful flow-engine.yml run. '
             'Pass the same id to fetch-engine so the engine and the reader come from one run',
    )
    parser.add_argument('--head-sha', help='Commit whose reader bundle should be staged')
    parser.add_argument('--branch', help='Newest successful flow-engine.yml run on this branch')
    parser.add_argument('--repo', help='GitHub repository (default: gh repo view)')
    parser.add_argument('--dest', type=Path, help='Staging directory (default: a user cache keyed by headSha)')
    args = parser.parse_args(argv)
    if not args.run_id and not args.head_sha and not args.branch:
        print('reader-bundle: pass --run-id, --head-sha, or --branch', file=sys.stderr)
        return 2
    try:
        staged = fetch_reader_bundle(
            repo=args.repo, run_id=args.run_id, head_sha=args.head_sha, branch=args.branch,
            dest=args.dest, gh=gh,
        )
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as error:
        print(detect_failure_message(error), file=sys.stderr)
        return 1
    print(staged.resolve())
    return 0


if __name__ == '__main__':
    sys.exit(main_package())
