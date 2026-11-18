"""Review oracles use actual native targets with clipboard/window/panel leaf spies."""
import hashlib,importlib.util,json,os,subprocess,time,unittest
from pathlib import Path
R=Path(__file__).resolve().parents[3]
D=Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
O=D/'test-output/native-cream-review-repair2'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

class ReviewRepair(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  configured=os.environ.get('REVIEW_REPAIR_OUTPUT')
  if not configured:raise unittest.SkipTest('Optional native review tests require explicit fresh task output and one outer Swift lock')
  cls.out=Path(configured).resolve()
  if not any(cls.out.is_relative_to(root) for root in [O,D/'test-output/native-cream-reader-repair3']) or cls.out.exists() or not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):raise RuntimeError('Fresh task output and single Swift lock required')
  cls.out.mkdir(parents=True)
  helper=cls.out/'ReviewEffects.swift'
  helper.write_text('''import AppKit
import UniformTypeIdentifiers
enum ReviewEffects {
 static var displays=0,panels=0,ordinaryBoards=0,systemEdits=0,exportWrites=0
 static func display(){displays += 1}
 static func edit(){systemEdits += 1}
 static func forbiddenBoard()->NSPasteboard { ordinaryBoards += 1; return NSPasteboard(name:NSPasteboard.Name("owned.review.general-spy")) }
 static func open(_ url:URL)->Bool { false }
 static func reveal(_ urls:[URL]){}
 static func about(options:[NSApplication.AboutPanelOptionKey:Any]) { panels += 1 }
 final class OpenPanel {
  var canChooseDirectories=false,allowsMultipleSelection=false
  var message="",title=""
  var allowedContentTypes=[UTType]();var url:URL?=nil
  func begin(completionHandler:(NSApplication.ModalResponse)->Void){panels += 1;completionHandler(.cancel)}
  func runModal()->NSApplication.ModalResponse{panels += 1;return .cancel}
 }
 final class SavePanel {
  var allowedContentTypes=[UTType]();var nameFieldStringValue="";var url:URL?=nil
  func beginSheetModal(for window:NSWindow,completionHandler:(NSApplication.ModalResponse)->Void){panels += 1;completionHandler(.cancel)}
 }
}
''')
  actual_run=subprocess.run;records=[]
  def adapt(argv,*args,**kwargs):
   original=list(map(str,argv));actual=list(original)
   if actual and Path(actual[0]).name=='swiftc':
    copies=cls.out/('compiled-'+str(len(records)));copies.mkdir();bindings=[]
    for i,arg in enumerate(actual):
     source=Path(arg)
     if source.suffix!='.swift' or source==helper:continue
     text=source.read_text();raw=text
     for literal in ['window?.orderFrontRegardless()','window?.makeKeyAndOrderFront(nil)','NSApp.activate(ignoringOtherApps: true)','showWindow(nil)']:text=text.replace(literal,'ReviewEffects.display()')
     text=text.replace('NSWorkspace.shared.open(','ReviewEffects.open(').replace('NSWorkspace.shared.activateFileViewerSelecting(','ReviewEffects.reveal(').replace('NSApp.orderFrontStandardAboutPanel(','ReviewEffects.about(').replace('NSOpenPanel()','ReviewEffects.OpenPanel()').replace('NSSavePanel()','ReviewEffects.SavePanel()').replace('NSPasteboard.general','ReviewEffects.forbiddenBoard()')
     if source.name=='NativeReaderInputTextView.swift':
      for action in ['copy','cut','paste','pasteAsPlainText','pasteAsRichText']:text=text.replace('super.'+action+'(sender)','ReviewEffects.edit()')
     if any(x in text for x in ['.orderFrontRegardless(','.makeKeyAndOrderFront(','NSApp.activate(','showWindow(nil)','NSPasteboard.general','NSOpenPanel()','NSSavePanel()']):raise RuntimeError('Unblocked OS leaf: '+str(source))
     target=copies/source.name;target.write_text(text);actual[i]=str(target)
     bindings.append(dict(original=str(source),originalSHA256=sha(source),compiled=str(target),compiledSHA256=sha(target),leafAdapterApplied=text!=raw))
    actual.insert(actual.index('-o'),str(helper))
    records.append(dict(originalargv=original,actualargv=actual,inputs=bindings,helperSHA256=sha(helper),assertionsUnchanged=True))
   return actual_run(actual,*args,**kwargs)
  path=R/'tests/flow-app/native-reader-app/test_native_ui_refinement.py';spec=importlib.util.spec_from_file_location('review_fixture_ui',path);ui=importlib.util.module_from_spec(spec);spec.loader.exec_module(ui)
  ui.O=cls.out;ui.RECOVERY_O=cls.out;os.environ['NATIVE_UI_OUTPUT']=str(cls.out/'fixture')
  packages=os.environ.get('FLOW_TEST_PACKAGE_CACHE',str(O/'typst-package-cache'))
  os.environ['FLOW_READER_PACKAGES']=packages
  os.environ['FLOW_TEST_PACKAGE_CACHE']=packages
  try:
   subprocess.run=adapt;ui.NativeUIRefinement.setUpClass()
   cls.fixture=ui.OUT;cls.ui=ui
   registry=json.loads((R/'apps/macos/sources.json').read_text());sources=[R/'apps/macos'/n for k in ['core','native','app'] for n in registry[k] if n!='main.swift']
   cls.binary=cls.out/'ReviewRepairTests';harness=R/'tests/flow-app/native-reader-app/NativeReviewRepairTests.swift';chat=R/'tests/flow-app/native-reader-app/NativeChatRecoveryTests.swift'
   argv=['/usr/bin/swiftc','-parse-as-library','-swift-version','5','-warnings-as-errors','-target','arm64-apple-macosx13.0','-module-cache-path',os.environ['SWIFT_MODULECACHE_PATH'],*map(str,sources),str(chat),str(harness),'-o',str(cls.binary)]
   start=time.time();p=subprocess.run(argv,cwd=R,capture_output=True,text=True,timeout=180)
   (cls.out/'compile.json').write_text(json.dumps(dict(argv=records[-1]['actualargv'],cwd=str(R),start=start,end=time.time(),exit=p.returncode,skip=0,stdout=p.stdout,stderr=p.stderr,binarySHA256=sha(cls.binary) if p.returncode==0 else None),indent=2)+'\n')
   if p.returncode:raise RuntimeError(p.stderr)
  finally:
   subprocess.run=actual_run
   (cls.out/'compiler-adapter.json').write_text(json.dumps(records,indent=2)+'\n')
   (cls.out/'fixture-runner.json').write_text(json.dumps(dict(path=str(path),SHA256=sha(path),outputOverride=str(cls.out/'fixture'),assertionsUnchanged=True),indent=2)+'\n')

 def scenario(self,name):
  out=self.out/name;out.mkdir();argv=[str(self.binary),str(self.fixture),name,str(out)];start=time.time();p=subprocess.run(argv,cwd=R,capture_output=True,text=True,timeout=90)
  (out/'command.json').write_text(json.dumps(dict(argv=argv,cwd=str(R),start=start,end=time.time(),exit=p.returncode,skip=0,binarySHA256=sha(self.binary),stdout=p.stdout,stderr=p.stderr),indent=2)+'\n');self.assertEqual(p.returncode,0,p.stdout+p.stderr)
 def test_fixture_search_and_composer_edit(self):self.scenario('review-edit')
 def test_settings_edit_and_leaf_read(self):self.scenario('settings')
 def test_recovered_pdf_export_boundary(self):self.scenario('pdf')
 def test_two_passage_draft_associations(self):self.scenario('review-cache')
 def test_late_stop_rejects_disposed_view(self):self.scenario('review-stop-late')
 def test_reentered_streaming_stop(self):self.scenario('review-stop')
 def test_same_paragraph_range_reentry(self):self.scenario('review-range')
 def test_duplicate_stop_keeps_first_completion(self):self.scenario('review-stop-duplicate')

if __name__=='__main__':unittest.main()
