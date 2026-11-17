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
EVIDENCE = Path(os.environ.get('NATIVE_DELIVERY_EVIDENCE_DIR', DEV / 'test-output/delivery-production/NA13'))
BUILD = Path(os.environ.get('NATIVE_DELIVERY_BUILD_DIR', DEV / 'build/delivery-production'))
ENGINE_INPUT = DEV / 'build/delivery-production/Lagrangian.app/Contents/MacOS/flow-engine'
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
        # Legacy schema-1 config is unchanged; unused external executable paths
        # must never be accessed or used by the verified bundle composition.
        cls.project=cls.out/'project';cls.project.mkdir();(cls.project/'main.typ').write_text('= Delivery\n\nReal portable backend and native $a/b$.\n')
        cls.packages=cls.out/'packages';cls.packages.mkdir()
        with socket.socket() as sock: sock.bind(('127.0.0.1',0)); cls.port=sock.getsockname()[1]
        parent={'id':'parent','name':'Delivery fixture','root':str(cls.project),'entry':'main.typ','fonts':[],
            'packages':str(cls.packages),'port':cls.port+1 if cls.port<65535 else cls.port-1,'publicURL':'','label':'dev.lagrangian.na13.fixture.parent'}
        cls.parent=parent
        save(Path(cls.env['FLOW_DATA_DIR'])/'profiles.json',{'schemaVersion':1,'selectedID':'parent','profiles':[parent]})
        config={'schemaVersion':1,'flowManager':'/__na13_previous_release__/Lagrangian','python':'/opt/homebrew/__na13_previous_release__/python3',
            'compiler':'/opt/homebrew/__na13_previous_release__/typst','engine':'/__na13_previous_release__/flow-engine',
            'services':[{'id':'reader','parentID':'parent','port':cls.port,'publicURL':''}]}
        save(Path(cls.env['FLOW_READER_DATA_DIR'])/'config.json',config)
        cls.config=config
        cls.config_file=Path(cls.env['FLOW_READER_DATA_DIR'])/'config.json'
        cls.config_bytes=cls.config_file.read_bytes()
        save(cls.out/'external-config-before.json',config)
        cls.manager=cls.root/'reader-manager'
        profiles=json.loads(cls.command([cls.manager,'--profiles']).stdout)
        if len(profiles['profiles']) != 1: raise RuntimeError('default manager did not resolve actual fixture profile')
        cls.plan=json.loads(cls.command([cls.manager,'--launch-plan','reader']).stdout)
        if cls.plan['arguments'][:2] != [str(cls.manager),'--backend'] or str(cls.root/'compiler/typst') not in cls.plan['arguments']:
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
        code=cls.attach_code()
        attachment=json.loads(cls.command([cls.python,'-s','-B','-c',code,cls.root,cls.project,cls.server.pid],loopback=True).stdout)
        save(cls.out/'attachment.json',{'root':str(cls.project),'attachment':attachment})
        query_code = r'''import json,sys,urllib.request,urllib.parse,uuid
state=json.loads(sys.argv[2]);service=state['service']
fields={'documentID':state['documentID'],'serviceID':f"reader:{service['pid']}:{service['startedAt']}",'revision':state['revision'],
        'generation':1,'schemaVersion':1,'capabilities':'semantic-tree-v1,image-layout-v1','requestID':str(uuid.uuid4()),'viewID':str(uuid.uuid4())}
url=sys.argv[1]+'api/native-document?'+urllib.parse.urlencode(fields)
origin=urllib.parse.urlsplit(sys.argv[1])
request=urllib.request.Request(url,headers={'Origin':origin.scheme+'://'+origin.netloc})
with urllib.request.urlopen(request,timeout=10) as response:print(response.read().decode())
'''
        cls.query_code=query_code
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
    def attach_code(cls):
        return r'''import importlib.util,json,sys
from pathlib import Path
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('bundled_delivery',root/'delivery.py');bundle=importlib.util.module_from_spec(spec);spec.loader.exec_module(bundle)
m=bundle.bundled_manager();m.job_pid=lambda profile,**kwargs:int(sys.argv[3])
def forbidden(*args):raise RuntimeError('unexpected lifecycle request')
m.control=forbidden
from flow_reader.services.manager import cli
raise SystemExit(cli(['--attach','--root',sys.argv[2],'--entry','main.typ'],manager=m))
'''

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
        self.assertGreater(self.result['originalPDFPages'],0)
        self.assertGreater(self.result['originalPDFPaintCount'],0)
        self.assertEqual(self.result['originalSourceAnchors'],'unsupported')
        self.assertEqual(self.result['originalDelivery'],'immutable-pdf-full-reset')
        self.assertEqual(delivery.sha(self.out/'installed-original.pdf'),self.result['originalPDFSHA256'])

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

    # Destructive Mach-O mutation runs after positive child execution: restoring
    # bytes does not synchronously restore the kernel's executable validation.
    def test_z_post_sign_tamper_and_external_symlink_reject(self):
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

    def test_external_configuration_is_unchanged_and_does_not_select_executables(self):
        self.assertEqual(self.config_file.read_bytes(),self.config_bytes)
        for key in ('python','compiler','flowManager','engine'):
            self.assertIn('__na13_previous_release__',self.config[key])
        self.assertIn(str(self.root/'compiler/typst'),self.plan['arguments'])
        self.assertIn(str(self.app/'Contents/MacOS/flow-engine'),self.plan['arguments'])
        self.assertEqual(self.plan['agent']['ProgramArguments'][0],str(self.manager))
        self.assertFalse((Path(self.env['FLOW_READER_DATA_DIR'])/'bin').exists())

    def test_outer_seal_release_pair_and_environment_cannot_forge_binding(self):
        for file in (self.root/'delivery-manifest.json',self.app/'Contents/Resources/release.json'):
            original=file.read_bytes()
            try:
                value=json.loads(original);value['sourceRevision']='0'*40;save(file,value)
                self.command([self.manager,'--profiles'],expected=1)
            finally:file.write_bytes(original)
        unsealed=self.out/'unsealed';unsealed.mkdir()
        shutil.copy2(self.root/'delivery.py',unsealed/'delivery.py')
        from unittest.mock import patch
        with patch.dict(self.env, NATIVE_READER_BUNDLE_ROOT=str(self.root), READER_EXECUTABLE_BINDINGS=json.dumps(self.manifest['entrypoints'])):
            p=self.command([self.python,'-s','-B',unsealed/'delivery.py','manager','--profiles'],expected=1)
        self.assertIn('not an app delivery layout',p.stderr)
        self.assertEqual(self.config_file.read_bytes(),self.config_bytes)

    def test_shared_child_reenters_verified_composition_with_external_config_unchanged(self):
        directory=self.out/'shared-manager';directory.mkdir()
        def free_port():
            with socket.socket() as sock:
                sock.bind(('127.0.0.1',0));return sock.getsockname()[1]
        occupied={self.port,self.parent['port']}
        def next_port():
            value=free_port()
            while value in occupied:value=free_port()
            occupied.add(value);return value
        legacy,shared=next_port(),next_port()
        config={**self.config,'services':[{**self.config['services'][0],'port':legacy}],'shared':{'port':shared}}
        file=directory/'config.json';save(file,config);original=file.read_bytes()
        env={**self.env,'FLOW_READER_DATA_DIR':str(directory)}
        from unittest.mock import patch
        with patch.dict(self.env,env,clear=True):
            plan=json.loads(self.command([self.manager,'--launch-plan','reader']).stdout)
            self.assertEqual(plan['arguments'],[str(self.manager),'--backend','--managed','--data',str(directory)])
            log=(self.out/'shared-backend.log').open('w')
            argv=['/usr/bin/sandbox-exec','-p',self.loopback,str(self.manager),'--serve-all']
            child=subprocess.Popen(argv,env=env,cwd=self.out,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            started=time.monotonic()
            try:
                for _ in range(300):
                    if child.poll() is not None:raise RuntimeError('shared child exited: '+(self.out/'shared-backend.log').read_text()[-4000:])
                    try:
                        with urllib.request.urlopen(f'http://127.0.0.1:{shared}/d/reader/api/state',timeout=1) as response:state=json.load(response)
                        if state.get('revision') and not state.get('compiling'):break
                    except OSError:pass
                    time.sleep(.1)
                else:raise RuntimeError('shared publication failed: '+(self.out/'shared-backend.log').read_text()[-4000:])
                report=json.loads((directory/'documents/reader/report.json').read_text())
                self.assertTrue(report['contentGatePassed'])
                self.assertEqual(report['compiler'],str(self.root/'compiler/typst'))
                # Host-side observation of our fixture PID only. macOS refuses
                # to exec ps inside this sandbox; the backend remains sandboxed.
                process=self.command(['/bin/ps','-p',str(child.pid),'-o','command='],sandbox=False).stdout
                # Official framework Python's bin launcher execs its bundled
                # Python.app image; ps reports that image, not the bin launcher.
                image=self.root/'python/Resources/Python.app/Contents/MacOS/Python'
                self.assertTrue(process.startswith(str(image)+' '))
                image_record=next(record for record in self.manifest['files']
                                  if record['path']==str(image.relative_to(self.root)))
                self.assertEqual(delivery.sha(image),image_record['sha256'])
                self.assertIn('manager --backend --managed',process)
                attached=json.loads(self.command([self.python,'-s','-B','-c',self.attach_code(),self.root,self.project,child.pid],loopback=True).stdout)
                self.assertEqual(attached['url'],f'http://127.0.0.1:{shared}/d/reader/')
                self.assertEqual(attached['service']['pid'],child.pid)
                scoped=self.out/'shared-native';scoped.mkdir()
                document=json.loads(self.command([self.python,'-s','-B','-c',self.query_code,attached['url'],json.dumps(state)],loopback=True).stdout)
                save(scoped/'document.json',document)
                save(scoped/'attachment.json',{'root':str(self.project),'attachment':attached})
                for name in ['math.json','paint-math.json']:shutil.copy2(self.out/name,scoped/name)
                self.command([self.binary,self.app,scoped,'--document'],loopback=True)
                painted=json.loads((scoped/'installed-native-results.json').read_text())
                self.assertGreater(painted['originalPDFPaintCount'],0)
                self.assertEqual(delivery.sha(scoped/'installed-original.pdf'),painted['originalPDFSHA256'])
                save(self.out/'shared-binding-proof.json',{'argv':argv,'pid':child.pid,'process':process,'plan':plan,'state':state,'compilerReport':report,'attachment':attached,'configBeforeSHA256':hashlib.sha256(original).hexdigest(),'configUnchanged':file.read_bytes()==original,'lifecycle':'contract fake PID for attach; actual foreground --serve-all child; no launchctl'})
                self.assertEqual(file.read_bytes(),original)
            finally:
                if child.poll() is None:os.killpg(child.pid,signal.SIGTERM)
                try:status=child.wait(timeout=10)
                except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);status=child.wait()
                log.close()
                self.commands.append({'argv':argv,'cwd':str(self.out),'exit':status,'seconds':time.monotonic()-started,'ownedFixture':True})
                save(self.out/'commands.json',self.commands)
        self.assertEqual(self.config_file.read_bytes(),self.config_bytes)

    def test_failed_staging_preserves_previous_valid_output(self):
        output=BUILD/'initial-delivery'
        before=delivery.sha(output/'delivery-manifest.json')
        binding=delivery.read(BUILD/'initial-binding.json')
        binding['sourceFiles']=delivery.source_binding(REPO)
        binding['sourceRevision']=subprocess.check_output(['git','-C',str(REPO),'rev-parse','HEAD'],text=True).strip()
        input_manifest=self.out/'rejected-candidate-binding.json';save(input_manifest,binding)
        argv=[sys.executable,'-B',REPO/'scripts/stage-native-reader-delivery.py','stage',
            '--manifest',input_manifest,'--engine',ENGINE_INPUT,
            '--runtime-source',BUILD/'runtime','--helper',DEV/'build/runtime-producer/NA11/runtime/helper.mjs',
            '--backend',REPO,'--reader-bundle',BUILD/'current-reader',
            '--python-archive',DEV/'dependencies/portable-python/python-3.13.11-macos11.pkg',
            '--compiler',DEV/'dependencies/portable-typst/v0.15.1/typst-aarch64-apple-darwin/typst',
            '--typst-packages',DEV/'dependencies/portable-typst/packages','--certifi-wheel',DEV/'dependencies/portable-python/certifi-2026.10.23-py3-none-any.whl','--output',output]
        p=self.command(argv,expected=1,sandbox=False)
        self.assertIn('old helper mismatch',p.stderr)
        self.assertEqual(delivery.sha(output/'delivery-manifest.json'),before)
        self.assertFalse(Path(str(output)+'.lock').exists())

    def test_final_app_acceptance_stays_distinct_from_delivery_integrity(self):
        self.assertEqual(self.manifest['capabilities']['originalPages'],'original-pdf-full-v1')
        self.assertEqual(self.manifest['capabilities']['GUI'],'unverified; fixed preparation integrated')
        self.assertEqual(self.manifest['capabilities']['sourceRevision'],self.manifest['sourceRevision'])
        self.assertFalse((self.out/'home/Library/LaunchAgents').exists())

    @classmethod
    def tearDownClass(cls):
        delivery.verify(cls.root)
        if cls.config_file.read_bytes()!=cls.config_bytes:raise RuntimeError('original fixture configuration changed')
        save(cls.out/'summary.json',{'tests':9,'requiredSkip':0,'native':cls.result,
            'sourceDenied':True,'dependencyDenied':True,'originalAppDenied':True,'networkDeniedProbe':True,
            'backend':'actual bundled foreground manager/reader/compiler','managedAttach':'contract fake process provider',
            'sourceRevision':cls.manifest['sourceRevision'],'sourceFiles':cls.manifest['sourceFiles']})


def gui_fixture_owner():
    """Compose final evidence storage with the unchanged fixed G1 fixture owner.

    This changes only its storage base and reentry script. Root/argument/source/
    HTTP/sandbox/clipboard/lifecycle policy remains in that owner.
    """
    spec = importlib.util.spec_from_file_location('final_gui_fixture_owner',
        Path(__file__).with_name('test_app_integration.py'))
    owner = importlib.util.module_from_spec(spec); spec.loader.exec_module(owner)
    owner.GUI_ROOT = Path(os.environ.get('FLOW_GUI_FIXTURE_ROOT', DEV / 'test-output/delivery-production/NA13/final-app-v1'))
    owner.GUI_SCRIPT = Path(__file__).resolve()
    return owner


if __name__=='__main__':
    if sys.argv[1:2]==['gui-fixture']:
        gui_fixture_owner().gui_cli(sys.argv[2:])
    else:
        unittest.main()
