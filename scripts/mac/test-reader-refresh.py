#!/usr/bin/env python3
"""Exercise updater reader transactions using isolated fake managers and HTTP."""
import hashlib
import http.server
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[2]

class Handler(http.server.BaseHTTPRequestHandler):
    paths = []
    status_code = 200
    events_path = None
    def do_GET(self):
        self.paths.append(self.path)
        if self.events_path is not None:
            with Path(self.events_path).open('a') as f:
                f.write('verify ' + self.path + '\n')
        self.send_response(self.status_code); self.end_headers()
    def log_message(self, *args): pass

class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name); self.data = self.home / 'Library/Application Support/Lagrangian/reader'
        (self.data / 'bin').mkdir(parents=True)
        self.server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close); self.addCleanup(self.server.shutdown)
        Handler.paths = []
        Handler.status_code = 200
        self.port = self.server.server_port
        self.env = dict(os.environ, HOME=str(self.home), READER_SRC=str(self.home / 'source'))
        (self.home / 'source/tools/flow-reader').mkdir(parents=True)
        self.events = self.home / 'events'
        Handler.events_path = self.events
        self.launcher = self.data / 'bin/flow-reader'
        self.launcher.write_text('''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
home=Path(os.environ['HOME']); data=home/'Library/Application Support/Lagrangian/reader'
config=json.loads((data/'config.json').read_text()); args=sys.argv[1:]
with (home/'events').open('a') as f: f.write(' '.join(args)+'\\n')
if args[0]=='--profiles':
 print(json.dumps({'profiles':[dict(id=s['id'], port=config.get('shared',{}).get('port',s['port']), shared=bool(config.get('shared')), label='shared' if config.get('shared') else s['id']) for s in config['services']]}))
elif args[0]=='--control':
 if config.get('shared') and args[1]=='stop': sys.exit(1)
else: sys.exit(1)
'''); self.launcher.chmod(0o755)
        self.config = self.data / 'config.json'
        self.services = [{'id':'one-reader','parentID':'one','port':1111}, {'id':'two-reader','parentID':'two','port':2222,'publicURL':''}]
        self.installer = self.home / 'source/tools/flow-reader/install.py'
        self.installer.write_text('''import os, sys
from pathlib import Path
with (Path.home()/'events').open('a') as f: f.write('install '+' '.join(sys.argv[1:])+'\\n')
if '--prune-only' in sys.argv:
 sys.exit(0)
if os.environ.get('FAIL_INSTALL') and sys.argv[sys.argv.index('--profile')+1]=='two':
 config=Path.home()/'Library/Application Support/Lagrangian/reader/config.json'
 config.write_text(config.read_text().replace('\"services\"', '\"changed\": true, \"services\"'))
 sys.exit(1)
''')
    def refresh(self, shared=True, fail=False, extra_env=None):
        self.config.write_text(json.dumps({'services':self.services, **({'shared':{'port':self.port}} if shared else {})}))
        env=dict(self.env, FAIL_INSTALL='1' if fail else '', **(extra_env or {}))
        return subprocess.run(['bash',str(ROOT/'scripts/mac/refresh-reader-engine.sh')],env=env,capture_output=True,text=True)
    def test_shared_transaction_and_empty_urls(self):
        result=self.refresh(); self.assertEqual(result.returncode,0,result.stderr)
        events=self.events.read_text().splitlines()
        controls=[e for e in events if e.startswith('--control')]
        self.assertEqual(controls,['--control stop-shared one-reader','--control start one-reader'])
        installs=[e for e in events if e.startswith('install ') and '--prune-only' not in e]
        prunes=[e for e in events if e.startswith('install --prune-only')]
        self.assertEqual(len(installs),2)
        self.assertEqual(len(prunes),1)
        self.assertIn('--profile one --port 1111', installs[0]); self.assertIn('--profile two --port 2222', installs[1])
        self.assertTrue(all('--no-prune' in e and '--start' not in e and '--public-url' not in e for e in installs))
        self.assertIn('--data ' + str(self.data), prunes[0])
        self.assertLess(events.index(controls[0]),events.index(installs[0])); self.assertLess(events.index(installs[1]),events.index(controls[1]))
        verifies=[i for i, e in enumerate(events) if e.startswith('verify ')]
        self.assertEqual(len(verifies), 2)
        self.assertLess(events.index(controls[1]), verifies[0])
        self.assertLess(verifies[-1], events.index(prunes[0]))
        self.assertEqual(Handler.paths,['/d/one-reader/','/d/two-reader/'])
    def test_failure_restores_files_and_starts_all_legacy_jobs(self):
        releases = self.data / 'releases'
        for name in ('r-old', 'r-active'):
            (releases / name).mkdir(parents=True)
            (releases / name / 'release.json').write_text(json.dumps({'revision': name}))
        original=self.launcher.read_bytes()
        result=self.refresh(shared=False,fail=True); self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.launcher.read_bytes(),original)
        self.assertEqual(json.loads(self.config.read_text())['services'],self.services)
        events=self.events.read_text().splitlines()
        controls=[e for e in events if e.startswith('--control')]
        self.assertEqual(controls[:2],['--control stop one-reader','--control stop two-reader'])
        self.assertEqual(controls[-2:],['--control start one-reader','--control start two-reader'])
        self.assertFalse(any('--prune-only' in e for e in events))
        self.assertTrue((releases / 'r-old').is_dir())
        self.assertTrue((releases / 'r-active').is_dir())

    def test_verify_failure_restores_files_and_deletes_no_releases(self):
        releases = self.data / 'releases'
        for name in ('r-ancient', 'r-old', 'r-new'):
            (releases / name).mkdir(parents=True)
            (releases / name / 'release.json').write_text(json.dumps({'revision': name}))
        self.installer.write_text('''import json, shutil, sys
from pathlib import Path
with (Path.home()/'events').open('a') as f: f.write('install '+' '.join(sys.argv[1:])+'\\n')
data = Path.home() / 'Library/Application Support/Lagrangian/reader'
if '--prune-only' in sys.argv:
 shutil.rmtree(data / 'releases/r-ancient')
 sys.exit(0)
config = data / 'config.json'
payload = json.loads(config.read_text())
payload['mutatedDuringInstall'] = True
config.write_text(json.dumps(payload))
''')
        Handler.status_code = 500
        original_launcher = self.launcher.read_bytes()
        result = self.refresh(shared=True, fail=False,
                              extra_env={'READER_VERIFY_ATTEMPTS': '2', 'READER_VERIFY_INTERVAL': '0'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.launcher.read_bytes(), original_launcher)
        restored_config = json.loads(self.config.read_text())
        self.assertNotIn('mutatedDuringInstall', restored_config)
        self.assertEqual(restored_config['services'], self.services)
        events = self.events.read_text().splitlines()
        installs = [e for e in events if e.startswith('install ') and '--prune-only' not in e]
        self.assertEqual(len(installs), 2)
        self.assertTrue(all('--no-prune' in e for e in installs))
        self.assertFalse(any('--prune-only' in e for e in events))
        for name in ('r-ancient', 'r-old', 'r-new'):
            self.assertTrue((releases / name).is_dir(), name)

    def test_refresh_prunes_obsolete_releases_once_after_verify(self):
        releases = self.data / 'releases'
        for name in ('r-ancient', 'r-prev', 'r-active'):
            (releases / name).mkdir(parents=True)
            (releases / name / 'release.json').write_text(json.dumps({'revision': name}))
        self.installer.write_text('''import shutil, sys
from pathlib import Path
with (Path.home()/'events').open('a') as f: f.write('install '+' '.join(sys.argv[1:])+'\\n')
data = Path.home() / 'Library/Application Support/Lagrangian/reader'
if '--prune-only' in sys.argv:
 assert (data / 'releases/r-ancient').is_dir()
 shutil.rmtree(data / 'releases/r-ancient')
 sys.exit(0)
assert '--no-prune' in sys.argv
assert (data / 'releases/r-ancient').is_dir()
''')
        result = self.refresh(shared=True, fail=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events.read_text().splitlines()
        prunes = [e for e in events if e.startswith('install --prune-only')]
        self.assertEqual(len(prunes), 1)
        verifies = [i for i, e in enumerate(events) if e.startswith('verify ')]
        self.assertLess(verifies[-1], events.index(prunes[0]))
        self.assertFalse((releases / 'r-ancient').exists())
        self.assertTrue((releases / 'r-prev').is_dir())
        self.assertTrue((releases / 'r-active').is_dir())

    def test_prune_nonzero_warns_exits_zero_and_does_not_rollback(self):
        releases = self.data / 'releases'
        for name in ('r-ancient', 'r-active'):
            (releases / name).mkdir(parents=True)
            (releases / name / 'release.json').write_text(json.dumps({'revision': name}))
        self.installer.write_text('''import json, sys
from pathlib import Path
with (Path.home()/'events').open('a') as f: f.write('install '+' '.join(sys.argv[1:])+'\\n')
data = Path.home() / 'Library/Application Support/Lagrangian/reader'
if '--prune-only' in sys.argv:
 print('simulated prune error', file=sys.stderr)
 sys.exit(42)
config = data / 'config.json'
payload = json.loads(config.read_text())
payload['refreshed'] = True
config.write_text(json.dumps(payload))
''')
        result = self.refresh(shared=True, fail=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Warning: Reader release pruning exited with status 42', result.stderr)
        self.assertIn('All Readers refreshed and verified', result.stdout)
        # Refreshed config must stay in place (no rollback occurred).
        refreshed_config = json.loads(self.config.read_text())
        self.assertTrue(refreshed_config.get('refreshed'))
        events = self.events.read_text().splitlines()
        controls = [e for e in events if e.startswith('--control')]
        self.assertEqual(controls, ['--control stop-shared one-reader', '--control start one-reader'])
        prunes = [e for e in events if e.startswith('install --prune-only')]
        self.assertEqual(len(prunes), 1)

    def test_updater_shared_verification_and_marker(self):
        app=self.home/'Applications/Lagrangian.app'; mac=app/'Contents/MacOS'; resources=app/'Contents/Resources'
        mac.mkdir(parents=True); resources.mkdir(parents=True)
        engine=mac/'flow-engine'; engine.write_text('engine')
        sha='a'*40
        (resources/'release.json').write_text(json.dumps({'sourceRevision':sha,'engineSHA256':hashlib.sha256(engine.read_bytes()).hexdigest()}))
        native=mac/'Lagrangian'
        native.write_text("#!/usr/bin/python3\nimport json\nprint(json.dumps({'profiles':[]}))\n"); native.chmod(0o755)
        release=self.data/'releases'/sha; serve=release/'tools/flow-reader/serve.py'
        serve.parent.mkdir(parents=True); serve.write_text('')
        (release/'release.json').write_text(json.dumps({'revision':sha}))
        module=serve.parent/'flow_reader/services'; module.mkdir(parents=True)
        (module/'manager.py').write_text("class ReaderManager:\n def __init__(self, data): pass\n def profile(self, identifier): return {'id':identifier}\n def document_arguments(self, profile): return ['--engine', %r]\n" % str(engine))
        self.launcher.write_text("""#!/usr/bin/python3
import json, os, sys
from pathlib import Path
home=Path.home(); port=int(os.environ['TEST_PORT']); sha=os.environ['TEST_SHA']
serve=home/'Library/Application Support/Lagrangian/reader/releases'/sha/'tools/flow-reader/serve.py'
args=sys.argv[1:]
if args[0]=='--profiles': print(json.dumps({'profiles':[{'id':'one-reader','port':port,'shared':True},{'id':'two-reader','port':port,'shared':True}]}))
elif args[0]=='--launch-plan': print(json.dumps({'arguments':['python3',str(serve),'--managed']}))
elif args[0]=='--status': print(json.dumps({'running':True,'managedByApp':True,'pid':43}))
else: sys.exit(1)
"""); self.launcher.chmod(0o755)
        self.config.write_text(json.dumps({'services':self.services,'shared':{'port':self.port}}))
        support=self.data.parent; helper=support/'refresh-reader-engine.sh'; helper.write_text('#!/bin/bash\nexit 0\n'); helper.chmod(0o755)
        fakebin=self.home/'bin'; fakebin.mkdir()
        for name, body in {'ps':'exit 0', 'sleep':':'}.items():
            path=fakebin/name; path.write_text('#!/bin/bash\n'+body+'\n'); path.chmod(0o755)
        (fakebin/'ps').write_text("#!/bin/bash\ncase \"$*\" in *\"-p 42\"*) echo \"$TEST_NATIVE --background\";; *) echo \"$TEST_SERVE\";; esac\n")
        # No pid before kickstart, so the pre-kickstart pid is empty. After
        # kickstart the same pid 42 is a replacement. lsof must show that
        # binary's inode and path or verify_services rejects the login job.
        (fakebin/'launchctl').write_text("""#!/bin/bash
marker="$HOME/launchctl-kicked"
if [[ "$1" == kickstart ]]; then
  : > "$marker"
  exit 0
fi
if [[ "$1" == print ]]; then
  if [[ -f "$marker" ]]; then
    printf 'state = running\\npid = 42\\n'
  else
    printf 'state = running\\n'
  fi
fi
exit 0
""")
        (fakebin/'launchctl').chmod(0o755)
        (fakebin/'lsof').write_text(
            "#!/bin/bash\nprintf 'ftxt\\ni%s\\nn%s\\n' " + repr(str(native.stat().st_ino)) + ' "$TEST_NATIVE"\n')
        (fakebin/'lsof').chmod(0o755)
        script="""source scripts/mac/auto-update-engine.sh
PATH="$HOME/bin:$PATH"
gh() { printf '%s\n' "$TEST_SHA"; }
git() { :; }
notify() { :; }
python3() {
 case "$1 $2" in
  'scripts/flow-app.py fetch-engine') printf '%s\n' "$TEST_ENGINE" ;;
  'scripts/fetch-reader-bundle.py --run-id') printf '%s\n' "$HOME/source" ;;
  'scripts/flow-app.py build') printf '%s\n' "$APP" ;;
  'scripts/flow-app.py install'|'scripts/flow-app.py verify') : ;;
  *) /usr/bin/python3 "$@" ;;
 esac
}
install_run 123
"""
        cache=self.home/'engine-cache'
        cache.mkdir()
        env=dict(self.env, TEST_PORT=str(self.port), TEST_SHA=sha, TEST_ENGINE=str(engine), TEST_SERVE=str(serve), TEST_NATIVE=str(native), LAGRANGIAN_ENGINE_CACHE=str(cache))
        result=subprocess.run(['bash','-c',script],cwd=ROOT,env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual((support/'last-installed-run').read_text(),'123\n')
        self.assertEqual(Handler.paths,['/d/one-reader/','/d/two-reader/'])

if __name__ == '__main__': unittest.main()
