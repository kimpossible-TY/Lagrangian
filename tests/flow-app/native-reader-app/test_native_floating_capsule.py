"""NA19 opt-in AppKit checks. One outer shared Swift lock; no visible application."""
import sys
sys.dont_write_bytecode = True
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
import unittest

R = Path(__file__).resolve().parents[3]
D = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
O = D / 'test-output/native-cream-na19'
CHAT_O = D / 'test-output/native-cream-chat-repair'
PACKAGING_O = D / 'test-output/native-cream-packaging-repair'
FIXTURE_O = D / 'test-output/native-cream-fixture-integration'
REVIEW_O = D / 'test-output/native-cream-review-repair2'
TASK_ROOTS = {REVIEW_O: 'native-cream-review-repair2', O: 'native-cream-na19', CHAT_O: 'native-cream-chat-repair', PACKAGING_O: 'native-cream-packaging-repair', FIXTURE_O: 'native-cream-fixture-integration'}
NEW = ['NativeAppDesign.swift', 'NativeBrandMark.swift', 'NativeFloatingCapsule.swift', 'NativeReaderInputTextView.swift']
H18 = '567841a5d200f15904c9cc824b9d15103a38b992'


def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def save(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class NativeFloatingCapsuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get('NATIVE_CAPSULE_OUTPUT')
        if not configured:
            raise unittest.SkipTest('Requires explicit isolated NA19 output and outer shared Swift lock')
        cls.out = Path(configured).resolve()
        task_root = next((root for root in TASK_ROOTS if cls.out.is_relative_to(root)), None)
        if sys.platform != 'darwin' or task_root is None or cls.out == task_root or cls.out.exists():
            raise RuntimeError('Use a fresh attempt under NA19 output on macOS')
        if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Use the shared outer Swift lock once')
        cls.out.mkdir(parents=True)
        # Preserve actual source and runner bytes for every attempt, including failures.
        cls.sources = [R / 'apps/macos' / p for group in ['core', 'native', 'app']
                       for p in json.loads((R/'apps/macos/sources.json').read_text())[group] if p != 'main.swift']
        cls.sources += [R/'apps/macos'/p for p in NEW if R/'apps/macos'/p not in cls.sources]
        cls.harness = R/'tests/flow-app/native-reader-app/NativeFloatingCapsuleTests.swift'
        inputs = cls.out/'inputs'; inputs.mkdir()
        extra_harness = R/'tests/flow-app/native-reader-app/NativeChatRecoveryTests.swift'
        for p in [*cls.sources, cls.harness, extra_harness, Path(__file__)]:
            target = inputs/p.relative_to(R); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(p.read_bytes())
        save(cls.out/'inputs.json', {str(p.relative_to(R)): sha(p) for p in [*cls.sources, cls.harness, Path(__file__)]})
        # Run the untouched existing compiler fixture setup with a bounded compile adapter.
        path = R/'tests/flow-app/native-reader-app/test_native_ui_refinement.py'
        spec = importlib.util.spec_from_file_location('na19_original_ui', path)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        cls.ui = module; module.O = cls.out/'existing-ui'; module.RECOVERY_O = module.O
        os.environ['NATIVE_UI_OUTPUT'] = str(module.O)
        actual_run = subprocess.run; adaptations = []
        def adapt(argv, *args, **kwargs):
            actual = list(map(str, argv))
            if actual and Path(actual[0]).name == 'swiftc':
                actual = [*actual[:actual.index('-o')], *[str(R/'apps/macos'/p) for p in NEW if str(R/'apps/macos'/p) not in actual], *actual[actual.index('-o'):]]
                adaptations.append(dict(originalargv=list(map(str, argv)), actualargv=actual,
                    extra_inputs={str(R/'apps/macos'/p): sha(R/'apps/macos'/p) for p in NEW}))
            return actual_run(actual, *args, **kwargs)
        try:
            subprocess.run = adapt
            module.NativeUIRefinement.setUpClass()
        finally:
            subprocess.run = actual_run
            save(cls.out/'existing-ui-adapter.json', dict(original_runner=str(path), runnerSHA256=sha(path),
                output_root_override=str(module.O), unchanged_assertions=True, adaptations=adaptations))
        cls.fixture = module.OUT
        from flow_reader.compiler.project import Project
        from flow_reader.server.state import ReaderState
        from flow_reader.server.native_reader import NativeReaderService, service_id
        from flow_reader.document.native_document import SUPPORTED_CAPABILITIES
        from urllib.parse import urlencode
        from uuid import uuid4
        source = cls.out/'long-source'; source.mkdir()
        (source/'main.typ').write_text('\n\n'.join('Paragraph '+str(i)+' — 한글 A\u030A selection.' for i in range(36)))
        state = ReaderState(Project(source,Path('main.typ'),R/'tools/flow-reader/packages',compiler=str(module.OUT/'compiler-bin/offline-typst')),cls.out/'long-publication','',False)
        try:
            state.compile()
            save(cls.out/'long-compiler.json',state.report)
            if not state.report.get('contentGatePassed'): raise RuntimeError('Long fixture actual compiler failed')
            q=dict(documentID=state.document_id,serviceID=service_id(state.focus.service),revision=state.revision,schemaVersion=1,generation=1,requestID=str(uuid4()),viewID=str(uuid4()),capabilities=','.join(SUPPORTED_CAPABILITIES))
            data,_=NativeReaderService(state).document(urlencode(q));(cls.fixture/'long-document.json').write_bytes(data)
        finally: state.close()
        before = os.environ.get('NATIVE_CAPSULE_BEFORE') == '1'
        sources = list(cls.sources)
        if before:
            pinned = O/'before'; pinned.mkdir(exist_ok=True)
            for name in ['FlowApp.swift', 'NativeReaderWindowController.swift', 'NativeReaderChatView.swift', 'NativeReaderTextView.swift']:
                data = subprocess.check_output(['git','show',H18+':apps/macos/'+name], cwd=R)
                path = pinned/name
                if path.exists() and path.read_bytes() != data: raise RuntimeError('Pinned before changed')
                path.write_bytes(data)
            save(pinned/'binding.json', dict(revision=H18, files={p.name:sha(p) for p in pinned.glob('*.swift')}))
            sources = [pinned/p.name if (pinned/p.name).exists() else p for p in sources]
        dirty_before = os.environ.get('NATIVE_CAPSULE_SNAPSHOT')
        if dirty_before:
            pinned = Path(dirty_before).resolve()
            if pinned != O/'round2/prefixed-dirty-snapshot': raise RuntimeError('Only round2 dirty snapshot is permitted')
            binding = json.loads((pinned/'binding.json').read_text())
            for record in binding['files']:
                if sha(Path(record['snapshot'])) != record['SHA256']: raise RuntimeError('Dirty before changed')
            sources = [pinned/p.name if (pinned/p.name).is_file() else p for p in sources]
        pinned = os.environ.get('NATIVE_CHAT_SNAPSHOT')
        if pinned:
            pinned = Path(pinned).resolve()
            allowed = {CHAT_O/'baseline':'016734db869f8892bf2cd1e330be2fb4edda962f', CHAT_O/'followup/baseline':'d04891d5b1ab83ccf4d9e4b054e80818baa514c7'}
            if pinned not in allowed: raise RuntimeError('Only fixed task-owned baseline permitted')
            binding = json.loads((pinned/'binding.json').read_text())
            if binding['revision'] != allowed[pinned]: raise RuntimeError('Wrong baseline')
            for name, digest in binding['files'].items():
                if sha(pinned/name) != digest: raise RuntimeError('Baseline drift')
            sources = [pinned/p.name if p.name in binding['files'] else p for p in sources]
        binary_name = '-'.join(cls.out.relative_to(task_root).parts)
        cls.binary = D/'tmp'/TASK_ROOTS[task_root]/(binary_name+'-Capsule')
        if cls.binary.exists(): raise RuntimeError('Refuse to overwrite an existing test binary')
        argv = ['swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0',
                '-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH']]
        if before: argv += ['-D','NA19_BEFORE']
        extra = R/'tests/flow-app/native-reader-app/NativeChatRecoveryTests.swift'
        sources += [extra]
        argv += [*map(str,sources),str(cls.harness),'-o',str(cls.binary)]
        cls.execute('compile',argv,{str(p):sha(p) for p in [*sources,cls.harness]})
        (cls.out/'test-binary').write_bytes(cls.binary.read_bytes())

    @classmethod
    def execute(cls, name, argv, inputs=None, expect=0):
        start=time.time(); p=subprocess.run(argv,cwd=R,capture_output=True,text=True,timeout=180)
        (cls.out/(name+'.stdout.log')).write_text(p.stdout); (cls.out/(name+'.stderr.log')).write_text(p.stderr)
        save(cls.out/(name+'.command.json'),dict(actualargv=argv,cwd=str(R),inputSHA256=inputs,started=start,finished=time.time(),exit=p.returncode,skip=0))
        if p.returncode != expect: raise AssertionError(p.stdout+p.stderr)
        return p

    def scenario(self,name):
        self.execute(name,[str(self.binary),str(self.fixture),name,str(self.out)],{'binary':sha(self.binary)})

    def test_UI9_pending_recovery_loading_and_failure(self): self.scenario('recovery')
    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_selection_capsule_and_local_composer(self): self.scenario('capsule')
    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_restrictions_and_layout(self): self.scenario('restrictions')

    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_existing_UI_states(self): self.ui.NativeUIRefinement().scenario('states')
    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_existing_UI_request_failure(self): self.ui.NativeUIRefinement().scenario('request-failure')
    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_existing_UI_recovered_reflow(self): self.ui.NativeUIRefinement().scenario('recovery-reflow')
    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_existing_UI_recovered_original(self): self.ui.NativeUIRefinement().scenario('recovery-original')

    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_36_block_capsule_restrictions(self): self.scenario('long')
    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_explicit_Send_and_account_denial(self): self.scenario('send')

    @unittest.skipIf(os.environ.get('NATIVE_CAPSULE_BEFORE')=='1','Before run is UI9-C1 only')
    def test_actual_home_and_settings_chrome(self): self.scenario('home')

    def test_R19_1_account_wait_preserves_explicit_intent(self): self.scenario('r19-account')
    def test_R19_1_open_wait_preserves_explicit_intent(self): self.scenario('r19-open')
    def test_R19_2_stale_selection_keeps_visible_unsent_draft(self): self.scenario('r19-stale')
    def test_R19_3_short_selection_does_not_cover_other_body(self): self.scenario('r19-occlusion')

    def test_R19_1_model_wait_preserves_explicit_intent(self): self.scenario('r19-model')

    def test_chat_replace_unconfirmed(self): self.scenario('chat-unconfirmed')
    def test_chat_replace_confirmed(self): self.scenario('chat-confirmed')
    def test_chat_close_reenter(self): self.scenario('chat-close')
    def test_chat_selection_controls(self): self.scenario('chat-selection')
    def test_chat_context_restrictions(self): self.scenario('chat-restrictions')

    def test_chat_user_Ask_resume_ESC(self): self.scenario('chat-ui-esc')
    def test_chat_user_Ask_resume_close_reselect(self): self.scenario('chat-ui-close')
