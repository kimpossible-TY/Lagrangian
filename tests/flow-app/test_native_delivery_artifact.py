"""Bounded native tar transport, using the shared reader archive owner. No Swift/CI."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import zipfile
import urllib.error
from email.message import Message
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import native_delivery_artifact as artifact
import reader_bundle


class NativeArtifactTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='artifact-format-'); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve(); self.payload = self.root/'payload'; self.payload.mkdir()
        (self.payload/'flow-engine').write_bytes(b'authenticated engine fixture'); (self.payload/'flow-engine').chmod(0o644)
        (self.payload/'flow-engine.sha256').write_text(reader_bundle.file_digest(self.payload/'flow-engine'))
        (self.payload/'release.json').write_text('{}')
        app = self.payload/'Lagrangian.app'; (app/'bin').mkdir(parents=True)
        (app/'bin/native').write_bytes(b'signed-bytes fixture'); (app/'bin/native').chmod(0o755)
        (app/'.hidden').write_bytes(b'never omitted'); (app/'.hidden').chmod(0o600)
        (app/'internal').symlink_to('bin')
        self.output = self.root/'transport'; self.head = 'a'*40
        artifact.pack(self.payload, self.output, repository='fixture/repo', run_id='17', head=self.head)
        self.original = self.tree(self.output)

    @staticmethod
    def tree(root):
        return {str(p.relative_to(root)):(p.lstat().st_mode, os.readlink(p) if p.is_symlink() else reader_bundle.file_digest(p) if p.is_file() else None)
                for p in root.rglob('*')}

    def rewrite(self, mutate=None, members=None, raw=None):
        target=self.root/'malformed'; shutil.copytree(self.output,target)
        archive=target/artifact.ARCHIVE; m=json.loads((target/artifact.MANIFEST).read_text())
        if members:
            with tarfile.open(archive,'r:') as tar:
                entries=[(info,tar.extractfile(info).read() if info.isfile() else None) for info in tar]
            data=io.BytesIO()
            with tarfile.open(fileobj=data,mode='w',format=tarfile.PAX_FORMAT) as tar:
                for info,body in members(entries):tar.addfile(info,io.BytesIO(body) if body is not None else None)
            archive.write_bytes(data.getvalue())
        if raw is not None:archive.write_bytes(raw)
        if mutate:mutate(m)
        m['archiveSHA256']=reader_bundle.file_digest(archive);m['inventorySHA256']=artifact.checksum(m['inventory'])
        (target/artifact.MANIFEST).write_text(json.dumps(m));return target

    def reject(self, target):
        with self.assertRaises((ValueError,tarfile.TarError,OSError)):
            artifact.unpack(target,self.root/'rejected',repository='fixture/repo',run_id='17',head=self.head)
        self.assertEqual(self.tree(self.output),self.original)

    def test_lossy_zip_envelope_retains_all_signed_modes_links_and_hidden_bytes(self):
        downloaded=self.root/'download';shutil.copytree(self.output,downloaded)
        for p in downloaded.iterdir():p.chmod(0o644)
        restored=artifact.unpack(downloaded,self.root/'restored',repository='fixture/repo',run_id='17',head=self.head)
        self.assertEqual(artifact.inventory(restored,cached=True),artifact.inventory(self.payload))
        raw=artifact.binding(restored,engine_normalized=False)
        (restored/'flow-engine').chmod(0o755)
        normalized=artifact.binding(restored)
        self.assertEqual(raw,normalized)
        self.assertEqual(raw['engineBeforeNormalization']['mode'],0o644)
        self.assertEqual(raw['engineAfterNormalization']['mode'],0o755)
        self.assertEqual((restored/'Lagrangian.app/internal').readlink(),Path('bin'))
        self.assertEqual((restored/'Lagrangian.app/.hidden').read_bytes(),b'never omitted')

    def test_archive_tamper_missing_legacy_and_mixed_flat_do_not_fallback(self):
        for name in ['tamper','missing','legacy','mixed']:
            with self.subTest(name=name):
                target=self.root/name;shutil.copytree(self.output,target)
                if name=='tamper':
                    with (target/artifact.ARCHIVE).open('ab') as stream:stream.write(b'tamper')
                elif name=='missing':(target/artifact.ARCHIVE).unlink()
                elif name=='legacy':
                    shutil.rmtree(target);shutil.copytree(self.payload,target,symlinks=True)
                else:(target/'flow-engine').write_bytes(b'not a fallback')
                with self.assertRaises(ValueError):artifact.unpack(target,self.root/(name+'-output'))
        self.assertEqual(self.tree(self.output),self.original)

    def test_R_H_repository_and_schema_are_exact(self):
        for kwargs in [dict(run_id='18'),dict(head='b'*40),dict(repository='other/repo')]:
            with self.subTest(kwargs=kwargs),self.assertRaises(ValueError):artifact.unpack(self.output,self.root/'bad',**kwargs)
        self.reject(self.rewrite(lambda m:m.update(schemaVersion=2)))

    def test_duplicate_member_and_special_type_mode_reject(self):
        self.reject(self.rewrite(members=lambda entries:entries+[entries[0]]))
        shutil.rmtree(self.root/'malformed')
        for kind in [tarfile.LNKTYPE,tarfile.CHRTYPE,tarfile.FIFOTYPE]:
            def change(entries):
                for info,data in entries:
                    if info.name=='flow-engine':info.type=kind;info.linkname='release.json';info.size=0;data=None
                    yield info,data
            self.reject(self.rewrite(members=change));shutil.rmtree(self.root/'malformed')
        def special(entries):
            for info,data in entries:
                if info.name=='flow-engine':info.mode=0o4755
                yield info,data
        self.reject(self.rewrite(members=special))

    def test_root_absolute_traversal_duplicate_inventory_and_escape_link_reject(self):
        for bad in ['/', '/absolute','../escape','Lagrangian.app/../escape','Lagrangian.app//escape']:
            def change(m):m['inventory'][0]['path']=bad
            self.reject(self.rewrite(change));shutil.rmtree(self.root/'malformed')
        self.reject(self.rewrite(lambda m:m['inventory'].append(m['inventory'][0])));shutil.rmtree(self.root/'malformed')
        def change(m):
            r=next(r for r in m['inventory'] if r['kind']=='symlink');r['link']='../../../outside';r['sha256']=hashlib.sha256(r['link'].encode()).hexdigest()
        self.reject(self.rewrite(change))

    def test_budgets_and_oversized_pax_before_allocation(self):
        for name in ['MAX_ARCHIVE','MAX_ENTRY','MAX_TOTAL','MAX_ENTRIES']:
            with self.subTest(name=name),patch.object(artifact,name,1),self.assertRaises(ValueError):
                artifact.unpack(self.output,self.root/'oversized')
        header=tarfile.TarInfo('pax');header.type=tarfile.XHDTYPE;header.size=artifact.MAX_ENTRY+1
        self.reject(self.rewrite(raw=header.tobuf()+b'\0'*1024))

    def test_archive_link_parent_and_cyclic_links_reject(self):
        m,_=artifact.checked_manifest(self.output/artifact.MANIFEST)
        records=[*m['inventory'],dict(path='Lagrangian.app/internal/child',kind='file',mode=0o644,bytes=0,sha256=hashlib.sha256(b'').hexdigest())]
        with self.assertRaises(ValueError):reader_bundle.extract_verified_tar(self.output/artifact.ARCHIVE,self.root/'links',records,m['archiveSHA256'],max_archive_bytes=artifact.MAX_ARCHIVE,max_entry_bytes=artifact.MAX_ENTRY,max_total_bytes=artifact.MAX_TOTAL,max_entries=artifact.MAX_ENTRIES)
        def mutate(m):
            r=next(r for r in m['inventory'] if r['kind']=='symlink');r['link']='internal';r['sha256']=hashlib.sha256(b'internal').hexdigest()
        def members(entries):
            for info,data in entries:
                if info.issym():info.linkname='internal'
                yield info,data
        self.reject(self.rewrite(mutate,members))

    def test_raw_digest_replay_and_cached_posthash_drift_reject(self):
        restored=artifact.unpack(self.output,self.root/'restored');(restored/'flow-engine').chmod(0o755)
        before=artifact.binding(restored)
        archive=restored/artifact.CACHE/artifact.ARCHIVE
        with archive.open('ab') as stream:stream.write(b'drift')
        with self.assertRaises(ValueError):artifact.binding(restored)
        archive.write_bytes((self.output/artifact.ARCHIVE).read_bytes())
        (restored/'Lagrangian.app/bin/native').chmod(0o644)
        with self.assertRaises(ValueError):artifact.binding(restored)
        self.assertEqual(before['archiveSHA256'],reader_bundle.file_digest(self.output/artifact.ARCHIVE))

    def test_symlinked_parent_unpacks_and_symlink_wrapper_is_rejected(self):
        base = self.root / 'link-base'
        real_parent = base / 'real-parent'
        real_parent.mkdir(parents=True)
        linked_parent = base / 'linked-parent'
        linked_parent.symlink_to(real_parent, target_is_directory=True)
        download = linked_parent / 'download'
        shutil.copytree(self.output, download)
        dest = linked_parent / 'restored'
        restored = artifact.unpack(download, dest, repository='fixture/repo', run_id='17', head=self.head)
        self.assertEqual(artifact.inventory(restored, cached=True), artifact.inventory(self.payload))
        self.assertEqual(restored, real_parent / 'restored')
        self.assertFalse(restored.is_symlink())

        wrapper = base / 'wrapper-link'
        wrapper.symlink_to(self.output, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'wrapper path escapes'):
            artifact.unpack(wrapper, base / 'escaped', repository='fixture/repo', run_id='17', head=self.head)
        self.assertFalse((base / 'escaped').exists())

        empty = base / 'empty-dest'
        empty.mkdir()
        dest_link = base / 'dest-link'
        dest_link.symlink_to(empty, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'canonical empty owned output'):
            artifact.unpack(download, dest_link, repository='fixture/repo', run_id='17', head=self.head)
        self.assertEqual(list(empty.iterdir()), [])
        self.assertTrue(dest_link.is_symlink())

    def test_producer_rejects_special_input_modes_without_normalizing_them(self):
        for name, mode in [('flow-engine',0o4755),('Lagrangian.app/bin/native',0o2755),('Lagrangian.app/bin',0o1755)]:
            path=self.payload/name; original=path.stat().st_mode&0o7777
            try:
                path.chmod(mode)
                with self.assertRaisesRegex(ValueError,'Special artifact input mode'):
                    artifact.pack(self.payload,self.output,repository='fixture/repo',run_id='17',head=self.head)
                self.assertEqual(path.stat().st_mode&0o7777,mode)
                self.assertEqual(self.tree(self.output),self.original)
            finally:path.chmod(original)

    def test_interruption_and_changed_input_preserve_previous_valid_publication(self):
        with patch.object(tarfile.TarFile,'addfile',side_effect=KeyboardInterrupt),self.assertRaises(KeyboardInterrupt):
            artifact.pack(self.payload,self.output,repository='fixture/repo',run_id='17',head=self.head)
        self.assertEqual(self.tree(self.output),self.original)
        original=artifact.verify_transport
        def drift(path):
            original(path);(self.payload/'Lagrangian.app/.hidden').write_bytes(b'changed during packaging')
        with patch.object(artifact,'verify_transport',drift),self.assertRaises(ValueError):
            artifact.pack(self.payload,self.output,repository='fixture/repo',run_id='17',head=self.head)
        self.assertEqual(self.tree(self.output),self.original)


class ParallelDownloadTests(unittest.TestCase):
    tree = staticmethod(NativeArtifactTests.tree)

    def setUp(self):
        NativeArtifactTests.setUp(self)
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in self.output.iterdir():
                archive.write(file, file.name)
        self.data = data.getvalue()
        self.ranges = []; self.fail_once = False; self.truncate = False; self.accept_ranges = True
        self.range_barrier = None; self.range_lock = threading.Lock(); self.ranges_overlapped = threading.Event()
        self.active_ranges = 0; self.max_active_ranges = 0
        self.auth = []; self.heads = 0; test = self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_HEAD(self):
                test.heads += 1
                test.auth.append(self.headers.get('Authorization'))
                self.send_response(200)
                if test.accept_ranges: self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Content-Length', str(len(test.data))); self.end_headers()
            def do_GET(self):
                test.auth.append(self.headers.get('Authorization'))
                value = self.headers.get('Range'); test.ranges.append(value)
                start, end = map(int, value.removeprefix('bytes=').split('-'))
                with test.range_lock:
                    test.active_ranges += 1
                    test.max_active_ranges = max(test.max_active_ranges, test.active_ranges)
                try:
                    if test.range_barrier and not test.ranges_overlapped.is_set():
                        try: test.range_barrier.wait(timeout=3)
                        except threading.BrokenBarrierError: pass
                    self.send_range(start, end)
                finally:
                    with test.range_lock: test.active_ranges -= 1
            def send_range(self, start, end):
                if test.fail_once:
                    test.fail_once = False; self.send_error(500); return
                body = test.data[start:end + 1]
                self.send_response(206)
                self.send_header('Content-Range', f'bytes {start}-{end}/{len(test.data)}')
                self.send_header('Content-Length', str(len(body))); self.end_headers()
                self.wfile.write(body[:-1] if test.truncate else body)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.addCleanup(self.server.server_close); self.addCleanup(self.thread.join); self.addCleanup(self.server.shutdown)
        self.url = f'http://127.0.0.1:{self.server.server_port}/blob'
        self.dest = self.root/'download'; self.dest.mkdir(); self.fallbacks = []

    def download(self):
        def fallback(args):
            self.fallbacks.append((args, list(self.dest.iterdir())))
            (self.dest/'fallback').write_text('used')
        with patch.object(artifact, '_artifact_url', return_value=self.url), patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY='4'):
            artifact.download_artifact('fixture/repo', '17', 'engine', self.dest, fallback_run=fallback, capture_gh=lambda _: None)

    def test_parallel_deflated_unpack_and_retry(self):
        self.fail_once = True
        self.range_barrier = threading.Barrier(2, action=self.ranges_overlapped.set)
        self.download()
        self.assertFalse(self.fallbacks); self.assertGreaterEqual(len(self.ranges), 5)
        self.assertGreaterEqual(self.max_active_ranges, 2)
        self.assertTrue(all(x is None for x in self.auth))
        restored = artifact.unpack(self.dest, self.root/'restored', repository='fixture/repo', run_id='17', head=self.head)
        self.assertEqual(artifact.inventory(restored, cached=True), artifact.inventory(self.payload))

    def test_preflight_and_truncated_fallback_clean_destination(self):
        for failure in ('preflight', 'truncated'):
            with self.subTest(failure=failure):
                (self.dest/'stale').write_text('old')
                self.accept_ranges = failure != 'preflight'; self.truncate = failure == 'truncated'
                self.download(); self.assertEqual(self.fallbacks[-1][1], [])
                self.assertEqual([p.name for p in self.dest.iterdir()], ['fallback'])
                (self.dest/'fallback').unlink()

    def test_unsafe_zip_falls_back_cleanly(self):
        for name, mode, body in [('../escape', 0, b'x'), ('/absolute', 0, b'x'),
                                 ('link', 0o120777, b'target'), ('large', 0, b'1234')]:
            data = io.BytesIO()
            with zipfile.ZipFile(data, 'w', zipfile.ZIP_DEFLATED) as z:
                info = zipfile.ZipInfo(name); info.external_attr = mode << 16
                z.writestr(info, body)
            self.data = data.getvalue()
            with self.subTest(name=name), patch.object(artifact, 'MAX_ARCHIVE', 3 if name == 'large' else artifact.MAX_ARCHIVE):
                (self.dest/'stale').write_text('old'); self.download()
                self.assertEqual(self.fallbacks[-1][1], [])
                (self.dest/'fallback').unlink()
        self.assertFalse((self.root/'escape').exists())

    def test_zip_uncompressed_byte_and_entry_budgets(self):
        archive = self.root/'budget.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('large', b'x' * 2000)
        with patch.object(artifact, 'MAX_ARCHIVE', 1000), self.assertRaises(ValueError):
            artifact._extract_zip(archive, self.dest)
        with zipfile.ZipFile(archive, 'w') as z:
            for i in range(65): z.writestr(str(i), b'')
        with self.assertRaises(ValueError): artifact._extract_zip(archive, self.dest)
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_concurrency_parsing_and_direct_fallback(self):
        for value, expected in [('garbage', 8), ('-1', 1), ('0', 1), ('1', 1), ('99', 16), ('4', 4)]:
            with patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY=value):
                self.assertEqual(artifact.download_concurrency(), expected)
        with patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY='1'):
            (self.dest/'stale').write_text('old')
            artifact.download_artifact('fixture/repo', '17', 'engine', self.dest,
                fallback_run=lambda args: self.assertEqual(list(self.dest.iterdir()), []),
                capture_gh=lambda _: self.fail('unexpected API'))

    def test_api_redirect_does_not_forward_token(self):
        headers = Message(); headers['Location'] = 'https://blob.example/file'
        class Opener:
            def open(self, request, timeout):
                self_request.append(request)
                raise urllib.error.HTTPError(request.full_url, 302, 'redirect', headers, None)
        self_request = []
        def capture(args):
            if args[1] == 'auth': return 'secret-token'
            return json.dumps([{'artifacts':[{'id': 4, 'name':'engine', 'expired':False}]}])
        local_opener = urllib.request.build_opener()
        blob_requests = []
        def open_blob(request, timeout):
            blob_requests.append(request)
            self.assertEqual(request.full_url, 'https://blob.example/file')
            local = urllib.request.Request(self.url, headers=dict(request.header_items()), method=request.get_method())
            return local_opener.open(local, timeout=timeout)
        with patch.object(artifact.urllib.request, 'build_opener', return_value=Opener()), \
             patch.object(artifact.urllib.request, 'urlopen', side_effect=open_blob), \
             patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY='4'):
            artifact.download_artifact('fixture/repo', '17', 'engine', self.dest,
                fallback_run=lambda _: self.fail('unexpected fallback'), capture_gh=capture)
        self.assertEqual(len(self_request), 1)
        self.assertEqual(self_request[0].host, 'api.github.com')
        self.assertEqual(self_request[0].get_header('Authorization'), 'Bearer secret-token')
        self.assertGreaterEqual(len(blob_requests), 5)
        self.assertTrue(all(request.get_header('Authorization') is None for request in blob_requests))
        self.assertTrue(all(x is None for x in self.auth))
        restored = artifact.unpack(self.dest, self.root/'redirect-restored', repository='fixture/repo', run_id='17', head=self.head)
        self.assertEqual(artifact.inventory(restored, cached=True), artifact.inventory(self.payload))

    def test_package_and_consumer_use_real_parallel_transport(self):
        spec = importlib.util.spec_from_file_location('transport_wiring_package', ROOT / 'scripts/flow-app.py')
        package = importlib.util.module_from_spec(spec); spec.loader.exec_module(package)
        consumer = package.native_delivery_consumer
        real_download = package.download_engine_artifact
        record = {'databaseId': 17, 'headSha': self.head}
        receipt = dict.fromkeys(consumer.FIELDS)
        receipt.update(schemaVersion=2, repository='fixture/repo', runId='17',
                       runHeadSHA=self.head, enginePath=str(self.payload/'flow-engine'))
        (self.payload/consumer.CONTEXT).write_text(json.dumps(receipt))
        owner = Mock()
        owner.read.return_value = receipt
        owner.require.side_effect = lambda condition, message: self.assertTrue(condition, message)
        class ReachedUnpack(Exception): pass
        with patch.object(artifact, '_artifact_url', return_value=self.url), \
             patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY='4'), \
             patch.object(package, 'run', side_effect=AssertionError('fallback called')), \
             patch.object(package, 'capture', return_value=self.head), \
             patch.object(package, 'github_repo', return_value='fixture/repo'), \
             patch.object(package, 'delivery_module', return_value=owner), \
             patch.object(consumer.flow_engine_runs, 'select_run', return_value=record), \
             patch.object(consumer, 'context', side_effect=[receipt, ReachedUnpack()]), \
             patch.object(package, 'download_engine_artifact', wraps=real_download) as download, \
             patch.object(artifact, 'unpack', wraps=artifact.unpack) as unpack:
            with self.assertRaises(ReachedUnpack):
                with consumer.consume(package, self.payload/'flow-engine'):
                    self.fail('consumer should stop after unpack')
        download.assert_called_once()
        self.assertEqual(download.call_args.args[:2], ('fixture/repo', '17'))
        unpack.assert_called_once()
        self.assertEqual(self.heads, 1)
        self.assertEqual(len(self.ranges), 4)
        self.assertTrue(all(value is None for value in self.auth))

    def test_only_expected_failures_fallback_with_sanitized_diagnostic(self):
        token = 'ghs_FAKE_TOKEN_DO_NOT_LEAK'
        message = f'{token} https://blob.example/file?sig=SECRETSIG#fragment suffix'
        errors = [OSError(message), ValueError(message), urllib.error.URLError(message),
                  zipfile.BadZipFile(message), subprocess.CalledProcessError(1, message),
                  json.JSONDecodeError(message, '', 0), KeyError(message)]
        def resolver(repo, run_id, name, capture):
            capture(['gh', 'auth', 'token'])
            raise current_error
        for current_error in errors:
            with self.subTest(error=type(current_error).__name__):
                stderr = io.StringIO(); stdout = io.StringIO(); fallback = Mock()
                with patch.object(artifact, '_artifact_url', side_effect=resolver), \
                     patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY='4'), \
                     patch('sys.stderr', stderr), patch('sys.stdout', stdout):
                    artifact.download_artifact('fixture/repo', '17', 'engine', self.dest,
                                               fallback_run=fallback, capture_gh=lambda _: token)
                fallback.assert_called_once()
                output = stdout.getvalue() + stderr.getvalue()
                safe = str(current_error).replace(token, '[REDACTED]').replace(
                    'https://blob.example/file?sig=SECRETSIG#fragment', 'https://blob.example/file')
                safe = ' '.join(safe.splitlines())
                self.assertEqual(stderr.getvalue(), f'parallel artifact download unavailable: '
                                 f'{type(current_error).__name__}: {safe}; using gh run download\n')
                for secret in (token, 'SECRETSIG', '?', '#fragment'):
                    self.assertNotIn(secret, output)

        for error in (TypeError('programming error'), RuntimeError('programming error'), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__):
                fallback = Mock()
                with patch.object(artifact, '_artifact_url', side_effect=error), \
                     patch.dict(os.environ, FLOW_DOWNLOAD_CONCURRENCY='4'), self.assertRaises(type(error)) as raised:
                    artifact.download_artifact('fixture/repo', '17', 'engine', self.dest,
                                               fallback_run=fallback, capture_gh=lambda _: token)
                self.assertIs(raised.exception, error)
                fallback.assert_not_called()


if __name__=='__main__':unittest.main()
