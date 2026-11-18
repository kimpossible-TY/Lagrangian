import AppKit

/// Standard editing keeps AppKit semantics normally. Fixture inputs reject
/// system clipboard operations at the responder, including direct commands.
class NativeReaderInputTextView: NSTextView {
  var blocksSystemClipboard = false
  var allowsPrivateCopy = false
  var standardClipboardOperation: ((Selector) -> Void)?
  private func blocked(_ action: Selector) -> Bool {
    let name = NSStringFromSelector(action)
    return blocksSystemClipboard && (["cut:", "paste:", "pasteAsPlainText:", "pasteAsRichText:", "pasteAndMatchStyle:"].contains(name) || (name == "copy:" && !allowsPrivateCopy))
  }
  private func clipboard(_ action: Selector, normal: () -> Void) {
    guard !blocked(action) else { return }
    if let operation = standardClipboardOperation { operation(action) } else { normal() }
  }
  override func copy(_ sender: Any?) { clipboard(#selector(copy(_:))) { super.copy(sender) } }
  override func cut(_ sender: Any?) { clipboard(#selector(cut(_:))) { super.cut(sender) } }
  override func paste(_ sender: Any?) { clipboard(#selector(paste(_:))) { super.paste(sender) } }
  override func pasteAsPlainText(_ sender: Any?) { clipboard(#selector(pasteAsPlainText(_:))) { super.pasteAsPlainText(sender) } }
  override func pasteAsRichText(_ sender: Any?) { clipboard(#selector(pasteAsRichText(_:))) { super.pasteAsRichText(sender) } }
  override func doCommand(by selector: Selector) { if !blocked(selector) { super.doCommand(by: selector) } }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if blocksSystemClipboard, event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
       let key = event.charactersIgnoringModifiers?.lowercased(), ["x", "c", "v"].contains(key) {
      doCommand(by: NSSelectorFromString(key == "x" ? "cut:" : key == "c" ? "copy:" : "paste:")); return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if let action = item.action, blocked(action) { return false }
    return super.validateUserInterfaceItem(item)
  }
}

/// One field editor policy covers settings, search and TextKit find fields.
final class NativeReaderEditingWindow: NSWindow {
  var fixtureMode = false
  private var fixtureEditor: NativeReaderInputTextView?
  override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
    guard fixtureMode else { return super.fieldEditor(createFlag, for: object) }
    if createFlag, fixtureEditor == nil {
      let editor = NativeReaderInputTextView(); editor.isFieldEditor = true
      editor.blocksSystemClipboard = true; editor.isRichText = false
      fixtureEditor = editor
    }
    return fixtureEditor
  }
}
