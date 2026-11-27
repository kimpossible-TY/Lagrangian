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
CHAT_BASE = '016734db869f8892bf2cd1e330be2fb4edda962f'
CHAT_CORRECTION = '8e57062ea768320c3fe64f266eb50f40f53d16c1'
RUNNER_CORRECTION = 'bb0123aedde56ec83117c217571a77bc7d6614d6'
FIXTURE_CORRECTION = '9ebe1fd44ef00ae4bec0565a7c7157586084a7cd'
REVIEW_CODE = '23513e74eb19b067746f1be5b774b4652e924852'
REVIEW_INPUT = 'ac9450d35c8725abfe625de79f1ab539ef8660ab'
REVIEW_DOCS = 'b8764fbaee9346a2f9ce0c6976b43029ccb8ea5e'
ANCHOR_DELIVERY = '54610a722f355d81bb79acf9dc2e681b7eac4ca9'
REPAIR3_CODE = '00f76c6a59dcfacebf950def09a45fa0c19a2404'
REPAIR3_DOCS = '876f646630f6e3b280621285578e12ca86f5a7b0'
REPAIR3_SWIFT = 'd994b652a1e9556058e5f3f0c10b74f7fb99f68d'
REPAIR3_REWORK_SWIFT = 'e345dbfa4de3b72787b3ec6510d2e531442a6fdb'
REPAIR3_C6_SWIFT = '693f2090373d0e3261d28ccd3837b81ec73b1f3b'
REPAIR3_C7_SWIFT = '41fc383c3e2c6e1339b1c9e6f7f425ca266e17e9'
REPAIR3_C8_SWIFT = 'ff6e024099ea14f79f9ca56d9ce8ea2067d67b54'
REPAIR3_C9A_SWIFT = '846a581dd0339ad24cd41023baa43a5b6ae3816a'
REPAIR3_C9B_SWIFT = 'bf7da60ff451801c4116fd43238214f410685b02'
REPAIR3_C10_SWIFT = 'a525249fc96d90289d4436536cda0d1868d4bbb0'
REPAIR3_C11_SWIFT = '96a1d1e584748726c7a699a2fd599dcb402592ae'
REPAIR3_C12_SWIFT = '6aa2ffd55ed75ec6abbd49abba33ad020baa05f2'
REPAIR3_C13_SWIFT = '1d23647c6c4410e29088bec367e6929039642995'
REPAIR3_C14_SWIFT = 'fc4306f0fe0fced54cd5c70d84b791bc1e2251f6'
REPAIR3_C15_SWIFT = 'fdd6f613f5451ecb2ac38660001c16833ee0c5ad'
FOOTNOTE_MERGE = '316417a79562efb6b6162a5802606b98ed4a35da'
PR31_MAC_AUTOUPDATE = 'e0259476cbeea2c0f7bb2977342ea860ac327236'
MINIMAL_REDESIGN_R04 = 'e1751f733772d57f00c0261d49d96a57ed1de57e'
MINIMAL_REDESIGN_R04_V3 = 'f17a02ba871159341b217cef2613a62882ca5e11'
MINIMAL_REDESIGN_R04_V4 = 'd055dba8948e684ba579ae7d5afb07386d482e72'
MINIMAL_REDESIGN_R04_V5 = 'c5c52ad95bf191b2af27885ca93c5bd7073756bb'
MINIMAL_REDESIGN_R04_V6 = 'd17337ed08594affb8df117bd21673881fa3fea9'
RELEASE_RETENTION = '36b05a6a8d6f0febba038e204eabad601a229ca4'
FLOW_READER_SELECTION = '86c8d12de6076dd1989d7981fad1b28a0870caf6'
PR32_MAC_UPDATER = 'edee107b243630d920d7efa8653bd22b7f6d10ea'
FLOW_READER_FOLLOWUP = 'ccb31c9b63741409d078ef0963ede12347dc63b2'
HOME_PDE_INTEGRATION = '40df486581d1b3d71cb7b421e2b85284e3cf9bf1'
XREF_INTEGRATION = 'c033eac8fcbf349cd7c711647e154c52c5bbbdad'
POSTREVIEW_CORRECTION = '44e0aa6f7efd3d08e4390bdc63924b5d60b268c3'
POSTREVIEW_MATH_CHUNK = '9942afbcf8d3860a3bb1ac5f5cffe4924fb78f88'
PR33_REREVIEW = 'd86c625fcb3a9554188309ca08351e8531f61c31'
NATIVE_MATH_RENDER_FIX = '767256c571085e7960b1de3e1c650820f27362af'
WEB_VIEWER_UNIFY = 'c45a45864e28c432021f094c47b581402a791903'
NATIVE_DESIGN_PARITY = '67c56a1b8c25cb1054f4d29ab7331427263d5da0'
TRANSIENT_OBJECT_CLASSIFICATION = 'e655167872306fb69d52c5371f09ab613e3a55ec'
PR34_REVIEW_FOLLOWUP = 'cb326c673abc33fe7e82161b2cfac9e9a8987567'
PR34_TIMEOUT_BUDGET = 'ec9b27ab6164771022cda7eeb700f9a2c3fb8f16'
PR34_THIRD_REVIEW = '085e209f13fb6d294b5588f3592566415a5a6271'
PR34_RESIZE_FIXTURE = '2feb566d6124214c8c40136ac351b13acf98fea9'
CROSS_PROJECT_UNIFY = '876f7d5dd3c6e16479095fd945b84c06df7ba33b'
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
        # Clean HEAD already contains these bytes. Commit only a real dirty
        # delivery overlay in this private clone; mutation tests still commit.
        cls.git('add','--all')
        if cls.git('diff','--cached','--name-only').strip():
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
        fixed = binding['fixedApplicationSources']
        prefix = json.loads(self.git('show', fixed['revision'] + ':' + str(POLICY)))['sourceProvenance']['ownerCorrections']
        corrections = binding['ownerCorrections']
        snapshots = [*corrections[:len(prefix)], fixed, *corrections[len(prefix):]]
        return next(f['sha256'] for c in reversed(snapshots) for f in c['files'] if f['path'] == name)

    def test_na19_fixed_snapshot_is_exact_and_not_head_delegation(self):
        binding = self.binding(); fixed = binding['fixedApplicationSources']
        self.assertEqual(fixed['revision'], '4bd6e0da0d529dafa9993ff8467cac4652bfa2ac')
        self.assertEqual(fixed['baseRevision'], DOCS_CORRECTION)
        expected = set(self.git('diff', '--no-renames', '--name-only', DOCS_CORRECTION, fixed['revision']).splitlines()) - set(owner.DELIVERY_SOURCE_PATHS)
        self.assertEqual({f['path'] for f in fixed['files']}, expected)
        for item in fixed['files']:
            self.assertEqual(item['sha256'], hashlib.sha256(self.git_bytes('show', fixed['revision'] + ':' + item['path'])).hexdigest())
            self.assertEqual(binding['files'][item['path']], self.latest_digest(binding, item['path']))
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

    def test_successor_registered_overlapping_chat_bytes_win(self):
        m = self.binding()
        correction = next(c for c in m['ownerCorrections'] if c['revision'] == CHAT_CORRECTION)
        self.assertEqual(correction['baseRevision'], CHAT_BASE)
        self.assertEqual({f['path'] for f in correction['files']}, set(self.git('diff','--no-renames','--name-only',CHAT_BASE,CHAT_CORRECTION).splitlines()))
        for item in correction['files']:
            self.assertEqual(item['baseSHA256'], hashlib.sha256(self.git_bytes('show', CHAT_BASE+':'+item['path'])).hexdigest() if self.git('ls-tree',CHAT_BASE,'--',item['path']).strip() else None)
            self.assertEqual(item['sha256'], hashlib.sha256(self.git_bytes('show',CHAT_CORRECTION+':'+item['path'])).hexdigest())
            self.assertEqual(m['files'][item['path']],self.latest_digest(m,item['path']))
        for name in ['NativeReaderChatView.swift','NativeReaderWindowController.swift']:
            path = 'apps/macos/'+name
            self.assertEqual(m['files'][path],hashlib.sha256((self.root/path).read_bytes()).hexdigest())

    def test_successor_missing_bad_base_digest_and_ancestry_reject(self):
        for kind in ['missing','base','digest','ancestry']:
            with self.subTest(kind=kind):
                self.setUp()
                def change(m):
                    c=next(c for c in m['ownerCorrections'] if c['revision']==CHAT_CORRECTION)
                    if kind=='missing':m['ownerCorrections'].remove(c)
                    elif kind=='base':c['baseRevision']=DOCS_BASE
                    elif kind=='digest':c['files'][0]['sha256']='0'*64
                    else:c['revision']=self.git('commit-tree',self.git('rev-parse','HEAD^{tree}').strip(),'-m','owned unrelated source').strip()
                self.metadata(change)
                with self.assertRaises((ValueError,subprocess.CalledProcessError)):self.binding()

    def test_fixed_owner_and_historical_bytes_are_distinct(self):
        m=self.binding();c=m['ownerCorrections'][0]
        self.assertEqual(c['revision'],CORRECTION);self.assertEqual(c['baseRevision'],BASE)
        self.assertEqual(len(c['files']),30)
        current=next(x for x in m['ownerCorrections'] if x['revision']==CURRENT_CORRECTION)
        self.assertEqual([x['revision'] for x in m['ownerCorrections']],[CORRECTION,'8744c1b3db0b494f2e36529df281be993ccf11b4','f510fe32337b16906ef355f327e88a8d37fb1b94',CURRENT_CORRECTION,DOCS_CORRECTION,CHAT_CORRECTION,RUNNER_CORRECTION,FIXTURE_CORRECTION,REVIEW_CODE,REVIEW_INPUT,REVIEW_DOCS,REPAIR3_CODE,REPAIR3_DOCS,REPAIR3_SWIFT,REPAIR3_REWORK_SWIFT,REPAIR3_C6_SWIFT,REPAIR3_C7_SWIFT,REPAIR3_C8_SWIFT,REPAIR3_C9A_SWIFT,REPAIR3_C9B_SWIFT,REPAIR3_C10_SWIFT,REPAIR3_C11_SWIFT,REPAIR3_C12_SWIFT,REPAIR3_C13_SWIFT,REPAIR3_C14_SWIFT,REPAIR3_C15_SWIFT,FOOTNOTE_MERGE,PR31_MAC_AUTOUPDATE,MINIMAL_REDESIGN_R04,MINIMAL_REDESIGN_R04_V3,MINIMAL_REDESIGN_R04_V4,MINIMAL_REDESIGN_R04_V5,MINIMAL_REDESIGN_R04_V6,RELEASE_RETENTION,FLOW_READER_SELECTION,PR32_MAC_UPDATER,FLOW_READER_FOLLOWUP,HOME_PDE_INTEGRATION,XREF_INTEGRATION,POSTREVIEW_CORRECTION,POSTREVIEW_MATH_CHUNK,PR33_REREVIEW,NATIVE_MATH_RENDER_FIX,WEB_VIEWER_UNIFY,NATIVE_DESIGN_PARITY,TRANSIENT_OBJECT_CLASSIFICATION,PR34_REVIEW_FOLLOWUP,PR34_TIMEOUT_BUDGET,PR34_THIRD_REVIEW,PR34_RESIZE_FIXTURE,CROSS_PROJECT_UNIFY])
        for revision, count in [(POSTREVIEW_CORRECTION, 27), (POSTREVIEW_MATH_CHUNK, 2), (NATIVE_MATH_RENDER_FIX, 7), (NATIVE_DESIGN_PARITY, 21), (TRANSIENT_OBJECT_CLASSIFICATION, 7), (PR34_REVIEW_FOLLOWUP, 8), (PR34_TIMEOUT_BUDGET, 5), (PR34_THIRD_REVIEW, 5), (PR34_RESIZE_FIXTURE, 1), (CROSS_PROJECT_UNIFY, 17)]:
            self.assertEqual(len(next(x for x in m['ownerCorrections'] if x['revision'] == revision)['files']), count)
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
        m=self.binding();c=next(c for c in m['ownerCorrections'] if c['revision']==DOCS_CORRECTION)
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
                        item=next(c for c in m['ownerCorrections'] if c['revision']==DOCS_CORRECTION)['files'][0]
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
        # Remove this exact historical entry, not a later native correction.
        self.metadata(lambda m:m['ownerCorrections'].remove(next(c for c in m['ownerCorrections'] if c['revision']==DOCS_CORRECTION)))
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
        for name in ['apps/macos/UnregisteredOwner.swift','apps/macos/NativeReaderAccessibility.swift']:
            with self.subTest(path=name):
                self.setUp();p=self.root/name;p.write_text(p.read_text()+'\n// owned later change\n' if p.exists() else '// owned new source\n')
                self.commit()
                with self.assertRaisesRegex(ValueError,'unregistered source changes'):self.binding()

    def test_missing_registered_source_fails(self):
        (self.root/'apps/macos/FlowApp.swift').unlink();self.commit()
        with self.assertRaisesRegex(ValueError,'missing/escaping owner source'):self.binding()

    def test_deleted_delivery_owned_source_fails(self):
        (self.root / 'docs/dev-guide.md').unlink(); self.commit()
        with self.assertRaises(ValueError) as error:
            self.binding()
        self.assertEqual(str(error.exception), 'owner source must be one regular tracked file: docs/dev-guide.md')

    def test_registered_deletion_binds_absence_and_rejects_reappearance(self):
        name = 'apps/macos/CrossProjectReference.swift'
        base = self.git('rev-parse', 'HEAD').strip()
        before = hashlib.sha256((self.root / name).read_bytes()).hexdigest()
        (self.root / name).unlink(); self.commit()
        revision = self.git('rev-parse', 'HEAD').strip()
        self.metadata(lambda m: m['ownerCorrections'].append(dict(revision=revision,
            baseRevision=base, files=[dict(path=name, baseSHA256=before, sha256=None)])))
        binding = self.binding()
        self.assertIsNone(binding['files'][name])
        self.assertIsNone(binding['ownerCorrections'][-1]['files'][0]['sha256'])
        recreation_base = self.git('rev-parse', 'HEAD').strip()
        (self.root / name).write_text('# unexpected reappearance\n'); self.commit()
        with self.assertRaisesRegex(ValueError, 'deleted owner source reappeared'):
            self.binding()
        recreation = self.git('rev-parse', 'HEAD').strip()
        digest = hashlib.sha256((self.root / name).read_bytes()).hexdigest()
        self.metadata(lambda m: m['ownerCorrections'].append(dict(revision=recreation,
            baseRevision=recreation_base, files=[dict(path=name, baseSHA256=None, sha256=digest)])))
        self.assertEqual(self.binding()['files'][name], digest)

    def test_exact_paths_and_unique_inventory_are_required(self):
        for kind in ['missing','duplicate','extra','delivery-path','empty']:
            with self.subTest(kind=kind):
                self.setUp()
                def change(m):
                    files=m['ownerCorrections'][-1]['files']
                    if kind=='missing':files.pop()
                    elif kind=='duplicate':files.append(copy.deepcopy(files[0]))
                    elif kind=='extra':files.append({'path':'apps/macos/NativeReaderAccessibility.swift','baseSHA256':'0'*64,'sha256':'1'*64})
                    elif kind=='delivery-path':files.append({'path':'scripts/flow-app.py','baseSHA256':'0'*64,'sha256':'1'*64})
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
        self.assertEqual(m['ownerCorrections'][-1]['revision'],CROSS_PROJECT_UNIFY)
        self.assertIn('tests/flow-app/test_reader_bundle.py', owner.DELIVERY_SOURCE_PATHS)
        # Guide anchor corrections belong to the existing delivery owner.
        # Native correction inventory forbids these paths; exact HEAD blobs
        # still bind both canonical input and generated Markdown.
        guide_paths = {'docs/tinymist/flow-app.typ', 'docs/tinymist/flow-app.md'}
        self.assertEqual(set(self.git('diff', '--no-renames', '--name-only', ANCHOR_DELIVERY+'^', ANCHOR_DELIVERY).splitlines()), guide_paths)
        self.git('merge-base', '--is-ancestor', ANCHOR_DELIVERY, 'HEAD')
        for name in guide_paths:
            self.assertIn(name, owner.DELIVERY_SOURCE_PATHS)
            historical = hashlib.sha256(self.git_bytes('show', ANCHOR_DELIVERY+':'+name)).hexdigest()
            original = hashlib.sha256(self.git_bytes('show', ANCHOR_DELIVERY+'^:'+name)).hexdigest()
            self.assertNotEqual(historical, original)
            expected = hashlib.sha256(self.git_bytes('show', 'HEAD:'+name)).hexdigest()
            self.assertEqual(m['files'][name], expected)
            self.assertEqual(m['files'][name], hashlib.sha256((self.root/name).read_bytes()).hexdigest())
            self.assertNotEqual(expected, hashlib.sha256(self.git_bytes('show', ANCHOR_DELIVERY+'^:'+name)).hexdigest())
        self.assertFalse(any(f['path'] in guide_paths for c in m['ownerCorrections'] for f in c['files']))

        # Actual mixed commit: delivery bytes stay HEAD-owned and every other
        # path keeps its original and corrected fixed Git-object digest.
        correction=next(c for c in m['ownerCorrections'] if c['revision']==REVIEW_CODE)
        changes=set(self.git('diff','--no-renames','--name-only',correction['baseRevision'],REVIEW_CODE).splitlines())
        self.assertIn('scripts/flow-app.py',changes)
        self.assertEqual({f['path'] for f in correction['files']},changes-set(owner.DELIVERY_SOURCE_PATHS))
        for item in correction['files']:
            self.assertEqual(item['sha256'],hashlib.sha256(self.git_bytes('show',REVIEW_CODE+':'+item['path'])).hexdigest())
        self.assertEqual(m['files']['scripts/flow-app.py'],hashlib.sha256((self.root/'scripts/flow-app.py').read_bytes()).hexdigest())
        self.assertEqual(next(c for c in m['ownerCorrections'] if c['revision']==DOCS_CORRECTION)['baseRevision'],DOCS_BASE)

    def test_legal_guide_followup_preserves_historical_anchor_proof(self):
        for name, note in [('docs/tinymist/flow-app.typ', '\n// Legal delivery-owned guide follow-up.\n'),
                           ('docs/tinymist/flow-app.md', '\n<!-- Legal delivery-owned guide follow-up. -->\n')]:
            path = self.root/name
            path.write_text(path.read_text()+note)
        self.commit()
        current = self.binding()
        for name in ['docs/tinymist/flow-app.typ', 'docs/tinymist/flow-app.md']:
            self.assertEqual(current['files'][name], hashlib.sha256((self.root/name).read_bytes()).hexdigest())
            self.assertNotEqual(current['files'][name], hashlib.sha256(self.git_bytes('show', ANCHOR_DELIVERY+':'+name)).hexdigest())
        self.test_explicit_delivery_edit_keeps_fixed_owner_bytes()

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




class RuntimeSigningBoundaryTests(unittest.TestCase):
    """Fake verified manifests/identity; real private copy and mutation counters. No Keychain."""
    def test_retained_certificate_rejected_before_copy_or_sign(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';(source/'runtime').mkdir(parents=True)
            (source/'runtime/runtime-manifest.json').write_text(json.dumps(dict(source=dict(sourceSHA=owner.RETAINED_RUNTIME_SOURCE['sourceSHA']))))
            m=dict(sourceRevision=CHAT_CORRECTION,signing='ad-hoc',entrypoints=dict(runtime='runtime',node='runtime/node'))
            original=(source/'runtime/runtime-manifest.json').read_bytes()
            with patch.object(owner,'verify',return_value=m),patch.object(owner.shutil,'copytree') as copied,patch.object(owner,'run',side_effect=ValueError('injected signer called')) as sign:
                with self.assertRaisesRegex(ValueError,'retained runtime.*ad-hoc'):
                    owner.copy_signed(source,root/'candidate','FAKE-CERTIFICATE-NO-KEYCHAIN')
                copied.assert_not_called();sign.assert_not_called()
            self.assertEqual(original,(source/'runtime/runtime-manifest.json').read_bytes());self.assertFalse((root/'candidate').exists())

    def test_retained_adhoc_copy_preserves_all_original_bytes(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';(source/'runtime').mkdir(parents=True)
            (source/'runtime/runtime-manifest.json').write_text(json.dumps(dict(source=dict(sourceSHA=owner.RETAINED_RUNTIME_SOURCE['sourceSHA']))))
            (source/'runtime/signed-node').write_bytes(b'fake signed immutable input')
            m=dict(sourceRevision=CHAT_CORRECTION,signing='ad-hoc',entrypoints=dict(runtime='runtime',node='runtime/signed-node'))
            original=owner.inventory(source)
            with patch.object(owner,'verify',return_value=m),patch.object(owner,'run') as sign:
                owner.copy_signed(source,root/'candidate','-',development=True);sign.assert_not_called()
            self.assertEqual(owner.inventory(source),original);self.assertEqual(owner.inventory(root/'candidate'),original)

    def test_current_source_runtime_keeps_private_certificate_resigning_path(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);source=root/'source';(source/'runtime').mkdir(parents=True)
            (source/'runtime/runtime-manifest.json').write_text(json.dumps(dict(source=dict(sourceSHA=CHAT_CORRECTION))))
            m=dict(sourceRevision=CHAT_CORRECTION,signing='ad-hoc',entrypoints=dict(runtime='runtime',node='runtime/node'))
            original=owner.inventory(source)
            with patch.object(owner,'verify',return_value=m),patch.object(owner,'run') as commands,patch.object(owner,'sign_images',return_value=[]):
                owner.copy_signed(source,root/'candidate','FAKE-CERTIFICATE-NO-KEYCHAIN')
                self.assertTrue(any('--sign' in list(map(str,c.args[0])) for c in commands.call_args_list))
            self.assertEqual(owner.inventory(source),original)


if __name__=='__main__':unittest.main()
