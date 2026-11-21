"""Real filesystem identity oracle for managed Unicode matching, never an alias mock."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time
import unicodedata
import unittest

REPO = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO/'tools/flow-reader'))
from flow_reader.services.manager import ReaderManager
from flow_reader.services.editor_sync import EditorAttachments
from flow_reader.compiler.project import document_identity
if fixed := os.environ.get('NATIVE_IDENTITY_MANAGER_SOURCE'):
    fixed = Path(fixed).resolve()
    if not any(fixed.is_relative_to(Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output')/name) for name in ('native-reader-identity-ui-v5','native-reader-scope-v8')):
        raise RuntimeError('Frozen source must remain in this task evidence root')
    spec = importlib.util.spec_from_file_location('fixed_identity_manager',fixed)
    module = importlib.util.module_from_spec(spec);sys.modules[spec.name]=module;spec.loader.exec_module(module)
    ReaderManager = module.ReaderManager
_default_output = tempfile.TemporaryDirectory(prefix='native-manager-identity-') if not os.environ.get('NATIVE_IDENTITY_OUTPUT') else None
OUT = Path(os.environ['NATIVE_IDENTITY_OUTPUT']) if _default_output is None else Path(_default_output.name)


def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def spelling(value, form): return unicodedata.normalize(form,str(value))


class NativeManagerIdentity(unittest.TestCase):
    def setUp(self):
        OUT.mkdir(parents=True,exist_ok=True)
        self.evidence=OUT/(self._testMethodName+'-'+str(time.time_ns()));self.evidence.mkdir()
        self.base=Path(tempfile.mkdtemp(prefix='identity-',dir=os.environ['TMPDIR']))
        self.root=self.base/"프로젝트 ' space";self.root.mkdir()
        self.entry="한글 ' main.typ";self.file=self.root/self.entry;self.file.write_text('Owned 한글 é target\n')
        self.profile=dict(id='reader',root=str(self.root),entry=self.entry,port=23625)
        self.profiles=[self.profile]
        self.manager=ReaderManager(self.base/'data',self.base/'agents')
        # Concrete inventory only. Filesystem identity/type/path syscalls are real.
        self.manager.profiles=lambda:self.profiles
        self.original=copy.deepcopy(self.profiles);self.before=sha(self.file)
        self.observations=[]
        self.addCleanup(self.record)

    def record(self):
        def observation(p):
            try:
                s=p.stat();return dict(path=str(p),device=s.st_dev,inode=s.st_ino,mode=s.st_mode,size=s.st_size,isFile=p.is_file(),isDirectory=p.is_dir(),sha256=sha(p) if p.is_file() else None)
            except OSError as e:return dict(path=str(p),error=type(e).__name__)
        self.evidence.joinpath('oracle.json').write_text(json.dumps(dict(root=str(self.root),entry=self.entry,profiles=self.profiles,inventoryUnchanged=self.profiles==self.original,sourceBeforeSHA256=self.before,sourceAfter=observation(self.file),filesystem=[observation(self.root),observation(Path(spelling(self.root,'NFD'))),observation(self.file),observation(Path(spelling(self.file,'NFD')))],observations=self.observations,filesystemCallsMocked=False,GUI=False),ensure_ascii=False,indent=2))

    def test_NFC_NFD_root_entry_real_identity_preserves_registered_spelling(self):
        for root,entry in [(spelling(self.root,'NFD'),spelling(self.entry,'NFC')),(spelling(self.root,'NFC'),spelling(self.entry,'NFD')),(spelling(self.root,'NFD'),spelling(self.entry,'NFD'))]:
            supplied=Path(root)/entry
            self.assertTrue(self.root.samefile(root));self.assertTrue(self.file.samefile(supplied))
            self.assertEqual(sha(supplied),self.before)
            self.observations.append(dict(root=root,entry=entry,sameRoot=True,sameFile=True,resolvedPathsEqual=self.file.resolve()==supplied.resolve(),sha256=sha(supplied)))
            self.assertIs(self.manager.match_document(root,entry),self.profile)
        self.assertEqual(self.profiles,self.original)

    def test_legacy_exact_and_resolved_root_alias_are_substitutable(self):
        self.assertIs(self.manager.match_document(self.root,self.entry),self.profile)
        alias=self.base/'legacy-root-alias';alias.symlink_to(self.root,target_is_directory=True)
        self.assertIs(self.manager.match_document(alias,self.file),self.profile)

    def test_different_roots_names_and_hardlinks_never_grant_a_match(self):
        other=self.base/'other';other.mkdir();(other/self.entry).write_bytes(self.file.read_bytes())
        link=self.root/'different-name.typ';os.link(self.file,link)
        otherlink=other/'same-inode.typ';os.link(self.file,otherlink)
        self.assertTrue(self.file.samefile(link));self.assertTrue(self.file.samefile(otherlink))
        for root,entry in [(other,self.entry),(self.root,link.name),(other,otherlink.name)]:
            with self.subTest(root=str(root),entry=entry),self.assertRaises(ValueError):self.manager.match_document(root,entry)
        self.observations.append(dict(hardlinkSameInode=True,hardlinkDifferentNameRejected=True,otherRootRejected=True))

    def test_ambiguity_rejects_and_explicit_service_preserves_exact_profile(self):
        second={**self.profile,'id':'second','root':spelling(self.root,'NFD'),'entry':spelling(self.entry,'NFD')}
        self.profiles.append(second);self.original=copy.deepcopy(self.profiles)
        with self.assertRaisesRegex(ValueError,'Multiple'):self.manager.match_document(self.root,self.entry)
        self.assertIs(self.manager.match_document(self.root,self.entry,'second'),second)
        self.assertIs(self.manager.match_document(spelling(self.root,'NFD'),self.entry,'reader'),self.profile)
        with self.assertRaises(ValueError):self.manager.match_document(self.root,self.entry,'unknown')

    def test_missing_or_directory_entry_and_file_root_fail_closed(self):
        self.file.unlink()
        with self.assertRaises(ValueError):self.manager.match_document(self.root,self.entry)
        self.file.mkdir()
        with self.assertRaises(ValueError):self.manager.match_document(self.root,self.entry)
        with self.assertRaises(ValueError):self.manager.match_document(self.file/'missing',self.entry)
        actual=self.base/'file-root';actual.write_text('not a directory')
        self.profiles[:]=[{**self.profile,'root':str(actual)}];self.original=copy.deepcopy(self.profiles)
        with self.assertRaises(ValueError):self.manager.match_document(actual,self.entry)

    def test_outside_symlinks_and_escape_do_not_match_even_same_inode(self):
        outside=self.base/'outside.typ';os.link(self.file,outside)
        alias=self.root/'outside-alias.typ';alias.symlink_to(outside)
        for entry in [alias.name,'../outside.typ',str(outside)]:
            with self.subTest(entry=entry),self.assertRaises(ValueError):self.manager.match_document(self.root,entry)
        self.file.unlink();self.file.symlink_to(outside)
        with self.assertRaises(ValueError):self.manager.match_document(self.root,self.entry)

    def test_casefold_and_compatibility_are_not_canonical_equivalence(self):
        case=self.root/(self.entry.replace('main','MAIN'))
        self.observations.append(dict(caseVariantExists=case.exists(),caseVariantSamefile=self.file.samefile(case) if case.exists() else False))
        with self.assertRaises(ValueError):self.manager.match_document(self.root,case.name)
        full=self.root/'ｍａｉｎ.typ';full.write_text('different compatibility name')
        with self.assertRaises(ValueError):self.manager.match_document(self.root,full.name)

    def test_missing_source_cleanup_retires_only_exact_native_token(self):
        control=self.base/'control';control.write_text('{}');control.chmod(0o600)
        attachments=EditorAttachments(self.manager.data/'documents/reader',document_identity(self.root,self.entry),dict(pid=os.getpid(),startedAt=1))
        nvim=shutil.which('nvim');self.assertIsNotNone(nvim)
        def register(native):return attachments.register(str(self.base/'editor.sock'),nvim,os.getpid(),str(control),jump_only=native)
        token,path=register(True);other,otherpath=register(True);terminal,terminalpath=register(False)
        preserved={str(p):sha(p) for p in [otherpath,terminalpath,control]}
        self.file.rename(self.root/'renamed.typ')
        self.assertEqual(self.manager.native_editor_local(self.root,self.entry,token),{'released':True})
        with self.assertRaises(ValueError):self.manager.match_document(self.root,self.entry)
        with self.assertRaises(ValueError):self.manager.native_editor_local(self.root,self.entry,other,descriptor=True)
        self.assertFalse(path.exists());self.assertEqual({str(p):sha(p) for p in [otherpath,terminalpath,control]},preserved)
        with self.assertRaises(ValueError):self.manager.native_editor_local(self.root,self.entry,terminal)
        self.assertTrue(terminalpath.exists())
        self.observations.append(dict(retiredOnlyOwnNative=True,otherNativePreserved=otherpath.exists(),terminalPreserved=terminalpath.exists(),newDescriptorRejected=True))

    def test_live_cleanup_wrong_document_record_still_rejected(self):
        output=self.manager.data/'documents/reader/editor-attachments';output.mkdir(parents=True,mode=0o700)
        token='a'*64;path=output/(token+'.json');path.write_text(json.dumps(dict(documentID='wrong-document',nativeJumpOnly=True)));path.chmod(0o600)
        with self.assertRaises(ValueError):self.manager.native_editor_local(self.root,self.entry,token)
        self.assertTrue(path.exists())


if __name__=='__main__':unittest.main()


class NativeOperationLifetime(unittest.TestCase):
    """Existing owner, real private files/stat, no editor RPC mocks for identity."""
    def setUp(self):
        from flow_reader.services.editor_sync import NativeEditorOperation
        self.Operation=NativeEditorOperation
        self.base=Path(tempfile.mkdtemp(prefix='operation-',dir=os.environ['TMPDIR']))
        self.root=self.base/'source';self.root.mkdir();self.entry=self.root/'main.typ';self.entry.write_text('owned source')
        self.data=self.base/'data';self.output=self.data/'documents/fixture'
        self.document='a'*24;self.service=dict(pid=os.getpid(),startedAt=123)
        self.owner=EditorAttachments(self.output,self.document,self.service)
        self.control=self.base/'control';self.control.write_text('{}');self.control.chmod(0o600)
        self.manager=ReaderManager(self.data,self.base/'agents')
        self.manager.profiles=lambda:[dict(id='fixture',root=str(self.root),entry=self.entry.name,port=24000)]
        self.retain=[]
        self.addCleanup(self.evidence)

    def evidence(self):
        OUT.mkdir(exist_ok=True,parents=True);target=OUT/(self._testMethodName+'-'+str(time.time_ns()));target.mkdir()
        (target/'operations.json').write_text(json.dumps(dict(files={str(p.relative_to(self.data)):sha(p) for p in self.data.rglob('*') if p.is_file()},base=str(self.base),realFilesystem=True,sourceSHA256=sha(self.entry) if self.entry.exists() else None),indent=2))

    def operation(self, value=None):
        import secrets
        return self.manager.native_operation(str(self.root),self.entry.name,value or secrets.token_hex(32))

    def reserve(self):
        op=self.operation();op.reserve('fixture',self.document,time.time()+6.5);return op

    def register(self,op=None,jump=True):
        return self.owner.register('owned-no-rpc',sys.executable,os.getpid(),str(self.control),jump_only=jump,operation=op)

    def test_atomic_publication_has_prior_intent_complete_bytes_and_same_inode(self):
        op=self.reserve();original=op.prepare;observed=[]
        def inspect(data,identity):
            self.assertFalse((self.owner.directory/(op.read()['token']+'.json')).exists())
            self.assertEqual(op.read()['state'],'reserved')
            staging=self.owner.directory/('.native-'+op.identifier)
            self.assertEqual(staging.read_bytes(),data);self.assertEqual(json.loads(data)['nativeOperation'],op.identifier)
            original(data,identity);self.assertEqual(op.read()['recordIdentity'],[staging.stat().st_dev,staging.stat().st_ino]);observed.append(True)
        op.prepare=inspect
        token,path=self.register(op);self.assertEqual(observed,[True]);self.assertEqual(op.read()['state'],'prepared')
        self.assertEqual(json.loads(path.read_text())['nativeOperation'],op.identifier);op.issued()
        self.assertIsNone(self.owner.resolve(token),'movement consent cannot become source writer')
        self.assertTrue(op.cancel());self.assertFalse(path.exists());self.assertFalse(op.cancel())
        with self.assertRaises(ValueError):op.issued()

    def test_cancel_before_reserve_tombstone_blocks_late_and_reentry(self):
        op=self.operation();self.assertFalse(op.cancel())
        with self.assertRaises(FileExistsError):op.reserve('fixture',self.document,time.time()+6)
        with self.assertRaises(ValueError):op.current()
        again=self.operation(op.identifier);self.assertFalse(again.cancel())

    def test_wrong_binding_ids_terminal_conversion_collision_and_replacement(self):
        op=self.reserve();terminal,path=self.register(jump=False);before=sha(path)
        with self.assertRaises(ValueError):self.register(op,jump=False)
        for root,entry,rid in [(str(self.base),str(self.entry),None),(str(self.root),str(self.root/'other.typ'),None),(str(self.root),str(self.entry),'other')]:
            bad=self.Operation(self.data,op.identifier,root,entry,rid)
            with self.assertRaises(ValueError):bad.cancel()
        for value in ['','../escape','G'*64,'0'*63]:
            with self.assertRaises(ValueError):self.operation(value or '../escape')
        value=op.read();value['token']=terminal;op.write(value)
        with self.assertRaises(FileExistsError):self.register(op)
        with self.assertRaises(ValueError):op.cancel()
        self.assertEqual(sha(path),before)
        op2=self.reserve();token,native=self.register(op2);saved=native.read_bytes();native.unlink();native.write_bytes(saved);native.chmod(0o600)
        with self.assertRaises(ValueError):op2.cancel()
        self.assertTrue(native.exists(),'byte-identical replacement inode must be preserved')
        self.assertEqual(sha(path),before)

    def test_source_missing_profile_removed_withdrawal_only_and_other_tokens(self):
        terminal,tp=self.register(jump=False);other,np=self.register();before={str(p):sha(p) for p in [tp,np,self.control]}
        op=self.reserve();token,path=self.register(op);op.issued()
        self.entry.unlink();self.manager.profiles=lambda:[]
        self.assertTrue(self.manager.release_native_operation(str(self.root),self.entry.name,op.identifier)['released'])
        self.assertFalse(path.exists());self.assertEqual({str(p):sha(p) for p in [tp,np,self.control]},before)
        with self.assertRaises(ValueError):self.manager.match_document(self.root,self.entry.name)

    def test_existing_32_quota_is_unchanged_and_collision_preserves_files(self):
        files=[self.register(jump=i%2==0)[1] for i in range(32)];before={str(p):sha(p) for p in files}
        op=self.reserve()
        with self.assertRaisesRegex(ValueError,'Too many'):self.register(op)
        self.assertEqual({str(p):sha(p) for p in files},before);self.assertFalse(op.cancel())

    def test_intent_symlink_mode_and_incomplete_stage_fail_closed(self):
        op=self.reserve();op.path.chmod(0o644)
        with self.assertRaises(ValueError):op.current()
        op.path.chmod(0o600)
        moved=op.path.with_suffix('.retained');op.path.rename(moved);op.path.symlink_to(moved)
        with self.assertRaises(ValueError):op.cancel()
        op.path.unlink();moved.rename(op.path)
        self.owner.directory.mkdir(mode=0o700,parents=True,exist_ok=True)
        stage=self.owner.directory/('.native-'+op.identifier);stage.write_text('{partial');stage.chmod(0o600)
        self.assertEqual(list(self.owner.directory.glob('*.json')),[])
        self.assertFalse(op.cancel());self.assertFalse(stage.exists())

    def test_budget_expiry_and_fault_before_publication_do_not_issue(self):
        from unittest.mock import patch
        op=self.operation()
        for budget in [-1,8,float('inf')]:
            with self.assertRaises(ValueError):op.reserve('fixture',self.document,time.time()+budget)
        op=self.reserve();real=os.link
        def fail_publish(source,target,**kwargs):
            if Path(target).parent==self.owner.directory:raise OSError('injected publish failure')
            return real(source,target,**kwargs)
        with patch('os.link',side_effect=fail_publish),self.assertRaises(OSError):self.register(op)
        self.assertEqual(op.read()['state'],'prepared');self.assertEqual(list(self.owner.directory.glob('*.json')),[])
        self.assertFalse(op.cancel())

    def test_malformed_journal_never_confirms_absence_or_removes_another_file(self):
        op=self.reserve();original=op.read()
        bad=[]
        for state in ['reserved','prepared','issued']:
            value=dict(original,state=state,token=None,profileID=None,documentID=None,recordSHA256=None,recordIdentity=None)
            bad.append(value)
        for state in ['prepared','issued']:
            bad.append(dict(original,state=state))
        bad.extend([dict(original,recordSHA256='b'*64),dict(original,recordIdentity=[1,2]),dict(original,state='unknown'),
                    dict(original,state='cancelled',token=None,profileID=None,documentID=None),
                    dict(original,state='cancelled',token=None,profileID=None,documentID=None,deadline=0,recordSHA256='b'*64,recordIdentity=[1,2]),
                    dict(original,version=True),dict(original,state=[])])
        for value in bad:
            op.write(value)
            with self.subTest(state=value['state']),self.assertRaises(ValueError):op.cancel()
            self.assertEqual(op.path.read_bytes(),json.dumps(value,sort_keys=True,separators=(',',':')).encode())
        op.write(original);self.assertFalse(op.cancel())

    def test_state_service_profile_and_source_changes_cannot_complete_native_plan(self):
        import secrets
        for fault in ['service','profile','source']:
            self.manager.profiles=lambda:[dict(id='fixture',root=str(self.root),entry=self.entry.name,port=24000)]
            self.manager.job_pid=lambda p,**kw:os.getpid()
            state=dict(documentID=__import__('flow_reader.compiler.project',fromlist=['document_identity']).document_identity(str(self.root),self.entry.name),service=self.service,editorAttachments=1)
            op=secrets.token_hex(32);after_ack=False;original=self.entry.read_bytes()
            def request(url,path,payload=None,**kw):
                nonlocal after_ack
                if path=='api/editor-attachment':
                    after_ack=True
                    if fault=='profile':self.manager.profiles=lambda:[]
                    if fault=='source':self.entry.write_bytes(original+b'changed by negative fixture')
                    return dict(connected=True)
                if after_ack and fault=='service':return {**state,'service':{**self.service,'startedAt':124}}
                return state
            self.manager.request=request
            with self.subTest(fault=fault),self.assertRaises(ValueError):
                self.manager.attach(str(self.root),self.entry.name,editor_server='owned-no-rpc',nvim=sys.executable,owner_pid=os.getpid(),control_file=str(self.control),native_editor_consent=True,native_editor_operation=op,native_editor_deadline=time.time()+6.5)
            self.entry.write_bytes(original)
            self.assertEqual(list(self.owner.directory.glob('*.json')),[])
            self.assertEqual(self.manager.native_operation(str(self.root),self.entry.name,op).read()['state'],'cancelled')

    def test_journal_write_bound_preserves_old_and_invalid_cleanup_deadline_fails(self):
        op=self.reserve();before=op.path.read_bytes();value=op.read();value['extra']='x'*17000
        with self.assertRaises(ValueError):op.write(value)
        self.assertEqual(op.path.read_bytes(),before)
        for deadline in [float('nan'),float('inf'),time.time()-1]:
            with self.assertRaises(ValueError):self.manager.release_native_operation(str(self.root),self.entry.name,op.identifier,deadline=deadline)
        self.assertEqual(op.path.read_bytes(),before)

    def test_v6_manager_scope_equivalence_alias_retarget_and_distinct_readers(self):
        profile=self.manager.profiles()[0];profiles=[profile];self.manager.profiles=lambda:profiles
        original=self.manager.native_scope(str(self.root),self.entry.name)
        alias=self.base/'scope-alias';alias.symlink_to(self.root,target_is_directory=True)
        same=self.manager.native_scope(str(alias),'./'+self.entry.name)
        self.assertEqual(same['scope'],original['scope']);self.assertNotEqual(same['requestBinding'],original['requestBinding'])
        self.assertEqual(self.manager.native_scope(str(self.root),'./'+self.entry.name)['scope'],original['scope'])
        other=self.base/'other-root';other.mkdir();(other/self.entry.name).write_text('unrelated source')
        profiles.append(dict(profile,id='other',root=str(other)))
        unrelated=self.manager.native_scope(str(other),self.entry.name,'other')
        self.assertNotEqual(unrelated['scope'],original['scope'])
        profiles.append(dict(profile,id='second-reader'))
        self.assertIsNone(self.manager.native_scope(str(self.root),self.entry.name)['scope'],'ambiguous inventory cannot authorize a new grant')
        self.assertNotEqual(self.manager.native_scope(str(self.root),self.entry.name,'fixture')['scope'],self.manager.native_scope(str(self.root),self.entry.name,'second-reader')['scope'])
        alias.unlink();alias.symlink_to(other,target_is_directory=True)
        retarget=self.manager.native_scope(str(alias),'./'+self.entry.name,'fixture')
        self.assertIsNone(retarget['scope'])
        # Stable spelling is a withdrawal correlation, never a target grant.
        stable=self.manager.native_scope(str(alias),'./'+self.entry.name)
        self.assertEqual(stable['requestBinding'],same['requestBinding'])
        self.assertNotEqual(stable['scope'],same['scope'])
        self.assertFalse(self.data.exists(),'readonly query must not create control, journal, service or attachment')

    def test_v6_stable_request_actual_binding_and_wrong_caller(self):
        alias=self.base/'root-alias';alias.symlink_to(self.root,target_is_directory=True)
        import secrets
        identifier=secrets.token_hex(32)
        op=self.manager.native_operation(str(alias),self.entry.name,identifier,'fixture')
        op.reserve('fixture',self.document,time.time()+6.5,document_root=str(self.root),document_entry=str(self.entry))
        token,path=self.register(op);op.issued();record=op.read()
        self.assertEqual(record['root'],str(alias));self.assertEqual(record['documentRoot'],str(self.root))
        before=sha(path)
        for root,entry,rid in [(str(self.root),self.entry.name,'fixture'),(str(alias),'other.typ','fixture'),(str(alias),self.entry.name,'other')]:
            with self.assertRaises(ValueError):self.manager.release_native_operation(root,entry,identifier,rid)
            self.assertEqual(sha(path),before)
        alias.unlink()
        self.assertTrue(self.manager.release_native_operation(str(alias),self.entry.name,identifier,'fixture')['released'])
        self.assertFalse(path.exists());self.assertFalse(self.manager.release_native_operation(str(alias),self.entry.name,identifier,'fixture')['released'])

    def test_v6_legacy_record_compatibility_and_state_document_completeness(self):
        op=self.reserve();value=op.read()
        for key in ['documentRoot','documentEntry']:
            bad=dict(value);bad[key]=None;op.write(bad)
            with self.assertRaises(ValueError):op.cancel()
        op.write(value)
        old=dict(value,version=1);old.pop('documentRoot');old.pop('documentEntry');op.write(old)
        token,path=self.register(op);op.issued();self.assertEqual(op.read()['version'],1)
        self.assertTrue(op.cancel());self.assertFalse(path.exists())


class NativeScopeV8(unittest.TestCase):
    setUp = NativeOperationLifetime.setUp
    evidence = NativeOperationLifetime.evidence
    def test_S1_symlink_dotdot_preserves_independent_request_bindings(self):
        a=self.root/'a';b=self.root/'b';a.mkdir();b.mkdir();(b/'sub').mkdir()
        (a/'main.typ').write_text('independent A');(b/'main.typ').write_text('independent B')
        (a/'link').symlink_to(b/'sub',target_is_directory=True)
        profiles=[dict(id=n,root=str(self.root),entry=n+'/main.typ',port=24000+i) for i,n in enumerate(('a','b'))]
        self.manager.profiles=lambda:profiles
        supplied='a/link/../main.typ'
        self.assertTrue((self.root/supplied).samefile(b/'main.typ'))
        scope_b=self.manager.native_scope(str(self.root),supplied)
        scope_a=self.manager.native_scope(str(self.root),'a/main.typ')
        self.assertNotEqual(scope_a['scope'],scope_b['scope'])
        OUT.mkdir(exist_ok=True,parents=True)
        (OUT/('S1-'+str(time.time_ns())+'.json')).write_text(json.dumps(dict(a=scope_a,b=scope_b,actualB=str((self.root/supplied).resolve()),sourceA=sha(a/'main.typ'),sourceB=sha(b/'main.typ')),indent=2))
        self.assertNotEqual(scope_a['requestBinding'],scope_b['requestBinding'],'different actual documents must not share withdrawal correlation through lexical dotdot removal')

    def test_R1_expected_scope_rejects_before_any_operation_or_registration(self):
        import secrets
        a=self.root; b=self.base/'other';b.mkdir();(b/self.entry.name).write_text('independent B')
        profiles=[dict(id='a',root=str(a),entry=self.entry.name,port=24000),dict(id='b',root=str(b),entry=self.entry.name,port=24001)]
        self.manager.profiles=lambda:profiles
        alias=self.base/'query-alias';alias.symlink_to(a,target_is_directory=True)
        expected=self.manager.native_scope(str(alias),self.entry.name)['scope']
        alias.unlink();alias.symlink_to(b,target_is_directory=True)
        effects=[];self.manager.job_pid=lambda p:effects.append('pid') or os.getpid()
        operation=secrets.token_hex(32)
        try:
            self.manager.attach(str(alias),self.entry.name,editor_server='owned',nvim=sys.executable,owner_pid=os.getpid(),control_file=str(self.control),native_editor_consent=True,native_editor_operation=operation,native_editor_deadline=time.time()+6.5,native_editor_expected_scope=expected)
        except ValueError as error:self.assertIn('scope',str(error))
        self.assertEqual(effects,[],'scope rejection must precede service/probe effects')
        self.assertFalse((self.data/'native-editor-operations'/(operation+'.json')).exists(),'no intent for mismatching issuance')
        self.assertFalse(list(self.data.glob('documents/*/editor-attachments/*.json')))

    def test_R1_expected_scope_shape_and_operation_association_fail_closed(self):
        import secrets
        for scope in ['', 'g'*64, 'a'*63, 1, 'A'*64]:
            with self.subTest(scope=scope),self.assertRaisesRegex(ValueError,'scope'):
                self.manager.attach(str(self.root),self.entry.name,native_editor_expected_scope=scope,native_editor_operation=secrets.token_hex(32))
        with self.assertRaisesRegex(ValueError,'scope'):
            self.manager.attach(str(self.root),self.entry.name,native_editor_expected_scope='a'*64)
        self.assertFalse(self.data.exists())
