import AppKit

private struct ReviewDocument: NativeReaderDocumentProviding {
  let document: NativeReaderDocument
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument { document.rebinding(generation:context.generation) }
}
@MainActor @main struct NativeReviewRepairTests {
  static func check(_ value: Bool, _ reason: String) throws { if !value { throw FlowError(message:reason) } }
  static func until(_ ready: () -> Bool) async throws {
    for _ in 0..<1000 { if ready() { return }; try await Task.sleep(nanoseconds:10_000_000) }
    throw FlowError(message:"Review fixture readiness timeout")
  }
  static func views(_ view: NSView) -> [NSView] { [view]+view.subviews.flatMap { views($0) } }
  static func button(_ root: NSView, _ action: String) throws -> NSButton {
    guard let result = views(root).compactMap({$0 as? NSButton}).first(where:{$0.action == NSSelectorFromString(action)}) else { throw FlowError(message:"Missing native action "+action) }
    return result
  }
  static func main() async {
    do { try await run() } catch { fputs("REVIEW ORACLE: \(error)\n",stderr);exit(1) }
  }
  static func run() async throws {
    let args=CommandLine.arguments,base=URL(fileURLWithPath:args[1]),mode=args[2],out=URL(fileURLWithPath:args[3])
    _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
    let doc=try NativeReaderDocument.decode(Data(contentsOf:base.appendingPathComponent("document.json")))
    if mode.hasPrefix("review-") {
      try await ChatRecoveryScenarios.review(document:doc,fixture:base,mode:mode,out:out)
    } else if mode == "settings" {
      let root=out.appendingPathComponent("devroot"),home=root.appendingPathComponent("home")
      let env=AppEnvironment(variables:[:],userHome:home,executable:out.appendingPathComponent("synthetic.app/Contents/MacOS/Lagrangian"),fixtureRoot:root)
      try env.prepareFixtureDirectories()
      let flow=FlowApp(environment:env,isolated:true,fixture:base.appendingPathComponent("document.json"),noActivate:true,showNativeWindow:false)
      defer { flow.session.dispose();flow.settingsWindow?.close();flow.window?.close() }
      flow.settings=Settings(selectedID:"test",profiles:[Profile(id:"test",name:"Fixture",root:base.path,entry:"main.typ",fonts:[],packages:"",port:23620,publicURL:"",label:"owned.fixture")])
      flow.buildWindow();flow.populate()
      try check(NSApp.sendAction(#selector(FlowApp.showSettings),to:flow,from:nil) && flow.isSettingsPresented,"Separated settings sheet/window opens")
      let settingsWindow=flow.settingsWindow!
      let editor=settingsWindow.fieldEditor(true,for:flow.fields["name"]!) as! NativeReaderInputTextView
      var calls=0;editor.standardClipboardOperation={_ in calls += 1}
      editor.string="Private edit";editor.setSelectedRange(NSRange(location:0,length:7))
      for name in ["cut:","copy:","paste:"] {
        let action=NSSelectorFromString(name),menu=NSMenuItem(title:name,action:action,keyEquivalent:"")
        _=NSApp.sendAction(action,to:editor,from:menu)
        editor.doCommand(by:action)
        let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:settingsWindow.windowNumber,context:nil,characters:name == "cut:" ? "x" : name == "copy:" ? "c" : "v",charactersIgnoringModifiers:name == "cut:" ? "x" : name == "copy:" ? "c" : "v",isARepeat:false,keyCode:0)!
        try check(editor.performKeyEquivalent(with:event),"Keyboard edit consumed")
      }
      try check(calls==0 && editor.string=="Private edit","Settings target/menu/key/responder rejects ordinary clipboard")
      let directory=out.appendingPathComponent("guarded-settings"),store=SettingsStore(directory:directory,localReplacement:true)
      try check(try store.load().profiles.isEmpty,"Absent fixture settings empty")
      try store.save(flow.settings);try check(try store.load().selectedID=="test","Regular fixture settings valid")
      let canary=out.appendingPathComponent("settings-canary.json");try FileManager.default.copyItem(at:store.file,to:canary)
      let bytes=try Data(contentsOf:canary);try FileManager.default.removeItem(at:store.file)
      try FileManager.default.createSymbolicLink(at:store.file,withDestinationURL:canary)
      var rejected=false;do {_=try store.load()}catch {rejected=true}
      try check(rejected && (try Data(contentsOf:canary))==bytes,"Fixture leaf symlink refused; canary unchanged")
      try check(try SettingsStore(directory:directory).load().selectedID=="test","Normal settings read preserves existing semantics")
      try FileManager.default.removeItem(at:store.file);try FileManager.default.createDirectory(at:store.file,withIntermediateDirectories:false)
      rejected=false;do {_=try store.load()}catch {rejected=true};try check(rejected,"Nonregular fixture settings refused")
    } else if mode == "pdf" {
      let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("publication.json"))) as! [String:Any]
      let pdf=try Data(contentsOf:base.appendingPathComponent("publication.pdf"))
      let live=NativeReaderWindowController(provider:ReviewDocument(document:doc),target:{_ in doc.identity},originalPages:{ context in
        var value=raw;value["generation"]=context.generation;value["viewID"]=context.viewID.uuidString.lowercased();value["requestID"]=context.requestID.uuidString.lowercased()
        return .init(publication:try JSONDecoder().decode(NativeOriginalPagePublication.self,from:JSONSerialization.data(withJSONObject:value)),data:pdf)
      },show:false,avoidActivation:true)
      defer { live.dispose() }
      let profile=Profile(id:"pdf",name:"PDF recovery",root:base.path,entry:"main.typ",fonts:[],packages:"",port:23620,publicURL:"",label:"owned.pdf")
      _=live.open(profile){_ in};try await until {live.session.state == .reading && live.textView.renderKey==live.textView.requestedRenderKey}
      let page=try button(live.hostWindow.window!.contentView!,"pageMode");_=NSApp.sendAction(page.action!,to:page.target,from:page)
      try await until {live.visibleMode == .originalPages && live.originalPageView.isPreparedForPaint}
      let context=live.session.context!
      var value=raw;value["generation"]=context.generation;value["viewID"]=context.viewID.uuidString.lowercased();value["requestID"]=context.requestID.uuidString.lowercased()
      let publication=try JSONDecoder().decode(NativeOriginalPagePublication.self,from:JSONSerialization.data(withJSONObject:value))
      let original=NativeOriginalPageRecovery(publication:publication,data:pdf,viewport:try live.originalPageView.recovery())
      let snapshot=NativeReaderRecoverySnapshot(document:live.store.document!,assets:[:],restoration:.initial,drafts:[],originalPages:original)
      let disk=NativeReaderRecoveryStore(root:out.appendingPathComponent("recovery"));try await disk.save(snapshot)
      let env=AppEnvironment(variables:[:],userHome:out.appendingPathComponent("namespace-home"),executable:out.appendingPathComponent("synthetic.app/Contents/MacOS/Lagrangian"))
      let namespace=env.nativeRecoveryRoot(for:profile).lastPathComponent
      try JSONSerialization.data(withJSONObject:["profileID":profile.id,"profileRoot":profile.root,"entry":profile.entry,"recoveryNamespace":namespace],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("fixture-snapshot.json"))
      let loaded=try await disk.load(identity:doc.identity)
      let fixture=NativeReaderWindowController(provider:NativeReaderOfflineProvider(),target:{_ in throw NativeReaderOperationFailure.unavailable},show:false,avoidActivation:true,fixtureMode:true)
      defer {fixture.dispose()}
      _=fixture.open(profile,refresh:false){_ in}
      fixture.hostWindow.window!.setFrame(NSRect(x:0,y:0,width:980,height:752),display:false)
      fixture.hostWindow.window!.contentView!.layoutSubtreeIfNeeded()
      print("PDF fixture restore begins")
      try await fixture.restoreRecovery(loaded)
      print("PDF fixture restore returned")
      try await until {fixture.visibleMode == .originalPages && fixture.originalPageView.isPreparedForPaint}
      var panels=0
      fixture.choosePDFDestination={_ in panels += 1;return out.appendingPathComponent("must-not-export.pdf")}
      fixture.stagePDFExport={_,_,_ in ReviewEffects.exportWrites += 1;throw NativeReaderOperationFailure.unavailable}
      let export=try button(fixture.hostWindow.displayPopoverContentView,"exportPDFExplicitly")
      try check(!export.isEnabled,"Fixture valid restored PDF export disabled")
      _=NSApp.sendAction(export.action!,to:export.target,from:export);fixture.hostWindow.onExportPDF?()
      await Task.yield()
      try check(panels==0 && ReviewEffects.exportWrites==0,"Forced PDF selector/owner panel and write effects0")
      try check(fixture.originalPageView.store.accepted != nil && loaded.originalPages?.data==pdf,"Local PDF viewing and exact recovery bytes preserved")
      // Normal owner retains verified export publication to a task-owned file.
      let destination=out.appendingPathComponent("normal-export.pdf")
      live.choosePDFDestination={_ in destination}
      let normal=try button(live.hostWindow.displayPopoverContentView,"exportPDFExplicitly")
      try check(normal.isEnabled,"Normal export remains enabled")
      _=NSApp.sendAction(normal.action!,to:normal.target,from:normal)
      try await until {live.hostWindow.notice.stringValue=="Original PDF exported."}
      try check(try Data(contentsOf:destination)==pdf,"Normal export uses exact verified publication bytes")
    }
    try check(ReviewEffects.displays==0 && ReviewEffects.panels==0,"All window/panel leaf effects blocked")
    try check(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy{!$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow},"Prohibited; visible/key/main0")
    print("\(mode): actual offscreen review oracle passed; no GUI or ordinary clipboard")
  }
}
