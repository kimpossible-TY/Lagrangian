"""Fixed-source provenance only: private git copies, no Swift/app/runtime production."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
POLICY = Path('tools/flow-reader/native/runtime/backend-delivery.json')
# Snapshot the actual assembled input, then overlay only explicit delivery-owned working bytes.
INPUT = subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip()
CURRENT_CORRECTION = '8744c1b3db0b494f2e36529df281be993ccf11b4'
CURRENT_BASE = '09e78630a6afb51436e45da140c3588c82c295f5'
CORRECTION = '338304a374bdd75ba76151a34bc8c284510ce725'
BASE = '09c5186bff1850b17f6e85fe2f3115153520bc94'
spec = importlib.util.spec_from_file_location('native_source_binding', ROOT/'scripts/stage-native-reader-delivery.py')
owner = importlib.util.module_from_spec(spec); spec.loader.exec_module(owner)


class FixedSourceBinding(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='native-source-binding-')
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name).resolve()/'checkout'
        cls.env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
            GIT_AUTHOR_NAME='Owned binding fixture', GIT_COMMITTER_NAME='Owned binding fixture',
            GIT_AUTHOR_EMAIL='binding-fixture@invalid', GIT_COMMITTER_EMAIL='binding-fixture@invalid')
        subprocess.run(['git','clone','--quiet','--shared','--no-checkout',str(ROOT),str(cls.root)],env=cls.env,check=True)
        cls.git('checkout','--quiet',INPUT)
        for name in owner.DELIVERY_SOURCE_PATHS:
            shutil.copy2(ROOT/name,cls.root/name)
        cls.commit()
        cls.fixed = cls.git('rev-parse','HEAD').strip()

    @classmethod
    def git(cls,*args):
        return subprocess.check_output(['git','-C',str(cls.root),'-c','core.hooksPath=/dev/null',*args],env=cls.env,text=True)

    @classmethod
    def git_bytes(cls,*args):
        return subprocess.check_output(['git','-C',str(cls.root),*args],env=cls.env)

    @classmethod
    def commit(cls):
        cls.git('add','--all');cls.git('commit','--quiet','-m','test: owned source binding fixture')

    def setUp(self):
        # Destructive restoration is restricted to this class's newly owned copy.
        self.assertTrue(self.root.is_relative_to(Path(self.temp.name).resolve()))
        self.assertNotEqual(self.root,ROOT)
        self.git('reset','--hard','--quiet',self.fixed);self.git('clean','-fd','--quiet')

    def metadata(self,change):
        p=self.root/POLICY;m=json.loads(p.read_text());change(m['sourceProvenance'])
        p.write_text(json.dumps(m,indent=2)+'\n');self.commit()

    def binding(self):return owner.integrated_sources(self.root)

    def test_fixed_owner_and_historical_bytes_are_distinct(self):
        m=self.binding();c=m['ownerCorrections'][0]
        self.assertEqual(c['revision'],CORRECTION);self.assertEqual(c['baseRevision'],BASE)
        self.assertEqual(len(c['files']),30)
        current=m['ownerCorrections'][-1]
        self.assertEqual([x['revision'] for x in m['ownerCorrections']],[CORRECTION,CURRENT_CORRECTION])
        self.assertEqual(current['baseRevision'],CURRENT_BASE)
        expected=set(self.git('diff','--no-renames','--name-only',CURRENT_BASE,CURRENT_CORRECTION).splitlines())
        self.assertEqual(len(expected),15);self.assertEqual({f['path'] for f in current['files']},expected)
        for item in current['files']:
            self.assertEqual(item['baseSHA256'],hashlib.sha256(self.git_bytes('show',CURRENT_BASE+':'+item['path'])).hexdigest())
            self.assertEqual(item['sha256'],hashlib.sha256(self.git_bytes('show',CURRENT_CORRECTION+':'+item['path'])).hexdigest())
            self.assertEqual(m['files'][item['path']],item['sha256'])
        historical=json.loads(self.git('show','708ea0fd6ecb143ad4da27e149f16497fac8115a:'+str(POLICY)))['sourceProvenance']['ownerCorrections'][0]
        self.assertEqual([{k:v for k,v in f.items() if k!='overrides'} for f in c['files']],historical['files'])

        path='apps/macos/FlowApp.swift';item=next(f for f in c['files'] if f['path']==path)
        self.assertEqual(m['files'][path],item['sha256'])
        self.assertNotEqual(item['sha256'],item['baseSHA256'])
        self.assertTrue(any(x['sha256']!=item['sha256'] for x in item['overrides']))
        gui=next(x for x in m['historicalSources'] if x['role']=='gui')
        self.assertNotEqual(gui['files'][path],m['files'][path])
        self.assertEqual(m['historicalBaseRevision'],'9b2dc87651eb16a809bb48dbe4539614cfe30d6a')
        self.assertNotIn('tests/flow-app/native-reader-app/test_original_pages.py',m['deliveryOwnedOverrides'])

    def test_metadata_is_part_of_existing_source_binding(self):
        fields=owner.source_binding(self.root)
        self.assertEqual(fields[str(POLICY)],hashlib.sha256((self.root/POLICY).read_bytes()).hexdigest())
        self.assertEqual(fields['scripts/stage-native-reader-delivery.py'],hashlib.sha256((self.root/'scripts/stage-native-reader-delivery.py').read_bytes()).hexdigest())

    def test_dirty_current_source_fails(self):
        with (self.root/'apps/macos/FlowApp.swift').open('a') as f:f.write('\n// owned drift\n')
        with self.assertRaisesRegex(ValueError,'clean checkout'):self.binding()

    def test_committed_drift_cannot_be_accepted_by_old_correction(self):
        # Actual8744 sources must fail under the preserved old338-only inventory.
        self.metadata(lambda m:m['ownerCorrections'].pop())
        with self.assertRaisesRegex(ValueError,'owner source drift'):self.binding()
        self.setUp()
        with (self.root/'apps/macos/FlowApp.swift').open('a') as f:f.write('\n// owned newer source\n')
        self.commit()
        with self.assertRaisesRegex(ValueError,'owner source drift'):self.binding()

    def test_new_path_or_other_native_source_needs_explicit_registration(self):
        for name in ['apps/macos/UnregisteredOwner.swift','apps/macos/NativeReaderDocument.swift']:
            with self.subTest(path=name):
                self.setUp();p=self.root/name;p.write_text(p.read_text()+'\n// owned later change\n' if p.exists() else '// owned new source\n')
                self.commit()
                with self.assertRaisesRegex(ValueError,'unregistered source changes'):self.binding()

    def test_missing_registered_source_fails(self):
        (self.root/'apps/macos/FlowApp.swift').unlink();self.commit()
        with self.assertRaisesRegex(ValueError,'missing/escaping owner source'):self.binding()

    def test_exact_paths_and_unique_inventory_are_required(self):
        for kind in ['missing','duplicate','extra','empty']:
            with self.subTest(kind=kind):
                self.setUp()
                def change(m):
                    files=m['ownerCorrections'][-1]['files']
                    if kind=='missing':files.pop()
                    elif kind=='duplicate':files.append(copy.deepcopy(files[0]))
                    elif kind=='extra':files.append({'path':'apps/macos/NativeReaderDocument.swift','baseSHA256':'0'*64,'sha256':'1'*64})
                    else:files.clear()
                self.metadata(change)
                with self.assertRaises(ValueError):self.binding()

    def test_original_corrected_or_rehashed_current_digest_mix_fails(self):
        for kind in ['swapped','corrected-as-original','rehash-current']:
            with self.subTest(kind=kind):
                self.setUp()
                if kind=='rehash-current':
                    with (self.root/'apps/macos/NativeReaderSession.swift').open('a') as f:f.write('\n// owned tamper\n')
                def change(m):
                    item=next(f for f in m['ownerCorrections'][-1]['files'] if f['path']=='apps/macos/NativeReaderSession.swift')
                    if kind=='swapped':item['baseSHA256'],item['sha256']=item['sha256'],item['baseSHA256']
                    elif kind=='corrected-as-original':item['baseSHA256']=item['sha256']
                    else:item['sha256']=hashlib.sha256((self.root/item['path']).read_bytes()).hexdigest()
                self.metadata(change)
                with self.assertRaisesRegex(ValueError,'original/corrected digest mismatch'):self.binding()

    def test_nonancestor_owner_is_rejected(self):
        orphan=self.git('commit-tree',self.git('rev-parse','HEAD^{tree}').strip(),'-m','owned negative orphan').strip()
        self.metadata(lambda m:m['ownerCorrections'][0].update(revision=orphan))
        with self.assertRaises(ValueError):self.binding()

    def test_full_revisions_schema_and_baseline_are_required(self):
        for kind in ['short','HEAD','baseline','missing','duplicate-revision']:
            with self.subTest(kind=kind):
                self.setUp()
                def change(m):
                    if kind in ['short','HEAD']:m['ownerCorrections'][0]['revision']=CORRECTION[:8] if kind=='short' else 'HEAD'
                    elif kind=='baseline':m['baselineRevision']=CORRECTION
                    elif kind=='missing':m['ownerCorrections']=[]
                    else:m['ownerCorrections'].append(copy.deepcopy(m['ownerCorrections'][0]))
                self.metadata(change)
                with self.assertRaises(ValueError):self.binding()

    def test_explicit_delivery_edit_keeps_fixed_owner_bytes(self):
        p=self.root/'docs/tinymist/dev/native-reader-delivery.typ'
        p.write_text(p.read_text()+'\n// owned delivery correction\n');self.commit()
        m=self.binding();self.assertEqual(m['files'][str(p.relative_to(self.root))],hashlib.sha256(p.read_bytes()).hexdigest())
        self.assertEqual(m['ownerCorrections'][0]['revision'],CORRECTION)
        self.assertEqual(m['ownerCorrections'][-1]['revision'],CURRENT_CORRECTION)

    def test_added_file_needs_fixed_inventory_and_explicit_original_absence(self):
        before=self.git('rev-parse','HEAD').strip()
        name='owned-fixture-added-source.txt';path=self.root/name
        path.write_text('New file in an isolated mechanism fixture, not a production owner.\n')
        self.commit();fixed=self.git('rev-parse','HEAD').strip()
        with self.assertRaisesRegex(ValueError,'unregistered source changes'):self.binding()
        self.metadata(lambda m:m['ownerCorrections'].append({'revision':fixed,'baseRevision':before,
            'files':[{'path':name,'baseSHA256':None,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}]}))
        m=self.binding();self.assertEqual(m['files'][name],hashlib.sha256(path.read_bytes()).hexdigest())
        self.assertIsNone(m['ownerCorrections'][-1]['files'][0]['baseSHA256'])


if __name__=='__main__':unittest.main()
