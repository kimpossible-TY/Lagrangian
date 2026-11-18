"""Opt-in existing chat/service subset with task-owned storage adaptation only."""
import hashlib
import json
import os
from pathlib import Path
import sys
import types
import unittest

R = Path(__file__).resolve().parents[3]
D = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
O = D/'test-output/native-cream-chat-repair'


class RequiresExplicitOutput(unittest.TestCase):
    @unittest.skip('Set NATIVE_CHAT_OWNER_OUTPUT and use one outer Swift lock')
    def test_opt_in(self): pass


def load_tests(loader, tests, pattern):
    configured = os.environ.get('NATIVE_CHAT_OWNER_OUTPUT')
    if not configured: return loader.loadTestsFromTestCase(RequiresExplicitOutput)
    out = Path(configured).resolve()
    if out.parent != O or out.exists() or not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
        raise RuntimeError('Fresh task output and one outer shared Swift lock required')
    os.environ['NA09_ROOT'] = str(O); os.environ['NA04_RUN'] = out.name
    os.environ['FLOW_TEST_PACKAGE_CACHE'] = str(D/'build/native-cream-na20/016734db869f8892bf2cd1e330be2fb4edda962f-round4/delivery/typst-packages')
    path = R/'tests/flow-app/native-reader-app/test_services.py'
    source = path.read_text()
    adapted = source.replace('ISOLATED = CLOSURE if CLOSURE else DEV', 'ISOLATED = DEV')
    adapted = adapted.replace('tmp/services', 'tmp/native-cream-chat-repair/services')
    adapted = adapted.replace('cache/services', 'cache/native-cream-chat-repair/services')
    # No assertions, authority or operation expectations are changed.
    module = types.ModuleType('chat_repair_existing_services'); module.__file__ = str(path)
    sys.modules[module.__name__] = module
    exec(compile(adapted, str(path), 'exec'), module.__dict__)
    (out/'storage-adapter.json').write_text(json.dumps(dict(original=str(path),
        originalSHA256=hashlib.sha256(source.encode()).hexdigest(), adaptedSHA256=hashlib.sha256(adapted.encode()).hexdigest(),
        replacements=['ISOLATED=DEV', 'tmp/services -> tmp/native-cream-chat-repair/services', 'cache/services -> cache/native-cream-chat-repair/services'],
        output=str(out), unchangedAssertions=True, unchangedOperations=True), indent=2)+'\n')
    (out/'storage-adapted-runner.py').write_text(adapted)
    selected = ['test_chat_only_explicit_send_dedup_independent_versions_drafts_and_cancel',
                'test_auth_stays_status_models_only_and_forwarded_home_never_mutates',
                'test_swift_real_http_root_prefixed_and_injected_state_recovery_appkit']
    return unittest.TestSuite(module.NativeServiceTests(name) for name in selected)
