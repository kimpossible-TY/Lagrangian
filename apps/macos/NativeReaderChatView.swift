import AppKit

/// An allowlisted answer representation; HTML, images and scripts remain literal text.
/// NA03 may supply native math paint through the explicit attributed-math operation.
enum NativeReaderAnswerPart: Equatable {
    case text(String), code(String), math(String)
    static func parse(_ markdown: String) -> [Self] {
        let text = String(markdown.prefix(80000))
        var parts = [Self](), plain = "", math = "", code = ""
        var inCode = false, inMath = false
        func flushPlain() { if !plain.isEmpty { parts.append(.text(plain)); plain = "" } }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") && !inMath {
                if inCode { parts.append(.code(code)); code = "" } else { flushPlain() }
                inCode.toggle(); continue
            }
            if inCode { code += line + "\n"; continue }
            if line.trimmingCharacters(in: .whitespaces) == "$$" {
                if inMath { parts.append(.math(math)); math = "" } else { flushPlain() }
                inMath.toggle(); continue
            }
            if inMath { math += line + "\n" } else { plain += line + "\n" }
        }
        if inCode { plain += "```\n" + code }
        if inMath { plain += "$$\n" + math }
        flushPlain()
        var expanded = [Self]()
        let pattern = #"\\\([\s\S]*?\\\)|\\\[[\s\S]*?\\\]|(?<!\\)\$[^$\n]+\$"#
        let expression = try? NSRegularExpression(pattern: pattern)
        for part in parts {
            guard case .text(let value) = part, let expression else { expanded.append(part); continue }
            let string = value as NSString
            var position = 0
            for match in expression.matches(in: value, range: NSRange(location: 0, length: string.length)) {
                if match.range.location > position { expanded.append(.text(string.substring(with: NSRange(location: position, length: match.range.location-position)))) }
                let token = string.substring(with: match.range)
                let edge = token.hasPrefix("$") ? 1 : 2
                expanded.append(.math(String(token.dropFirst(edge).dropLast(edge))))
                position = NSMaxRange(match.range)
            }
            if position < string.length { expanded.append(.text(string.substring(from: position))) }
        }
        return expanded
    }

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

/// Inline AppKit composer. The host anchors this view beside the selected native
/// block; only the Send button calls send. Restoring/history/model changes cannot infer.
@MainActor final class NativeReaderChatView: NSView, NSTextViewDelegate {
    let composer = NSTextView()
    let answer = NSTextView()
    let models = NSPopUpButton()
    let sendButton = NSButton(title: "Send", target: nil, action: nil)
    let cancelButton = NSButton(title: "Stop response", target: nil, action: nil)
    let accountButton = NSButton(title: "Manage on Homepage", target: nil, action: nil)
    let notice = NSTextField(wrappingLabelWithString: "")
    var persistDraft: ((NativeReaderRecoveredDraft) -> Void)?
    var openHomepage: ((URL) -> Void)?
    var nativeMath: ((String) -> NSAttributedString?)?
    private let actions: NativeReaderActions
    private let context: NativeReaderRequestContext
    private let authorize: () throws -> Void
    private var conversation: NativeReaderConversation?
    private var homepage: URL?
    private var preferredModel: String?
    private var editGeneration = 0
    private var dirty = false
    private var pendingMessage: UUID?
    private var unknownEffect = false
    private var subscription: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var disposed = false
    private var operationEpoch = 0

    init(actions: NativeReaderActions, context: NativeReaderRequestContext, authorize: @escaping () throws -> Void) {
        self.actions = actions; self.context = context; self.authorize = authorize
        super.init(frame: .zero)
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
        let controls = NSStackView(views: [models, sendButton, cancelButton, accountButton])
        controls.orientation = .horizontal
        let stack = NSStackView(views: [notice, answerScroll, questionScroll, controls])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [answerScroll, questionScroll, controls, notice] { view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            answerScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), answerScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            questionScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), questionScroll.heightAnchor.constraint(equalToConstant: 80)
        ])
        models.target = self; models.action = #selector(modelChanged)
        sendButton.target = self; sendButton.action = #selector(sendExplicitly)
        cancelButton.target = self; cancelButton.action = #selector(cancelExplicitly)
        accountButton.target = self; accountButton.action = #selector(manageExplicitly)
        updateControls()
    }
    required init?(coder: NSCoder) { nil }

    func present(_ value: NativeReaderConversation, recovered: NativeReaderRecoveredDraft? = nil) {
        guard !disposed, value.state.context == context else { return }
        if let old = conversation, old.state.conversationID == value.state.conversationID,
           (value.state.version < old.state.version || value.state.sequence < old.state.sequence) { return }
        conversation = value
        if !dirty { composer.string = value.draft }
        if let recovered, recovered.conversationID == value.state.conversationID {
            composer.string = recovered.text; dirty = true; pendingMessage = recovered.pendingMessageID
            unknownEffect = pendingMessage != nil
            preferredModel = recovered.model
            if let model = recovered.model { models.selectItem(withTitle: model) }
            notice.stringValue = "Recovered draft. Read authoritative history before retrying a pending Send."
        }
        let output = NSMutableAttributedString(string: "")
        for message in value.state.messages {
            output.append(NSAttributedString(string: message.role == .user ? "You\n" : "Assistant\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
            output.append(NativeReaderAnswerPart.attributed(message.markdown, math: nativeMath))
        }
        answer.textStorage?.setAttributedString(output)
        updateControls()
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
        preferredModel = models.titleOfSelectedItem
        persistCurrentDraft()
    }

    private func persistCurrentDraft() {
        if let value = conversation {
            persistDraft?(NativeReaderRecoveredDraft(conversationID: value.state.conversationID, version: value.state.version,
                text: composer.string, pendingMessageID: pendingMessage, model: models.titleOfSelectedItem))
        }
    }

    func textDidChange(_ notification: Notification) {
        guard !disposed else { return }
        editGeneration += 1; dirty = true
        if let value = conversation {
            persistCurrentDraft()
            let generation = editGeneration, text = composer.string
            draftTask?.cancel()
            draftTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    guard let self, !disposed, generation == editGeneration, !unknownEffect else { return }
                    try authorize()
                    _ = try await actions.perform(.draft(conversation: value.state.conversationID, version: value.state.version, text: text), context: context)
                    if let updated = await actions.conversation(value.state.conversationID), generation == editGeneration { present(updated) }
                } catch { /* Local draft remains visible and in the injected recovery store. */ }
            }
        }
        updateControls()
    }

    @objc func sendExplicitly() {
        guard !disposed, operation == nil, !unknownEffect, let record = conversation,
              let model = models.titleOfSelectedItem else { return }
        do { try authorize() } catch { notice.stringValue = "Reselect a current passage before sending."; return }
        draftTask?.cancel()
        let text = composer.string, generation = editGeneration, message = pendingMessage ?? UUID()
        pendingMessage = message
        persistDraft?(NativeReaderRecoveredDraft(conversationID: record.state.conversationID, version: record.state.version, text: text, pendingMessageID: message, model: model))
        operationEpoch += 1
        let epoch = operationEpoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationEpoch == epoch { operation = nil; updateControls() } }
            do {
                _ = try await actions.perform(.send(conversation: record.state.conversationID, version: record.state.version,
                    message: message, question: text, model: model), context: context)
                guard !disposed, operationEpoch == epoch else { return }
                try authorize()
                pendingMessage = nil
                if generation == editGeneration { dirty = false }
                if let updated = await actions.conversation(record.state.conversationID) { present(updated) }
                persistCurrentDraft()
                observe(record.state.conversationID)
            } catch {
                guard !disposed else { return }
                unknownEffect = true
                notice.stringValue = "Send acknowledgment unavailable. Read history before an explicit retry."
            }
        }
        updateControls()
    }

    func readAuthoritativeHistory() async throws {
        try authorize()
        let generation = editGeneration
        let records = try await actions.history(context: context)
        guard !disposed, let id = conversation?.state.conversationID,
              let record = records.first(where: { $0.state.conversationID == id }) else { return }
        if let pendingMessage, record.state.messages.contains(where: { $0.id == pendingMessage }) {
            self.pendingMessage = nil
            if generation == editGeneration { dirty = false }
        }
        unknownEffect = false
        present(record)
        persistCurrentDraft()
    }

    private func observe(_ id: UUID) {
        subscription?.cancel()
        subscription = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in actions.observe(conversation: id, context: context) {
                    guard !disposed else { return }
                    if let record = await actions.conversation(id) { present(record) }
                }
            } catch { if !disposed { notice.stringValue = "Stream disconnected. Read history to resume." } }
        }
    }

    @objc func cancelExplicitly() {
        guard !disposed, let record = conversation else { return }
        operation?.cancel()
        operationEpoch += 1
        let epoch = operationEpoch
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if operationEpoch == epoch { operation = nil; updateControls() } }
            do { try authorize(); _ = try await actions.perform(.cancel(conversation: record.state.conversationID), context: context) }
            catch { notice.stringValue = "Stop acknowledgment unavailable; read history." }
        }
    }
    @objc func manageExplicitly() { if !disposed, let homepage { openHomepage?(homepage) } }
    private func updateControls() {
        sendButton.isEnabled = !disposed && operation == nil && !unknownEffect && conversation != nil && models.numberOfItems > 0 && !composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        cancelButton.isEnabled = !disposed && conversation?.status == "streaming"
    }
    func dispose() {
        disposed = true; operationEpoch += 1; subscription?.cancel(); operation?.cancel(); draftTask?.cancel()
        subscription = nil; operation = nil; draftTask = nil; updateControls()
    }
}
