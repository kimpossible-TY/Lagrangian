"""Bounded native tar transport, using the shared reader archive owner. No Swift/CI."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

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


if __name__=='__main__':unittest.main()
