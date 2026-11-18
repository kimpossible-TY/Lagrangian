"""Actual offscreen AppKit controls over compiler-accepted semantic/PDF input.
No visible windows, user boards, HTTP, auth, provider or installed service effects.
"""
import sys
sys.dont_write_bytecode = True
import hashlib,json,os,shutil,subprocess,time,unittest
from pathlib import Path
from uuid import uuid4
from urllib.parse import urlencode
R=Path(__file__).resolve().parents[3]
D=Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
O=D/'test-output/native-reader-ui-v7'
RECOVERY_O=D/'test-output/native-reader-recovery-status-v9'
OUT = None  # Collection/import never creates or validates fixture storage.
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n')
class NativeUIRefinement(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  global OUT
  configured = os.environ.get('NATIVE_UI_OUTPUT')
  if not configured or sys.platform != 'darwin':
   raise unittest.SkipTest('Optional macOS fixture requires explicit NATIVE_UI_OUTPUT; import/collection has no storage effects')
  OUT = Path(configured).resolve()
  if not any(OUT.is_relative_to(root.resolve()) for root in (O,RECOVERY_O)):raise RuntimeError('UI evidence must stay in an explicitly owned v7/v9 output')
  if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):raise RuntimeError('Use one outer shared Swift lock')
  OUT.mkdir(exist_ok=True,parents=True)
  sys.path.insert(0,str(R/'tools/flow-reader'))
  from flow_reader.compiler.project import Project
  from flow_reader.server.state import ReaderState
  from flow_reader.server.native_reader import NativeReaderService,service_id
  from flow_reader.server.native_pages import NativePageService
  from flow_reader.document.native_document import SUPPORTED_CAPABILITIES
  source=OUT/'source';source.mkdir()
  (source/'main.typ').write_text('= 긴 한국어 제목과 문서 탐색을 위한 실제 컴파일 문서\n\nSelect this paragraph.\n\nSearch needle on the first page.\n\n#pagebreak()\n\n= 두 번째 절\n\nOther page body.\n')
  compiler=shutil.which('typst')
  if not compiler:raise RuntimeError('Prebuilt Typst required')
  wrapper=OUT/'compiler-bin/offline-typst';wrapper.parent.mkdir()
  wrapper.write_text('#!'+sys.executable+'\nimport sys,os;sys.dont_write_bytecode=True\nos.execv("/usr/bin/sandbox-exec",["sandbox-exec","-p",\'(version 1)(allow default)(deny network*)\','+repr(compiler)+']+sys.argv[1:])\n');wrapper.chmod(0o700)
  state=ReaderState(Project(source,Path('main.typ'),R/'tools/flow-reader/packages',compiler=str(wrapper)),OUT/'publication','',False)
  try:
   state.compile()
   if not state.report.get('contentGatePassed'):raise RuntimeError(str(state.report))
   native=NativeReaderService(state);pages=NativePageService(state,native)
   context=dict(documentID=state.document_id,serviceID=service_id(state.focus.service),revision=state.revision,schemaVersion=1,generation=1,requestID=str(uuid4()),viewID=str(uuid4()))
   q={**context,'capabilities':','.join(SUPPORTED_CAPABILITIES)}
   data,_=native.document(urlencode(q));(OUT/'document.json').write_bytes(data)
   q={**context,'capabilities':'original-pdf-full-v1'};manifest=pages.manifest(urlencode(q));(OUT/'publication.json').write_bytes(manifest)
   resource=json.loads(manifest)['resource'].removeprefix('api/native-pages/')
   (OUT/'publication.pdf').write_bytes(pages.resource(urlencode(q),resource));save(OUT/'compiler.json',state.report)
  finally:state.close()
  registry=json.loads((R/'apps/macos/sources.json').read_text());sources=[R/'apps/macos'/p for k in ['core','native','app'] for p in registry[k] if p!='main.swift']
  if os.environ.get('NATIVE_UI_BEFORE')=='1':
   before=O/'before';binding=json.loads((before/'binding.json').read_text())
   for p in before.glob('*.swift'):
    if sha(p)!=binding['files'][p.name]:raise RuntimeError('Before source changed')
   sources=[before/p.name if p.name in binding['files'] else p for p in sources]
  if os.environ.get('NATIVE_UI_PENDING_BEFORE')=='1':
   before=O/'resume1-before';binding=json.loads((before/'binding.json').read_text())
   for name,value in binding['files'].items():
    if sha(before/name)!=value:raise RuntimeError('Pinned pending-failure snapshot changed')
   sources=[before/p.name if p.name in binding['files'] else p for p in sources]
  if os.environ.get('NATIVE_RECOVERY_BEFORE')=='1':
   before=RECOVERY_O/'before';binding=json.loads((before/'binding.json').read_text());frozen=before/'NativeReaderWindowController.swift'
   if binding['revision']!='cb31c504d21a16dd8fc4786537c7917a14970588' or sha(frozen)!=binding['sha256']:raise RuntimeError('Pinned H8 recovery snapshot changed')
   sources=[frozen if p.name=='NativeReaderWindowController.swift' else p for p in sources]
  harness=R/'tests/flow-app/native-reader-app/NativeReaderUIRefinementTests.swift';cls.binary=OUT/'NativeReaderUIRefinementTests'
  argv=['swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0','-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH'],*map(str,sources),str(harness),'-o',str(cls.binary)]
  start=time.monotonic();p=subprocess.run(argv,cwd=R,capture_output=True,text=True,timeout=180)
  save(OUT/'compile.json',dict(argv=argv,cwd=str(R),exit=p.returncode,elapsed=time.monotonic()-start,stdout=p.stdout,stderr=p.stderr,inputs={str(x):sha(x) for x in [*sources,harness]},environment={k:os.environ.get(k) for k in ['TMPDIR','CLANG_MODULE_CACHE_PATH','SWIFT_MODULECACHE_PATH','LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD']}))
  if p.returncode:raise RuntimeError(p.stderr)
 def scenario(self,mode):
  out=OUT/mode;out.mkdir();argv=[str(self.binary),str(OUT),mode,str(out)]
  start=time.monotonic();p=subprocess.run(argv,cwd=R,capture_output=True,text=True,timeout=90)
  save(out/'command.json',dict(argv=argv,cwd=str(R),exit=p.returncode,elapsed=time.monotonic()-start,stdout=p.stdout,stderr=p.stderr))
  self.assertEqual(p.returncode,0,p.stdout+p.stderr)
 def test_S1_header_content_area(self):self.scenario('layout')
 def test_S2_actual_selection_mode_state(self):self.scenario('states')
 def test_auxiliary_focus_commands_large_fonts(self):self.scenario('tools')

 def test_requested_mode_failure_keeps_prior_view_and_refresh_contract(self):self.scenario('request-failure')

 def test_recovered_reflow_rejects_original_mode_without_preparing(self):self.scenario('recovery-reflow')
 def test_recovered_original_rejects_reflow_without_preparing(self):self.scenario('recovery-original')
