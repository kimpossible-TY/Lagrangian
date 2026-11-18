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
    if not fixed.is_relative_to(Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/native-reader-identity-ui-v5')):
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
