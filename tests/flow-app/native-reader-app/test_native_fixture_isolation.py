"""Explicit NA24 offscreen fixture boundary; OS effects are injected, never performed."""
from pathlib import Path
import os,sys,json,hashlib,subprocess,shutil,time,importlib.util,unittest
R=Path(__file__).resolve().parents[3];D=Path('/Volumes/devSSD/Developer/lagrangian-native-20261117');O=D/'test-output/native-cream-fixture-integration'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
class FixtureIsolation(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  selected=os.environ.get('FIXTURE_ISOLATION_OUTPUT');baseline=os.environ.get('FIXTURE_ISOLATION_BASELINE')=='1'
  if not selected:raise unittest.SkipTest('Explicit task output and one outer Swift lock required')
  cls.out=Path(selected).resolve()
  if not cls.out.is_relative_to(O) or cls.out==O or cls.out.exists() or not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):raise RuntimeError('Fresh task output and shared outer lock required')
  cls.out.mkdir(parents=True);shutil.copy2(__file__,cls.out/'runner.py');cls.root=cls.out/'probe';cls.root.mkdir();cls.ordinary=cls.out/'ordinary-home';cls.ordinary.mkdir()
  (cls.ordinary/'canary.txt').write_text('Virtual home only; must not change.\n');(cls.ordinary/'invalid-descriptor.json').write_text('invalid virtual descriptor; do not resolve in fixture mode')
  reader=cls.ordinary/'Library/Application Support/Lagrangian/reader';reader.mkdir(parents=True);(reader/'config.json').write_text('{"canary":"ordinary manager settings"}')
  original=D/'test-output/native-cream-argv-isolation/round2/candidate-fixture';fixture=cls.out/'candidate-fixture';shutil.copytree(original,fixture);cls.fixture=fixture/'native.json'
  original_doc=json.loads(cls.fixture.read_text());io_doc=json.loads(cls.fixture.read_text());io_doc['blocks']=io_doc['blocks'][:2];io_doc['assets']=[];io_doc['diagnostics']=[]
  io_revision=hashlib.sha256(json.dumps(io_doc['blocks'],sort_keys=True).encode()).hexdigest();io_doc['identity'].update(documentID=io_revision[:24],revision=io_revision)
  cls.io_fixture=fixture/'io-native.json';cls.io_fixture.write_text(json.dumps(io_doc))
  (cls.out/'fixture-derivation.json').write_text(json.dumps(dict(original=str(cls.fixture),originalSHA256=sha(cls.fixture),IOOnly=str(cls.io_fixture),IOOnlySHA256=sha(cls.io_fixture),scope='Separate first-heading/paragraph IO fixture with independent identity; rich document is unchanged and tested separately',nestedSandboxWitness=str(O/'round2-nested-sandbox-oracle.json')),indent=2)+'\n')
  runtime=D/'build/native-reader-intermediate-v4/runtime';expected='aa824a56c4d310a9977cdcc1f7a65dd718b92fcba46605347cad20dd431623fc'
  if sha(runtime/'runtime-manifest.json')!=expected:raise RuntimeError('Runtime input drift')
  rm=json.loads((runtime/'runtime-manifest.json').read_text())
  if sha(runtime/'node/bin/node')!=rm['node']['sha256']:raise RuntimeError('Node pre-execution input drift')
  subprocess.run(['/usr/bin/codesign','--verify','--strict',str(runtime/'node/bin/node')],check=True,capture_output=True)
  subprocess.run([str(runtime/'node/bin/node'),str(runtime/'verify-runtime.mjs'),'--verify',str(runtime),'--node',str(runtime/'node/bin/node')],check=True,capture_output=True)
  (cls.out/'runtime-input').symlink_to(runtime,target_is_directory=True)
  cls.binary=D/'tmp/native-cream-fixture-integration'/(cls.out.name+'-Isolation')
  if cls.binary.exists():raise RuntimeError('Refuse binary overwrite')
  registry=json.loads((R/'apps/macos/sources.json').read_text());sources=[R/'apps/macos'/n for section in ['core','native','app'] for n in registry[section] if n!='main.swift']
  binding=json.loads((O/'baseline/binding.json').read_text());actual=[];adaptations=[];inputs={}
  copies=cls.out/'inputs';copies.mkdir()
  for source in sources:
   relative=str(source.relative_to(R));raw=source.read_text()
   if baseline and relative in binding['files']:
    source=O/'baseline'/relative
    if sha(source)!=binding['files'][relative]:raise RuntimeError('Baseline snapshot drift')
    raw=source.read_text()
   inputs[str(source)]=sha(source);original_text=raw
   if source.name=='FlowApp.swift':
    raw=raw.replace('NSWorkspace.shared.open(', 'FixtureEffects.open(').replace('NSWorkspace.shared.activateFileViewerSelecting(', 'FixtureEffects.reveal(').replace('NSApp.orderFrontStandardAboutPanel(', 'FixtureEffects.about(').replace('let panel = NSOpenPanel()', 'let panel = FixtureEffects.Panel()').replace('try NativeReaderManagedEditor.consentedDescriptor(descriptor)', 'try FixtureEffects.descriptor(descriptor)')
    old='NSPasteboard.general.clearContents()\n      NSPasteboard.general.setString(p.url, forType: .string)'
    raw=raw.replace(old,'_ = p.url; FixtureEffects.general += 1 // intercepted prohibited general-board operation')
   if source.name=='CommandRunner.swift':raw=raw.replace('    try task.run()', '    FixtureEffects.observeChild(path, task.environment)\n    try task.run()')
   if source.name=='EngineLaunch.swift':raw=raw.replace('func serve(_ profile: Profile) throws -> Never {','func serve(_ profile: Profile) throws -> Never {\n    if FixtureEffects.blockEngine { FixtureEffects.engines += 1; throw FlowError(message: "Injected engine dispatch; execution refused") }')
   presentation=[]
   if source.name in ['FlowApp.swift','NativeReaderWindowController.swift']:
    for literal,kind in [('window?.orderFrontRegardless()','order-front'),('window?.makeKeyAndOrderFront(nil)','make-key'),('NSApp.activate(ignoringOtherApps: true)','activate'),('showWindow(nil)','host-show')]:
     count=raw.count(literal)
     if count:
      raw=raw.replace(literal,'FixtureEffects.display("'+kind+'")');presentation.append(dict(literal=literal,count=count,facade='FixtureEffects.windowDisplays'))
    if any(x in raw for x in ['.orderFrontRegardless(','.makeKeyAndOrderFront(','NSApp.activate(','showWindow(nil)']):raise RuntimeError('Unblocked display operation')
   target=copies/source.name;target.write_text(raw);actual.append(target)
   if raw!=original_text:adaptations.append(dict(source=str(source),originalSHA256=hashlib.sha256(original_text.encode()).hexdigest(),compiled=str(target),compiledSHA256=sha(target),role='Injected OS/descriptor/engine/display operations only; guards/authority/properties/assertions unchanged',presentationFacades=presentation))
  harness=R/'tests/flow-app/native-reader-app/NativeFixtureIsolationTests.swift';shutil.copy2(harness,copies/harness.name);actual.append(copies/harness.name)
  argv=['swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0','-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH']]
  if baseline:argv+=['-D','FIXTURE_BASELINE']
  argv+=[*map(str,actual),'-o',str(cls.binary)]
  start=time.time();c=subprocess.run(argv,cwd=R,capture_output=True,text=True)
  (cls.out/'compile.json').write_text(json.dumps(dict(argv=argv,cwd=str(R),start=start,end=time.time(),exit=c.returncode,skip=0,originalInputSHA256=inputs,compiledInputSHA256={str(p):sha(p) for p in actual},harnessSHA256=sha(harness),adaptations=adaptations,stdout=c.stdout,stderr=c.stderr),indent=2)+'\n')
  if c.returncode:raise RuntimeError(c.stderr)
 @classmethod
 def tearDownClass(cls):pass
 def execute_case(self, io_only):
  name="io" if io_only else "rich";fixture=self.io_fixture if io_only else self.fixture
  out=self.out/("result-"+name);out.mkdir();dev=self.out/("devroot-"+name);exe=self.out/'synthetic.app/Contents/MacOS/Lagrangian'
  # Only parent test harness gets a virtual ordinary HOME. No dev TMP/cache/data
  # environment override is supplied to the application configuration.
  env={k:os.environ[k] for k in ['PATH'] if k in os.environ};env.update(HOME=str(self.ordinary),CFFIXED_USER_HOME=str(self.ordinary))
  support=dev/'home/Library/Application Support/Lagrangian';support.mkdir(parents=True)
  profile=dict(id='fixture',name='Fixture',root=str(fixture.parent/'source'),entry='main.typ',fonts=[],packages='',port=23818,publicURL='',label='owned.fixture.integration')
  (support/'profiles.json').write_text(json.dumps(dict(schemaVersion=1,selectedID='fixture',profiles=[profile])))
  argv=[str(self.binary),str(out),str(exe),str(self.ordinary),'--dev-root',str(dev),'--dev-no-activate','--native-reader-fixture',str(fixture)]
  real_home='/Users/taeyoung';policy='(version 1)(allow default)(deny network*)(deny file-write*)(allow file-write* (subpath "'+str(O)+'") (subpath "'+str(D/'tmp/native-cream-fixture-integration')+'") (subpath "'+str(D/'cache/native-cream-fixture-integration')+'"))(deny file-read* (subpath "'+real_home+'"))'
  ordinary_before={str(p.relative_to(self.ordinary)):sha(p) for p in self.ordinary.rglob('*') if p.is_file()}
  command=['/usr/bin/sandbox-exec','-p',policy,*argv] if io_only else argv;start=time.time();p=subprocess.run(command,cwd=R,env=env,capture_output=True,text=True,timeout=120)
  ordinary_after={str(p.relative_to(self.ordinary)):sha(p) for p in self.ordinary.rglob('*') if p.is_file()}
  (out/'command.json').write_text(json.dumps(dict(argv=command,applicationArguments=argv[-5:],cwd=str(R),inputSHA256={str(self.binary):sha(self.binary),str(fixture):sha(fixture)},parentEnvironment=env,parentDoesNotSeedDevChildEnvironment=True,ordinaryBefore=ordinary_before,ordinaryAfter=ordinary_after,outerSandbox=io_only,mathSandbox="Existing production NativeMathWorker PATH-only write/network deny; nested parent unsupported",start=start,end=time.time(),exit=p.returncode,skip=0,stdout=p.stdout,stderr=p.stderr),indent=2)+'\n')
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
  for name,digest in ordinary_before.items():self.assertEqual(ordinary_after.get(name),digest,name)

 def test_three_argument_IO_root_and_local_recovery(self):self.execute_case(True)
 def test_three_argument_rich_fixture_and_actual_math_worker(self):self.execute_case(False)
