import AppKit

struct CrossProjectPreviewContent: Equatable {
  var projectKey: String
  var projectTitle: String
  var referenceText: String
  var label: String
  var snippetText: String
  var truncated: Bool
}

/// Presents a resolved reference; the reader owns project adoption and navigation.
@MainActor final class NativeCrossProjectPreviewView: NSView {
  let content: CrossProjectPreviewContent
  let surface = NativeDesignSurface()
  let openButton = NativeDesignButton(title: "", target: nil, action: nil)
  private let header = NSTextField(labelWithString: "")
  private let snippet = NSTextField(wrappingLabelWithString: "")
  var onOpenTarget: ((CrossProjectPreviewContent) -> Void)?

  init(content: CrossProjectPreviewContent) {
    self.content = content
    super.init(frame: .zero)
    surface.role = .floating
    addSubview(surface)
    addSubview(header)
    addSubview(snippet)
    addSubview(openButton)

    header.stringValue = content.projectTitle + " · " + content.referenceText
    header.isEditable = false
    header.isSelectable = false
    header.font = NativeAppDesign.Typography.font(.control)
    header.lineBreakMode = .byTruncatingTail
    header.textColor = NSColor(name: nil) { appearance in
      NativeAppDesign.palette(.current(appearance: appearance)).ink
    }
    snippet.stringValue = content.snippetText
    snippet.isEditable = false
    snippet.isSelectable = false
    snippet.identifier = NSUserInterfaceItemIdentifier("crossProjectPreview.snippet")
    snippet.font = NativeAppDesign.Typography.font(.caption)
    snippet.lineBreakMode = .byTruncatingTail
    snippet.maximumNumberOfLines = 5
    snippet.textColor = NSColor(name: nil) { appearance in
      NativeAppDesign.palette(.current(appearance: appearance)).secondaryInk
    }

    openButton.identifier = NSUserInterfaceItemIdentifier("crossProjectPreview.open")
    openButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
    openButton.imagePosition = .imageOnly
    openButton.toolTip = "해당 문서로 이동"
    openButton.setAccessibilityLabel("해당 문서로 이동")
    openButton.target = self
    openButton.action = #selector(openTarget)
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize { NSSize(width: 340, height: 160) }

  override func layout() {
    super.layout()
    surface.frame = bounds
    let padding = NativeAppDesign.Spacing.control
    let gap = NativeAppDesign.Spacing.small
    let inner = bounds.insetBy(dx: padding, dy: padding)
    let buttonSize = NativeAppDesign.Shape.minimumControlHeight
    openButton.frame = NSRect(x: inner.maxX - buttonSize, y: inner.minY,
                              width: buttonSize, height: buttonSize)
    header.frame = NSRect(x: inner.minX, y: inner.minY,
                          width: max(0, inner.width - buttonSize - gap), height: buttonSize)
    snippet.frame = NSRect(x: inner.minX, y: openButton.frame.maxY + gap,
                           width: max(0, inner.width),
                           height: max(0, inner.maxY - openButton.frame.maxY - gap))
  }

  /// Keep native button tracking while making every other part of the preview actionable.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hit = super.hitTest(point) else { return nil }
    return hit === openButton || hit.isDescendant(of: openButton) ? hit : self
  }

  override func mouseDown(with event: NSEvent) { openTarget() }
  @objc private func openTarget() { onOpenTarget?(content) }
}
