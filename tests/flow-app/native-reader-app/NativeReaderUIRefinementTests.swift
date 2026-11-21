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
  @MainActor static func view(_ root: NSView, id: String) -> NSView? {
    views(root).first { $0.identifier?.rawValue == id }
  }
  @MainActor static func button(_ root: NSView, _ action: String) throws -> NSButton {
    guard let b=views(root).compactMap({$0 as? NSButton}).first(where:{$0.action.map(NSStringFromSelector)==action}) else { throw FlowError(message:"Missing native action "+action) };return b
  }
  @MainActor static func click(_ root: NSView,_ action:String) throws {
    let b=try button(root,action);try check(b.isEnabled,"Expected enabled "+action)
    try check(NSApp.sendAction(b.action!,to:b.target,from:b),"Native target/action "+action)
  }
  @MainActor static func menuItem(_ menu: NSMenu, action: String) -> NSMenuItem? {
    for item in menu.items {
      if item.action.map(NSStringFromSelector) == action { return item }
      if let sub = item.submenu, let found = menuItem(sub, action: action) { return found }
    }
    return nil
  }
  @MainActor static func menuItems(_ menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map { menuItems($0) } ?? []) }
  }
  @MainActor static func triggerMenu(_ menu: NSMenu, action: String) throws {
    guard let item = menuItem(menu, action: action) else { throw FlowError(message: "Missing menu action " + action) }
    try check(item.isEnabled, "Expected enabled menu item " + action)
    try check(NSApp.sendAction(item.action!, to: item.target, from: item), "Menu target/action " + action)
  }
  @MainActor static func verifyHorizontalRow(_ controls: [NSView], in root: NSView, _ label: String) throws {
    var rects = [NSRect]()
    for control in controls where !control.isHiddenOrHasHiddenAncestor {
      let rect = control.convert(control.bounds, to: root)
      try check(rect.minX >= -0.5 && rect.maxX <= root.bounds.width + 0.5, "\(label) horizontal bounds: \(control.identifier?.rawValue ?? "") \(rect)")
      for existing in rects {
        try check(!existing.insetBy(dx: 0.5, dy: 0.5).intersects(rect), "\(label) non-overlapping controls: \(existing) vs \(rect)")
      }
      rects.append(rect)
    }
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
      if original {
        let badge = view(root, id: "offlinePDFBadge")
        try check(badge != nil && !badge!.isHiddenOrHasHiddenAncestor && labels(badge!) == "오프라인 PDF", "offline original PDF shows exact '오프라인 PDF' badge")
        let nav = view(root, id: "pageNavigation")
        try check(nav != nil && !nav!.isHiddenOrHasHiddenAncestor && labels(nav!).contains("1 / 2"), "offline PDF toolbar shows centered pageNavigation counter")
        let search = view(root, id: "findPage") as? NSSearchField
        try check(search != nil && !search!.isHiddenOrHasHiddenAncestor && search!.bezelStyle == .roundedBezel, "offline PDF toolbar shows rounded search field")
        try check(!(try button(root, "toggleTools")).isHiddenOrHasHiddenAncestor, "offline PDF toolbar shows overflow trigger")
      }
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
      try check((value["header"] as! CGFloat)<=72,"S1 minimal single-row toolbar leaves >= 85% body height at 980x752")
      try check(host.textView.frame.height >= root.bounds.height * 0.85,"S1 body content area occupies at least 85% of window content height")
      try check(host.textView.frame.height >= window.frame.height * 0.85,"S1 body content area occupies at least 85% of 980x752 window height")
      let contentsPopup = host.hostWindow.contents
      let reflowBtn = try button(root,"reflowMode"), pdfBtn = try button(root,"pageMode")
      let findBtn = try button(root,"triggerFind"), aaBtn = try button(root,"toggleDisplayPopover"), moreBtn = try button(root,"toggleTools")
      let toolbarItems: [NSView] = [contentsPopup, reflowBtn, pdfBtn, findBtn, aaBtn, moreBtn]
      for item in toolbarItems { try check(!item.isHiddenOrHasHiddenAncestor, "Reflow single-row toolbar item visible") }
      let midY = reflowBtn.convert(NSPoint(x: 0, y: reflowBtn.bounds.midY), to: root).y
      for item in toolbarItems {
        let itemY = item.convert(NSPoint(x: 0, y: item.bounds.midY), to: root).y
        try check(abs(itemY - midY) <= 4, "All reflow toolbar controls sit on a single row")
      }
      try verifyHorizontalRow(toolbarItems, in: root, "Reflow 980pt toolbar")
      try check((try button(root,"releasePageSelection")).isHiddenOrHasHiddenAncestor, "Top releaseSelection row hidden without selection")
      let visibleChromeLabels = views(root).compactMap { $0 as? NSTextField }.filter { !$0.isHiddenOrHasHiddenAncestor }
      try check(visibleChromeLabels.isEmpty, "No subtitle or extra status label visible in minimal reader chrome")
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
      try await until{host.session.hasSelection && !host.hostWindow.capsule.isHidden}
      let capsule = host.hostWindow.capsule
      let pdfViewport = host.originalPageView.enclosingScrollView!.contentView.convert(host.originalPageView.enclosingScrollView!.contentView.bounds, to: root)
      let capsuleRect = capsule.convert(capsule.bounds, to: root)
      try check(!capsuleRect.intersects(pdfViewport), "PDF search-hit capsule docks without overlapping PDF body/highlights")
      try check(!capsule.buttons[.copy]!.isHidden && capsule.buttons[.copy]!.isEnabled && !capsule.closeButton.isHidden, "PDF search-hit capsule shows copy and close")
      try check(capsule.buttons[.source]!.isHidden && capsule.buttons[.highlight]!.isHidden && capsule.buttons[.ask]!.isHidden && capsule.buttons[.editor]!.isHidden && capsule.releaseSelectionButton.isHidden, "PDF search-hit capsule hides 4 unsupported buttons and duplicate release button")
      try check(capsule.footnote.stringValue == "오프라인 PDF · 복사·검색만 지원" && !capsule.footnote.isHidden, "PDF search-hit capsule shows compact footer note")
      try check(views(root).compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor && $0.title.contains("복사") }).count == 1, "No duplicate copy button alongside capsule")
      try click(root,"reflowMode")
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
      try check(trigger.title == "•••","discoverable overflow trigger")
      let aaButton = try button(root,"toggleDisplayPopover")
      try check(aaButton.title == "Aa" && !host.hostWindow.isDisplayPopoverOpen, "Aa trigger initially closed")
      var commands=0;host.hostWindow.onAccount={commands+=1}
      var marks=0,undo=0,clear=0,saves=0,lists=0,appearance=0
      host.hostWindow.onMarkReview={marks+=1};host.hostWindow.onUndoReview={undo+=1};host.hostWindow.onClearReview={clear+=1}
      host.hostWindow.onSaveOffline={saves+=1};host.hostWindow.onListOffline={lists+=1}
      let originalAppearance=host.hostWindow.onAppearance
      host.hostWindow.onAppearance={appearance+=1;originalAppearance?()}
      host.hostWindow.storageAvailable=true

      // Verify Aa popover: opaque NativeDesignSurface(.floating), no preview/apply/cancel, immediate theme & font stepper
      try click(root, "toggleDisplayPopover")
      try check(host.hostWindow.isDisplayPopoverOpen && (aaButton as? NativeDesignButton)?.designRole == .primary, "Aa button highlights when popover opens")
      let popView = host.hostWindow.displayPopoverContentView
      try check((popView as? NativeDesignSurface)?.role == .floating, "Aa popover uses opaque NativeDesignSurface(.floating)")
      for removed in ["previewDisplayExplicitly", "applyDisplayExplicitly", "cancelDisplayExplicitly"] {
        try check(!views(root).contains { $0.identifier?.rawValue == removed } && !views(popView).contains { $0.identifier?.rawValue == removed }, "Removed obsolete button " + removed)
      }
      for required in ["themeLight", "themeDark", "themeAutomatic", "decreaseFontSize", "fontSizeLabel", "increaseFontSize", "saveOfflineExplicitly", "exportPDFExplicitly"] {
        try check(view(popView, id: required) != nil, "Aa popover contains " + required)
      }

      for width in [980.0, 640.0] {
        window.setFrame(NSRect(x:0,y:0,width:width,height:752),display:false);root.layoutSubtreeIfNeeded()
        for targetSize in [32, 14] {
          for dark in [false, true] {
            try click(popView, dark ? "selectDarkTheme" : "selectLightTheme")
            if targetSize == 32 {
              while Int(host.textView.textAppearance.fontSize.rounded()) < 32 { try click(popView, "increaseFontSize") }
            } else {
              while Int(host.textView.textAppearance.fontSize.rounded()) > 14 { try click(popView, "decreaseFontSize") }
            }
            try await until { host.textView.renderKey == host.textView.requestedRenderKey && Int(host.textView.textAppearance.fontSize.rounded()) == targetSize }
            try check(host.textView.textAppearance.theme == (dark ? .dark : .light), "Aa immediate theme resolves Light/Dark")
            try check((view(popView, id: "fontSizeLabel") as? NSTextField)?.stringValue == "\(targetSize)pt", "Aa stepper updates pt label immediately")

            // Verify overflow menu reachability & callback execution
            try click(root, "toggleTools")
            let menu = host.hostWindow.moreMenu
            let expectedSelectors = ["sourceSelected","highlightSelected","askSelected","locateSelected","editorReceipt","lastEdit","account","zoomIn","zoomOut","fitPage","markSelected","undoReviewExplicitly","clearReviewExplicitly","saveOfflineExplicitly","refreshSavedExplicitly","openSavedMenuEntry:","cancelStorageExplicitly","exportPDFExplicitly","refreshDocument"]
            for sel in expectedSelectors {
              if sel == "openSavedMenuEntry:" {
                try check(menu.items.contains { $0.title == "저장 문서 열기" }, "Overflow menu retains saved documents submenu")
              } else {
                try check(menuItem(menu, action: sel) != nil, "Overflow menu retains command " + sel)
              }
            }
            try check(menu.items.contains { $0.title.hasPrefix("최근 진단:") }, "Overflow menu exposes recent diagnostic")
            try triggerMenu(menu, action: "account")
            try triggerMenu(menu, action: "markSelected"); host.hostWindow.reviewCount = 1
            try triggerMenu(menu, action: "undoReviewExplicitly"); try triggerMenu(menu, action: "clearReviewExplicitly")
            try triggerMenu(menu, action: "saveOfflineExplicitly"); try triggerMenu(menu, action: "refreshSavedExplicitly")
            try check(host.textView.frame.height >= 220, "body remains usable at narrow/large font")

            // Check narrow width collapse and bounds at 640pt
            if width <= 640 {
              try check(host.hostWindow.contents.isHiddenOrHasHiddenAncestor, "Reflow 640pt collapses contents into overflow")
              try check((try button(root, "triggerFind")).isHiddenOrHasHiddenAncestor, "Reflow 640pt collapses find trigger into overflow")
              try check(menuItem(menu, action: "outlineMenuSelected:") != nil && menuItem(menu, action: "triggerFind") != nil, "Reflow 640pt overflow contains collapsed items")
            }
            try verifyHorizontalRow([host.hostWindow.contents, try button(root, "reflowMode"), try button(root, "pageMode"), try button(root, "triggerFind"), aaButton, trigger], in: root, "Reflow \(Int(width))pt")
            try save(["collapsed":frames(host),"readingFont":host.textView.textAppearance.fontSize,"dark":dark,"actualWindowAppearance":window.effectiveAppearance.name.rawValue,"width":width],out.appendingPathComponent("layout-\(width)-\(targetSize)-\(dark).json"))
          }
        }
      }
      try click(root, "toggleDisplayPopover")
      try check(!host.hostWindow.isDisplayPopoverOpen && (aaButton as? NativeDesignButton)?.designRole == .standard, "Aa button resets highlight on close")

      try check(host.hostWindow.contents.toolTip == host.hostWindow.contents.titleOfSelectedItem,"long Korean contents retains full text in native popup")
      let paragraph=host.store.document!.blocks.first{$0.kind == .paragraph}!
      try host.textView.select(from:.init(blockID:paragraph.id,utf16:0,affinity:.upstream),to:.init(blockID:paragraph.id,utf16:paragraph.displayText.utf16.count,affinity:.downstream))
      host.textView.textViewDidChangeSelection(Notification(name:NSTextView.didChangeSelectionNotification))
      try await until { !host.hostWindow.capsule.isHidden }
      let reflowCapsule = host.hostWindow.capsule
      try check(!reflowCapsule.buttons[.copy]!.isHidden && reflowCapsule.buttons[.copy]!.isEnabled, "Reflow capsule surfaces available copy action")
      for action in NativeFloatingCapsule.Action.allCases {
        let b = reflowCapsule.buttons[action]!
        try check(b.isHidden == !b.isEnabled, "Reflow capsule hides unavailable action \(action.rawValue) and shows only available actions")
      }
      var highlights=0;host.textView.callbacks.sourceRequested={ request in if request.action == .highlight { highlights+=1 } }
      try click(root,"toggleTools")
      try triggerMenu(host.hostWindow.moreMenu, action: "highlightSelected")
      try check(highlights==1,"source group actual typed highlight callback with real selection; no source write")
      host.hostWindow.updateReaderControls(readOnly:true)
      for action in ["sourceSelected","highlightSelected","askSelected","locateSelected","editorReceipt","lastEdit","account"] {
        try check(menuItem(host.hostWindow.moreMenu, action: action)?.isEnabled == false, "readonly live command disabled " + action)
      }
      try check(commands==8 && marks==8 && undo==8 && clear==8 && saves==8 && lists==8 && appearance>=8,"representative native group callbacks; storage/account injected, production IO checked separately")

      // Verify 640pt PDF narrow-width collapse keeps pageNavigation visible & centered without overlap
      host.hostWindow.releasePageSelection()
      host.hostWindow.updateReaderControls(readOnly: false)
      try click(root, "pageMode")
      try await until { host.visibleMode == .originalPages && host.originalPageView.isPreparedForPaint }
      window.setFrame(NSRect(x:0,y:0,width:640,height:752),display:false); root.layoutSubtreeIfNeeded()
      let nav = view(root, id: "pageNavigation")!
      try check(!nav.isHiddenOrHasHiddenAncestor, "640pt PDF keeps pageNavigation visible")
      try check(abs(nav.convert(NSPoint(x: nav.bounds.midX, y: 0), to: root).x - root.bounds.midX) <= 12, "640pt PDF keeps pageNavigation centered")
      try check(host.hostWindow.contents.isHiddenOrHasHiddenAncestor && host.hostWindow.findField.isHiddenOrHasHiddenAncestor, "640pt PDF collapses secondary items into overflow")
      try verifyHorizontalRow([nav, trigger], in: root, "PDF 640pt")
      try click(root, "reflowMode")
      try await until { host.visibleMode == .nativeReflow }

      try check(!trigger.keyEquivalent.isEmpty,"native disclosure keyboard equivalent")
      let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[.command,.option],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"t",charactersIgnoringModifiers:"t",isARepeat:false,keyCode:17)!
      try check(root.performKeyEquivalent(with:event),"actual native keyboard equivalent opens overflow menu")
    }
    try check(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy{!$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow},"no visible/key/main GUI windows")
    try save(["case":mode,"assertions":checks,"skips":0,"visibleWindows":0,"activation":"prohibited","GUIAcceptance":false],out.appendingPathComponent("result.json"))
    print("UI oracle pass \(mode): \(checks)")
  }
}
