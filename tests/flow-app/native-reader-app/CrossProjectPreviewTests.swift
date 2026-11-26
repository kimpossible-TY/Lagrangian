import AppKit

private struct Failure: Error { let message: String }

@main
struct CrossProjectPreviewTests {
  @MainActor static func check(_ value: Bool, _ message: String) throws {
    if !value { throw Failure(message: message) }
  }

  @MainActor static func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  @MainActor static func readerHelpers() throws {
    let store = NativeReaderDocumentStore()
    let view = NativeReaderTextView(store: store)
    try check(view.nodeRectInView(forNodeID: "first") == nil, "Unrendered nodes have no geometry")
    let empty = view.currentCrossProjectPosition()
    try check(empty.anchor == nil && empty.blockID == nil,
              "Empty viewport snapshot")
    try check(!view.scrollToCrossProjectLocation(anchor: nil, blockID: nil, scrollOffset: 0), "Unrendered view cannot scroll")
    let generation = try store.beginRequest()
    let identity = NativeDocumentIdentity(documentID: "doc", serviceID: "service", revision: "revision", scope: .fixture)
    let text = String(repeating: "A long line of text. ", count: 40)
    func block(_ id: String, _ anchors: [String], children: [NativeReaderNode] = []) -> NativeReaderNode {
      NativeReaderNode(id: id, sectionID: "section", kind: children.isEmpty ? .text : .paragraph, canonicalText: text, displayText: text,
        rangeUTF16: [0, text.utf16.count], offsets: NativeTextOffsets(text), children: children, anchors: anchors,
        annotationTargets: [], visible: true, mapping: .unmapped, passageKey: nil, direction: nil, language: nil,
        headingLevel: nil, math: nil, cell: nil, link: nil, assetID: nil, alt: nil)
    }
    let document = NativeReaderDocument(schemaVersion: 1, identity: identity, generation: generation,
      requiredCapabilities: ["semantic-tree-v1"], blocks: [block("first", [], children: [block("child", ["child-anchor"])]), block("second", ["block-anchor"])], assets: [], diagnostics: [])
    let context = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: generation, target: identity)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    try view.adopt(document, context: context)
    view.layoutSubtreeIfNeeded()
    let first = document.blocks[0]
    guard let raw = view.rects(blockID: first.id, logical: 0..<first.displayText.utf16.count).first,
          let converted = view.nodeRectInView(forNodeID: first.id) else { throw Failure(message: "Rendered node geometry") }
    try check(converted == view.bodyTextView.convert(raw, to: view), "Node rectangle is converted to reader coordinates")
    try check(view.nodeRectInView(forNodeID: "missing") == nil, "Unknown node has no rectangle")
    let snap = view.currentCrossProjectPosition()
    try check(snap.blockID == "first" && snap.anchor == nil && snap.scrollOffset == Double(view.scrollView.contentView.bounds.origin.y), "Snapshot captures the block without inheriting its child's anchor")
    try check(view.scrollToCrossProjectLocation(anchor: "block-anchor", blockID: "first", scrollOffset: 0) && view.focusedNodeID == "second", "Anchor takes priority")
    let anchoredSnap = view.currentCrossProjectPosition()
    try check(anchoredSnap.blockID == "second" && anchoredSnap.anchor == "block-anchor", "Snapshot captures the block's own anchor")
    try check(!view.scrollToCrossProjectLocation(anchor: "missing", blockID: "first", scrollOffset: 0), "Missing anchor does not fall back")
    try check(view.scrollToCrossProjectLocation(anchor: "", blockID: "first", scrollOffset: nil) && view.focusedNodeID == "first", "Block navigation")
    try check(view.scrollToCrossProjectLocation(anchor: nil, blockID: nil, scrollOffset: .greatestFiniteMagnitude), "Finite offset accepted")
    let maximum = max(0, view.bodyTextView.bounds.height - view.scrollView.contentView.bounds.height)
    try check(abs(view.scrollView.contentView.bounds.minY - maximum) < 1, "Offset clamps to bottom")
    try check(view.scrollToCrossProjectLocation(anchor: nil, blockID: "", scrollOffset: -5) && view.scrollView.contentView.bounds.minY == 0, "Offset clamps to top")
    try check(!view.scrollToCrossProjectLocation(anchor: nil, blockID: nil, scrollOffset: .nan) && !view.scrollToCrossProjectLocation(anchor: nil, blockID: nil, scrollOffset: nil), "Missing and nonfinite offsets fail")
    let nextGeneration = try store.beginRequest()
    let nextDocument = NativeReaderDocument(schemaVersion: 1, identity: identity, generation: nextGeneration,
      requiredCapabilities: ["semantic-tree-v1"], blocks: document.blocks, assets: [], diagnostics: [])
    let nextContext = NativeReaderRequestContext(requestID: UUID(), viewID: store.viewID, generation: nextGeneration, target: identity)
    try store.adopt(nextDocument, for: nextContext)
    try check(view.renderKey != view.requestedRenderKey, "Fixture retains stale geometry")
    try check(view.nodeRectInView(forNodeID: "first") == nil && !view.scrollToCrossProjectLocation(anchor: nil, blockID: nil, scrollOffset: 0),
              "Stale geometry and scrolling are rejected")
    view.dispose()
    try check(view.nodeRectInView(forNodeID: "first") == nil && !view.scrollToCrossProjectLocation(anchor: nil, blockID: nil, scrollOffset: 0),
              "Disposed view rejects geometry and scrolling")
  }

  @MainActor static func controllerScenario(_ scenario: String) async throws {
    let host = NativeReaderWindowController(provider: NativeReaderOfflineProvider(),
      target: { _ in throw NativeReaderOperationFailure.unavailable }, show: false, avoidActivation: true, fixtureMode: true)
    defer { host.dispose() }
    host.hostWindow.initialize()
    let generation = try host.store.beginRequest()
    let identity = NativeDocumentIdentity(documentID: "doc", serviceID: "service", revision: "revision", scope: .fixture)
    let url = "https://example.org/book.pdf#page=2"
    let text = "Theorem 2"
    let leaf = NativeReaderNode(id: "leaf", sectionID: "section", kind: .text, canonicalText: text, displayText: text,
      rangeUTF16: [0, text.utf16.count], offsets: NativeTextOffsets(text), children: [], anchors: [],
      annotationTargets: [], visible: true, mapping: .unmapped, passageKey: nil, direction: nil, language: nil,
      headingLevel: nil, math: nil, cell: nil, link: nil, assetID: nil, alt: nil)
    let link = NativeReaderNode(id: "link", sectionID: "section", kind: .link, canonicalText: text, displayText: text,
      rangeUTF16: [0, text.utf16.count], offsets: NativeTextOffsets(text), children: [leaf], anchors: ["origin"],
      annotationTargets: [], visible: true, mapping: .unmapped, passageKey: nil, direction: nil, language: nil,
      headingLevel: nil, math: nil, cell: nil, link: url, assetID: nil, alt: nil)
    let document = NativeReaderDocument(schemaVersion: 1, identity: identity, generation: generation,
      requiredCapabilities: ["semantic-tree-v1"], blocks: [link], assets: [], diagnostics: [])
    let context = NativeReaderRequestContext(requestID: UUID(), viewID: host.store.viewID, generation: generation, target: identity)
    let pending = CrossProjectNavigationEntry(profileID: "origin", documentTitle: "Origin", anchor: "origin", blockID: nil, scrollOffset: 0)
    host.pendingCrossProjectTarget = pending
    let adoption = try await host.prepare(document, context: context)
    try adoption.adopt()
    try check(host.pendingCrossProjectTarget == nil && host.textView.focusedNodeID == "link", "Document adoption consumes and restores pending location")
    host.pendingCrossProjectTarget = pending
    let reflow = try await host.prepare(document, context: context, reflowOnly: true)
    try reflow.adopt()
    try check(host.pendingCrossProjectTarget == pending, "Reflow preserves pending location")
    host.pendingCrossProjectTarget = nil
    host.hostWindow.window?.contentView?.layoutSubtreeIfNeeded()
    let project = CrossProjectCatalogProject(title: "Book", pdfURL: "https://example.org/book.pdf",
      references: ["thm": CrossProjectCatalogEntry(page: 2, text: text)], ambiguousLabels: [])
    host.crossProjectCatalogProvider = { CrossProjectCatalog(projects: ["book": project]) }
    var opened: [URL] = []
    host.openHomepage = { opened.append($0) }
    if scenario == "reader_preview_first_click" {
      try check(host.textView.activate(nodeID: "link"), "Activate link")
      try check(opened.isEmpty && host.activeCrossProjectPreviewView?.content.snippetText == "Theorem 2 · p. 2", "First click previews without opening")
      host.crossProjectCatalogProvider = { CrossProjectCatalog(projects: [:]) }
      _ = host.textView.activate(nodeID: "link")
      try check(opened.count == 1, "Unresolved links open normally")
      var ambiguous = project; ambiguous.ambiguousLabels = ["thm"]
      host.crossProjectCatalogProvider = { CrossProjectCatalog(projects: ["book": ambiguous]) }
      _ = host.textView.activate(nodeID: "link")
      try check(opened.count == 2, "Ambiguous links open normally")
      host.dispose()
      try check(host.activeCrossProjectPreviewView == nil, "Dispose clears preview")
    } else if scenario == "reader_async_snippet" {
      var continuations: [CheckedContinuation<CrossProjectPreviewContent?, Never>] = []
      host.crossProjectSnippetLoader = { _ in await withCheckedContinuation { continuations.append($0) } }
      _ = host.textView.activate(nodeID: "link")
      await Task.yield()
      guard let old = host.activeCrossProjectPreviewView else { throw Failure(message: "First preview") }
      _ = host.textView.activate(nodeID: "link")
      await Task.yield()
      guard let current = host.activeCrossProjectPreviewView else { throw Failure(message: "Second preview") }
      try check(continuations.count == 2 && old !== current, "New click replaces pending preview")
      var loaded = current.content; loaded.snippetText = "Loaded snippet"
      continuations[0].resume(returning: loaded)
      await Task.yield()
      try check(current.content.snippetText != loaded.snippetText && old.content.snippetText != loaded.snippetText, "Cancelled stale result ignored")
      continuations[1].resume(returning: loaded)
      await Task.yield()
      try check(current.content == loaded, "Current snippet updates")
      _ = host.textView.activate(nodeID: "link")
      await Task.yield()
      guard let dismissed = host.activeCrossProjectPreviewView,
            let popover = Mirror(reflecting: host).children.first(where: { $0.label == "crossProjectPreviewPopover" })?.value as? NSPopover,
            let delegate = popover.delegate else { throw Failure(message: "Presented popover") }
      popover.close()
      // Deliver the same AppKit delegate event if an offscreen popover was not shown.
      delegate.popoverDidClose?(Notification(name: NSPopover.didCloseNotification, object: popover))
      try check(host.activeCrossProjectPreviewView == nil, "Popover close clears active preview")
      _ = host.textView.activate(nodeID: "link")
      await Task.yield()
      guard let newest = host.activeCrossProjectPreviewView else { throw Failure(message: "Replacement preview") }
      delegate.popoverDidClose?(Notification(name: NSPopover.didCloseNotification, object: popover))
      try check(host.activeCrossProjectPreviewView === newest, "Old close event cannot dismiss replacement")
      continuations[2].resume(returning: loaded)
      continuations[3].resume(returning: nil)
      await Task.yield()
      try check(dismissed.content != loaded, "Dismissed preview ignores late snippet")
    } else {
      var captured: CrossProjectNavigationEntry?
      var target: CrossProjectPreviewContent?
      host.onOpenCrossProjectTarget = { target = $0; captured = $1 }
      let position = host.textView.currentCrossProjectPosition()
      _ = host.textView.activate(nodeID: "link")
      host.activeCrossProjectPreviewView?.openButton.performClick(nil)
      try check(target?.label == "thm" && captured == CrossProjectNavigationEntry(profileID: "", documentTitle: "", anchor: position.anchor, blockID: position.blockID, scrollOffset: position.scrollOffset), "Second click captures origin")
      try check(opened.isEmpty && host.activeCrossProjectPreviewView == nil, "Jump dismisses preview")
      host.onOpenCrossProjectTarget = nil
      _ = host.textView.activate(nodeID: "link")
      host.activeCrossProjectPreviewView?.openButton.performClick(nil)
      try check(opened.count == 1, "Missing jump callback opens URL")
      var returns = 0
      host.canReturnFromCrossProject = { true }
      host.onReturnFromCrossProject = { returns += 1; return true }
      guard let back = Mirror(reflecting: host.hostWindow).children.first(where: { $0.label == "back" })?.value as? NSButton else {
        throw Failure(message: "Back control")
      }
      try check(back.isEnabled, "Cross-project return enables Back")
      guard let menuBack = host.hostWindow.moreMenu.item(withTitle: "돌아가기") else { throw Failure(message: "Back menu item") }
      try check(menuBack.isEnabled, "Cross-project return enables Back menu item")
      _ = host.textView.navigate(toNodeID: "link")
      try check(host.textView.canReturnFromReference, "Fixture provides local return")
      host.hostWindow.returnFromReference()
      try check(returns == 0 && !host.textView.canReturnFromReference, "Local return has priority")
      guard let crossBack = host.hostWindow.moreMenu.item(withTitle: "돌아가기"), crossBack.isEnabled,
            let action = crossBack.action else { throw Failure(message: "Cross-project Back menu action") }
      _ = NSApp.sendAction(action, to: crossBack.target, from: crossBack)
      try check(returns == 1, "Next Back invokes cross-project return")
      host.hostWindow.displayMode(.originalPages)
      host.hostWindow.updateNavigation()
      host.hostWindow.returnFromReference()
      try check(!back.isEnabled && host.hostWindow.moreMenu.item(withTitle: "돌아가기")?.isEnabled == false && returns == 1, "Original pages disable Back")
    }
  }

  @MainActor static func clickBody(_ view: NativeCrossProjectPreviewView, _ point: NSPoint, in window: NSWindow) throws {
    let location = view.convert(point, to: nil)
    guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location,
      modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
      context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
      let hit = window.contentView?.hitTest(location) else {
      throw Failure(message: "Fixture must dispatch an actual hit-tested AppKit body event")
    }
    hit.mouseDown(with: event)
  }

  @MainActor static func main() async {
    do {
      _ = NSApplication.shared
      NSApp.setActivationPolicy(.prohibited)
      let content = CrossProjectPreviewContent(
        projectKey: "book", projectTitle: "미적분", referenceText: "정리 2", label: "theorem-2",
        snippetText: "연속인 함수의 성질을 살펴봅니다.\nThe next paragraph explains the result.", truncated: true)
      let view = NativeCrossProjectPreviewView(content: content)
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                            styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      window.contentView = view
      view.layoutSubtreeIfNeeded()
      let all = descendants(view)
      guard let snippet = all.first(where: { $0.identifier?.rawValue == "crossProjectPreview.snippet" }) as? NSTextField,
            let header = all.compactMap({ $0 as? NSTextField }).first(where: { $0.stringValue == "미적분 · 정리 2" }) else {
        throw Failure(message: "Header and identified snippet must render supplied content")
      }
      switch CommandLine.arguments[1] {
      case "content":
        try check(view.content == content, "The view must retain the exact target")
        try check(snippet.stringValue == content.snippetText, "Snippet remains exact even when excerpt is truncated")
        try check(!snippet.isEditable && !snippet.isSelectable && !header.isEditable, "Preview labels are display-only")
        try check(view.openButton.identifier?.rawValue == "crossProjectPreview.open", "Open control identifier")
        try check(view.openButton.title.isEmpty && view.openButton.imagePosition == .imageOnly, "Interactive icon has no visible title")
        // AppKit's system-symbol images have no NSImage cache name on this OS.
        let expectedSymbol = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
        let actualPixels = view.openButton.image?.tiffRepresentation
        try check(actualPixels != nil && actualPixels == expectedSymbol?.tiffRepresentation,
                  "The control must render the arrow.up.right SF Symbol")
        try check(view.openButton.toolTip == "해당 문서로 이동"
                    && view.openButton.accessibilityLabel() == "해당 문서로 이동", "Tooltip and accessibility label")
        try check(view.openButton.isEnabled && view.openButton.target != nil && view.openButton.action != nil,
                  "Icon must be an actual actionable button")
        try check(header.font == NativeAppDesign.Typography.font(.control)
                    && snippet.font == NativeAppDesign.Typography.font(.caption), "Labels use shared chrome typography")
        try check(!all.compactMap { ($0 as? NSButton)?.title }.contains(where: { $0.contains("열기") }),
                  "No button may display the forbidden text label")
        var replacement = content
        replacement.projectTitle = "대수"; replacement.referenceText = "정리 3"; replacement.snippetText = "Updated excerpt"
        view.update(content: replacement)
        try check(view.content == replacement && header.stringValue == "대수 · 정리 3" && snippet.stringValue == "Updated excerpt",
                  "Updating content changes the existing labels and target")
        var activated: CrossProjectPreviewContent?
        view.onOpenTarget = { activated = $0 }
        view.openButton.performClick(nil)
        try check(activated == replacement, "Activation uses updated target")
      case "activation":
        var targets: [CrossProjectPreviewContent] = []
        view.onOpenTarget = { targets.append($0) }
        try check(targets.isEmpty, "Preview presentation alone must not navigate")
        let buttonPoint = view.openButton.convert(NSPoint(x: view.openButton.bounds.midX, y: view.openButton.bounds.midY), to: nil)
        try check(window.contentView?.hitTest(buttonPoint) === view.openButton,
                  "Body activation must preserve native button hit testing")
        view.openButton.performClick(nil)
        try check(targets == [content], "Button activation emits its target exactly once")
        let snippetPoint = snippet.convert(NSPoint(x: snippet.bounds.midX, y: snippet.bounds.midY), to: view)
        try clickBody(view, snippetPoint, in: window)
        try check(targets == [content, content], "Clicking snippet body emits the same target exactly once")
        let headerPoint = header.convert(NSPoint(x: header.bounds.midX, y: header.bounds.midY), to: view)
        try clickBody(view, headerPoint, in: window)
        try check(targets.count == 3 && targets.last == content, "Header is part of the interactive preview body")
        try clickBody(view, NSPoint(x: 4, y: 4), in: window)
        try check(targets.count == 4 && targets.last == content, "Preview padding also activates the target")
        view.onOpenTarget = nil
        view.openButton.performClick(nil)
        try check(targets.count == 4, "Absent callback is harmless")
      case "layout":
        guard let surface = all.compactMap({ $0 as? NativeDesignSurface }).first else {
          throw Failure(message: "Preview must use the shared design surface")
        }
        try check(surface.role == .floating, "Shared floating role supplies the palette and shape")
        try check(surface === view.surface && surface.superview === view,
                  "The NSView exposes its composed design surface")
        for theme in NativeAppDesign.Theme.allCases {
          view.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
          for width: CGFloat in [240, 340, 480] {
            window.setContentSize(NSSize(width: width, height: 180))
            view.layoutSubtreeIfNeeded()
            try check(surface.frame == view.bounds, "Surface fills the preview")
            try check(surface.preferences.theme == theme, "Floating surface follows the inherited appearance")
            let buttonRect = view.openButton.convert(view.openButton.bounds, to: view)
            let headerRect = header.convert(header.bounds, to: view)
            let snippetRect = snippet.convert(snippet.bounds, to: view)
            try check(view.bounds.contains(buttonRect) && view.bounds.contains(headerRect)
                        && view.bounds.contains(snippetRect), "All controls fit compact bounds")
            try check(buttonRect.height >= NativeAppDesign.Shape.minimumControlHeight,
                      "Icon preserves the shared minimum target size")
            try check(buttonRect.minY == NativeAppDesign.Spacing.control
                        && snippetRect.minY - buttonRect.maxY == NativeAppDesign.Spacing.small,
                      "Compact layout uses shared spacing")
            try check(!buttonRect.intersects(headerRect) && !buttonRect.intersects(snippetRect), "Icon remains separately clickable")
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
              throw Failure(message: "Offscreen AppKit paint must be available")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "Preview paints in both appearances")
          }
        }
      case "reader": try readerHelpers()
      case "reader_preview_first_click", "reader_async_snippet", "reader_second_click_and_back":
        try await controllerScenario(CommandLine.arguments[1])
      default: throw Failure(message: "Unknown fixture scenario")
      }
      print("Passed \(CommandLine.arguments[1]); isolated AppKit component only")
    } catch {
      fputs("CrossProjectPreviewTests: \(error)\n", stderr)
      exit(1)
    }
  }
}
