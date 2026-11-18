"""Compile the dedicated Swift test via sources.json; actual HTTP/Neovim oracle."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import threading
import time
import unittest

REPO=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(REPO/'tools/flow-reader/tests'))
from test_native_editor_dispatch import CompilerEditorFixture, OUT, sha


class NativeSwiftEditorTests(CompilerEditorFixture):
    def setUp(self):
        # Quota/lifetime uses an ASCII registered entry. The separate retained
        # debug evidence exposes the existing NFC/NFD manager match gap; this
        # test does not silently change that production matching policy.
        if 'SF2_' in self._testMethodName: self.entry_filename='main.typ'
        super().setUp()

    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True,exist_ok=True)
        cls.binary=OUT/'NativeEditorActionTests'
        manifest=json.loads((REPO/'apps/macos/sources.json').read_text())
        sources=[REPO/'apps/macos'/name for group in ('core','native','app') for name in manifest[group] if name != 'main.swift']
        if fixed := os.environ.get('NA15_FIXED_SOURCES'):
            fixed=Path(fixed).resolve()
            allowed=Path('/Volumes/devSSD/Developer/lagrangian-native-20261117/test-output/native-app-corrections-v4')
            if not fixed.is_relative_to(allowed): raise RuntimeError('Fixed source evidence must remain isolated')
            sources=[fixed/p.name for p in sources]
        # Outer command owns the single Swift lock. Never invoke a nested lock.
        if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Wrap this top-level test once with with-native-swift-lock.py')
        argv=['swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0',
              '-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH'],*map(str,sources),str(REPO/'tests/flow-app/native-reader-app/NativeEditorActionTests.swift'),'-o',str(cls.binary)]
        start=time.monotonic(); result=subprocess.run(argv,capture_output=True,text=True,timeout=180)
        (OUT/'swift-build.json').write_text(json.dumps({'argv':argv,'exit':result.returncode,'seconds':time.monotonic()-start,'stdout':result.stdout,'stderr':result.stderr,
            'sources':{str(p):sha(p) for p in sources}},indent=2))
        if result.returncode: raise RuntimeError(result.stderr)

    def run_swift(self,mode):
        config=self.work/'attachment.json'
        config.write_text(json.dumps(dict(url=self.base_url,documentID=self.state.document_id,service=self.state.focus.service,
            editorAttachment=self.token,consentID=self.request['consentID'],revision=self.state.revision,nativeEditorActions=1,root=str(self.root),entry=self.entry.name)))
        config.chmod(0o600)
        marker=self.work/'gate'
        errors=[]
        def mutate():
            try:
                deadline=time.monotonic()+15
                while not marker.exists() and time.monotonic()<deadline: time.sleep(.01)
                if not marker.exists(): raise RuntimeError('Swift gate unavailable')
                if mode == 'SF1-control': self.control.unlink()
                elif mode == 'SF1-owner': self.registration_owner.terminate(); self.registration_owner.wait(timeout=5)
                elif mode == 'SF1-registration': self.record_path.unlink()
                elif mode in ('source-change','ui-stale'): self.entry.write_text(self.original.replace('target','edited'))
                elif mode=='ui-registration-replaced':
                    record=json.loads(self.record_path.read_text()); record['address']=str(self.work/'replacement.sock'); self.record_path.write_text(json.dumps(record))
                else: self.record_path.unlink()
                Path(str(marker)+'.done').write_text('done')
            except Exception as e: errors.append(str(e))
        thread=None
        if mode in ('source-change','wrong-attachment','ui-stale','ui-registration-replaced','SF1-control','SF1-owner','SF1-registration'):
            thread=threading.Thread(target=mutate); thread.start()
        start=time.monotonic()
        result=subprocess.run([str(self.binary),str(config),mode,str(marker)],capture_output=True,text=True,timeout=35)
        if thread: thread.join(2)
        self.save('swift-command.json',dict(argv=[str(self.binary),'private-attachment',mode,'private-gate'],exit=result.returncode,seconds=time.monotonic()-start,stdout=result.stdout,stderr=result.stderr,fixtureErrors=errors))
        self.assertEqual(result.returncode,0,result.stdout+result.stderr); self.assertEqual(errors,[])
        summary=json.loads(result.stdout); self.assertEqual(summary['skips'],0)
        self.save('swift-result.json',summary)
        after=self.oracle(); self.save('after.json',after)
        self.assertEqual(after['buffers'],self.before['buffers'])
        expected=self.original.replace('target','edited') if mode in ('source-change','ui-stale') else self.original
        self.assertEqual(self.entry.read_text(),expected)
        if mode in ('jump','managed','lost-receipt','lost-receipt-unread','cancel-after','late-result','ui-jump','ui-lost','ui-new-selection','ui-registration-replaced'):
            self.assertEqual((after['file'],after['line'],after['columnUTF8']),(str(self.entry),3,len('Préface 한글 '.encode())))
        else: self.assertEqual(after,self.before)
        return summary

    def queued_effect(self,mode):
        import sqlite3
        held=threading.Event();release=threading.Event();errors=[]
        def gate():
            with self.state.selection.edit_lock:
                held.set();release.wait(20)
        lock_thread=threading.Thread(target=gate);lock_thread.start();self.assertTrue(held.wait(5))
        marker=self.work/'gate'
        def observe():
            try:
                deadline=time.monotonic()+15
                coordinator=self.state._native_editor_actions
                while time.monotonic()<deadline:
                    path=coordinator.path
                    if path.exists():
                        with sqlite3.connect(path) as db: rows=db.execute('SELECT status FROM jumps').fetchall()
                        if rows:break
                    time.sleep(.01)
                else:raise RuntimeError('jump was not persisted/queued at actual edit_lock')
                self.assertEqual(rows,[('unknown',)])
                with coordinator.lock:
                    queued_view=next(dict(v) for k,v in coordinator.views.items() if k!=self.request['viewID'])
                (self.work/'gate.queued').write_text('actual jump waiting at held effect gate')
                while not (self.work/'gate.revoked').exists() and time.monotonic()<deadline:time.sleep(.01)
                self.assertTrue((self.work/'gate.revoked').exists())
                with coordinator.lock:
                    # Fixture has an initial independent view and the actual Swift
                    # view. The latter must have no actionable selection binding.
                    revoked=[v for k,v in coordinator.views.items() if k!=self.request['viewID']]
                    self.assertEqual(len(revoked),1)
                    self.assertTrue(revoked[0]['binding']!=queued_view['binding'] or revoked[0]['closed'])
                self.save('actual-effect-gate.json',dict(jumpPersistedBeforeGate=True,rowsBefore=rows,revokedBeforeRelease=True,sourceBefore=sha(self.entry)))
            except Exception as error:errors.append(repr(error))
            finally:release.set()
        observer=threading.Thread(target=observe);observer.start()
        try:self.run_swift(mode)
        finally:release.set();observer.join(5);lock_thread.join(5)
        self.assertEqual(errors,[]);self.assertFalse(observer.is_alive() or lock_thread.is_alive())
        self.assert_unchanged(self.before)
        with sqlite3.connect(self.state._native_editor_actions.path) as db:
            self.assertEqual(db.execute('SELECT status FROM jumps').fetchall(),[('stale',)])
    def test_actual_queued_jump_invalid_new_selection(self):self.queued_effect('queued-invalid')
    def test_actual_queued_jump_explicit_cancel(self):self.queued_effect('queued-cancel')

    def test_SF1_slow_revoke_cannot_restore_older_selection(self):self.run_swift('selection-race');self.assert_unchanged(self.before)

    def test_SF2_owned_manager_leases_and_production_descriptor(self):
        from flow_reader.services.manager import ReaderManager
        from flow_reader.services.editor_sync import EditorAttachments
        terminal,terminal_path=self.state.editor_attachments.register(str(self.socket),shutil.which('nvim'),self.editor.pid,str(self.control))
        retained={str(p):sha(p) for p in [terminal_path,self.record_path,self.control]}
        profile=dict(id='fixture',root=str(self.root),entry=self.entry.name,port=self.server.server_port)
        settings=self.work/'manager-fixture.json'
        settings.write_text(json.dumps(dict(data=str(self.work/'manager-data'),agents=str(self.work/'agents'),profile=profile,pid=self.state.focus.service['pid'])))
        wrapper=self.work/'manager-wrapper'
        wrapper.write_text('#!'+sys.executable+'\nimport sys,json,time\nfrom pathlib import Path\nsys.path.insert(0,'+repr(str(REPO/'tools/flow-reader'))+')\nfrom flow_reader.services.manager import ReaderManager,main\nv=json.loads(Path('+repr(str(settings))+').read_text())\nclass Owned(ReaderManager):\n def profiles(self): return [v["profile"]]\n def job_pid(self,p,**kwargs): return v["pid"] # explicit fake process observation; real HTTP below\nm=Owned(data=v["data"],agents=v["agents"])\nwith open('+repr(str(self.evidence/'manager-argv.jsonl'))+',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\ntry:\n main(sys.argv[1:],manager=m)\nexcept BaseException:\n import traceback\n with open(' + repr(str(self.evidence/'manager-errors.log')) + ',\"a\") as f:traceback.print_exc(file=f)\n raise\n')
        wrapper.chmod(0o700)
        manager=ReaderManager(data=self.work/'manager-data',agents=self.work/'agents')
        manager.profiles=lambda:[profile]
        descriptor=manager.native_editor_local(str(self.root),self.entry.name,terminal,descriptor=True)['descriptorFile']
        self.assertEqual(set(json.loads(Path(descriptor).read_text())),{'address','executable','ownerPID','controlFile'})
        config=self.work/'lease-config.json';config.write_text(json.dumps(dict(manager=str(wrapper),descriptor=descriptor,root=str(self.root),entry=self.entry.name)))
        result=subprocess.run([str(self.binary),str(config),'SF2',str(self.work/'gate')],capture_output=True,text=True,timeout=120)
        self.save('lease-swift.json',dict(exit=result.returncode,stdout=result.stdout,stderr=result.stderr,argv=[str(self.binary),str(config),'SF2'],fake=['PID observation/profile inventory'],real=['ReaderManager attach/release','production descriptor','HTTP probe','live editor']))
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual({str(p):sha(p) for p in [terminal_path,self.record_path,self.control]},retained)
        active=[p for p in self.state.editor_attachments.directory.glob('*.json') if self.state.editor_attachments.record(p.stem)]
        self.assertEqual(set(active),{terminal_path,self.record_path})
        self.assertIsNone(self.editor.poll());self.assert_unchanged(self.before)

    def response_boundary_fixture(self, delay=False):
        from flow_reader.services.manager import ReaderManager
        terminal, terminal_path = self.state.editor_attachments.register(str(self.socket),shutil.which('nvim'),self.editor.pid,str(self.control))
        profile=dict(id='fixture',root=str(self.root),entry=self.entry.name,port=self.server.server_port)
        settings=self.work/'response-manager.json'
        settings.write_text(json.dumps(dict(data=str(self.work/'manager-data'),agents=str(self.work/'agents'),profile=profile,pid=self.state.focus.service['pid'])))
        wrapper=self.work/'response-manager'
        wrapper.write_text('#!'+sys.executable+'\nimport sys;sys.dont_write_bytecode=True\nimport json,time\nfrom pathlib import Path\nsys.path.insert(0,'+repr(str(REPO/'tools/flow-reader'))+')\nfrom flow_reader.services.manager import ReaderManager,main\nv=json.loads(Path('+repr(str(settings))+').read_text())\nclass Owned(ReaderManager):\n def profiles(self): return [v["profile"]]\n def job_pid(self,p,**kwargs): return v["pid"]\n def request(self,url,path,*args,**kwargs):\n  result=super().request(url,path,*args,**kwargs)\n  if path=="api/editor-attachment" and '+repr(delay)+':\n   Path('+repr(str(self.work/'registered'))+').write_text("acknowledged before response")\n   time.sleep(60)\n  return result\nmain(sys.argv[1:],manager=Owned(data=v["data"],agents=v["agents"]))\n')
        wrapper.chmod(0o700)
        text=wrapper.read_text().replace('main(sys.argv[1:],manager=',
            'with open('+repr(str(self.evidence/'response-manager-commands.jsonl'))+',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nmain(sys.argv[1:],manager=')
        wrapper.write_text(text)
        args=['--attach','--root',str(self.root),'--entry',self.entry.name,'--editor-server',str(self.socket),'--nvim',shutil.which('nvim'),'--owner-pid',str(self.editor.pid),'--control-file',str(self.control),'--native-editor-consent']
        manager=ReaderManager(data=self.work/'manager-data',agents=self.work/'agents');manager.profiles=lambda:[profile]
        return wrapper,args,manager,terminal_path

    def test_SF2_response_before_plan_timeout_and_sigkill_known_gap(self):
        wrapper,args,manager,terminal_path=self.response_boundary_fixture(delay=True)
        retained={str(p):sha(p) for p in [terminal_path,self.record_path,self.control]}
        before=set(self.state.editor_attachments.directory.glob('*.json'))
        config=self.work/'timeout.json';config.write_text(json.dumps(dict(manager=str(wrapper),attachArguments=args)))
        command=[str(self.binary),str(config),'response-timeout',str(self.work/'unused')]
        start=time.monotonic();result=subprocess.run(command,capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue((self.work/'registered').exists())
        timed=set(self.state.editor_attachments.directory.glob('*.json'))-before
        self.assertEqual(len(timed),1,'known R1 leak must be measured, not hidden')
        for path in timed:self.assertTrue(self.state.editor_attachments.record(path.stem))
        (self.work/'registered').unlink()
        child=subprocess.Popen([str(wrapper),*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            deadline=time.monotonic()+10
            while not (self.work/'registered').exists() and child.poll() is None and time.monotonic()<deadline:time.sleep(.01)
            self.assertTrue((self.work/'registered').exists());child.kill();stdout,stderr=child.communicate(timeout=5)
        finally:
            if child.poll() is None:child.kill();child.wait(timeout=5)
        self.assertEqual(child.returncode,-9)
        leaked=set(self.state.editor_attachments.directory.glob('*.json'))-before
        self.assertEqual(len(leaked),2)
        self.assertEqual({str(p):sha(p) for p in [terminal_path,self.record_path,self.control]},retained)
        self.assertIsNone(self.editor.poll());self.assert_unchanged(self.before)
        for path in leaked:self.assertTrue(manager.native_editor_local(str(self.root),self.entry.name,path.stem)['released'])
        self.assertEqual(set(self.state.editor_attachments.directory.glob('*.json')),before)
        self.save('response-gap.json',dict(command=command,exit=result.returncode,stdout=result.stdout,stderr=result.stderr,elapsed=time.monotonic()-start,sigkillExit=child.returncode,leakedActive=2,cleanupExactOwned=2,retained=retained,knownGap=True,issue='R1 remains blocked: existing EditorAttachments.register generates token internally before returning it; pre-known operation binding needs this readonly owner API',fake=['profile inventory/PID observation','post-real-ack delay'],real=['CommandRunner ten-second timeout','actual manager registration','production HTTP acknowledgment','SIGKILL','headless editor','exact local release']))

    def test_SF2_failed_cleanup_lock_is_pending_until_explicit_retry(self):
        import fcntl
        wrapper,args,manager,terminal_path=self.response_boundary_fixture()
        plan=json.loads(subprocess.check_output([str(wrapper),*args]))
        token=plan['editorAttachment'];retained={str(p):sha(p) for p in [terminal_path,self.record_path,self.control]}
        release=['--release-native-editor','--root',str(self.root),'--entry',self.entry.name,'--token',token]
        config=self.work/'retry.json';config.write_text(json.dumps(dict(manager=str(wrapper),releaseArguments=release)))
        marker=self.work/'retry-marker';lock=(self.work/'manager-data/control.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX)
        command=[str(self.binary),str(config),'lease-retry',str(marker)]
        child=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            deadline=time.monotonic()+15
            while not marker.exists() and child.poll() is None and time.monotonic()<deadline:time.sleep(.01)
            self.assertTrue(marker.exists());self.assertTrue(Path(plan['attachmentFile']).is_file())
            fcntl.flock(lock,fcntl.LOCK_UN);Path(str(marker)+'.retry').write_text('explicit retry')
            stdout,stderr=child.communicate(timeout=15)
        finally:
            lock.close()
            if child.poll() is None:child.kill();child.wait(timeout=5)
        self.assertEqual(child.returncode,0,stdout+stderr)
        self.assertFalse(Path(plan['attachmentFile']).exists())
        calls=[json.loads(line) for line in (self.evidence/'response-manager-commands.jsonl').read_text().splitlines()]
        self.assertEqual(sum(call[0]=='--release-native-editor' for call in calls),2,'concurrent failure coalesces; confirmed release never respawns')
        self.assertEqual({str(p):sha(p) for p in [terminal_path,self.record_path,self.control]},retained)
        self.assert_unchanged(self.before)
        self.save('cleanup-retry.json',dict(argv=command,exit=child.returncode,stdout=stdout,stderr=stderr,realLockContention=True,exactAbsent=True,retained=retained))

    def test_SF1_editor_owner_exit_preserves_source_and_ask(self):
        self.registration_owner=subprocess.Popen([sys.executable,'-c','import sys;sys.stdin.read()'],stdin=subprocess.PIPE)
        self.addCleanup(lambda:self.registration_owner.poll() is None and self.registration_owner.terminate())
        record=json.loads(self.record_path.read_text());record['ownerPID']=self.registration_owner.pid;self.record_path.write_text(json.dumps(record))
        self.run_swift('SF1-owner');self.assert_unchanged(self.before)
    def test_SF1_removed_control_preserves_source_and_ask(self):self.run_swift('SF1-control');self.assert_unchanged(self.before)
    def test_SF1_removed_registration_preserves_source_and_ask(self):self.run_swift('SF1-registration');self.assert_unchanged(self.before)
    def test_SF1_sync_network_failure_preserves_source_and_ask(self):self.run_swift('SF1-network');self.assert_unchanged(self.before)

    def test_native_swift_production_http_actual_cursor(self): self.run_swift('jump')
    def test_lost_receipt_bounded_query_no_redispatch(self): self.run_swift('lost-receipt')
    def test_new_selection_before_dispatch(self): self.run_swift('new-selection')
    def test_failed_receipt_read_and_foreign_query_cannot_enable_replay(self): self.run_swift('lost-receipt-unread')
    def test_invalid_new_selection_before_dispatch(self): self.run_swift('invalid-selection')
    def test_disposed_before_dispatch(self): self.run_swift('dispose')
    def test_cancelled_before_dispatch(self): self.run_swift('cancel-before')
    def test_cancelled_after_prepare(self): self.run_swift('cancel-prepare')
    def test_late_result_cannot_adopt_new_selection(self): self.run_swift('late-result')
    def test_cancel_after_actual_effect_requires_receipt(self): self.run_swift('cancel-after')
    def test_source_changed_before_dispatch(self): self.run_swift('source-change')
    def test_attachment_revoked_before_dispatch(self): self.run_swift('wrong-attachment')
    def test_no_consent_cannot_jump(self): self.run_swift('no-consent')
    def test_modified_actual_editor_from_native(self):
        self.rpc('vim.api.nvim_buf_set_lines(0,0,1,false,{"Unsaved target"}); return true')
        self.before=self.oracle(); self.run_swift('modified')
    def test_explicit_private_descriptor_validation(self):
        descriptor=self.work/'editor.json'
        descriptor.write_text(json.dumps(dict(address=str(self.socket),executable=shutil.which('nvim'),ownerPID=self.editor.pid,controlFile=str(self.control))))
        descriptor.chmod(0o600)
        self.run_swift('descriptor')
    def test_consented_managed_client_composes_actual_transport(self):
        descriptor=self.work/'editor.json'
        descriptor.write_text(json.dumps(dict(address=str(self.socket),executable=shutil.which('nvim'),ownerPID=self.editor.pid,controlFile=str(self.control))))
        descriptor.chmod(0o600)
        self.run_swift('managed')
    def test_closed_managed_view_requires_new_editor_consent(self):
        descriptor=self.work/'editor.json'
        descriptor.write_text(json.dumps(dict(address=str(self.socket),executable=shutil.which('nvim'),ownerPID=self.editor.pid,controlFile=str(self.control))))
        descriptor.chmod(0o600)
        self.run_swift('managed-close')
    def test_close_during_managed_attach_cannot_restore_consent(self):
        descriptor=self.work/'editor.json'
        descriptor.write_text(json.dumps(dict(address=str(self.socket),executable=shutil.which('nvim'),ownerPID=self.editor.pid,controlFile=str(self.control))))
        descriptor.chmod(0o600)
        self.run_swift('managed-pending-close')

    def ui_fixture(self,mode):
        descriptor=self.work/'editor.json'
        descriptor.write_text(json.dumps(dict(address=str(self.socket),executable=shutil.which('nvim'),ownerPID=self.editor.pid,controlFile=str(self.control))))
        descriptor.chmod(0o644 if mode=='ui-invalid-descriptor' else 0o600)
        result=self.run_swift(mode)
        self.assertTrue(result['offscreenAppKit']);self.assertTrue(result['productionControlCallbacks'])
        self.assertEqual(result['activationPolicy'],'prohibited');self.assertEqual(result['visibleWindows'],0)
        return result

    def test_rework_offscreen_production_control_jump(self): self.ui_fixture('ui-jump')
    def test_rework_offscreen_lost_repeat_locate_queries_original_receipt(self): self.ui_fixture('ui-lost')
    def test_rework_offscreen_new_selection_rejects_old_receipt(self): self.ui_fixture('ui-new-selection')
    def test_rework_offscreen_close_before_dispatch(self): self.ui_fixture('ui-close')
    def test_rework_offscreen_changed_source_before_dispatch(self): self.ui_fixture('ui-stale')
    def test_rework_offscreen_replaced_registration_keeps_unknown(self): self.ui_fixture('ui-registration-replaced')
    def test_rework_flowapp_no_consent_has_no_native_editor(self): self.ui_fixture('ui-no-consent')
    def test_rework_flowapp_declined_consent_has_no_native_editor(self): self.ui_fixture('ui-declined')
    def test_rework_flowapp_invalid_descriptor_never_asks_consent(self): self.ui_fixture('ui-invalid-descriptor')


if __name__=='__main__': unittest.main()
