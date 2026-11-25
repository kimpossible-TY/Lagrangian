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

  @MainActor static func main() {
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
      default: throw Failure(message: "Unknown fixture scenario")
      }
      print("Passed \(CommandLine.arguments[1]); isolated AppKit component only")
    } catch {
      fputs("CrossProjectPreviewTests: \(error)\n", stderr)
      exit(1)
    }
  }
}
