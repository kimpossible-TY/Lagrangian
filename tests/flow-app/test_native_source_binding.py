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
CURRENT_CORRECTION = 'd98f6e98cd282450a47cf8ceea9d8fea59145cda'
CURRENT_BASE = 'f510fe32337b16906ef355f327e88a8d37fb1b94'
DOCS_CORRECTION = '72bd0b385d8d71ef4ad7f30d5067e9171493bc05'
DOCS_BASE = '7c98e620ea1480764ac536c578894bf2d12e6cd6'
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

    def latest_digest(self, binding, name):
        snapshots = [*binding['ownerCorrections'], binding['fixedApplicationSources']]
        return next(f['sha256'] for c in reversed(snapshots) for f in c['files'] if f['path'] == name)

    def test_na19_fixed_snapshot_is_exact_and_not_head_delegation(self):
        binding = self.binding(); fixed = binding['fixedApplicationSources']
        self.assertEqual(fixed['revision'], '4bd6e0da0d529dafa9993ff8467cac4652bfa2ac')
        self.assertEqual(fixed['baseRevision'], DOCS_CORRECTION)
        expected = set(self.git('diff', '--no-renames', '--name-only', DOCS_CORRECTION, fixed['revision']).splitlines()) - set(owner.DELIVERY_SOURCE_PATHS)
        self.assertEqual({f['path'] for f in fixed['files']}, expected)
        for item in fixed['files']:
            self.assertEqual(item['sha256'], hashlib.sha256(self.git_bytes('show', fixed['revision'] + ':' + item['path'])).hexdigest())
            self.assertEqual(binding['files'][item['path']], item['sha256'])
        for name in ['NativeAppDesign.swift', 'NativeBrandMark.swift', 'NativeFloatingCapsule.swift']:
            self.assertEqual(json.loads((self.root/'apps/macos/sources.json').read_text())['native'].count(name), 1)
        self.assertNotIn('apps/macos/FlowApp.swift', owner.DELIVERY_SOURCE_PATHS)

    def test_retained_runtime_requires_exact_original_manifest_and_source(self):
        manifest = dict(source=copy.deepcopy(owner.RETAINED_RUNTIME_SOURCE))
        owner.runtime_source_binding(manifest, owner.RETAINED_RUNTIME_MANIFEST, INPUT)
        for field in ['hash', 'revision', 'dirty', 'input']:
            altered = copy.deepcopy(manifest); digest = owner.RETAINED_RUNTIME_MANIFEST
            if field == 'hash': digest = '0' * 64
            elif field == 'revision': altered['source']['sourceSHA'] = 'f' * 40
            elif field == 'dirty': altered['source']['dirty'] = 'M source'
            else: altered['source']['sourceFiles'][0]['sha256'] = '0' * 64
            with self.subTest(field=field), self.assertRaises(ValueError):
                owner.runtime_source_binding(altered, digest, INPUT)

    def test_fixed_owner_and_historical_bytes_are_distinct(self):
        m=self.binding();c=m['ownerCorrections'][0]
        self.assertEqual(c['revision'],CORRECTION);self.assertEqual(c['baseRevision'],BASE)
        self.assertEqual(len(c['files']),30)
        current=next(x for x in m['ownerCorrections'] if x['revision']==CURRENT_CORRECTION)
        self.assertEqual([x['revision'] for x in m['ownerCorrections']],[CORRECTION,'8744c1b3db0b494f2e36529df281be993ccf11b4','f510fe32337b16906ef355f327e88a8d37fb1b94',CURRENT_CORRECTION,DOCS_CORRECTION])
        self.assertEqual(current['baseRevision'],CURRENT_BASE)
        expected=set(self.git('diff','--no-renames','--name-only',CURRENT_BASE,CURRENT_CORRECTION).splitlines())
        self.assertEqual(len(expected),28);self.assertEqual({f['path'] for f in current['files']},expected)
        for item in current['files']:
            self.assertEqual(item['baseSHA256'],hashlib.sha256(self.git_bytes('show',CURRENT_BASE+':'+item['path'])).hexdigest())
            self.assertEqual(item['sha256'],hashlib.sha256(self.git_bytes('show',CURRENT_CORRECTION+':'+item['path'])).hexdigest())
            latest=next(f for x in reversed(m['ownerCorrections']) for f in x['files'] if f['path']==item['path'])
            self.assertEqual(m['files'][item['path']],self.latest_digest(m,item['path']))
        historical=json.loads(self.git('show','708ea0fd6ecb143ad4da27e149f16497fac8115a:'+str(POLICY)))['sourceProvenance']['ownerCorrections'][0]
        self.assertEqual([{k:v for k,v in f.items() if k!='overrides'} for f in c['files']],historical['files'])

        path='apps/macos/FlowApp.swift';item=next(f for f in c['files'] if f['path']==path)
        self.assertEqual(m['files'][path],self.latest_digest(m,path))
        self.assertNotEqual(item['sha256'],item['baseSHA256'])
        self.assertTrue(any(x['sha256']!=item['sha256'] for x in item['overrides']))
        gui=next(x for x in m['historicalSources'] if x['role']=='gui')
        self.assertNotEqual(gui['files'][path],m['files'][path])
        self.assertEqual(m['historicalBaseRevision'],'9b2dc87651eb16a809bb48dbe4539614cfe30d6a')
        self.assertNotIn('tests/flow-app/native-reader-app/test_original_pages.py',m['deliveryOwnedOverrides'])

    def test_docs_correction_has_exact_fixed_chain_and_bytes(self):
        m=self.binding();c=m['ownerCorrections'][-1]
        self.assertEqual(c['revision'],DOCS_CORRECTION)
        self.assertEqual(c['baseRevision'],DOCS_BASE)
        self.assertEqual(self.git('rev-parse',DOCS_CORRECTION+'^').strip(),DOCS_BASE)
        self.git('merge-base','--is-ancestor',CURRENT_CORRECTION,DOCS_BASE)
        self.git('merge-base','--is-ancestor',DOCS_CORRECTION,'HEAD')
        paths=self.git('diff','--no-renames','--name-only',DOCS_BASE,DOCS_CORRECTION).splitlines()
        self.assertEqual(paths,['docs/tinymist/dev/native-reader-app-contract.typ'])
        self.assertEqual([f['path'] for f in c['files']],paths)
        for item in c['files']:
            self.assertEqual(item['baseSHA256'],hashlib.sha256(self.git_bytes('show',DOCS_BASE+':'+item['path'])).hexdigest())
            self.assertEqual(item['sha256'],hashlib.sha256(self.git_bytes('show',DOCS_CORRECTION+':'+item['path'])).hexdigest())
            self.assertNotEqual(item['baseSHA256'],item['sha256'])
            self.assertEqual(m['files'][item['path']],self.latest_digest(m,item['path']))
        native=next(x for x in m['ownerCorrections'] if x['revision']==CURRENT_CORRECTION)
        self.assertEqual(len(native['files']),28)
        for item in native['files']:
            if item['path'].startswith('apps/macos/'):
                self.assertEqual(m['files'][item['path']],self.latest_digest(m,item['path']))

    def test_docs_correction_cannot_mix_or_hide_unregistered_bytes(self):
        for kind in ['swap','native-path','later-doc-drift']:
            with self.subTest(kind=kind):
                self.setUp()
                if kind=='later-doc-drift':
                    with (self.root/'docs/tinymist/dev/native-reader-app-contract.typ').open('a') as f:f.write('\n// owned unregistered docs drift\n')
                    self.commit()
                else:
                    def change(m):
                        item=m['ownerCorrections'][-1]['files'][0]
                        if kind=='swap':item['baseSHA256'],item['sha256']=item['sha256'],item['baseSHA256']
                        else:item['path']='apps/macos/NativeReaderSession.swift'
                    self.metadata(change)
                with self.assertRaises(ValueError):self.binding()

    def test_metadata_is_part_of_existing_source_binding(self):
        fields=owner.source_binding(self.root)
        self.assertEqual(fields[str(POLICY)],hashlib.sha256((self.root/POLICY).read_bytes()).hexdigest())
        self.assertEqual(fields['scripts/stage-native-reader-delivery.py'],hashlib.sha256((self.root/'scripts/stage-native-reader-delivery.py').read_bytes()).hexdigest())

    def test_dirty_current_source_fails(self):
        with (self.root/'apps/macos/FlowApp.swift').open('a') as f:f.write('\n// owned drift\n')
        with self.assertRaisesRegex(ValueError,'clean checkout'):self.binding()

    def test_committed_drift_cannot_be_accepted_by_old_correction(self):
        # The docs-only correction cannot grant any native-source authority.
        self.metadata(lambda m:m['ownerCorrections'].pop())
        with self.assertRaisesRegex(ValueError,'owner source drift'):self.binding()
        self.setUp()
        self.metadata(lambda m:m.update(ownerCorrections=[x for x in m['ownerCorrections'] if x['revision']!=CURRENT_CORRECTION]))
        with self.assertRaisesRegex(ValueError,'unregistered source changes'):self.binding()
        self.setUp()
        self.metadata(lambda m:m.update(ownerCorrections=m['ownerCorrections'][:1]))
        with self.assertRaisesRegex(ValueError,'unregistered source changes'):self.binding()
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
                    current=next(x for x in m['ownerCorrections'] if x['revision']==CURRENT_CORRECTION)
                    item=next(f for f in current['files'] if f['path']=='apps/macos/NativeReaderSession.swift')
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
        self.assertEqual(m['ownerCorrections'][-1]['revision'],DOCS_CORRECTION)

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
