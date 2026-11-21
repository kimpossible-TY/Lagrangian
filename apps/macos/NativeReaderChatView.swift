import AppKit

/// An allowlisted answer representation; HTML, images and scripts remain literal text.
/// NA03 may supply native math paint through the explicit attributed-math operation.
enum NativeReaderAnswerPart: Equatable {
    case text(String), code(String), math(String)
    struct Token {
        let part: NativeReaderAnswerPart
        let original: String
        let display: Bool
    }
    /// Single bounded scan. Unclosed math/code stays literal, including delimiters.
    /// Backtick spans/fences shield math. A backslash escapes the next character.
    static func tokens(_ markdown: String) -> [Token] {
        guard markdown.utf8.count <= 80000 else { return [Token(part: .text(markdown), original: markdown, display: false)] }
        let chars = Array(markdown)
        var result = [Token](), plain = "", i = 0
        func has(_ token: String, _ at: Int) -> Bool {
            let t = Array(token)
            return at + t.count <= chars.count && Array(chars[at..<at+t.count]) == t
        }
        func flush() {
            if !plain.isEmpty { result.append(Token(part: .text(plain), original: plain, display: false)); plain = "" }
        }
        while i < chars.count {
            if chars[i] == "`" {
                var n = 1
                while i+n < chars.count && chars[i+n] == "`" { n += 1 }
                guard n <= 32 else { plain += String(chars[i...]); break }
                let edge = String(repeating: "`", count: n), start = i
                i += n
                while i < chars.count && !has(edge, i) { i += 1 }
                guard i < chars.count else { plain += String(chars[start...]); break }
                let code = String(chars[start+n..<i]); i += n
                flush(); result.append(Token(part: .code(code), original: String(chars[start..<i]), display: false))
                continue
            }
            let opening: String?, closing: String?, display: Bool
            if has("$$", i) { opening = "$$"; closing = "$$"; display = true }
            else if has("\\[", i) { opening = "\\["; closing = "\\]"; display = true }
            else if has("\\(", i) { opening = "\\("; closing = "\\)"; display = false }
            else if chars[i] == "$" { opening = "$"; closing = "$"; display = false }
            else { opening = nil; closing = nil; display = false }
            if let opening, let closing {
                let start = i, edge = opening.count
                var end = i + edge
                while end < chars.count {
                    if has(closing, end) { break }
                    if !display && chars[end] == "\n" { break }
                    if chars[end] == "\\" { end += min(2, chars.count-end) } else { end += 1 }
                }
                if end < chars.count, has(closing, end), end > i+edge {
                    let tex = String(chars[i+edge..<end])
                    flush(); i = end + closing.count
                    result.append(Token(part: .math(tex), original: String(chars[start..<i]), display: display))
                    continue
                }
                // Do not reinterpret an unmatched opening as another delimiter.
                plain += String(chars[i...]); break
            }
            plain.append(chars[i]); i += 1
            if chars[i-1] == "\\", i < chars.count { plain.append(chars[i]); i += 1 }
        }
        flush(); return result
    }
    static func parse(_ markdown: String) -> [Self] { tokens(markdown).map(\.part) }

    @MainActor static func attributed(_ markdown: String, math: ((String) -> NSAttributedString?)? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for part in parse(markdown) {
            switch part {
            case .text(let text):
                // Simple native headings, emphasis and inline code. No HTML/DOM importer.
                for line in text.components(separatedBy: "\n") {
                    var value = line
                    var font = NSFont.systemFont(ofSize: 14)
                    if value.hasPrefix("# ") { value.removeFirst(2); font = .boldSystemFont(ofSize: 18) }
                    else if value.hasPrefix("## ") { value.removeFirst(3); font = .boldSystemFont(ofSize: 16) }
                    let attributed = NSMutableAttributedString(string: value + "\n", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                    for (pattern, attribute) in [("\\*\\*([^*\\n]+)\\*\\*", NSFont.boldSystemFont(ofSize: 14)), ("`([^`\\n]+)`", NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))] {
                        if let expression = try? NSRegularExpression(pattern: pattern) {
                            for match in expression.matches(in: attributed.string, range: NSRange(location: 0, length: attributed.length)) {
                                attributed.addAttribute(.font, value: attribute, range: match.range(at: 1))
                            }
                        }
                    }
                    result.append(attributed)
                }
            case .code(let text):
                result.append(NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor]))
            case .math(let text):
                result.append(math?(text) ?? NSAttributedString(string: "[Math — native layout unavailable]\n" + text,
                    attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor]))
            }
        }
        return result
    }
}

private let answerMathCopy = NSAttributedString.Key("NativeAnswerOrdinaryCopy")

/// Plain answer copy carries authored TeX delimiters. No document excerpt API.
final class NativeReaderAnswerTextView: NativeReaderInputTextView {
    var semanticValue = ""
    override func accessibilityValue() -> String? { semanticValue }
    func ordinaryText(in range: NSRange) -> String {
        guard let storage = textStorage, range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= storage.length, range.length <= storage.length - range.location else { return "" }
        var text = ""
        // Copy attribution is not a token identity: equal values can coalesce.
        // Each selected attachment character restores its own original token.
        storage.enumerateAttribute(.attachment, in: range) { attachment, subrange, _ in
            if attachment != nil {
                for index in subrange.location..<NSMaxRange(subrange) {
                    text += storage.attribute(answerMathCopy, at: index, effectiveRange: nil) as? String ??
                        (storage.string as NSString).substring(with: NSRange(location: index, length: 1))
                }
            } else { text += (storage.string as NSString).substring(with: subrange) }
        }
        return text
    }
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string else { return false }
        return pboard.setString(ordinaryText(in: selectedRange()), forType: .string)
    }
}

private final class NativeAnswerMathCell: NSTextAttachmentCell {
    let baseline: CGFloat
    init(_ prepared: NativePreparedAnswerMath) {
        baseline = CGFloat(prepared.layout.whole.descent)
        super.init(imageCell: NSImage(cgImage: prepared.image, size: prepared.size))
    }
    required init(coder: NSCoder) { fatalError("not archived") }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -baseline) }
}

private struct NativePreparedAnswerToken {
    let token: NativeReaderAnswerPart.Token
    let math: NativePreparedAnswerMath?
    let failure: String?
}
private struct NativePreparedAnswerMessage {
    let id: UUID
    let tokens: [NativePreparedAnswerToken]
}

/// No effects except the injected math worker. One bounded transcript job per view;
/// the view owns cancellation/adoption and does not queue another preparation.
private enum NativeAnswerPreparation {
    static func prepare(_ messages: [NativeReaderChatState.Message], worker: NativeMathWorker,
                        context: NativeObjectContext) async throws -> [NativePreparedAnswerMessage] {
        guard messages.count <= 256, messages.reduce(0, { $0 + $1.markdown.utf8.count }) <= 512 * 1024 else { throw NativeObjectError.budget }
        var result = [NativePreparedAnswerMessage](), formulas = 0, cost = 0
        for message in messages where message.complete && message.role == .assistant {
            try Task.checkCancellation()
            var tokens = [NativePreparedAnswerToken]()
            for token in NativeReaderAnswerPart.tokens(message.markdown) {
                try Task.checkCancellation()
                var prepared: NativePreparedAnswerMath?, failure: String?
                if case .math(let tex) = token.part {
                    formulas += 1
                    guard formulas <= 64 else { throw NativeObjectError.budget }
                    do {
                        prepared = try await worker.prepare(tex: tex, display: token.display, context: context)
                        cost += prepared!.image.bytesPerRow * prepared!.image.height
                        guard cost <= 16 * 1024 * 1024 else { throw NativeObjectError.budget }
                    } catch {
                        try Task.checkCancellation()
                        if error as? NativeObjectError == .budget { throw error }
                        failure = "Math unavailable: " + String(describing: error).prefix(128)
                    }
                }
                tokens.append(NativePreparedAnswerToken(token: token, math: prepared, failure: failure))
            }
            result.append(NativePreparedAnswerMessage(id: message.id, tokens: tokens))
        }
        return result
    }
}

/// Inline AppKit composer. The host anchors this view beside the selected native
/// block; only the Send button calls send. Restoring/history/model changes cannot infer.
@MainActor final class NativeReaderChatView: NSView, NSTextViewDelegate {
    let composer = NativeReaderInputTextView()
    let answer = NativeReaderAnswerTextView()
    let models = NSPopUpButton()
    let sendButton = NativeDesignButton(title: "Send", target: nil, action: nil)
    let cancelButton = NativeDesignButton(title: "Stop response", target: nil, action: nil)
    let historyButton = NativeDesignButton(title: "Refresh conversation", target: nil, action: nil)
    let accountButton = NativeDesignButton(title: "Manage on Homepage", target: nil, action: nil)
    let notice = NSTextField(wrappingLabelWithString: "")
    var persistDraft: ((NativeReaderRecoveredDraft) -> Void)?
    var recoverConversation: ((NativeReaderConversation) throws -> NativeReaderRecoveredDraft?)?
    var openHomepage: ((URL) -> Void)?
    // Compatibility operation: callers must supply immutable cache lookup only.
    var nativeMath: ((String) -> NSAttributedString?)?
    private let resolveActions: () async throws -> NativeReaderActions
    private var resolvedActions: NativeReaderActions?
    private var localSelection: NativeReaderSelection?
    private let initialSelection: NativeReaderSelection?
    var localSelectionTicket: UUID? { initialSelection?.ticket }
    var onDismiss: (() -> Void)?
    let dismissButton = NativeDesignButton(title: "작성기 닫기", target: nil, action: nil)
    private let chrome = NativeDesignSurface()
    private func owner() async throws -> NativeReaderActions {
        if let resolvedActions { return resolvedActions }
        let result = try await resolveActions(); resolvedActions = result; return result
    }
    private let context: NativeReaderRequestContext
    private let authorize: () throws -> Void
    private let authorizeSend: () throws -> Void
    // UI projection only. Effect-time authorization remains in every action.
    // Passive present/paint/copy/AX/resize must never invoke injected operations.
    private var controlAvailability = (conversation: true, selection: true)
    var presentationConversation: NativeReaderConversation? { conversation }
    var presentationSelection: NativeReaderSelection? { localSelection == nil ? initialSelection : nil }
    var presentationModels: [String] { models.itemTitles }
    func restoreModelChoices(_ choices: [String]) {
        models.removeAllItems(); models.addItems(withTitles: choices)
    }
    private var conversation: NativeReaderConversation?
    private var homepage: URL?
    private var preferredModel: String?
    private var editGeneration = 0
    private var modelEditGeneration = 0
    private var dirty = false
    private var pendingQuestion: String?
    private var pendingModel: String?
    private var pendingMessage: UUID?
    private var unknownEffect = false
    private var subscription: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var disposed = false
    private var operationEpoch = 0
    private var cancelling = false

    private struct MathKey: Equatable {
        struct Message: Equatable { let id: UUID; let text: String; let complete: Bool; let assistant: Bool }
        let context: NativeReaderRequestContext
        let object: NativeObjectContext
        let conversation: UUID
        let version: Int, sequence: Int
        let messages: [Message]
    }
    private var mathWorker: NativeMathWorker?
    private var mathContext: NativeObjectContext?
    private var mathKey: MathKey?
    private var mathEpoch = 0
    private var mathTask: Task<Void, Never>?
    private var preparedMessages = [NativePreparedAnswerMessage]()
    private(set) var mathPreparationCount = 0
    private(set) var preparedFormulaCount = 0
    private(set) var mathFailure: String?

    /// Host injection: pinned worker URLs and explicit current layout inputs.
    /// Resize/theme/font changes call this again. It schedules no inference.
    func configureMath(worker: NativeMathWorker, context: NativeObjectContext) throws {
        guard !disposed, context.identity == self.context.target,
              context.snapshotGeneration == self.context.generation else { throw NativeObjectError.stale }
        try context.validate()
        if mathContext == context, mathWorker === worker { return }
        invalidateMath(); mathWorker = worker; mathContext = context
        answer.appearance = NSAppearance(named: context.theme == .dark ? .darkAqua : .aqua)
        if let conversation { present(conversation) }
    }
    func clearMath(reason: String) {
        invalidateMath(); mathWorker = nil; mathContext = nil; mathFailure = reason
        if let conversation { renderTranscript(conversation) }
        notice.stringValue = reason
    }
    private func invalidateMath() {
        mathEpoch += 1; mathTask?.cancel(); mathTask = nil; mathKey = nil
        preparedMessages = []; preparedFormulaCount = 0; mathFailure = nil
    }

    convenience init(actions: NativeReaderActions, context: NativeReaderRequestContext, authorize: @escaping () throws -> Void,
                     authorizeSend: (() throws -> Void)? = nil) {
        self.init(resolveActions: { actions }, context: context, selection: nil, authorize: authorize, authorizeSend: authorizeSend)
        resolvedActions = actions
    }
    init(resolveActions: @escaping () async throws -> NativeReaderActions, context: NativeReaderRequestContext,
         selection: NativeReaderSelection?, authorize: @escaping () throws -> Void,
         authorizeSend: (() throws -> Void)? = nil) {
        self.resolveActions = resolveActions; self.context = context; self.authorize = authorize; self.authorizeSend = authorizeSend ?? authorize; self.localSelection = selection; self.initialSelection = selection
        super.init(frame: .zero)
        chrome.role = .panel; addSubview(chrome)
        dismissButton.target = self; dismissButton.action = #selector(dismissComposerExplicitly)
        composer.isRichText = false
        composer.font = .systemFont(ofSize: 14)
        composer.delegate = self
        composer.setAccessibilityLabel("Question draft")
        answer.isEditable = false; answer.isSelectable = true
        answer.setAccessibilityLabel("Conversation")
        let questionScroll = NSScrollView(); questionScroll.documentView = composer; questionScroll.hasVerticalScroller = true
        let answerScroll = NSScrollView(); answerScroll.documentView = answer; answerScroll.hasVerticalScroller = true
        composer.isVerticallyResizable = true; composer.autoresizingMask = [.width]
        answer.isVerticallyResizable = true; answer.autoresizingMask = [.width]
        let controls = NativeChromeControlRow([models, sendButton, cancelButton, historyButton, accountButton, dismissButton])
        let stack = NSStackView(views: [notice, answerScroll, questionScroll, controls])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [answerScroll, questionScroll, controls, notice] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor), notice.widthAnchor.constraint(equalTo: stack.widthAnchor),
            answerScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), answerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            questionScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), questionScroll.heightAnchor.constraint(equalToConstant: 80)
        ])
        models.target = self; models.action = #selector(modelChanged)
        sendButton.target = self; sendButton.action = #selector(sendExplicitly)
        cancelButton.target = self; cancelButton.action = #selector(cancelExplicitly)
        historyButton.target = self; historyButton.action = #selector(refreshConversationExplicitly)
        accountButton.target = self; accountButton.action = #selector(manageExplicitly)
        NativeChrome.apply(to: self)
        sendButton.designRole = .primary
        if selection != nil { notice.stringValue = "현재 선택의 질문 작성기 · 명시 Send 전에는 요청하지 않습니다. 전송 시 계정·권한·모델을 확인합니다." }
        updateControls()
    }
    override func layout() { super.layout(); chrome.frame = bounds }
    @objc func dismissComposerExplicitly() { onDismiss?() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { onDismiss?(); return true }
        return false
    }
    func refreshAuthorization() {
        let live = (try? authorize()) != nil
        controlAvailability = (live, live && (try? authorizeSend()) != nil)
        if initialSelection != nil, !unknownEffect, !controlAvailability.selection { notice.stringValue = "선택이 변경되어 전송할 수 없습니다. 현재 내용을 다시 선택해 질문하세요. 초안은 유지됩니다." }
        updateControls()
    }
    required init?(coder: NSCoder) { nil }

    /// Both host entry paths consume the same existing draft owner, only after
    /// an accepted conversation has established its identity and context.
    @discardableResult func adopt(_ value: NativeReaderConversation, preservingLocalDraft: Bool = false) throws -> Bool {
        let recovered = try recoverConversation?(value)
        present(value, recovered: recovered, preservingLocalDraft: preservingLocalDraft)
        persistCurrentDraft()
        return recovered != nil
    }

    func present(_ value: NativeReaderConversation, recovered: NativeReaderRecoveredDraft? = nil,
                 preservingLocalDraft: Bool = false) {
        guard !disposed, value.state.context == context else { return }
        if let old = conversation, old.state.conversationID == value.state.conversationID,
           (value.state.version < old.state.version || value.state.sequence < old.state.sequence) { return }
        guard value.state.messages.count <= 256, value.state.messages.reduce(0, { $0 + $1.markdown.utf8.count }) <= 512 * 1024 else { return }
        conversation = value
        if !dirty { composer.string = value.draft }
        if let recovered, recovered.conversationID == value.state.conversationID, recovered.version <= value.state.version {
            if !preservingLocalDraft || !dirty { composer.string = recovered.text }
            dirty = true; pendingMessage = recovered.pendingMessageID
            pendingQuestion = recovered.pendingMessageID == nil ? nil : (recovered.pendingQuestion ?? recovered.text)
            pendingModel = recovered.pendingMessageID == nil ? nil : (recovered.pendingModel ?? recovered.model)
            unknownEffect = pendingMessage != nil
            if !preservingLocalDraft || modelEditGeneration == 0 {
                preferredModel = recovered.model
                if let model = recovered.model { models.selectItem(withTitle: model) }
            }
            notice.stringValue = "Recovered draft. Refresh conversation before retrying a pending Send."
        }
        prepareMathIfNeeded(value)
        renderTranscript(value)
        updateControls()
    }

    private func prepareMathIfNeeded(_ value: NativeReaderConversation) {
        guard let worker = mathWorker, let object = mathContext else { return }
        let key = MathKey(context: context, object: object, conversation: value.state.conversationID,
            version: value.state.version, sequence: value.state.sequence,
            messages: value.state.messages.map { .init(id: $0.id, text: $0.markdown, complete: $0.complete, assistant: $0.role == .assistant) })
        guard key != mathKey else { return }
        invalidateMath(); mathKey = key
        let epoch = mathEpoch, messages = value.state.messages
        guard messages.contains(where: { $0.complete && $0.role == .assistant }) else { return }
        mathPreparationCount += 1
        let computation = Task.detached(priority: .userInitiated) {
            try await NativeAnswerPreparation.prepare(messages, worker: worker, context: object)
        }
        mathTask = Task { [weak self] in
            do {
                let prepared = try await withTaskCancellationHandler(operation: { try await computation.value }, onCancel: { computation.cancel() })
                guard let self, !disposed, epoch == mathEpoch, mathKey == key, let current = conversation else { return }
                preparedMessages = prepared
                preparedFormulaCount = prepared.reduce(0) { $0 + $1.tokens.filter { $0.math != nil }.count }
                mathTask = nil
                renderTranscript(current)
            } catch {
                guard let self, !disposed, epoch == mathEpoch, mathKey == key else { return }
                mathTask = nil; mathFailure = "Math preparation unavailable"
            }
        }
    }

    // Synchronous presentation reads immutable pixels/metrics; no parser/helper/layout.
    private func renderTranscript(_ value: NativeReaderConversation) {
        let output = NSMutableAttributedString(string: "")
        var semantic = ""
        for message in value.state.messages {
            let role = message.role == .user ? "You\n" : "Assistant\n"
            output.append(NSAttributedString(string: role, attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]))
            semantic += role
            if message.complete, message.role == .assistant,
               let prepared = preparedMessages.first(where: { $0.id == message.id }) {
                for item in prepared.tokens {
                    if let math = item.math {
                        let attachment = NSTextAttachment(); attachment.attachmentCell = NativeAnswerMathCell(math)
                        let text = NSMutableAttributedString(attachment: attachment)
                        text.addAttribute(answerMathCopy, value: item.token.original, range: NSRange(location: 0, length: text.length))
                        output.append(text); semantic += math.math.normalizedText
                    } else {
                        let original = item.token.original
                        output.append(NSAttributedString(string: original, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]))
                        semantic += original
                        if let failure = item.failure { semantic += " [" + failure + "]" }
                    }
                }
            } else {
                output.append(NSAttributedString(string: message.markdown, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]))
                semantic += message.markdown
            }
            output.append(NSAttributedString(string: "\n")); semantic += "\n"
        }
        answer.semanticValue = semantic
        answer.textStorage?.setAttributedString(output)
    }

    func presentAccount(_ state: NativeReaderAccountState) {
        guard !disposed else { return }
        let selected = preferredModel ?? models.titleOfSelectedItem
        models.removeAllItems(); models.addItems(withTitles: state.models)
        if let selected, state.models.contains(selected) { models.selectItem(withTitle: selected) }
        homepage = state.homepage
        notice.stringValue = state.signedIn ? (state.planEnabled ? "Connected" : "Plan unavailable") : "Sign in through the configured Homepage."
        accountButton.isEnabled = homepage != nil
        updateControls()
    }

    @objc func modelChanged() {
        guard !disposed else { return }
        modelEditGeneration += 1
        preferredModel = models.titleOfSelectedItem
        persistCurrentDraft()
        updateControls()
    }

    var recoveryDraft: NativeReaderRecoveredDraft? {
        guard let value = conversation else { return nil }
        return NativeReaderRecoveredDraft(conversationID: value.state.conversationID, version: value.state.version,
            text: composer.string, pendingMessageID: pendingMessage, model: models.titleOfSelectedItem ?? preferredModel,
            pendingQuestion: pendingQuestion, pendingModel: pendingModel)
    }
    private func persistCurrentDraft() { if let draft = recoveryDraft { persistDraft?(draft) } }

    func textDidChange(_ notification: Notification) {
        guard !disposed else { return }
        editGeneration += 1; dirty = true
        if let value = conversation {
            persistCurrentDraft()
            // A locally reopened Ask stays local until an explicit operation resolves its owner.
            guard resolvedActions != nil else { updateControls(); return }
            let generation = editGeneration, text = composer.string
            draftTask?.cancel()
            draftTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    guard let self, !disposed, generation == editGeneration, !unknownEffect else { return }
                    try authorize()
                    _ = try await (try await owner()).perform(.draft(conversation: value.state.conversationID, version: value.state.version, text: text), context: context)
                    if let updated = await (try await owner()).conversation(value.state.conversationID), generation == editGeneration { present(updated) }
                } catch { /* Local draft remains visible and in the injected recovery store. */ }
            }
        }
        updateControls()
    }

    @objc func sendExplicitly() {
        if localSelection != nil { sendLocalExplicitly(); return }
        guard !disposed, operation == nil, !unknownEffect, let record = conversation,
              let model = models.titleOfSelectedItem else { return }
        do { try authorize(); try authorizeSend() } catch { notice.stringValue = "Reselect a current passage before sending."; return }
        draftTask?.cancel()
        guard pendingMessage == nil || (pendingQuestion.map { Array($0.unicodeScalars) == Array(composer.string.unicodeScalars) } == true && pendingModel == model) else {
            notice.stringValue = "Previous Send remains unconfirmed. Explicit retry requires its original question/model."
            return
        }
        let text = composer.string, generation = editGeneration, message = pendingMessage ?? UUID()
        pendingMessage = message; pendingQuestion = text; pendingModel = model
        persistCurrentDraft()
        operationEpoch += 1
        let epoch = operationEpoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationEpoch == epoch { operation = nil; updateControls() } }
            do {
                _ = try await (try await owner()).perform(.send(conversation: record.state.conversationID, version: record.state.version,
                    message: message, question: text, model: model), context: context)
                guard !disposed, operationEpoch == epoch else { return }
                try authorize()
                pendingMessage = nil; pendingQuestion = nil; pendingModel = nil
                if generation == editGeneration { dirty = false }
                if let updated = await (try await owner()).conversation(record.state.conversationID) { present(updated) }
                persistCurrentDraft()
                observe(record.state.conversationID)
            } catch {
                guard !disposed, operationEpoch == epoch, !Task.isCancelled else { return }
                unknownEffect = true
                notice.stringValue = "Send acknowledgment unavailable. Refresh conversation before an explicit retry."
            }
        }
        updateControls()
    }

    private func sendLocalExplicitly() {
        guard !disposed, operation == nil, !unknownEffect, let selection = localSelection,
              pendingMessage == nil || (pendingQuestion.map { Array($0.unicodeScalars) == Array(composer.string.unicodeScalars) } == true && pendingModel == models.titleOfSelectedItem),
              !composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try authorizeSend() } catch { notice.stringValue = "선택이 변경되었습니다. 현재 내용을 다시 선택하세요."; updateControls(); return }
        // Seal this click's intent before any account/selection/open await.
        // Native draft edits and model changes require another explicit Send.
        let question = composer.string, generation = editGeneration, modelGeneration = modelEditGeneration
        let selectedModel = models.titleOfSelectedItem ?? preferredModel
        let knownConversation = conversation?.state.conversationID
        func intentIsCurrent() -> Bool {
            editGeneration == generation && modelEditGeneration == modelGeneration &&
                Array(composer.string.unicodeScalars) == Array(question.unicodeScalars) &&
                (selectedModel == nil || models.titleOfSelectedItem == selectedModel)
        }
        func requireNewSend() {
            notice.stringValue = "준비 중 질문이나 모델이 변경되어 전송하지 않았습니다. 현재 초안을 확인하고 다시 Send를 누르세요."
        }
        operationEpoch += 1; let epoch = operationEpoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationEpoch == epoch { operation = nil; updateControls() } }
            do {
                let actions = try await owner()
                try Task.checkCancellation(); try authorizeSend()
                let account = try await actions.account(context: context)
                try Task.checkCancellation(); try authorizeSend()
                presentAccount(account)
                guard account.signedIn, account.planEnabled, !account.models.isEmpty else {
                    notice.stringValue = "계정·이용 권한 또는 모델이 없어 전송하지 않았습니다. 기존 홈페이지에서 연결 상태를 확인하세요."; return
                }
                guard intentIsCurrent() else { requireNewSend(); return }
                try await actions.updateSelection(selection, context: context)
                try Task.checkCancellation(); try authorizeSend()
                guard intentIsCurrent() else { requireNewSend(); return }
                let state = try await actions.perform(.open(selection), context: context)
                try Task.checkCancellation(); try authorizeSend()
                guard !disposed, operationEpoch == epoch,
                      let record = await actions.conversation(state.conversationID) else { return }
                dirty = true
                if let knownConversation {
                    guard record.state.conversationID == knownConversation else { throw NativeReaderOperationFailure.unavailable }
                    present(record) // Already restored/reconciled in this view; never replay older recovery.
                    localSelection = nil
                } else {
                    let restored = try adopt(record, preservingLocalDraft: true)
                    localSelection = nil
                    if restored {
                        notice.stringValue = "이전 대화와 초안을 복원했습니다. 대화를 확인한 뒤 명시적으로 다시 Send를 누르세요."
                        return
                    }
                }
                // If open completed after an edit, adopt its conversation while
                // retaining the current draft; do not continue the old Send.
                guard intentIsCurrent() else { requireNewSend(); return }
                // Continue the same explicit user Send through the established UUID/receipt owner.
                operation = nil; sendExplicitly()
            } catch {
                guard !disposed, operationEpoch == epoch, !Task.isCancelled else { return }
                notice.stringValue = "대화를 준비하지 못해 전송하지 않았습니다. 선택·연결 상태를 확인한 뒤 다시 시도하세요."
            }
        }
        updateControls()
    }

    @objc func refreshConversationExplicitly() {
        guard !disposed, operation == nil, conversation != nil else { return }
        draftTask?.cancel()
        operationEpoch += 1
        let epoch = operationEpoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationEpoch == epoch { operation = nil; updateControls() } }
            do { try await readAuthoritativeHistory() }
            catch {
                guard !disposed, operationEpoch == epoch, !Task.isCancelled else { return }
                notice.stringValue = "Conversation refresh unavailable. Draft and pending Send retained."
            }
        }
        updateControls()
    }

    func readAuthoritativeHistory() async throws {
        guard !disposed, let before = conversation else { throw NativeReaderOperationFailure.unavailable }
        try Task.checkCancellation()
        try authorize()
        let generation = editGeneration, epoch = operationEpoch
        let records = try await (try await owner()).history(context: context)
        try Task.checkCancellation()
        guard !disposed, epoch == operationEpoch, let current = conversation,
              current.state.conversationID == before.state.conversationID else { throw NativeReaderOperationFailure.unavailable }
        try authorize()
        guard let record = records.first(where: { $0.state.conversationID == current.state.conversationID }) else {
            throw NativeReaderOperationFailure.rejected(code: "conversation-not-found")
        }
        guard record.state.context == context, record.state.version >= current.state.version,
              record.state.sequence >= current.state.sequence else { throw NativeReaderContractError.staleGeneration }
        if let pendingMessage, let pendingQuestion,
           record.state.confirmsUserMessage(pendingMessage, question: pendingQuestion) {
            // A newer local draft is never acknowledged by the older message.
            if generation == editGeneration && Array(composer.string.unicodeScalars) == Array(pendingQuestion.unicodeScalars) {
                dirty = false
            }
            self.pendingMessage = nil; self.pendingQuestion = nil; self.pendingModel = nil
        }
        unknownEffect = false
        present(record)
        persistCurrentDraft()
        notice.stringValue = pendingMessage == nil ? "Conversation refreshed." : "Previous Send is unconfirmed. Retry only its original question and model."
    }

    private func observe(_ id: UUID) {
        subscription?.cancel()
        subscription = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in (try await owner()).observe(conversation: id, context: context) {
                    guard !disposed else { return }
                    if let record = await (try await owner()).conversation(id) { present(record) }
                }
            } catch { if !disposed { notice.stringValue = "Stream disconnected. Refresh conversation to resume." } }
        }
    }

    @objc func cancelExplicitly() {
        guard !disposed, !cancelling, let record = conversation, record.status == "streaming" else { return }
        cancelling = true
        operation?.cancel()
        invalidateMath()
        operationEpoch += 1
        let epoch = operationEpoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationEpoch == epoch { cancelling = false; operation = nil; updateControls() } }
            do {
                try authorize()
                let actions = try await owner()
                try Task.checkCancellation()
                guard !disposed, operationEpoch == epoch else { throw NativeReaderContractError.disposed }
                try authorize()
                let state = try await actions.perform(.cancel(conversation: record.state.conversationID), context: context)
                try Task.checkCancellation()
                let latest = await actions.conversation(record.state.conversationID)
                guard !disposed, operationEpoch == epoch, state.context == context,
                      state.conversationID == record.state.conversationID,
                      conversation?.state.conversationID == record.state.conversationID, let accepted = latest,
                      accepted.state.version >= record.state.version, accepted.state.sequence >= record.state.sequence,
                      accepted.state.context == context, accepted.state.conversationID == state.conversationID,
                      accepted.state.version >= state.version, accepted.state.sequence >= state.sequence else { throw NativeReaderContractError.staleGeneration }
                try authorize()
                present(accepted) // Presentation only; pending Send reconciliation still requires history.
                persistCurrentDraft()
            }
            catch {
                guard !disposed, operationEpoch == epoch, !Task.isCancelled else { return }
                notice.stringValue = "Stop acknowledgment unavailable; refresh conversation."
            }
        }
        updateControls()
    }
    @objc func manageExplicitly() { if !disposed, let homepage { openHomepage?(homepage) } }
    private func updateControls() {
        let retryMatches = pendingMessage == nil || (pendingQuestion.map { Array($0.unicodeScalars) == Array(composer.string.unicodeScalars) } == true && pendingModel == models.titleOfSelectedItem)
        let live = controlAvailability.conversation
        let current = controlAvailability.selection
        sendButton.isEnabled = current && retryMatches && !disposed && operation == nil && !unknownEffect && (localSelection != nil || (conversation != nil && models.numberOfItems > 0)) && !composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        cancelButton.isEnabled = live && !disposed && !cancelling && conversation?.status == "streaming"
        historyButton.isEnabled = live && !disposed && operation == nil && conversation != nil
    }
    func dispose() {
        invalidateMath()
        disposed = true; operationEpoch += 1; subscription?.cancel(); operation?.cancel(); draftTask?.cancel()
        subscription = nil; operation = nil; draftTask = nil; cancelling = false; updateControls()
    }
}
