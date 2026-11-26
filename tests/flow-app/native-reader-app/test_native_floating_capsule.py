"""Offscreen AppKit regressions over temporary compiler-accepted fixtures.

No external output directory, shared lock, live service, or visible window is used.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from urllib.parse import urlencode
from uuid import uuid4

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin', 'AppKit requires macOS')
class NativeFloatingCapsuleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix='native-capsule-')
        cls.addClassCleanup(temporary.cleanup)
        cls.output = Path(temporary.name)
        cls.fixture = cls.output / 'fixture'
        cls.fixture.mkdir()
        cache = cls.output / 'module-cache'
        cache.mkdir()
        cls.environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(cache),
                               SWIFT_MODULECACHE_PATH=str(cache), PYTHONDONTWRITEBYTECODE='1')
        cls.prepare_fixtures()
        registry = json.loads((ROOT / 'apps/macos/sources.json').read_text())
        sources = [ROOT / 'apps/macos' / name for group in ('core', 'native', 'app')
                   for name in registry[group] if name != 'main.swift']
        cls.binary = cls.output / 'capsule'
        cls.ui_binary = cls.output / 'ui'
        for binary, harnesses, flags in [
            (cls.binary, ['NativeFloatingCapsuleTests.swift', 'NativeChatRecoveryTests.swift'], ['-D', 'NATIVE_CHAT_RECOVERY']),
            (cls.ui_binary, ['NativeReaderUIRefinementTests.swift'], []),
        ]:
            command = ['swiftc', '-parse-as-library', '-swift-version', '5', '-warnings-as-errors',
                       '-target', 'arm64-apple-macosx13.0', '-module-cache-path', str(cache), *flags,
                       *map(str, sources), *[str(Path(__file__).with_name(name)) for name in harnesses], '-o', str(binary)]
            result = subprocess.run(command, cwd=ROOT, env=cls.environment, capture_output=True, text=True, timeout=240)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)

    @classmethod
    def prepare_fixtures(cls):
        compiler = shutil.which('typst')
        if not compiler:
            raise RuntimeError('Prebuilt Typst required for accepted semantic/PDF fixtures')
        # Keep compiler execution offline, including accidental package resolution.
        wrapper = cls.output / 'offline-typst'
        wrapper.write_text('#!' + sys.executable + '\nimport os, sys\nos.execv("/usr/bin/sandbox-exec", '
                           '["sandbox-exec", "-p", "(version 1)(allow default)(deny network*)", '
                           + repr(compiler) + '] + sys.argv[1:])\n')
        wrapper.chmod(0o700)
        sys.path.insert(0, str(ROOT / 'tools/flow-reader'))
        cls.addClassCleanup(sys.path.remove, str(ROOT / 'tools/flow-reader'))
        from flow_reader.compiler.project import Project
        from flow_reader.server.state import ReaderState
        from flow_reader.server.native_reader import NativeReaderService, service_id
        from flow_reader.server.native_pages import NativePageService
        from flow_reader.document.native_document import SUPPORTED_CAPABILITIES
        inputs = {
            'document': '= 긴 한국어 제목과 문서 탐색을 위한 실제 컴파일 문서\n\nSelect this paragraph.\n\nSearch needle on the first page.\n\n#pagebreak()\n\n= 두 번째 절\n\nOther page body.\n',
            'long-document': '\n\n'.join('Paragraph ' + str(i) + ' — 한글 A\u030A selection.' for i in range(36)),
        }
        for name, text in inputs.items():
            source = cls.output / (name + '-source')
            source.mkdir()
            (source / 'main.typ').write_text(text)
            state = ReaderState(Project(source, Path('main.typ'), ROOT / 'tools/flow-reader/packages', compiler=str(wrapper)),
                                cls.output / (name + '-publication'), '', False)
            try:
                state.compile()
                if not state.report.get('contentGatePassed'):
                    raise RuntimeError(str(state.report))
                native = NativeReaderService(state)
                context = dict(documentID=state.document_id, serviceID=service_id(state.focus.service), revision=state.revision,
                               schemaVersion=1, generation=1, requestID=str(uuid4()), viewID=str(uuid4()))
                query = {**context, 'capabilities': ','.join(SUPPORTED_CAPABILITIES)}
                data, _ = native.document(urlencode(query))
                (cls.fixture / (name + '.json')).write_bytes(data)
                if name == 'document':
                    pages = NativePageService(state, native)
                    query = {**context, 'capabilities': 'original-pdf-full-v1'}
                    manifest = pages.manifest(urlencode(query))
                    (cls.fixture / 'publication.json').write_bytes(manifest)
                    resource = json.loads(manifest)['resource'].removeprefix('api/native-pages/')
                    (cls.fixture / 'publication.pdf').write_bytes(pages.resource(urlencode(query), resource))
            finally:
                state.close()

    def scenario(self, name, ui=False):
        output = self.output / ('run-ui-' + name if ui else 'run-' + name)
        output.mkdir()
        result = subprocess.run([str(self.ui_binary if ui else self.binary), str(self.fixture), name, str(output)],
                                cwd=ROOT, env=self.environment, capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_UI9_pending_recovery_loading_and_failure(self): self.scenario('recovery')
    def test_selection_capsule_and_local_composer(self): self.scenario('capsule')
    def test_restrictions_and_layout(self): self.scenario('restrictions')

    def test_existing_UI_layout(self): self.scenario('layout', ui=True)
    def test_existing_UI_tools(self): self.scenario('tools', ui=True)
    def test_existing_UI_states(self): self.scenario('states', ui=True)
    def test_existing_UI_request_failure(self): self.scenario('request-failure', ui=True)
    def test_existing_UI_recovered_reflow(self): self.scenario('recovery-reflow', ui=True)
    def test_existing_UI_recovered_original(self): self.scenario('recovery-original', ui=True)

    def test_36_block_capsule_restrictions(self): self.scenario('long')
    def test_explicit_Send_and_account_denial(self): self.scenario('send')

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
