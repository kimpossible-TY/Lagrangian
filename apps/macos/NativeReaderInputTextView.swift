import AppKit

@MainActor protocol NativeReaderFindActionHost: AnyObject {
  var isReaderFindHostHidden: Bool { get }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool
  func performTextFinderAction(_ sender: Any?)
}

@MainActor protocol NativeReaderCancelActionHost: AnyObject {
  func handleReaderEscape() -> Bool
}

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
  override func performTextFinderAction(_ sender: Any?) {
    if !(self is NativeReaderBodyTextView),
       let controller = window?.windowController as? NativeReaderFindActionHost {
      controller.performTextFinderAction(sender)
      return
    }
    super.performTextFinderAction(sender)
  }
  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if let action = item.action, blocked(action) { return false }
    if !(self is NativeReaderBodyTextView),
       item.action == #selector(NSResponder.performTextFinderAction(_:)),
       let controller = window?.windowController as? NativeReaderFindActionHost {
      let menuItem: NSMenuItem
      if let existing = item as? NSMenuItem {
        menuItem = existing
      } else {
        let temp = NSMenuItem(title: "", action: item.action, keyEquivalent: "")
        temp.tag = item.tag
        menuItem = temp
      }
      return controller.validateMenuItem(menuItem)
    }
    return super.validateUserInterfaceItem(item)
  }
}

/// One field editor policy covers settings, search and TextKit find fields.
final class NativeReaderEditingWindow: NSWindow {
  var fixtureMode = false
  private var fieldEditorStorage: NativeReaderInputTextView?
  override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
    if createFlag, fieldEditorStorage == nil {
      let editor = NativeReaderInputTextView(); editor.isFieldEditor = true
      editor.isRichText = false
      fieldEditorStorage = editor
    }
    fieldEditorStorage?.blocksSystemClipboard = fixtureMode
    return fieldEditorStorage
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command {
      let character = event.charactersIgnoringModifiers?.lowercased()
      let isAscii = character?.first?.isASCII == true
      if (character == "f" || (!isAscii && event.keyCode == 3)),
         let controller = windowController as? NativeReaderFindActionHost,
         controller.isReaderFindHostHidden {
        let item = NSMenuItem(title: "", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        if controller.validateMenuItem(item) {
          controller.performTextFinderAction(item)
          return true
        }
      }
    }
    return super.performKeyEquivalent(with: event)
  }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown,
       event.keyCode == 53,
       event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty {
      let responderView = firstResponder as? NSView
      let isFieldEditor = (responderView as? NSTextView)?.isFieldEditor == true
      let isNonBodyInput = responderView is NativeReaderInputTextView && !(responderView is NativeReaderBodyTextView)
      if !isFieldEditor && !isNonBodyInput,
         let controller = windowController as? NativeReaderCancelActionHost,
         controller.handleReaderEscape() {
        return
      }
    }
    super.sendEvent(event)
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty {
      let responderView = firstResponder as? NSView
      let isFieldEditor = (responderView as? NSTextView)?.isFieldEditor == true
      let isNonBodyInput = responderView is NativeReaderInputTextView && !(responderView is NativeReaderBodyTextView)
      if !isFieldEditor && !isNonBodyInput,
         (windowController as? NativeReaderCancelActionHost)?.handleReaderEscape() == true {
        return
      }
    }
    super.keyDown(with: event)
  }
}
