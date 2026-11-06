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
    def do_GET(self):
        self.paths.append(self.path)
        self.send_response(200); self.end_headers()
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
        self.port = self.server.server_port
        self.env = dict(os.environ, HOME=str(self.home), READER_SRC=str(self.home / 'source'))
        (self.home / 'source/tools/flow-reader').mkdir(parents=True)
        self.events = self.home / 'events'
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
if os.environ.get('FAIL_INSTALL') and sys.argv[sys.argv.index('--profile')+1]=='two':
 config=Path.home()/'Library/Application Support/Lagrangian/reader/config.json'
 config.write_text(config.read_text().replace('\"services\"', '\"changed\": true, \"services\"'))
 sys.exit(1)
''')
    def refresh(self, shared=True, fail=False):
        self.config.write_text(json.dumps({'services':self.services, **({'shared':{'port':self.port}} if shared else {})}))
        env=dict(self.env, FAIL_INSTALL='1' if fail else '')
        return subprocess.run(['bash',str(ROOT/'scripts/mac/refresh-reader-engine.sh')],env=env,capture_output=True,text=True)
    def test_shared_transaction_and_empty_urls(self):
        result=self.refresh(); self.assertEqual(result.returncode,0,result.stderr)
        events=self.events.read_text().splitlines()
        controls=[e for e in events if e.startswith('--control')]
        self.assertEqual(controls,['--control stop-shared one-reader','--control start one-reader'])
        installs=[e for e in events if e.startswith('install ')]
        self.assertEqual(len(installs),2)
        self.assertIn('--profile one --port 1111', installs[0]); self.assertIn('--profile two --port 2222', installs[1])
        self.assertTrue(all('--start' not in e and '--public-url' not in e for e in installs))
        self.assertLess(events.index(controls[0]),events.index(installs[0])); self.assertLess(events.index(installs[1]),events.index(controls[1]))
        self.assertEqual(Handler.paths,['/d/one-reader/','/d/two-reader/'])
    def test_failure_restores_files_and_starts_all_legacy_jobs(self):
        original=self.launcher.read_bytes()
        result=self.refresh(shared=False,fail=True); self.assertNotEqual(result.returncode,0)
        self.assertEqual(self.launcher.read_bytes(),original)
        self.assertEqual(json.loads(self.config.read_text())['services'],self.services)
        controls=[e for e in self.events.read_text().splitlines() if e.startswith('--control')]
        self.assertEqual(controls[:2],['--control stop one-reader','--control stop two-reader'])
        self.assertEqual(controls[-2:],['--control start one-reader','--control start two-reader'])

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
        for name, body in {'launchctl':'echo "pid = 42"', 'ps':'case "$*" in *42*) if [[ "$TEST_PS_READER" == 1 ]]; then echo "$TEST_SERVE"; else echo "$TEST_NATIVE --background"; fi;; esac', 'sleep':':'}.items():
            path=fakebin/name; path.write_text('#!/bin/bash\n'+body+'\n'); path.chmod(0o755)
        (fakebin/'ps').write_text("#!/bin/bash\ncase \"$*\" in *\"-p 42\"*) echo \"$TEST_NATIVE --background\";; *) echo \"$TEST_SERVE\";; esac\n")
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
        env=dict(self.env, TEST_PORT=str(self.port), TEST_SHA=sha, TEST_ENGINE=str(engine), TEST_SERVE=str(serve), TEST_NATIVE=str(native))
        result=subprocess.run(['bash','-c',script],cwd=ROOT,env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual((support/'last-installed-run').read_text(),'123\n')
        self.assertEqual(Handler.paths,['/d/one-reader/','/d/two-reader/'])

if __name__ == '__main__': unittest.main()
