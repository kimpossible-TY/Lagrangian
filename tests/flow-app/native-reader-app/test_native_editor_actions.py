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
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True,exist_ok=True)
        cls.binary=OUT/'NativeEditorActionTests'
        manifest=json.loads((REPO/'apps/macos/sources.json').read_text())
        sources=[REPO/'apps/macos'/name for group in ('core','native','app') for name in manifest[group] if name != 'main.swift']
        # Outer command owns the single Swift lock. Never invoke a nested lock.
        if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Wrap this top-level test once with with-native-swift-lock.py')
        argv=['swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0',
              '-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH'],*map(str,sources),str(REPO/'tests/flow-app/native-reader-app/NativeEditorActionTests.swift'),'-o',str(cls.binary)]
        start=time.monotonic(); result=subprocess.run(argv,capture_output=True,text=True,timeout=180)
        (OUT/'swift-build.json').write_text(json.dumps({'argv':argv,'exit':result.returncode,'seconds':time.monotonic()-start,'stdout':result.stdout,'stderr':result.stderr,
            'sources':{str(p.relative_to(REPO)):sha(p) for p in sources}},indent=2))
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
                if mode in ('source-change','ui-stale'): self.entry.write_text(self.original.replace('target','edited'))
                elif mode=='ui-registration-replaced':
                    record=json.loads(self.record_path.read_text()); record['address']=str(self.work/'replacement.sock'); self.record_path.write_text(json.dumps(record))
                else: self.record_path.unlink()
                Path(str(marker)+'.done').write_text('done')
            except Exception as e: errors.append(str(e))
        thread=None
        if mode in ('source-change','wrong-attachment','ui-stale','ui-registration-replaced'):
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
