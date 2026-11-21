"""NA15 actual saved compiler/source/HTTP/Neovim fixture. No GUI or user services."""
import copy
from contextlib import closing
import hashlib
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from urllib.parse import urlencode
from uuid import uuid4
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(REPO / 'tools/flow-reader'))
from flow_reader.compiler.project import Project
from flow_reader.server.state import ReaderState
from flow_reader.server.http import handler_for
from flow_reader.server.native_reader import service_id
from flow_reader.services.editor_sync import NeovimEditor, vim_string
from flow_reader.services.native_editor_actions import NativeEditorActions

OUT = Path(os.environ.get('NA15_OUTPUT', Path(tempfile.gettempdir()) / 'native-editor-actions'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class CompilerEditorFixture(unittest.TestCase):
    def save(self, name, value):
        self.evidence.joinpath(name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')

    def setUp(self):
        for tool in ('nvim', 'typst', 'sandbox-exec'):
            if not shutil.which(tool):
                raise RuntimeError('Required existing fixture prerequisite unavailable: ' + tool)
        OUT.mkdir(parents=True, exist_ok=True)
        self.evidence = OUT / (self._testMethodName + '-' + str(time.time_ns()))
        self.evidence.mkdir(mode=0o700)
        self.work = Path(tempfile.mkdtemp(prefix='na15-', dir=os.environ['TMPDIR'])).resolve()
        # Retain isolated fixture bytes for independent oracle inspection.
        self.root = self.work / getattr(self, 'source_directory', 'source'); self.root.mkdir()
        self.entry = self.root / getattr(self,"entry_filename","한글' main.typ")
        self.original = '= Native fixture\n\nPréface 한글 target passage.\n\nOther independent paragraph.\n\n#include \"included.typ\"\n'
        if 'SF1_' in self._testMethodName or 'SF2_' in self._testMethodName:
            self.original=self.original.replace('#include', '$ frac(1, 2) $\n\n#include',1)
        self.entry.write_text(self.original)
        self.dependency=self.root/'included.typ'; self.dependency.write_text('Included dependency.\n')
        self.control = self.work / 'control.json'; self.control.write_text('{}'); self.control.chmod(0o600)
        self.socket = self.work / 'editor.sock'
        (self.work / 'compiler').mkdir()
        self.compiler = self.work / 'compiler/offline-typst'
        # No network or writes to fixture sources, checkout or existing cache.
        protected = [self.root, REPO, Path(os.environ['TYPST_PACKAGE_CACHE_PATH'])]
        profile = '(version 1)(allow default)(deny network*)' + ''.join('(deny file-write* (subpath '+json.dumps(str(p))+'))' for p in protected)
        self.compiler_log=self.work/'compiler-executions.jsonl'
        self.compiler.write_text('#!'+sys.executable+'\nimport json,subprocess,sys,time\nargv='+repr(['/usr/bin/sandbox-exec','-p',profile,shutil.which('typst')])+'+sys.argv[1:]\nstart=time.monotonic()\nr=subprocess.run(argv,capture_output=True)\nwith open('+repr(str(self.compiler_log))+',"a") as f: f.write(json.dumps({"argv":argv,"exit":r.returncode,"seconds":time.monotonic()-start,"stdout":r.stdout.decode(errors="replace"),"stderr":r.stderr.decode(errors="replace")})+"\\n")\nsys.stdout.buffer.write(r.stdout);sys.stderr.buffer.write(r.stderr)\nraise SystemExit(r.returncode)\n')
        self.compiler.chmod(0o700)
        self.state = ReaderState(Project(self.root, Path(self.entry.name), REPO/'tools/flow-reader/packages', compiler=str(self.compiler)), self.work/'manager-data/documents/fixture', '', False)
        from test_homepage import FakeAuth, FakeProvider
        provider=FakeProvider();provider.auth=FakeAuth(self.work)
        self.state.chat_data=self.work/'chat';self.state.chat_provider=provider
        self.addCleanup(self.state.close)
        self.state.compile()
        self.assertTrue(self.state.report.get('contentGatePassed'), self.state.report)
        self.assertIsNotNone(self.state.revision)
        self.save('compiler-report.json', self.state.report)
        setup = 'lua vim.opt.rtp:append('+json.dumps(str(REPO/'editors/neovim'))+"); require('tinymist.reader').setup({auto_open=false, root="+json.dumps(str(self.root),ensure_ascii=False)+'})'
        editor_log=(self.evidence/'editor-stderr.log').open('w');self.addCleanup(editor_log.close)
        self.editor = subprocess.Popen([shutil.which('nvim'), '--headless', '-u', 'NONE', '-i', 'NONE', '-n', '--listen', str(self.socket), '-c', setup, str(self.entry)], stdout=subprocess.DEVNULL, stderr=editor_log)
        self.addCleanup(self.stop_editor)
        deadline = time.monotonic()+5
        while not self.socket.exists() and self.editor.poll() is None and time.monotonic()<deadline:
            time.sleep(.01)
        self.assertTrue(self.socket.exists(), 'actual isolated Neovim must start')
        self.token, self.record_path = self.state.editor_attachments.register(str(self.socket), shutil.which('nvim'), self.editor.pid, str(self.control), jump_only=True)
        base = handler_for(self.state)
        class Quiet(base):
            def log_message(self, *_): pass
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Quiet)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True); self.thread.start()
        self.addCleanup(self.stop_server)
        self.base_url = f'http://127.0.0.1:{self.server.server_port}/'
        self.context = dict(documentID=self.state.document_id, serviceID=service_id(self.state.focus.service), revision=self.state.revision,
            schemaVersion=1, capabilities=['semantic-tree-v1','image-layout-v1'], requestID=str(uuid4()), viewID=str(uuid4()), generation=1)
        query = {**self.context, 'capabilities': ','.join(self.context['capabilities'])}
        code, raw, headers = self.http('GET', '/api/native-document?'+urlencode(query))
        self.assertEqual(code, 200, raw)
        self.document = json.loads(raw); self.context['inputID'] = headers['X-Native-Input-ID']
        block = next(b for b in self.document['blocks'] if b['canonicalText']=='Préface 한글 target passage.')
        prefix = 'Préface 한글 '
        start = len(prefix.encode('utf-16-le'))//2
        self.selection = {'ticket':str(uuid4()), 'fragments':[{'blockID':block['id'], 'rangeUTF16':[start,start+6], 'exact':'target'}]}
        self.request = dict(self.context, consentID=str(uuid4()), editorAttachment=self.token, sequence=1, selection=self.selection, receiptID=str(uuid4()))
        self.assertEqual(self.action('sync')['status'], 'ready')
        self.dependency_hash=sha(self.dependency)
        self.before = self.oracle()
        self.save('before.json', self.before)
        self.save('binding.json', {'documentID':self.state.document_id, 'serviceID':self.context['serviceID'], 'revision':self.state.revision,
            'inputID':self.context['inputID'], 'sourceSHA256':sha(self.entry), 'compilerSHA256':sha(shutil.which('typst')),
            'nvimSHA256':sha(shutil.which('nvim')), 'acceptedHTMLSHA256':hashlib.sha256(self.state.document).hexdigest(),
            'mapping':'actual compiler default carriers; no hand-built accepted bundle', 'nativeUI':'not run'})
        self.save('expected-oracle.json', {'file':str(self.entry), 'line':3, 'columnUTF8':len(prefix.encode('utf-8'))})

    def tearDown(self):
        if hasattr(self, 'compiler_log') and self.compiler_log.exists():
            shutil.copyfile(self.compiler_log,self.evidence/'compiler-executions.jsonl')
        if hasattr(self, 'before'):
            self.save('source-after.json', {'sourceBeforeSHA256':hashlib.sha256(self.original.encode()).hexdigest(),
                'sourceAfterSHA256':sha(self.entry), 'dependencyBeforeSHA256':self.dependency_hash,
                'dependencyAfterSHA256':sha(self.dependency),
                'fixtureSourceMutation':self.entry.read_text()!=self.original or sha(self.dependency)!=self.dependency_hash,
                'note':'Negative source/dependency edits are test setup. Each effect asserts exact preservation of its current input.'})
            self.save('final-oracle.json',self.oracle())

    def stop_server(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join(5)

    def stop_editor(self):
        if self.editor.poll() is None:
            self.editor.terminate(); self.editor.wait(timeout=5)

    def rpc(self, lua, address=None):
        # Independent editor oracle: raw nvim API, never reader.cursor/jump result.
        expression = 'luaeval('+vim_string('vim.json.encode((function() '+lua+' end)())')+')'
        r = subprocess.run([shutil.which('nvim'), '--server', str(address or self.socket), '--remote-expr', expression], capture_output=True, text=True, timeout=5)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def oracle(self, address=None):
        return self.rpc('local c=vim.api.nvim_win_get_cursor(0); local b={}; for _,n in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_is_loaded(n) then table.insert(b,{name=vim.api.nvim_buf_get_name(n),lines=vim.api.nvim_buf_get_lines(n,0,-1,false),modified=vim.bo[n].modified}) end end; return {file=vim.api.nvim_buf_get_name(0),line=c[1],columnUTF8=c[2],buffers=b}',address)

    def http(self, method, path, body=None, headers=None):
        h={'Origin':self.base_url.rstrip('/'), 'Content-Type':'application/json'}
        h.update(headers or {}); h={k:v for k,v in h.items() if v is not None}
        connection=HTTPConnection('127.0.0.1',self.server.server_port,timeout=10)
        connection.request(method,path,body=json.dumps(body) if body is not None else None,headers=h)
        response=connection.getresponse(); result=response.status,response.read(),dict(response.getheaders()); connection.close()
        return result

    def action(self, operation, request=None, code=200, headers=None):
        status,raw,_=self.http('POST','/api/native-editor',{**(request or self.request),'operation':operation},headers)
        self.assertEqual(status,code,raw)
        value=json.loads(raw)
        self.assertFalse({'path','source_hash','line','column','editorAttachment','address','executable','registration','fingerprint'} & value.keys())
        self.assertNotIn(str(self.root),raw.decode()); self.assertNotIn(self.token,raw.decode()); self.assertNotIn(str(self.socket),raw.decode())
        return value

    def assert_unchanged(self, before, source=None):
        self.assertEqual(sha(self.dependency),self.dependency_hash)
        self.assertEqual(self.oracle(),before)
        self.assertEqual(self.entry.read_bytes(),self.original.encode() if source is None else source)


class NativeManagerEditorIdentityTests(CompilerEditorFixture):
    source_directory = "프로젝트 ' space"

    def test_unicode_manager_attachment_to_actual_http_and_same_editor(self):
        import unicodedata
        from test_native_manager_identity import ReaderManager
        self.assertTrue(self.rpc("return package.loaded['tinymist.reader'] ~= nil"),'actual Unicode Lua setup must load unchanged owner')
        profile=dict(id='fixture',root=str(self.root),entry=self.entry.name,port=self.server.server_port)
        class Owned(ReaderManager):
            def profiles(manager):return [profile, *manager.extra_profiles]
            def job_pid(manager, _profile):return self.state.focus.service['pid']
            def control(manager,*_args):raise AssertionError('No service lifecycle operation allowed')
        manager=Owned(self.work/'manager-data',self.work/'agents');manager.extra_profiles=[]
        nfd=lambda value:unicodedata.normalize('NFD',str(value))
        self.assertTrue(self.root.samefile(nfd(self.root)))
        self.assertTrue(self.entry.samefile(Path(nfd(self.root))/nfd(self.entry.name)))
        before_record=self.record_path.read_bytes()
        plan=manager.attach(nfd(self.root),nfd(self.entry.name),editor_server=str(self.socket),
            nvim=shutil.which('nvim'),owner_pid=self.editor.pid,control_file=str(self.control),native_editor_consent=True)
        self.save('manager-attachment.json',dict(plan=plan,registered=profile,suppliedRoot=nfd(self.root),suppliedEntry=nfd(self.entry.name),sameFile=True,
            fake=['configured profile inventory','managed PID observation'],real=['filesystem stat/content','ReaderManager match/attach','production HTTP','private editor registration','headless Neovim']))
        self.assertEqual(plan['documentID'],self.state.document_id)
        self.assertEqual(plan['service'],self.state.focus.service)
        self.assertEqual(plan['nativeEditorActions'],1)
        self.assertNotEqual(plan['editorAttachment'],self.token)
        self.assertIsNone(self.state.editor_attachments.resolve(plan['editorAttachment']))
        payload={**self.request,'editorAttachment':plan['editorAttachment'],'viewID':str(uuid4())}
        self.assertEqual(self.action('sync',payload)['status'],'ready')
        self.assertEqual(self.action('prepare',payload)['status'],'ready')
        self.assertEqual(self.action('jump',payload)['status'],'jumped')
        actual=self.oracle();self.save('actual-editor-after.json',actual)
        self.assertEqual((actual['file'],actual['line'],actual['columnUTF8']),(str(self.entry),3,len('Préface 한글 '.encode())))
        self.assertEqual(actual['buffers'],self.before['buffers']);self.assertEqual(sha(self.entry),hashlib.sha256(self.original.encode()).hexdigest())
        self.assertEqual(sha(self.dependency),self.dependency_hash)
        manager.extra_profiles=[{**profile,'id':'second','root':nfd(self.root),'entry':nfd(self.entry.name)}]
        with self.assertRaisesRegex(ValueError,'Multiple'):manager.attach(nfd(self.root),nfd(self.entry.name))
        self.assertEqual(manager.match_document(nfd(self.root),nfd(self.entry.name),'fixture'),profile)
        with self.assertRaises(ValueError):manager.attach(nfd(self.root),'different.typ')
        self.assertEqual(self.oracle(),actual)
        manager.extra_profiles=[]
        self.assertEqual(manager.native_editor_local(nfd(self.root),nfd(self.entry.name),plan['editorAttachment']),{'released':True})
        self.assertFalse(Path(plan['attachmentFile']).exists());self.assertEqual(self.record_path.read_bytes(),before_record)
        self.save('identity-effect-oracle.json',dict(actual=actual,sourceSHA256=sha(self.entry),dependencySHA256=sha(self.dependency),originalTokenPreserved=True,newTokenRetired=True,ambiguousAndOtherFileEffects=0))


class NativeEditorDispatchTests(CompilerEditorFixture):
    def test_actual_jump_and_duplicate_uuid_query_never_redispatch(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        self.assert_unchanged(self.before)
        self.assertEqual(self.action('jump')['status'],'jumped')
        actual=self.oracle(); self.save('after.json',actual)
        self.assertEqual((actual['file'],actual['line'],actual['columnUTF8']),(str(self.entry),3,len('Préface 한글 '.encode())))
        self.assertEqual(actual['buffers'],self.before['buffers'])
        self.rpc('vim.api.nvim_win_set_cursor(0,{1,0}); return true')
        reset=self.oracle()
        for operation in ('jump','prepare','receipt'):
            self.assertEqual(self.action(operation)['status'],'jumped')
            self.assert_unchanged(reset)
        changed={**self.request,'consentID':str(uuid4())}
        self.assertEqual(self.action('jump',changed)['status'],'refused')
        self.save('receipt.json',self.action('receipt'))

    def test_real_dirty_target_and_other_dirty_buffer_are_preserved(self):
        self.rpc('vim.api.nvim_buf_set_lines(0,0,1,false,{"Unsaved target"}); return true')
        dirty=self.oracle()
        self.assertEqual(self.action('prepare')['status'],'ready')
        self.assertEqual(self.action('jump')['status'],'modified')
        self.assert_unchanged(dirty)
        self.rpc('vim.cmd("edit!"); vim.cmd("enew"); vim.bo.bufhidden="hide"; vim.api.nvim_buf_set_lines(0,0,-1,false,{"Other unsaved"}); return true')
        other=self.oracle(); self.save('other-dirty-before.json',other)
        self.request['receiptID']=str(uuid4())
        self.assertEqual(self.action('prepare')['status'],'ready'); self.assertEqual(self.action('jump')['status'],'jumped')
        after=self.oracle(); self.save('other-dirty-after.json',after)
        self.assertEqual(after['buffers'],other['buffers']); self.assertEqual(self.entry.read_text(),self.original)

    def test_source_input_dependency_and_rpc_hash_stale_fail_closed(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        changed=self.original.replace('target','edited').encode(); self.entry.write_bytes(changed)
        self.assertEqual(self.action('jump')['status'],'stale'); self.assert_unchanged(self.before,changed)
        direct=NeovimEditor(str(self.socket),shutil.which('nvim'))
        self.assertEqual(direct.jump({'path':str(self.entry),'source_hash':hashlib.sha256(self.original.encode()).hexdigest(),'line':3,'column':0},lambda:True),'stale')
        self.assert_unchanged(self.before,changed)
        self.action('prepare',code=409)

    def test_wrong_attachment_service_identity_coordinates_and_guards(self):
        for patch in ({'editorAttachment':'0'*64},{'editorAttachment':None}):
            self.assertEqual(self.action('prepare',{**self.request,**patch})['status'],'stale')
        for patch in ({'serviceID':'reader:1:1'},{'inputID':'0'*64},{'revision':'old'}):
            self.action('prepare',{**self.request,**patch},code=409 if 'inputID' not in patch else 200)
        # A forged binding is not the synchronized view, even before source checks.
        for patch in ({'generation':2},{'viewID':str(uuid4())},{'requestID':str(uuid4())},{'consentID':str(uuid4())}):
            self.assertEqual(self.action('prepare',{**self.request,**patch})['status'],'stale')
        for patch in ({'path':str(self.entry)},{'executable':'/bin/sh'},{'address':str(self.socket)},{'line':3}):
            self.action('prepare',{**self.request,**patch},code=400)
        for headers,code in [({'Origin':None},403),({'Origin':'http://evil.invalid'},403),({'X-Forwarded-For':'127.0.0.1'},403),({'Host':'evil.invalid'},421)]:
            self.http('POST','/api/native-editor',{**self.request,'operation':'jump'},headers)[0]==code or self.fail('transport guard')
        self.assert_unchanged(self.before)

    def test_new_selection_cancel_close_late_and_unknown_receipts(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        old=copy.deepcopy(self.request)
        self.request.update(sequence=2,selection={**self.selection,'ticket':str(uuid4())})
        self.assertEqual(self.action('sync')['status'],'ready')
        self.assertEqual(self.action('jump',old)['status'],'stale')
        self.request['receiptID']=str(uuid4()); self.assertEqual(self.action('prepare')['status'],'ready')
        self.request['sequence']=3
        self.assertEqual(self.action('close')['status'],'closed')
        self.assertEqual(self.action('sync',{**self.request,'sequence':4})['status'],'stale')
        self.assertEqual(self.action('jump',old)['status'],'stale')
        self.assert_unchanged(self.before)

    def test_attachment_control_owner_and_service_lifetime(self):
        for change in ('control','registration','owner','service'):
            with self.subTest(change=change):
                self.request['receiptID']=str(uuid4()); self.assertEqual(self.action('prepare')['status'],'ready')
                record=self.record_path.read_bytes()
                if change=='control': self.control.unlink()
                elif change=='registration':
                    value=json.loads(record); value['address']=str(self.work/'other.sock'); self.record_path.write_text(json.dumps(value))
                elif change=='owner':
                    value=json.loads(record); value['ownerPID']=2147483647; self.record_path.write_text(json.dumps(value))
                else: self.state.focus.service={**self.state.focus.service,'startedAt':self.state.focus.service['startedAt']+1}
                self.action('jump',code=409 if change=='service' else 200)
                self.assert_unchanged(self.before)
                self.record_path.write_bytes(record)
                if not self.control.exists(): self.control.write_text('{}'); self.control.chmod(0o600)
                if change=='service': break

    def test_expired_disconnected_unknown_and_service_adapter_restart(self):
        self.assertEqual(self.action('receipt')['status'],'unknown')
        self.assertEqual(self.action('prepare')['status'],'ready')
        self.state._native_editor_actions.pending[self.request['receiptID']]['expires']=0
        self.assertEqual(self.action('jump')['status'],'stale'); self.assert_unchanged(self.before)
        self.request['receiptID']=str(uuid4()); self.assertEqual(self.action('prepare')['status'],'ready')
        from flow_reader.server.native_reader import NativeReaderService
        native=NativeReaderService(self.state)
        self.assertEqual(native.editor({**self.request,'operation':'jump'},lambda:False)['status'],'stale')
        self.assert_unchanged(self.before)
        self.request['receiptID']=str(uuid4()); self.assertEqual(self.action('prepare')['status'],'ready')
        self.assertEqual(self.action('jump')['status'],'jumped')
        # Reconstruct receipt owner to exercise persisted no-redispatch state.
        restarted=NativeEditorActions(self.state)
        restarted.views=copy.deepcopy(self.state._native_editor_actions.views)
        result=restarted.handle(native,{**self.request,'operation':'jump'})
        self.assertEqual(result['status'],'jumped')
        self.assertEqual(self.entry.read_text(),self.original)

    def test_changed_dependency_and_compiling_saved_snapshot(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        self.dependency.write_text('Changed dependency.\n')
        self.assertEqual(self.action('jump')['status'],'stale')
        self.assertEqual(self.oracle(),self.before); self.assertEqual(self.entry.read_text(),self.original)
        self.state.compiling=True
        self.action('prepare',code=409)

    def test_exact_manager_registration_and_other_attachment_survives_close(self):
        from flow_reader.services.manager import ReaderManager
        data=self.work/'manager'; (data/'documents').mkdir(parents=True)
        (data/'documents/exact').symlink_to(self.state.output,target_is_directory=True)
        manager=ReaderManager(data=data,agents=self.work/'agents')
        profile={'id':'exact','root':str(self.root),'entry':self.entry.name,'port':self.server.server_port}
        with patch.object(manager,'match_document',return_value=profile), patch.object(manager,'job_pid',return_value=self.state.focus.service['pid']), patch.object(manager,'document_url',return_value=self.base_url), patch.object(manager,'control',side_effect=AssertionError('No service control')):
            plan=manager.attach(self.root,self.entry.name,identifier='exact',editor_server=str(self.socket),nvim=shutil.which('nvim'),owner_pid=self.editor.pid,control_file=str(self.control),native_editor_consent=True)
        self.assertEqual(plan['nativeEditorActions'],1)
        self.assertNotEqual(plan['editorAttachment'],self.token)
        self.assertTrue(self.state.editor_attachments.record(plan['editorAttachment'])['nativeJumpOnly'])
        self.assertIsNone(self.state.editor_attachments.resolve(plan['editorAttachment']))
        code,raw,_=self.http('POST','/api/native-action',{**self.context,'operation':'highlight',
            'selection':self.selection,'receiptID':str(uuid4()),'editorAttachment':plan['editorAttachment']})
        self.assertEqual(code,200,raw);self.assertEqual(json.loads(raw)['status'],'editor-mismatch')
        self.assert_unchanged(self.before)
        other=Path(plan['attachmentFile']); before=other.read_bytes()
        self.assertEqual(self.action('prepare')['status'],'ready')
        self.request['sequence']=2; self.assertEqual(self.action('close')['status'],'closed')
        self.assertTrue(self.state.editor_attachments.record(plan['editorAttachment']))
        self.assertEqual(other.read_bytes(),before); self.assert_unchanged(self.before)

    def test_receipt_database_uncertainty_and_no_rpc_retry(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        # Transport loss is injected after a real Lua effect, never a fake jump.
        real=NeovimEditor.jump
        def lost(editor,location,current):
            self.assertEqual(real(editor,location,current),'jumped')
            return 'unknown'
        with patch.object(NeovimEditor,'jump',lost):
            self.assertEqual(self.action('jump')['status'],'unknown')
        self.rpc('vim.api.nvim_win_set_cursor(0,{1,0}); return true')
        before=self.oracle()
        for operation in ('prepare','jump','receipt'):
            self.assertEqual(self.action(operation)['status'],'unknown'); self.assert_unchanged(before)
        self.save('uncertain-receipt.json',self.action('receipt'))
        self.control.unlink()
        self.assertEqual(self.action('receipt')['status'],'unknown')
        self.assert_unchanged(before)

    def test_failed_new_selection_revokes_old_and_foreign_close_is_denied(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        other_token,other_path=self.state.editor_attachments.register(str(self.socket),shutil.which('nvim'),self.editor.pid,str(self.control))
        foreign={**self.request,'sequence':2,'editorAttachment':other_token}
        self.assertEqual(self.action('close',foreign)['status'],'stale')
        self.assertTrue(self.state.editor_attachments.record(self.token))
        newer=copy.deepcopy(self.request); newer['sequence']=2; newer['selection']['fragments'][0]['exact']='forged'
        self.action('sync',newer,code=400)
        self.assertEqual(self.action('jump')['status'],'stale')
        self.assert_unchanged(self.before)
        self.assertTrue(other_path.exists())

    def test_actual_service_process_restart_rejects_previous_attachment_and_receipt(self):
        self.assertEqual(self.action('prepare')['status'],'ready')
        port=self.server.server_port
        self.stop_server()
        configuration=self.work/'server-fixture.json'
        configuration.write_text(json.dumps(dict(root=str(self.root),entry=self.entry.name,compiler=str(self.compiler),output=str(self.state.output),port=port)))
        configuration.chmod(0o600)
        process=subprocess.Popen([sys.executable,'-B',str(Path(__file__).resolve()),'--serve-fixture',str(configuration)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        def stop_process():
            if process.poll() is None: process.terminate()
            process.communicate(timeout=5)
        self.addCleanup(stop_process)
        import select
        self.assertTrue(select.select([process.stdout],[],[],10)[0],'Restarted actual service must be ready')
        ready=json.loads(process.stdout.readline()); self.assertEqual(ready['ready'],True)
        self.action('jump',code=409)
        code,raw,_=self.http('GET','/api/state')
        self.assertEqual(code,200); state=json.loads(raw)
        self.assertNotEqual(state['service']['pid'],self.state.focus.service['pid'])
        self.assertNotEqual(state['service'],self.state.focus.service)
        query={**self.context,'serviceID':service_id(state['service']),'revision':state['revision'],'capabilities':','.join(self.context['capabilities'])}
        code,_,headers=self.http('GET','/api/native-document?'+urlencode({k:v for k,v in query.items() if k!='inputID'}))
        self.assertEqual(code,200)
        new={**self.request,'serviceID':query['serviceID'],'revision':query['revision'],'inputID':headers['X-Native-Input-ID'],'viewID':str(uuid4())}
        self.assertEqual(self.action('sync',new)['status'],'unavailable')
        self.assert_unchanged(self.before)
        self.save('service-restart.json',dict(old=self.state.focus.service,new=state['service'],oldRequestHTTP=409,oldAttachment='unavailable',actualProcessRestart=True))

    def test_registered_document_prefix_dispatch_and_unknown_prefix_guards(self):
        from flow_reader.server.routing import handler_for_reader
        from flow_reader.services.home_account import HomeAccount
        from flow_reader.services.homepage import HomeInventory
        from test_homepage import FakeAuth, FakeProvider, FakeManager
        auth=FakeAuth(self.work); provider=FakeProvider()
        inventory=HomeInventory(FakeManager()); inventory.observe(); self.addCleanup(inventory.close)
        base=handler_for_reader({'exact':self.state},inventory,HomeAccount(auth,provider),capability='isolated-fixture')
        class Quiet(base):
            def log_message(self,*_): pass
        server=ThreadingHTTPServer(('127.0.0.1',0),Quiet)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        self.addCleanup(lambda:(server.shutdown(),server.server_close(),thread.join(5)))
        def send(prefix,operation):
            connection=HTTPConnection('127.0.0.1',server.server_port,timeout=10)
            connection.request('POST',prefix+'api/native-editor',body=json.dumps({**self.request,'operation':operation}),headers={'Origin':f'http://127.0.0.1:{server.server_port}','Content-Type':'application/json'})
            response=connection.getresponse(); result=response.status,response.read();connection.close();return result
        self.assertEqual(send('/d/unknown/','jump')[0],404)
        self.assertEqual(send('/','jump')[0],404)
        self.assert_unchanged(self.before)
        for operation,expected in [('prepare','ready'),('jump','jumped'),('receipt','jumped')]:
            code,raw=send('/d/exact/',operation);self.assertEqual(code,200,raw);self.assertEqual(json.loads(raw)['status'],expected)
            self.assertNotIn(self.token,raw.decode());self.assertNotIn(str(self.root),raw.decode())
        after=self.oracle();self.save('after.json',after)
        self.assertEqual((after['line'],after['columnUTF8']),(3,len('Préface 한글 '.encode())))
        self.assertEqual(after['buffers'],self.before['buffers']);self.assertEqual(self.entry.read_text(),self.original)

    def test_rework_registration_replacement_receipt_never_moves_either_editor(self):
        other=self.work/'other.sock'
        setup='lua vim.opt.rtp:append('+json.dumps(str(REPO/'editors/neovim'))+"); require('tinymist.reader').setup({auto_open=false, root="+json.dumps(str(self.root))+'})'
        process=subprocess.Popen([shutil.which('nvim'),'--headless','-u','NONE','-i','NONE','-n','--listen',str(other),'-c',setup,str(self.entry)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        self.addCleanup(lambda:(process.terminate(),process.wait(timeout=5)) if process.poll() is None else None)
        deadline=time.monotonic()+5
        while not other.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.01)
        self.assertTrue(other.exists())
        self.assertEqual(self.action('prepare')['status'],'ready')
        self.assertEqual(self.action('jump')['status'],'jumped')
        self.assertEqual(self.oracle()['line'],3)
        self.rpc('vim.api.nvim_win_set_cursor(0,{1,0}); return true')
        first,second=self.oracle(),self.oracle(other)
        original=self.record_path.read_bytes();record=json.loads(original);record['address']=str(other)
        self.record_path.write_text(json.dumps(record))
        self.assertIsNotNone(self.state.editor_attachments.record(self.token),'replacement remains a valid locally owned registration')
        results={}
        for operation in ('receipt','prepare','jump','receipt'):
            results[operation]=self.action(operation)['status'];self.assertEqual(results[operation],'unknown')
            self.assertEqual(self.oracle(),first);self.assertEqual(self.oracle(other),second)
            self.assertEqual(self.entry.read_text(),self.original)
        self.record_path.write_bytes(original)
        self.assertEqual(self.action('receipt')['status'],'unknown')
        self.save('rework-registration-receipt.json',dict(before='jumped',replacementLocallyValid=True,after=results,originalOracle=first,replacementOracle=second,redispatch=0))

    def test_rework_control_replace_and_recreate_invalidate_persisted_receipt(self):
        results=[]
        for kind in ('replace','recreate','registration-recreate'):
            self.request['receiptID']=str(uuid4())
            self.assertEqual(self.action('prepare')['status'],'ready');self.assertEqual(self.action('jump')['status'],'jumped')
            self.rpc('vim.api.nvim_win_set_cursor(0,{1,0}); return true');before=self.oracle()
            if kind=='registration-recreate':
                raw=self.record_path.read_bytes();self.record_path.unlink();self.record_path.write_bytes(raw);self.record_path.chmod(0o600)
            elif kind=='replace':
                replacement=self.work/'replacement-control';replacement.write_bytes(self.control.read_bytes());replacement.chmod(0o600);replacement.replace(self.control)
            else:
                raw=self.control.read_bytes();self.control.unlink();self.control.write_bytes(raw);self.control.chmod(0o600)
            self.assertIsNotNone(self.state.editor_attachments.record(self.token))
            for operation in ('receipt','prepare','jump'):
                self.assertEqual(self.action(operation)['status'],'unknown');self.assert_unchanged(before)
            results.append(dict(lifetimeChange=kind,receipt='unknown',redispatch=0))
        self.save('rework-control-receipts.json',results)

    def test_rework_legacy_receipt_without_fingerprint_is_unknown_and_never_replayed(self):
        path=self.state._native_editor_actions.path;path.touch(mode=0o600)
        with closing(sqlite3.connect(path)) as db:
            db.execute('CREATE TABLE jumps (id TEXT PRIMARY KEY,binding TEXT NOT NULL,status TEXT NOT NULL)')
            db.execute('INSERT INTO jumps VALUES (?,?,?)',(self.request['receiptID'],NativeEditorActions.binding(self.request),'jumped'))
            db.commit()
        for operation in ('receipt','prepare','jump'):
            self.assertEqual(self.action(operation)['status'],'unknown');self.assert_unchanged(self.before)
        with closing(sqlite3.connect(path)) as db:
            row=db.execute('SELECT status,registration FROM jumps').fetchone()
        self.assertEqual(row,('unknown',None))
        self.save('rework-legacy-receipt.json',dict(syntheticOldSchema=True,status=row[0],fingerprint=row[1],redispatch=0))

    def test_rework_legacy_or_nonboolean_marker_cannot_grant_native_authority(self):
        legacy,path=self.state.editor_attachments.register(str(self.socket),shutil.which('nvim'),self.editor.pid,str(self.control))
        self.assertIsNotNone(self.state.editor_attachments.resolve(legacy),'legacy source-write resolver remains available')
        for marker in (None,False,1,'true'):
            record=json.loads(path.read_text())
            if marker is None:record.pop('nativeJumpOnly',None)
            else:record['nativeJumpOnly']=marker
            path.write_text(json.dumps(record))
            request={**self.request,'viewID':str(uuid4()),'consentID':str(uuid4()),'editorAttachment':legacy,'receiptID':str(uuid4())}
            self.assertEqual(self.action('sync',request)['status'],'unavailable')
            self.action('sync',{**request,'nativeJumpOnly':True},code=400)
            for operation in ('prepare','jump'):self.assertEqual(self.action(operation,request)['status'],'stale')
            self.assert_unchanged(self.before)
        self.save('rework-marker-proof.json',dict(nativeRegistration=True,legacyHTTPConsentDenied=True,nonBooleanMarkersDenied=True,legacyWriteResolverPreserved=True))


def serve_fixture(config):
    value=json.loads(Path(config).read_text())
    state=ReaderState(Project(Path(value['root']),Path(value['entry']),REPO/'tools/flow-reader/packages',compiler=value['compiler']),Path(value['output']),'',False)
    state.compile()
    if not state.report.get('contentGatePassed'): raise RuntimeError('Restart compiler failure')
    base=handler_for(state)
    class Quiet(base):
        def log_message(self,*_): pass
    server=ThreadingHTTPServer(('127.0.0.1',value['port']),Quiet)
    print('{"ready":true}',flush=True)
    try: server.serve_forever()
    finally: server.server_close(); state.close()


if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--serve-fixture': serve_fixture(sys.argv[2])
    else: unittest.main()
