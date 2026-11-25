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
      default: throw Failure(message: "Unknown fixture scenario")
      }
      print("Passed \(CommandLine.arguments[1]); isolated AppKit component only")
    } catch {
      fputs("CrossProjectPreviewTests: \(error)\n", stderr)
      exit(1)
    }
  }
}
