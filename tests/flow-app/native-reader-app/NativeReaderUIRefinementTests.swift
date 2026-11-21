import AppKit

private actor UIInput: NativeReaderDocumentProviding {
  let document: NativeReaderDocument
  var stale = false
  var calls = 0
  func count() -> Int { calls }
  init(_ document: NativeReaderDocument) { self.document = document }
  func fail(_ value: Bool) { stale = value }
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
    calls += 1
    if stale { throw NativeOriginalPageError.stale }
    return document.rebinding(generation: context.generation)
  }
}
private actor UIPathCalls {
  var targets=0, pages=0
  func target() { targets += 1 }
  func page() { pages += 1 }
  func counts() -> [Int] { [targets,pages] }
}
@main struct NativeReaderUIRefinementTests {
  @MainActor static var checks = 0
  @MainActor static func check(_ condition: Bool, _ reason: String) throws {
    checks += 1; if !condition { throw FlowError(message: reason) }
  }
  @MainActor static func until(_ condition: () -> Bool) async throws {
    for _ in 0..<1200 { if condition() { return }; try await Task.sleep(nanoseconds:10_000_000) }
    throw FlowError(message:"UI condition timeout")
  }
  @MainActor static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { views($0) } }
  @MainActor static func button(_ root: NSView, _ action: String) throws -> NSButton {
    guard let b=views(root).compactMap({$0 as? NSButton}).first(where:{$0.action.map(NSStringFromSelector)==action}) else { throw FlowError(message:"Missing native action "+action) };return b
  }
  @MainActor static func click(_ root: NSView,_ action:String) throws {
    let b=try button(root,action);try check(b.isEnabled,"Expected enabled "+action)
    try check(NSApp.sendAction(b.action!,to:b.target,from:b),"Native target/action "+action)
  }
  @MainActor static func labels(_ root: NSView) -> String { views(root).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator:"\n") }
  @MainActor static func save(_ value:[String:Any],_ url:URL)throws{try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:url)}
  @MainActor static func frames(_ host:NativeReaderWindowController)->[String:Any] {
    let w=host.hostWindow.window!,root=w.contentView!,rect=host.textView.convert(host.textView.bounds,to:root)
    return ["window":[w.frame.width,w.frame.height],"content":[root.bounds.width,root.bounds.height],"reader":[rect.minX,rect.minY,rect.width,rect.height],"header":root.bounds.height-rect.maxY,"minSize":[w.minSize.width,w.minSize.height],"contentMinSize":[w.contentMinSize.width,w.contentMinSize.height]]
  }
  @MainActor static func main() async {
    do { try await run() } catch { fputs("UI ORACLE FAILURE: \(error)\n",stderr);exit(1) }
  }
  @MainActor static func run() async throws {
    let args=CommandLine.arguments,base=URL(fileURLWithPath:CommandLine.arguments[1]),mode=args[2],out=URL(fileURLWithPath:args[3])
    _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
    let doc=try NativeReaderDocument.decode(Data(contentsOf:base.appendingPathComponent("document.json"))),input=UIInput(doc)
    let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("publication.json"))) as! [String:Any]
    let pdf=try Data(contentsOf:base.appendingPathComponent("publication.pdf"))
    let paths=UIPathCalls()
    let host=NativeReaderWindowController(provider:input,target:{_ in await paths.target();return doc.identity},originalPages:{context in
      await paths.page()
      var value=raw;value["generation"]=context.generation;value["viewID"]=context.viewID.uuidString.lowercased();value["requestID"]=context.requestID.uuidString.lowercased()
      return .init(publication:try JSONDecoder().decode(NativeOriginalPagePublication.self,from:JSONSerialization.data(withJSONObject:value)),data:pdf)
    },show:false,avoidActivation:true)
    defer{host.dispose()}
    let profile=Profile(id:"ui-v7",name:"실제 오프스크린 문서",root:base.path,entry:"main.typ",fonts:[],packages:"",port:23620,publicURL:"",label:"owned.ui-v7")
    _=host.open(profile){_ in}
    try await until { host.session.state == .reading && host.textView.renderKey != nil && host.textView.renderKey == host.textView.requestedRenderKey }
    let window=host.hostWindow.window!,root=window.contentView!
    window.setFrame(NSRect(x:0,y:0,width:980,height:752),display:false);root.layoutSubtreeIfNeeded()
    if mode=="recovery-reflow" || mode=="recovery-original" {
      if mode=="recovery-original" {
        try click(root,"pageMode")
        try await until{host.visibleMode == .originalPages && host.session.state == .reading && host.originalPageView.isPreparedForPaint}
      }
      var snapshot=NativeReaderRecoverySnapshot(document:host.store.document!,assets:[:],restoration:.initial,drafts:[])
      if mode=="recovery-original" {
        let context=host.session.context!
        var value=raw;value["generation"]=context.generation;value["viewID"]=context.viewID.uuidString.lowercased();value["requestID"]=context.requestID.uuidString.lowercased()
        let publication=try JSONDecoder().decode(NativeOriginalPagePublication.self,from:JSONSerialization.data(withJSONObject:value))
        snapshot.originalPages=NativeOriginalPageRecovery(publication:publication,data:pdf,viewport:try host.originalPageView.recovery())
      }
      try snapshot.validate()
      try await host.restoreRecovery(snapshot)
      try await until{host.session.hasRecoveryCopy && host.session.state == .offline}
      let original = mode=="recovery-original"
      try check(host.visibleMode == (original ? .originalPages:.nativeReflow),"valid restored visible mode")
      try check(!host.session.hasSelection,"counterexample has no retained selection")
      let document=host.store.document,context=host.session.context,priorCalls=await paths.counts(),priorProvider=await input.count()
      let action=original ? "reflowMode":"pageMode",control=try button(root,action),enabled=control.isEnabled
      // Deliberately send target/action even if the policy disables its button.
      // A stale/programmatic action must not bypass the recovery guard.
      try check(NSApp.sendAction(control.action!,to:control.target,from:control),"actual recovered mode target/action")
      try await Task.sleep(nanoseconds:150_000_000)
      let text=labels(root),afterCalls=await paths.counts(),afterProvider=await input.count()
      var sourceDenied=false
      do{try host.session.authorize(context!)}catch{sourceDenied=true}
      try save(["labels":text,"buttonEnabled":enabled,"targetAction":action,"providerBefore":priorProvider,"providerAfter":afterProvider,"targetAndPagesBefore":priorCalls,"targetAndPagesAfter":afterCalls,"mode":original ? "originalPages":"nativeReflow","sameDocument":host.store.document==document,"sameContext":host.session.context==context,"readOnly":host.session.isReadOnly,"sourceDenied":sourceDenied,"snapshotValidated":true,"snapshotHasOriginalPages":snapshot.originalPages != nil,"visibleWindows":NSApp.windows.filter{$0.isVisible}.count],out.appendingPathComponent("recovery-oracle.json"))
      try check(host.visibleMode == (original ? .originalPages:.nativeReflow) && host.store.document==document && host.session.context==context,"rejected mode preserves current document/context/mode")
      try check(host.session.isReadOnly && sourceDenied,"offline authority remains read only")
      try check(priorCalls==afterCalls && priorProvider==afterProvider,"rejected mode has zero target/provider/PDF preparation effects")
      try check(text.contains(original ? "현재: 원본 PDF":"현재: 본문") && text.contains("오프라인") && text.contains("전환할 수 없습니다") && !text.contains("준비"),"recovered mode rejection explains current offline copy, never pending preparation")
      try check(!enabled && !(try button(root,"refreshDocument")).isEnabled,"mode and refresh controls agree with unsupported recovery actions")
      let frozenCalls=await paths.counts(),frozenProvider=await input.count()
      host.dispose()
      _=NSApp.sendAction(control.action!,to:control.target,from:control)
      let disposedCalls=await paths.counts(),disposedProvider=await input.count()
      try check(disposedCalls==frozenCalls && disposedProvider==frozenProvider,"disposed action creates no live work")
      try check(!labels(root).contains("모드를 준비"),"disposed request never leaves preparing mode intent")
    } else if mode=="request-failure" {
      let previous=host.store.document
      await input.fail(true);try click(root,"pageMode");try await until{host.session.failure != nil}
      let text=labels(root)
      try save(["labels":text,"failure":host.session.failure!,"rawDiagnostic":host.diagnostic ?? "","priorVisibleReflow":host.visibleMode == .nativeReflow,"priorDocumentPreserved":host.store.document==previous],out.appendingPathComponent("requested-failure.json"))
      try check(host.store.document==previous && host.visibleMode == .nativeReflow,"requested failure preserves actual prior mode/document")
      try check(text.contains("현재: 본문") && text.contains("전환 요청: 원본 PDF") && text.contains("이전 읽기 결과") && text.contains("새로고침") && !text.contains("원본 PDF 모드를 준비"),"failure cannot be masked by requested-mode preparation")
      let priorCalls=await input.count();await input.fail(false);try click(root,"refreshDocument")
      try await until{host.visibleMode == .originalPages && host.session.state == .reading}
      try check(await input.count()==priorCalls+1,"explicit live refresh resolves only once")
      let snapshot=NativeReaderRecoverySnapshot(document:doc,assets:[:],restoration:.initial,drafts:[])
      try await host.restoreRecovery(snapshot)
      try await until{host.session.hasRecoveryCopy && host.visibleMode == .nativeReflow && host.session.state == .offline}
      let saved=host.store.document,offlineCalls=await input.count(),refresh=try button(root,"refreshDocument")
      try check(!refresh.isEnabled,"recovered offline copy does not offer live refresh")
      _ = NSApp.sendAction(refresh.action!,to:refresh.target,from:refresh)
      try await Task.sleep(nanoseconds:150_000_000)
      try check(await input.count()==offlineCalls && host.store.document==saved && host.session.isReadOnly,"forced target/action cannot escape recovered authority")
    } else if mode=="layout" {
      let value=frames(host);try save(value,out.appendingPathComponent("frames.json"))
      try check((value["header"] as! CGFloat)<=200,"S1 compact primary header must leave at least524pt content at980x752")
      try check(host.textView.frame.height>=500,"S1 body content area")
      let x=try button(root,"pageMode").convert(NSPoint.zero,to:root).x
      try host.textView.select(from:.init(blockID:doc.blocks[0].id,utf16:0,affinity:.upstream),to:.init(blockID:doc.blocks[0].id,utf16:min(2,doc.blocks[0].displayText.utf16.count),affinity:.downstream))
      try click(root,"pageMode");root.layoutSubtreeIfNeeded()
      try check(abs(try button(root,"pageMode").convert(NSPoint.zero,to:root).x-x)<1,"S1 primary alignment cannot shift on held state")
    } else if mode=="states" {
      let block=doc.blocks.first{$0.kind == .paragraph}!
      try host.textView.select(from:.init(blockID:block.id,utf16:0,affinity:.upstream),to:.init(blockID:block.id,utf16:block.displayText.utf16.count,affinity:.downstream))
      host.textView.textViewDidChangeSelection(Notification(name:NSTextView.didChangeSelectionNotification))
      try await until{host.session.hasSelection};try click(root,"pageMode")
      try save(["labels":labels(root),"bodyHeld":host.session.hasSelection,"visibleReflow":host.visibleMode == .nativeReflow],out.appendingPathComponent("held-body.json"))
      try check(labels(root).contains("현재: 본문") && labels(root).contains("전환 요청: 원본 PDF") && labels(root).contains("본문에서 선택"),"S2 current/requested mode and actual body hold explanation")
      try click(root,"releasePageSelection");try check(!host.session.hasSelection && host.visibleMode == .nativeReflow,"release does not silently approve requested mode")
      try click(root,"pageMode");do {try await until{host.visibleMode == .originalPages && host.originalPageView.isPreparedForPaint}} catch {throw FlowError(message:"PDF switch: state=\(host.session.state) failure=\(host.session.failure ?? "nil") diagnostic=\(host.diagnostic ?? "nil") visible=\(host.visibleMode) ready=\(host.originalPageView.isPreparedForPaint)")}
      let hits=try await host.originalPageView.search("Search needle")
      try check(!hits.isEmpty && !host.session.hasSelection,"search results alone do not hold selection")
      let field=views(root).compactMap{$0 as? NSSearchField}.first!;field.stringValue="Search needle"
      try check(NSApp.sendAction(field.action!,to:field.target,from:field),"actual search target/action")
      try await until{host.session.hasSelection};try click(root,"reflowMode")
      try check(labels(root).contains("検索")==false && labels(root).contains("검색 결과에서 선택"),"S2 real search-selected ticket explanation")
      try save(["labels":labels(root),"pdfHeld":host.originalPageView.selected != nil,"query":field.stringValue],out.appendingPathComponent("held-search.json"))
      try click(root,"releasePageSelection");try check(!host.session.hasSelection,"actual display selection release")
      try click(root,"reflowMode");try await until{host.visibleMode == .nativeReflow}
      try check(field.stringValue=="Search needle","query need not clear for explicit switch after release")
      try click(root,"pageMode");do {try await until{host.visibleMode == .originalPages && host.originalPageView.isPreparedForPaint}} catch {throw FlowError(message:"PDF switch: state=\(host.session.state) failure=\(host.session.failure ?? "nil") diagnostic=\(host.diagnostic ?? "nil") visible=\(host.visibleMode) ready=\(host.originalPageView.isPreparedForPaint)")}
      let hit=try await host.originalPageView.search("Search needle").first!
      try await host.originalPageView.select(page:hit.pageIndex,range:hit.rangeUTF16);try click(root,"reflowMode")
      try check(labels(root).contains("PDF에서 선택") && !labels(root).contains("검색 결과에서 선택"),"new PDF selection does not reuse old search provenance")
      try click(root,"releasePageSelection");await input.fail(true)
      let accepted=host.store.document;try click(root,"refreshDocument");try await until{host.session.failure != nil}
      try check(host.store.document==accepted && labels(root).contains("이전 읽기 결과") && labels(root).contains("새로고침"),"stale previous view and explicit next action")
      try save(["labels":labels(root),"rawDiagnostic":host.hostWindow.notice.stringValue,"priorDocumentPreserved":host.store.document==accepted],out.appendingPathComponent("stale.json"))
    } else {
      let trigger=try button(root,"toggleTools")
      try check(trigger.title.contains("도구"),"discoverable Korean native disclosure")
      var commands=0;host.hostWindow.onAccount={commands+=1}
      var marks=0,undo=0,clear=0,saves=0,lists=0,appearance=0
      host.hostWindow.onMarkReview={marks+=1};host.hostWindow.onUndoReview={undo+=1};host.hostWindow.onClearReview={clear+=1}
      host.hostWindow.onSaveOffline={saves+=1};host.hostWindow.onListOffline={lists+=1}
      let originalAppearance=host.hostWindow.onAppearance
      host.hostWindow.onAppearance={appearance+=1;originalAppearance?()}
      host.hostWindow.storageAvailable=true
      for width in [980.0,640.0] { for size in [13.0,32.0] { for dark in [false,true] {
        host.hostWindow.theme.selectItem(at:dark ? 1:0)
        for control in views(root).compactMap({$0 as? NSControl}) { control.font = .systemFont(ofSize:size) }
        host.hostWindow.textSize.selectItem(withTitle:size == 32 ? "32" : "14")
        try check(NSApp.sendAction(host.hostWindow.textSize.action!,to:host.hostWindow.textSize.target,from:host.hostWindow.textSize),"actual reading font selection")
        window.setFrame(NSRect(x:0,y:0,width:width,height:752),display:false);root.layoutSubtreeIfNeeded()
        try await until{host.textView.renderKey == host.textView.requestedRenderKey && host.textView.textAppearance.fontSize == (size == 32 ? 32 : 14)}
        try check(host.textView.textAppearance.theme == (dark ? .dark : .light),"actual native theme control resolves requested Light/Dark")
        try click(root,"toggleTools");root.layoutSubtreeIfNeeded()
        let expected:Set<String>=["sourceSelected","highlightSelected","askSelected","locateSelected","editorReceipt","lastEdit","account","zoomIn","zoomOut","fitPage","previewDisplayExplicitly","applyDisplayExplicitly","cancelDisplayExplicitly","markSelected","undoReviewExplicitly","clearReviewExplicitly","saveOfflineExplicitly","refreshSavedExplicitly","openSavedExplicitly","cancelStorageExplicitly","exportPDFExplicitly","manageAccountExplicitly"]
        for selector in expected {
          let control=try button(root,selector)
          _ = control.scrollToVisible(control.bounds);root.layoutSubtreeIfNeeded()
          try check(!control.isHiddenOrHasHiddenAncestor && control.target != nil && control.identifier?.rawValue==selector,"existing native auxiliary command retained "+selector)
          if let scroll=control.enclosingScrollView, let document=scroll.documentView {
            try check(scroll.contentView.documentVisibleRect.intersects(control.convert(control.bounds,to:document)),"actual auxiliary scroll reaches command "+selector)
          }
          try check(control.accessibilityLabel()==control.title,"native Korean AX label "+selector)
          try check(control.bounds.width + 1 >= min(control.fittingSize.width,root.bounds.width-32),"native button label fits "+selector)
          if control.isEnabled { try check(window.makeFirstResponder(control),"native keyboard focus reaches "+selector) }
        }
        try check(host.hostWindow.contents.toolTip == host.hostWindow.contents.titleOfSelectedItem,"long Korean contents retains full text in native popup")
        let account=try button(root,"account");try check(!account.isHiddenOrHasHiddenAncestor,"auxiliary account reachable")
        try check(window.makeFirstResponder(account),"offscreen auxiliary focus")
        try click(root,"account")
        try click(root,"markSelected");host.hostWindow.reviewCount=1
        try click(root,"undoReviewExplicitly");try click(root,"clearReviewExplicitly")
        try click(root,"saveOfflineExplicitly");try click(root,"refreshSavedExplicitly")
        let prior=frames(host)
        try click(root,"toggleTools");root.layoutSubtreeIfNeeded()
        try check(window.firstResponder===trigger,"collapse returns focused child to trigger")
        try check(account.isHiddenOrHasHiddenAncestor,"collapsed command remains owned but hidden")
        try check(host.textView.frame.height>=220,"body remains usable at narrow/large font")
        for v in views(root) where v is NSControl && !v.isHiddenOrHasHiddenAncestor {
          let rect=v.convert(v.bounds,to:root)
          try check(rect.minX>=0 && rect.maxX<=root.bounds.width+1,"visible native control horizontal bounds")
        }
        try save(["expanded":prior,"collapsed":frames(host),"controlFont":size,"readingFont":host.textView.textAppearance.fontSize,"dark":dark,"actualWindowAppearance":window.effectiveAppearance.name.rawValue,"accountEnabled":account.isEnabled],out.appendingPathComponent("layout-\(width)-\(size)-\(dark).json"))
      } } }
      let paragraph=host.store.document!.blocks.first{$0.kind == .paragraph}!
      try host.textView.select(from:.init(blockID:paragraph.id,utf16:0,affinity:.upstream),to:.init(blockID:paragraph.id,utf16:paragraph.displayText.utf16.count,affinity:.downstream))
      var highlights=0;host.textView.callbacks.sourceRequested={ request in if request.action == .highlight { highlights+=1 } }
      try click(root,"toggleTools");try click(root,"highlightSelected")
      try check(highlights==1,"source group actual typed highlight callback with real selection; no source write")
      host.hostWindow.updateReaderControls(readOnly:true)
      for action in ["sourceSelected","highlightSelected","askSelected","locateSelected","editorReceipt","lastEdit","account"] { try check(!(try button(root,action)).isEnabled,"readonly live command disabled "+action) }
      try click(root,"toggleTools")
      try check(commands==8 && marks==8 && undo==8 && clear==8 && saves==8 && lists==8 && appearance>=8,"representative native group callbacks; storage/account injected, production IO checked separately")
      try check(!trigger.keyEquivalent.isEmpty,"native disclosure keyboard equivalent")
      let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.option],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"t",charactersIgnoringModifiers:"t",isARepeat:false,keyCode:17)!
      try check(root.performKeyEquivalent(with:event),"actual native keyboard equivalent opens disclosure")
      try check(!(try button(root,"account")).isHiddenOrHasHiddenAncestor,"keyboard reaches auxiliary commands")
    }
    try check(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy{!$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow},"no visible/key/main GUI windows")
    try save(["case":mode,"assertions":checks,"skips":0,"visibleWindows":0,"activation":"prohibited","GUIAcceptance":false],out.appendingPathComponent("result.json"))
    print("UI oracle pass \(mode): \(checks)")
  }
}
