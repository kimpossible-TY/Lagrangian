"""Required actual signed app, relocation, offline/source-denied backend/native proof.

No optional skips, GUI activation, live launchd, account, installation or Rust.
Wrap this top-level suite exactly once with with-native-swift-lock.py.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time
import unittest
import urllib.request

REPO = Path(__file__).resolve().parents[3]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
EVIDENCE = DEV / 'test-output/delivery-production/NA13'
APP = Path(os.environ.get('NATIVE_DELIVERY_APP', DEV / 'build/delivery-production/Lagrangian.app'))
spec = importlib.util.spec_from_file_location('required_delivery', REPO / 'scripts/stage-native-reader-delivery.py')
delivery = importlib.util.module_from_spec(spec); spec.loader.exec_module(delivery)


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


class InstalledDeliveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not APP.is_dir():
            raise RuntimeError('Required actual .app missing; build with --delivery first')
        if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Required top-level Swift lock missing')
        cls.out = EVIDENCE / ('installed-' + str(time.time_ns())); cls.out.mkdir(parents=True)
        cls.commands = []; cls.server = None
        cls.app = cls.out / 'relocated/Lagrangian.app'
        shutil.copytree(APP, cls.app, symlinks=True)
        cls.root = cls.app / 'Contents/Resources/native-reader'
        cls.manifest = delivery.verify(cls.root)
        cls.env = {k:str(cls.out/name) for k,name in [('HOME','home'),('TMPDIR','tmp'),('FLOW_DATA_DIR','app-data'),
            ('FLOW_LOG_DIR','app-logs'),('FLOW_READER_DATA_DIR','reader-data'),('XDG_CACHE_HOME','cache'),('TYPST_PACKAGE_CACHE_PATH','package-cache')]}
        for name in cls.env.values(): Path(name).mkdir(parents=True)
        cls.env.update(PATH='/usr/bin:/bin', PYTHONHOME=str(cls.root/'python'), PYTHONNOUSERSITE='1', PYTHONDONTWRITEBYTECODE='1', NODE_PATH='', NODE_OPTIONS='')
        cls.env['FLOW_ENGINE_PATH'] = str(cls.app/'Contents/MacOS/flow-engine')
        deny = [DEV/'worktrees',DEV/'dependencies',Path('/opt/homebrew'),Path('/Users/taeyoung/.npm'),Path('/Users/taeyoung/Library/Caches'), APP]
        cls.profile = '(version 1)(allow default)(deny network*)' + ''.join('(deny file-read* (subpath '+json.dumps(str(p))+'))' for p in deny)
        cls.loopback = cls.profile + '(allow network-inbound (local ip "localhost:*"))(allow network-outbound (remote ip "localhost:*"))'
        cls.node = cls.root / 'runtime/node/bin/node'; cls.python = cls.root/'python/bin/python3.13'
        # Real denial probes must succeed as denials before any positive proof.
        p=cls.command([cls.node,'-e',"require('net').createConnection({host:'127.0.0.1',port:9})"], expected=1)
        if 'EPERM' not in p.stderr: raise RuntimeError('OS network denial not demonstrated')
        for denied in [REPO/'package.json',DEV/'dependencies/native-runtime/package.json',APP/'Contents/Info.plist']:
            p=cls.command([cls.node,'-e','require("fs").readFileSync(process.argv[1])',denied],expected=1)
            if 'EPERM' not in p.stderr: raise RuntimeError('OS source/dependency/original-app denial not demonstrated')
        cls.command([cls.python,'-s','-B','-c','import sys,ssl,sqlite3,ctypes,zlib,bz2,lzma; print(sys.prefix); print(ssl.OPENSSL_VERSION)'])
        # Existing profile/config contracts, all paths point into this relocated app.
        cls.project=cls.out/'project';cls.project.mkdir();(cls.project/'main.typ').write_text('= Delivery\n\nReal portable backend and native $a/b$.\n')
        cls.packages=cls.out/'packages';cls.packages.mkdir()
        with socket.socket() as sock: sock.bind(('127.0.0.1',0)); cls.port=sock.getsockname()[1]
        parent={'id':'parent','name':'Delivery fixture','root':str(cls.project),'entry':'main.typ','fonts':[],
            'packages':str(cls.packages),'port':cls.port+1 if cls.port<65535 else cls.port-1,'publicURL':'','label':'dev.lagrangian.na13.fixture.parent'}
        save(Path(cls.env['FLOW_DATA_DIR'])/'profiles.json',{'schemaVersion':1,'selectedID':'parent','profiles':[parent]})
        config={'schemaVersion':1,'flowManager':str(cls.app/'Contents/MacOS/Lagrangian'),'python':str(cls.python),
            'compiler':str(cls.root/'compiler/typst'),'engine':str(cls.app/'Contents/MacOS/flow-engine'),
            'services':[{'id':'reader','parentID':'parent','port':cls.port,'publicURL':''}]}
        save(Path(cls.env['FLOW_READER_DATA_DIR'])/'config.json',config)
        cls.manager=cls.root/'reader-manager'
        profiles=json.loads(cls.command([cls.manager,'--profiles']).stdout)
        if len(profiles['profiles']) != 1: raise RuntimeError('default manager did not resolve actual fixture profile')
        cls.plan=json.loads(cls.command([cls.manager,'--launch-plan','reader']).stdout)
        if cls.plan['arguments'][0] != str(cls.python) or str(cls.root/'compiler/typst') not in cls.plan['arguments']:
            raise RuntimeError('default manager plan escaped bundled dependencies')
        tls_code = r'''import importlib.util,json,sys,ssl,os
from pathlib import Path
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('bundled_delivery',root/'delivery.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
module.launch_manager(['--profiles'])
context=ssl.create_default_context();stats=context.cert_store_stats()
assert stats['x509_ca']>0 and os.environ['SSL_CERT_FILE']==str(root/'certificates/cacert.pem')
print(json.dumps({'trustStore':os.environ['SSL_CERT_FILE'],'stats':stats,'networkUsed':False}))
'''
        tls=cls.command([cls.python,'-s','-B','-c',tls_code,cls.root])
        save(cls.out/'tls-data-proof.json',json.loads(tls.stdout.splitlines()[-1]))
        # --serve is the existing foreground service entrypoint; no launchctl call.
        log=(cls.out/'backend.log').open('w');cls.addClassCleanup(log.close)
        argv=['/usr/bin/sandbox-exec','-p',cls.loopback,str(cls.manager),'--serve','reader']
        cls.server=subprocess.Popen(argv,env=cls.env,cwd=cls.out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        cls.addClassCleanup(cls.stop_server)
        state=None
        for _ in range(300):
            if cls.server.poll() is not None: raise RuntimeError('bundled backend exited: '+(cls.out/'backend.log').read_text()[-4000:])
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{cls.port}/api/state',timeout=1) as response: state=json.load(response)
                if state.get('revision') and not state.get('compiling'): break
            except OSError: pass
            time.sleep(.1)
        else: raise RuntimeError('required default backend publication failed: '+(cls.out/'backend.log').read_text()[-4000:])
        save(cls.out/'backend-state.json',state)
        # Contract fake process observation; real manager.attach and actual HTTP.
        # No real launchd operation is used or claimed.
        code='''import json,sys
from pathlib import Path
root=Path(sys.argv[1]); sys.path.insert(0,str(root/'tools/flow-reader'))
from flow_reader.services.manager import ReaderManager
m=ReaderManager();m.job_pid=lambda profile,**kwargs:int(sys.argv[3])
def forbidden(*args):raise RuntimeError('unexpected lifecycle request')
m.control=forbidden
print(json.dumps(m.attach(sys.argv[2],'main.typ')))
'''
        attachment=json.loads(cls.command([cls.python,'-s','-B','-c',code,cls.root,cls.project,cls.server.pid],loopback=True).stdout)
        save(cls.out/'attachment.json',{'root':str(cls.project),'attachment':attachment})
        query_code = r'''import json,sys,urllib.request,urllib.parse,uuid
state=json.loads(sys.argv[2]);service=state['service']
fields={'documentID':state['documentID'],'serviceID':f"reader:{service['pid']}:{service['startedAt']}",'revision':state['revision'],
        'generation':1,'schemaVersion':1,'capabilities':'semantic-tree-v1,image-layout-v1','requestID':str(uuid.uuid4()),'viewID':str(uuid.uuid4())}
url=sys.argv[1]+'api/native-document?'+urllib.parse.urlencode(fields)
request=urllib.request.Request(url,headers={'Origin':sys.argv[1].rstrip('/')})
with urllib.request.urlopen(request,timeout=10) as response:print(response.read().decode())
'''
        document=json.loads(cls.command([cls.python,'-s','-B','-c',query_code,f'http://127.0.0.1:{cls.port}/',json.dumps(state)],loopback=True).stdout)
        save(cls.out/'document.json',document)
        def nodes(values):
            for node in values:
                yield node
                yield from nodes(node['children'])
        actual_math=next(n['math'] for n in nodes(document['blocks']) if n.get('math'))
        save(cls.out/'paint-math.json',actual_math)
        request={'mathML':actual_math['mathML'],'width':320,'fontSize':20,'font':'MathJaxNewcm',
                 'context':{'revision':document['identity']['revision'],'generation':1,'theme':'light'}}
        math=cls.command([cls.node,cls.root/'runtime/helper.mjs','--runtime',cls.root/'runtime'],input=json.dumps(request)).stdout
        (cls.out/'math.json').write_text(math)
        sources=json.loads((REPO/'apps/macos/sources.json').read_text())
        swift=[REPO/'apps/macos'/name for section in ('core','native') for name in sources[section]]
        cls.binary=cls.out/'InstalledProbe'
        cls.command(['/usr/bin/swiftc','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0',
            '-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH'],*swift,REPO/'tests/flow-app/native-reader-app/NativeReaderBundleEnvironmentTests.swift','-o',cls.binary],sandbox=False,timeout=180)
        cls.command([cls.binary,cls.app,cls.out,'--document'],loopback=True,timeout=120)
        cls.result=json.loads((cls.out/'installed-native-results.json').read_text())
        save(EVIDENCE/'installed-latest.json',{'output':str(cls.out),'app':str(cls.app),'manifestSHA256':delivery.sha(cls.root/'delivery-manifest.json'),
            'requiredSkip':0,'managedLifecycle':'not executed; foreground --serve plus contract fake process observation','GUI':False,'macOS13Execution':'unverified'})

    @classmethod
    def command(cls,args,expected=0,input=None,loopback=False,sandbox=True,timeout=120):
        argv=list(map(str,args)); argv=(['/usr/bin/sandbox-exec','-p',cls.loopback if loopback else cls.profile]+argv) if sandbox else argv
        started=time.monotonic();p=subprocess.run(argv,input=input,text=True,capture_output=True,env=cls.env if sandbox else None,cwd=cls.out,timeout=timeout)
        cls.commands.append({'argv':argv,'cwd':str(cls.out),'input':input,'exit':p.returncode,'seconds':time.monotonic()-started,'stdout':p.stdout,'stderr':p.stderr})
        save(cls.out/'commands.json',cls.commands)
        if (p.returncode == 0 if expected is None else p.returncode != expected):raise RuntimeError(f'expected {expected}, got {p.returncode}: {argv}: {p.stderr[-4000:]}')
        return p

    @classmethod
    def stop_server(cls):
        if cls.server is not None:
            if cls.server.poll() is None: os.killpg(cls.server.pid,signal.SIGTERM)
            try: status=cls.server.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(cls.server.pid,signal.SIGKILL);status=cls.server.wait()
            cls.commands.append({'argv':[str(cls.manager),'--serve','reader'],'cwd':str(cls.out),'exit':status,'termination':'owned fixture stopped after proof'})
            save(cls.out/'commands.json',cls.commands)

    def test_actual_default_backend_scoped_document_and_native_paint(self):
        self.assertGreater(self.result['nativeDocumentBlocks'],0)
        self.assertTrue(self.result['defaultBundleEnvironment'])
        self.assertTrue(all(self.result[k]>10 for k in ('above','below','rule')))
        self.assertEqual(self.result['requiredSkip'],0)
        self.assertFalse(self.result['GUI'])

    def test_missing_interpreter_node_compiler_module_and_image_reject(self):
        for name in ['python/bin/python3.13','runtime/node/bin/node','compiler/typst','runtime/node_modules/@mathjax/src/cjs/mathjax.js','tools/flow-reader/manage.py','python/lib/libssl.3.dylib','certificates/cacert.pem']:
            path=self.root/name;backup=path.with_name(path.name+'.withheld');path.rename(backup)
            try:
                with self.assertRaises((ValueError,OSError)):delivery.verify(self.root,signatures=False)
                self.command([self.manager,'--profiles'],expected=None)
            finally:backup.rename(path)

    def test_stale_source_helper_and_manifest_path_escape_reject(self):
        m=self.manifest
        for key in ['sourceRevision','helperSHA256','runtimeManifestSHA256','readerBundleChecksum']:
            expected={**m,key:('0'*40 if key=='sourceRevision' else '0'*64)}
            with self.assertRaises(ValueError):delivery.verify(self.root,expected,signatures=False)
        file=self.root/'delivery-manifest.json';original=file.read_bytes()
        try:
            altered={**m,'entrypoints':{**m['entrypoints'],'manager':'../../escape'}};save(file,altered)
            with self.assertRaises(ValueError):delivery.verify(self.root,signatures=False)
        finally:file.write_bytes(original)

    def test_post_sign_tamper_and_external_symlink_reject(self):
        file=self.root/'compiler/typst';original=file.read_bytes()
        try:
            with file.open('ab') as stream:stream.write(b'post-sign tamper')
            with self.assertRaises(ValueError):delivery.verify(self.root,signatures=False)
            p=subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',self.app],capture_output=True)
            self.assertNotEqual(p.returncode,0)
        finally:file.write_bytes(original)
        link=self.root/'external';link.symlink_to('/etc/hosts')
        try:
            with self.assertRaises(ValueError):delivery.verify(self.root,signatures=False)
        finally:link.unlink()

    def test_unbound_external_configuration_is_not_a_fallback(self):
        file=Path(self.env['FLOW_READER_DATA_DIR'])/'config.json';original=file.read_bytes()
        try:
            config=json.loads(original);config['compiler']='/usr/bin/true';save(file,config)
            p=self.command([self.manager,'--profiles'],expected=1)
            self.assertIn('rebinding',p.stderr)
        finally:file.write_bytes(original)

    def test_failed_staging_preserves_previous_valid_output(self):
        output=DEV/'build/delivery-production/initial-delivery'
        before=delivery.sha(output/'delivery-manifest.json')
        binding=delivery.read(DEV/'build/delivery-production/initial-binding.json')
        binding['sourceFiles']=delivery.source_binding(REPO)
        binding['sourceRevision']=subprocess.check_output(['git','-C',str(REPO),'rev-parse','HEAD'],text=True).strip()
        input_manifest=self.out/'rejected-candidate-binding.json';save(input_manifest,binding)
        argv=[sys.executable,'-B',REPO/'scripts/stage-native-reader-delivery.py','stage',
            '--manifest',input_manifest,'--engine',Path('/Users/taeyoung/Applications/Lagrangian.app/Contents/MacOS/flow-engine'),
            '--runtime-source',DEV/'build/delivery-production/runtime','--helper',DEV/'build/runtime-producer/NA11/runtime/helper.mjs',
            '--backend',REPO,'--reader-bundle',DEV/'build/delivery-production/current-reader',
            '--python-archive',DEV/'dependencies/portable-python/python-3.13.11-macos11.pkg',
            '--compiler',DEV/'dependencies/portable-typst/v0.15.1/typst-aarch64-apple-darwin/typst',
            '--typst-packages',DEV/'dependencies/portable-typst/packages','--certifi-wheel',DEV/'dependencies/portable-python/certifi-2026.10.23-py3-none-any.whl','--output',output]
        p=self.command(argv,expected=1,sandbox=False)
        self.assertIn('old helper mismatch',p.stderr)
        self.assertEqual(delivery.sha(output/'delivery-manifest.json'),before)
        self.assertFalse(Path(str(output)+'.lock').exists())

    def test_final_app_acceptance_stays_distinct_from_delivery_integrity(self):
        self.assertEqual(self.manifest['capabilities']['originalPages'],'pending NA12')
        self.assertEqual(self.manifest['capabilities']['GUI'],'unverified')
        self.assertFalse((self.out/'home/Library/LaunchAgents').exists())

    @classmethod
    def tearDownClass(cls):
        delivery.verify(cls.root)
        save(cls.out/'summary.json',{'tests':7,'requiredSkip':0,'native':cls.result,
            'sourceDenied':True,'dependencyDenied':True,'originalAppDenied':True,'networkDeniedProbe':True,
            'backend':'actual bundled foreground manager/reader/compiler','managedAttach':'contract fake process provider',
            'sourceRevision':cls.manifest['sourceRevision'],'sourceFiles':cls.manifest['sourceFiles']})


if __name__=='__main__':unittest.main()
