import AppKit

private actor RecoveryHTTP {
    var document: NativeReaderDocument
    let id = UUID()
    var requests = [[String: String]]()
    var providerMessages = Set<String>()
    var messages = [[String: Any]]()
    var factoryResolutions = 0
    func factoryResolved() { factoryResolutions += 1 }
    func factoryCount() -> Int { factoryResolutions }
    var version = 1
    var streaming = false
    var interrupted = false
    var cancelWaiting = false
    var cancelGate: CheckedContinuation<Void, Never>?
    var gateNextCancel = false
    var gateAppliedCancel = false
    var rangeUpdates = false
    var lastRange: String?
    func gateCancel() { gateNextCancel = true }
    func gateCancelAfterApply() { gateAppliedCancel = true }
    func enableRangeUpdates() { rangeUpdates = true }
    func enteredCancel() -> Bool { cancelWaiting }
    func releaseCancel() { cancelGate?.resume();cancelGate=nil;cancelWaiting=false }
    var separatePassages = false
    let secondID = UUID()
    var activeID: UUID?
    struct Slot {
        var version: Int; var messages: [[String: Any]]; var pending: [String: Any]?
        var streaming: Bool; var interrupted: Bool; var loseNext: Bool
    }
    var slots = [UUID: Slot]()
    func separate(_ value: Bool) { separatePassages = value }
    func switchTo(_ next: UUID) {
        if let activeID { slots[activeID] = Slot(version: version, messages: messages, pending: pending, streaming: streaming, interrupted: interrupted, loseNext: loseNext) }
        let slot = slots[next] ?? Slot(version: 1, messages: [], pending: nil, streaming: false, interrupted: false, loseNext: false)
        version = slot.version; messages = slot.messages; pending = slot.pending
        streaming = slot.streaming; interrupted = slot.interrupted; loseNext = slot.loseNext; activeID = next
    }
    var loseNext = true
    var acceptedLost = false
    var pending: [String: Any]?
    init(_ document: NativeReaderDocument) { self.document = document }
    func identity() -> NativeDocumentIdentity { document.identity }
    func configure(streaming: Bool) { self.streaming = streaming; loseNext = !streaming }
    func confirmLost() {
        if let pending, !messages.contains(where: { $0["id"] as? String == pending["id"] as? String }) {
            messages.append(pending); version += 1
        }
    }
    func advance() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as! [String: Any]
        var identity = object["identity"] as! [String: Any]; identity["revision"] = String(repeating: "b", count: 64)
        object["identity"] = identity
        document = try NativeReaderDocument.decode(JSONSerialization.data(withJSONObject: object))
    }
    func records() -> [[String: String]] { requests }
    func providerCount() -> Int { providerMessages.count }
    func send(_ request: URLRequest) async throws -> NativeReaderHTTPResponse {
        let fields = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let operation = fields["operation"] as? String ?? "document"
        requests.append(fields.reduce(into: ["path": request.url!.path, "operation": operation]) { result, item in
            if let string = item.value as? String { result[item.key] = string }
        })
        if let selection = fields["selection"] as? [String: Any], let ticket = selection["ticket"] as? String {
            requests[requests.count - 1]["selectionTicket"] = ticket
            if rangeUpdates {
                let range = String(data: try JSONSerialization.data(withJSONObject: selection["fragments"]!, options: [.sortedKeys]), encoding: .utf8)!
                if let lastRange, lastRange != range { version += 1 }
                lastRange = range
            }
        }
        var object: [String: Any]
        if request.url!.path.hasSuffix("native-document") {
            let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            let generation = Int(query.first { $0.name == "generation" }!.value!)!
            object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.rebinding(generation:generation))) as! [String:Any]
        } else if request.url!.path.hasSuffix("chat/auth") {
            object = ["signedIn":true,"planEnabled":true,"models":[["id":"model-M","label":"model-M"],["id":"model-N2","label":"model-N2"]]]
        } else {
            if separatePassages {
                var selectedID = activeID ?? id
                if operation == "open", let selection = fields["selection"] as? [String: Any],
                   let fragment = (selection["fragments"] as? [[String: Any]])?.first {
                    selectedID = fragment["blockID"] as? String == document.blocks.first(where: { $0.displayText.utf16.count > 8 })?.id ? id : secondID
                } else if let text = fields["conversationID"] as? String, let requested = UUID(uuidString: text) { selectedID = requested }
                if activeID == nil { activeID = id }
                if selectedID != activeID { switchTo(selectedID) }
            }
            if operation == "send" {
                providerMessages.insert(fields["messageID"] as! String)
                let message: [String: Any] = ["id":fields["messageID"]!,"role":"user","text":fields["question"]!,"status":"complete"]
                if loseNext { loseNext = false; pending = message; throw URLError(.networkConnectionLost) }
                if !messages.contains(where: { $0["id"] as? String == message["id"] as? String }) { messages.append(message) }
                version += 1
            }
            if operation == "cancel" {
                guard fields["version"] as? Int == version else { throw URLError(.badServerResponse) }
                if gateNextCancel { gateNextCancel=false;cancelWaiting=true;await withCheckedContinuation { cancelGate=$0 } }
                streaming = false; interrupted = true; version += 1
                if gateAppliedCancel { gateAppliedCancel=false;cancelWaiting=true;await withCheckedContinuation { cancelGate=$0 } }
            }
            object = fields
            object["conversations"] = [["conversation_id":(separatePassages ? (activeID ?? id) : id).uuidString.lowercased(),"version":version,"sequence":version,
                "thread":messages,"draft":"server draft must not replace N2","status":streaming ? "streaming" : interrupted ? "interrupted" : "idle","attachment":["state":"attached"]]]
        }
        return NativeReaderHTTPResponse(status:200,headers:["content-type":"application/json","x-native-input-id":String(repeating:"a",count:64)],data:try JSONSerialization.data(withJSONObject:object))
    }
}

@MainActor enum ChatRecoveryScenarios {
    static let m = "M — 원 질문 A\u{030A}"
    static let n2 = "N2 — 최신 한글 A\u{030A} / Å 🧪"
    static var checks = 0
    static func check(_ value: Bool, _ reason: String) throws { checks += 1; if !value { throw FlowError(message:reason) } }
    static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<1600 { if condition() { return }; try await Task.sleep(nanoseconds:10_000_000) }
        throw FlowError(message:"chat oracle timed out")
    }
    static func click(_ button: NSButton, forced: Bool = false) throws {
        if !forced { try check(button.isEnabled,"Actual enabled target: " + button.title) }
        try check(NSApp.sendAction(button.action!,to:button.target,from:button),"Native target/action delivered")
    }
    static func text(_ chat: NativeReaderChatView, _ text: String, model: String? = nil) {
        chat.composer.string = text; chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
        if let model { chat.models.selectItem(withTitle:model); _ = NSApp.sendAction(chat.models.action!,to:chat.models.target,from:chat.models) }
    }
    static func equal(_ a: String?, _ b: String) -> Bool { a.map { Array($0.unicodeScalars) == Array(b.unicodeScalars) } == true }
    static func save(_ values: [String: Any], _ out: URL, _ name: String) throws {
        try JSONSerialization.data(withJSONObject:values,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent(name+".json"))
    }
    private static func setup(_ document: NativeReaderDocument, _ fixture: URL, streaming: Bool, separate: Bool = false, fixtureMode: Bool = false) async throws -> (NativeReaderWindowController, RecoveryHTTP, NativeReaderActions) {
        let http = RecoveryHTTP(document); await http.configure(streaming:streaming); await http.separate(separate)
        let service = document.identity.serviceID.split(separator:":")
        let attachment = try NativeReaderAttachment(data:JSONSerialization.data(withJSONObject:["url":"http://127.0.0.1:12345/","documentID":document.identity.documentID,"service":["pid":Int64(service[1])!,"startedAt":Int64(service[2])!]]))
        let transport = NativeReaderTransport(attachment:attachment,network:NativeReaderNetwork(send:{r,_ in try await http.send(r)},stream:{_ in AsyncThrowingStream { _ in }}))
        let actions = NativeReaderActions(transport:transport)
        let host = NativeReaderWindowController(provider:transport,target:{_ in await http.identity()},actions:{await http.factoryResolved();return actions},show:false,avoidActivation:true,fixtureMode:fixtureMode)
        let profile = Profile(id:"chat-repair",name:"Chat repair",root:fixture.path,entry:"main.typ",fonts:[],packages:"",port:23621,publicURL:"",label:"owned.chat-repair")
        _ = host.open(profile) {_ in }
        try await until { host.session.state == .reading && host.textView.renderKey != nil && host.textView.renderKey == host.textView.requestedRenderKey }
        host.hostWindow.window!.setFrame(NSRect(x:0,y:0,width:980,height:1000),display:false)
        host.hostWindow.window!.contentView!.layoutSubtreeIfNeeded()
        try await until { host.textView.renderKey == host.textView.requestedRenderKey }
        return (host,http,actions)
    }
    static func select(_ host: NativeReaderWindowController, offset: Int = 0) async throws {
        let block = host.store.document!.blocks.first { $0.displayText.utf16.count > 8 }!
        try host.textView.select(from:.init(blockID:block.id,utf16:offset,affinity:.downstream),to:.init(blockID:block.id,utf16:offset+4,affinity:.upstream))
        try await Task.sleep(nanoseconds:80_000_000)
    }
    static func ask(_ host: NativeReaderWindowController) async throws -> NativeReaderChatView {
        host.hostWindow.showSelectionActions()
        try await until { host.hostWindow.capsule.binding != nil }
        try click(host.hostWindow.capsule.buttons[.ask]!)
        return host.chatView!
    }
    private static func start(_ host: NativeReaderWindowController, _ http: RecoveryHTTP, streaming: Bool) async throws -> NativeReaderChatView {
        try await select(host)
        let before = await http.records()
        let factoriesBeforeAsk = await http.factoryCount()
        let chat = try await ask(host); text(chat,m)
        try await Task.sleep(nanoseconds:350_000_000)
        try check(await http.records() == before,"Ask/edit performs no owner HTTP/account/provider effects")
        let factoryCount = await http.factoryCount(), providerCount = await http.providerCount()
        try check(factoryCount == factoriesBeforeAsk && providerCount == 0,"Initial Ask/edit has zero additional factory/provider resolution")
        print("Initial Ask/edit observed factory before=\(factoriesBeforeAsk), after=\(factoryCount), provider=\(providerCount), HTTP delta=0")
        try click(chat.sendButton)
        try await until { streaming ? chat.cancelButton.isEnabled && chat.historyButton.isEnabled : chat.notice.stringValue.contains("acknowledgment unavailable") }
        return chat
    }
    static func review(document: NativeReaderDocument, fixture: URL, mode: String, out: URL) async throws {
        let streaming = mode.hasPrefix("review-stop")
        let (host,http,_) = try await setup(document,fixture,streaming:streaming,separate:!streaming,fixtureMode:mode == "review-edit")
        defer { host.dispose() }
        if mode == "review-range" { await http.enableRangeUpdates() }
        if mode == "review-edit" {
            try await select(host)
            let chat = try await ask(host)
            let editor = host.hostWindow.window!.fieldEditor(true, for: host.hostWindow.findField) as! NativeReaderInputTextView
            var ordinary = 0
            for input in [editor,chat.composer] {
                input.standardClipboardOperation = { _ in ordinary += 1 }
                input.string = "Unicode A\u{030A} 🧪";input.setSelectedRange(NSRange(location:0,length:3))
                for name in ["cut:","copy:","paste:","pasteAsPlainText:","pasteAsRichText:"] {
                    let selector = NSSelectorFromString(name)
                    _ = NSApp.sendAction(selector,to:input,from:nil)
                    input.doCommand(by:selector)
                }
                for key in ["x","c","v"] {
                    let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:host.hostWindow.window!.windowNumber,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:0)!
                    try check(input.performKeyEquivalent(with:event),"Fixture keyboard command handled")
                }
                try check(input.string == "Unicode A\u{030A} 🧪","Rejected edit keeps actual field/composer text")
            }
            try check(ordinary == 0,"Search and multiline responder clipboard operation spy0")
            try check(await http.records().filter { $0["operation"] != "document" }.isEmpty,"Initial Ask/edit HTTP0")
            let normal = NativeReaderInputTextView();normal.standardClipboardOperation = { _ in ordinary += 1 }
            for name in ["cut:","copy:","paste:"] { normal.doCommand(by:NSSelectorFromString(name)) }
            try check(ordinary == 3,"Normal keyboard commands preserve injected operations")
            try save(["ordinaryFixtureCalls":0,"normalCalls":ordinary,"actualSearchFieldAndComposer":true],out,mode)
            return
        }
        let first = try await start(host,http,streaming:streaming)
        if mode == "review-range" {
            let original = first.recoveryDraft!.pendingMessageID!, id = first.recoveryDraft!.conversationID
            text(first,n2,model:"model-N2")
            try await select(host,offset:1)
            let a2 = try await ask(host);text(a2,n2,model:"model-N2")
            try click(a2.sendButton)
            try await until { a2.historyButton.isEnabled }
            try check(a2.recoveryDraft?.conversationID == id && a2.recoveryDraft!.version > first.recoveryDraft!.version,"Same paragraph open advances same UUID version")
            let latest = n2 + " / A2 latest"
            text(a2,latest,model:"model-N2")
            let version = a2.recoveryDraft!.version
            try await select(host)
            let before = await http.records(), factories = await http.factoryCount()
            let a1 = try await ask(host)
            let restored = equal(a1.composer.string,latest) && a1.recoveryDraft?.version == version && a1.recoveryDraft?.conversationID == id && a1.recoveryDraft?.pendingMessageID == original && a1.models.titleOfSelectedItem == "model-N2" && a1.historyButton.isEnabled
            try save(["restored":restored,"expectedVersion":version,"actualVersion":a1.recoveryDraft?.version ?? -1,"composer":a1.composer.string,"requests":await http.records()],out,mode)
            try check(restored,"A1 -> A2 -> A1 restores latest same UUID snapshot/draft/model/pending")
            let quiet = await http.records(), quietFactories = await http.factoryCount()
            try check(quiet == before && quietFactories == factories,"Same-range association Ask is HTTP/account/factory0")
            try click(a1.historyButton);try await until { a1.historyButton.isEnabled }
            try click(a1.dismissButton)
            let reopened = try await ask(host)
            text(reopened,m,model:"model-M")
            try save(["sendEnabled":reopened.sendButton.isEnabled,"refreshEnabled":reopened.historyButton.isEnabled,"pendingID":reopened.recoveryDraft?.pendingMessageID?.uuidString ?? "nil","notice":reopened.notice.stringValue],out,mode+"-reopened")
            try check(!reopened.sendButton.isEnabled && reopened.historyButton.isEnabled && reopened.recoveryDraft?.pendingMessageID == original,"Reopened matching original Send requires another successful Refresh")
            await http.confirmLost();try click(reopened.historyButton);try await until { reopened.historyButton.isEnabled && reopened.recoveryDraft?.pendingMessageID == nil }
            text(reopened,latest,model:"model-N2")
            let ready = await http.records()
            try await select(host,offset:2)
            try check(!reopened.sendButton.isEnabled,"Stale selection disables new question")
            try click(reopened.sendButton,forced:true)
            try check(await http.records() == ready,"Forced stale Send dispatch0")
            try await select(host)
            let current = try await ask(host), ticket = host.store.selection!.ticket
            try click(current.sendButton);try await until { current.historyButton.isEnabled }
            let final = await http.records(), sends = final.filter { $0["operation"] == "send" }
            try check(final.last { $0["operation"] == "open" }?["selectionTicket"] == ticket.uuidString.lowercased(),"Explicit Send reauthorizes current selection ticket through existing owner")
            try check(sends.count == 2 && sends.last?["question"] == latest && sends.last?["model"] == "model-N2","Confirmed original then explicit latest question once")
            try save(["restored":true,"UUID":id.uuidString,"pendingOriginal":original.uuidString,"currentTicket":ticket.uuidString,"requests":final],out,mode+"-complete")
            return
        }
        if streaming {
            try click(first.dismissButton)
            let requests = await http.records(), factories = await http.factoryCount()
            let current = try await ask(host)
            let quietRequests = await http.records(), quietFactories = await http.factoryCount()
            try check(quietRequests == requests && quietFactories == factories,"Streaming reentry HTTP/factory0")
            if mode == "review-stop-late" { await http.gateCancel() }
            if mode == "review-stop-duplicate" { await http.gateCancelAfterApply() }
            try click(current.cancelButton)
            if mode == "review-stop-duplicate" {
                for _ in 0..<1000 { if await http.enteredCancel() { break };try await Task.sleep(nanoseconds:1_000_000) }
                try check(await http.enteredCancel(),"First Stop applied; reply remains gated")
                let disabled = !current.cancelButton.isEnabled
                try click(current.cancelButton,forced:true)
                await Task.yield();await http.releaseCancel()
                try await until { current.historyButton.isEnabled }
                try await Task.sleep(nanoseconds:80_000_000)
                let count = await http.records().filter { $0["operation"] == "cancel" }.count
                try save(["disabledDuringStop":disabled,"cancelRequests":count,"status":current.presentationConversation?.status ?? "nil"],out,mode)
                try check(disabled && count == 1 && current.presentationConversation?.status == "interrupted" && !current.cancelButton.isEnabled,"Duplicate Stop preserves genuine first completion without Refresh")
                return
            }
            if mode == "review-stop-late" {
                for _ in 0..<1000 { if await http.enteredCancel() { break };try await Task.sleep(nanoseconds:1_000_000) }
                try check(await http.enteredCancel(),"Injected cancel response gate reached")
                host.dispose();await http.releaseCancel()
                try await Task.sleep(nanoseconds:80_000_000)
                try check(!current.cancelButton.isEnabled && current.presentationConversation?.status == "streaming","Disposed view rejects late accepted Stop presentation")
                try check(await http.records().filter { $0["operation"] == "cancel" }.count == 1,"Late response still has one explicit request")
                try save(["requests":await http.records(),"stopEnabled":current.cancelButton.isEnabled,"lateDisposedPresentationRejected":true],out,mode)
                return
            }
            try await until { current.historyButton.isEnabled }
            try check(current.presentationConversation?.status == "interrupted" && !current.cancelButton.isEnabled,"Stop immediately presents accepted interrupted without Refresh")
            try check(await http.records().filter { $0["operation"] == "cancel" }.count == 1,"One Stop request")
            try save(["requests":await http.records(),"status":current.presentationConversation?.status ?? "nil","stopEnabled":current.cancelButton.isEnabled],out,mode)
        } else {
            let original = first.recoveryDraft!.pendingMessageID
            text(first,n2,model:"model-N2")
            let a = host.store.document!.blocks.first { $0.displayText.utf16.count > 8 }!
            let b = host.store.document!.blocks.first { $0.id != a.id && $0.displayText.utf16.count > 8 }!
            try host.textView.select(from:.init(blockID:b.id,utf16:0,affinity:.downstream),to:.init(blockID:b.id,utf16:4,affinity:.upstream))
            let other = try await ask(host);text(other,"B question")
            try click(other.sendButton);try await until { other.historyButton.isEnabled }
            let bID = other.recoveryDraft!.conversationID
            text(other,"B latest 🧪",model:"model-N2")
            let before = await http.records(), factories = await http.factoryCount()
            try host.textView.select(from:.init(blockID:a.id,utf16:0,affinity:.downstream),to:.init(blockID:a.id,utf16:4,affinity:.upstream))
            let current = try await ask(host)
            try check(equal(current.composer.string,n2) && current.models.titleOfSelectedItem == "model-N2" && current.recoveryDraft?.pendingMessageID == original && current.historyButton.isEnabled,"A pending/N2/model/history survives distinct B conversation")
            let quietRequests = await http.records(), quietFactories = await http.factoryCount()
            try check(quietRequests == before && quietFactories == factories,"A association restore performs HTTP/factory0")
            try host.textView.select(from:.init(blockID:b.id,utf16:0,affinity:.downstream),to:.init(blockID:b.id,utf16:4,affinity:.upstream))
            let back = try await ask(host)
            try check(equal(back.composer.string,"B latest 🧪") && back.recoveryDraft?.conversationID == bID && back.recoveryDraft?.pendingMessageID == nil,"B draft stays separate")
            try save(["requests":await http.records(),"AOriginalPending":original!.uuidString,"BConversation":bID.uuidString,"restoredWithoutTyping":true],out,mode)
        }
    }
    private static func userResume(document: NativeReaderDocument, fixture: URL, mode: String, out: URL) async throws {
        let (host,http,_) = try await setup(document,fixture,streaming:false);defer {host.dispose()}
        let first = try await start(host,http,streaming:false)
        let original = await http.records().first { $0["operation"] == "send" }!
        text(first,n2,model:"model-N2")
        let selected = host.store.selection!.ticket
        if mode == "chat-ui-esc" {
            try check(first.textView(first.composer,doCommandBy:#selector(NSResponder.cancelOperation(_:))),"Actual ESC callback")
        } else { try click(first.dismissButton) }
        try check(host.chatView == nil && host.store.selection?.ticket == selected,"Close removes composer and retains selection")
        try check(host.hostWindow.window?.firstResponder === host.textView.bodyTextView,"Close returns original body focus")
        if mode == "chat-ui-close" { try await select(host); await http.confirmLost() }
        let requests = await http.records(), factories = await http.factoryCount()
        var resumed = try await ask(host) // No text/model setter or accepted-conversation seam.
        let draft = resumed.recoveryDraft
        let restored = equal(resumed.composer.string,n2) && resumed.models.titleOfSelectedItem == "model-N2" && draft?.pendingMessageID?.uuidString.lowercased() == original["messageID"] && equal(draft?.pendingQuestion,m) && draft?.pendingModel == "model-M"
        let afterAskRequests = await http.records(), afterAskFactories = await http.factoryCount()
        let quiet = afterAskRequests == requests && afterAskFactories == factories
        try save(["restoredWithoutRetyping":restored,"zeroInitialEffects":quiet,"composer":resumed.composer.string,"model":resumed.models.titleOfSelectedItem ?? "nil","pendingID":draft?.pendingMessageID?.uuidString ?? "nil","pendingQuestion":draft?.pendingQuestion ?? "nil","pendingModel":draft?.pendingModel ?? "nil","original":original,"requestsBefore":requests,"requestsAfter":await http.records(),"factoriesBefore":factories,"factoriesAfter":await http.factoryCount(),"bodyFocusReturned":host.hostWindow.window?.firstResponder === resumed.composer],out,mode+"-resume")
        try check(restored && quiet && !resumed.sendButton.isEnabled && resumed.historyButton.isEnabled,"Actual Ask restores N2/model/pending M without retyping or factory/HTTP effects")
        if mode == "chat-ui-close" {
            // Closing again before any explicit rebind must not promote a UI ticket to authority.
            try click(resumed.dismissButton)
            resumed = try await ask(host)
            try check(equal(resumed.composer.string,n2) && resumed.models.titleOfSelectedItem == "model-N2" && resumed.recoveryDraft?.pendingMessageID?.uuidString.lowercased() == original["messageID"],"Repeated user Close/Ask restores the same pending M without retyping")
            try check(await http.records() == requests,"Repeated Close/Ask performs no HTTP")
            try check(await http.factoryCount() == factories,"Repeated Close/Ask does not resolve factory")
        }
        let newer = "N3 — latest explicit edit A\u{030A} 🧪"
        text(resumed,newer)
        try await Task.sleep(nanoseconds:350_000_000)
        try click(resumed.sendButton,forced:true)
        try await Task.sleep(nanoseconds:50_000_000)
        let afterEditRequests = await http.records(), afterEditFactories = await http.factoryCount()
        try check(equal(resumed.composer.string,newer) && afterEditRequests == requests && afterEditFactories == factories,"N3 wins; unknown Send cannot resolve a factory or dispatch")
        try click(resumed.historyButton);try await until { resumed.historyButton.isEnabled }
        try check(equal(resumed.composer.string,newer),"Explicit history does not overwrite N3")
        if mode == "chat-ui-esc" {
            try check(!resumed.sendButton.isEnabled && resumed.recoveryDraft?.pendingMessageID != nil,"Unconfirmed M blocks a new question")
            text(resumed,m,model:"model-M");try click(resumed.sendButton);try await until { resumed.historyButton.isEnabled }
            let sends = await http.records().filter{$0["operation"]=="send"}
            let awaitProviderCount = await http.providerCount()
            try check(sends.count == 2 && sends[0]["messageID"]==sends[1]["messageID"] && sends[0]["question"]==sends[1]["question"] && sends[0]["model"]==sends[1]["model"] && awaitProviderCount==1,"Only original explicit M retry; no duplicate provider effect")
        } else {
            try check(resumed.recoveryDraft?.pendingMessageID == nil && resumed.sendButton.isEnabled,"Confirmed M permits explicit N3")
            try click(resumed.sendButton);try await until { resumed.historyButton.isEnabled }
            let sends = await http.records().filter{$0["operation"]=="send"}
            try check(sends.count == 2 && sends.last?["question"] == newer && sends.first?["messageID"] != sends.last?["messageID"],"Reselected same passage rebinds only on explicit N3 Send")
        }
        let next = "N4 — confirmed conversation local draft 🧪"
        text(resumed,next,model:"model-N2")
        try click(resumed.dismissButton)
        let beforeLocalAsk = await http.records(), beforeLocalFactories = await http.factoryCount()
        resumed = try await ask(host)
        try check(equal(resumed.composer.string,next) && resumed.models.titleOfSelectedItem == "model-N2" && resumed.recoveryDraft?.pendingMessageID == nil,"Confirmed conversation Ask restores latest local draft/model")
        text(resumed,"N5 — newer local edit 🧪")
        try await Task.sleep(nanoseconds:350_000_000)
        try check(await http.records() == beforeLocalAsk,"Reopened Ask and edit have zero HTTP effects without pending Send")
        try check(await http.factoryCount() == beforeLocalFactories,"Reopened Ask and edit do not resolve owner without pending Send")
        try await select(host,offset:2)
        text(resumed,"stale current selection question")
        let beforeStale = await http.records()
        try check(!resumed.sendButton.isEnabled && resumed.historyButton.isEnabled,"Stale Send disabled; context history remains available")
        try click(resumed.sendButton,forced:true);try await Task.sleep(nanoseconds:80_000_000)
        try check(await http.records() == beforeStale,"Forced stale Send has no HTTP effect")
        try save(["requests":await http.records(),"factories":await http.factoryCount(),"noGUI":true,"sameOriginalPendingID":original["messageID"]!],out,mode+"-result")
    }

    static func run(document: NativeReaderDocument, fixture: URL, mode: String, out: URL) async throws {
        if mode.hasPrefix("chat-ui-") { try await userResume(document:document,fixture:fixture,mode:mode,out:out) }
        else if mode == "chat-restrictions" {
            var rows = [[String: Any]](); var valid = true
            for boundary in ["offline","restored","revision","disposed"] {
                let (host,http,_) = try await setup(document,fixture,streaming:true)
                let chat = try await start(host,http,streaming:true)
                host.session.acknowledge(ticket:host.store.selection!.ticket)
                if boundary == "offline" { host.session.event(.network(false)) }
                else if boundary == "restored" { try await host.restoreRecovery(.init(document:document,assets:[:],restoration:.initial,drafts:[])) }
                else if boundary == "revision" { try await http.advance(); host.session.refresh(); try await until { host.session.state == .reading && host.store.document?.identity.revision != document.identity.revision } }
                else { host.dispose() }
                let before = await http.records(); let disabled = !chat.sendButton.isEnabled && !chat.cancelButton.isEnabled && !chat.historyButton.isEnabled
                try click(chat.cancelButton,forced:true);try await Task.sleep(nanoseconds:80_000_000)
                try click(chat.historyButton,forced:true);try await Task.sleep(nanoseconds:80_000_000)
                text(chat,"stale forced question");try click(chat.sendButton,forced:true);try await Task.sleep(nanoseconds:80_000_000)
                let unchanged = await http.records() == before
                rows.append(["boundary":boundary,"controlsDisabled":disabled,"HTTPUnchanged":unchanged,"requestsBefore":before,"requestsAfter":await http.records()]); valid = valid && disabled && unchanged
                host.dispose()
            }
            try save(["cases":rows,"injectedHTTP":true,"GUI":false],out,mode)
            try check(valid,"C2 offline/restored/revision/disposed buttons and forced actions have zero effect")
        } else {
            let streaming = mode == "chat-selection"
            let (host,http,owner) = try await setup(document,fixture,streaming:streaming);defer {host.dispose()}
            let chat = try await start(host,http,streaming:streaming)
            let context = host.session.context!
            if streaming {
                text(chat,n2,model:"model-N2")
                try await select(host,offset:1)
                let ticket = host.store.selection!.ticket
                host.session.acknowledge(ticket:ticket)
                let before = await http.records()
                let controls = chat.cancelButton.isEnabled && chat.historyButton.isEnabled && !chat.sendButton.isEnabled
                try click(chat.cancelButton);try await until { chat.historyButton.isEnabled }
                try click(chat.historyButton);try await until { chat.historyButton.isEnabled }
                try click(chat.sendButton,forced:true);try await Task.sleep(nanoseconds:80_000_000)
                let after = await http.records();let cancel = after.filter{$0["operation"]=="cancel"}.count;let history = after.filter{$0["operation"]=="list"}.count
                try save(["controlsAgree":controls,"cancelCount":cancel,"historyCount":history,"requestsBefore":before,"requestsAfter":after,"draft":chat.composer.string,"selectionCleared":host.store.selection == nil],out,mode)
                try check(controls && cancel == 1 && history == 1 && after.filter{$0["operation"]=="send"}.count == 1,"C2 selection change/clear allows exactly one Stop and history, stale Send0")
            } else {
                let sent = await http.records().first { $0["operation"] == "send" }!
                text(chat,n2,model:"model-N2")
                let id = http.id
                var current = chat
                if mode == "chat-close" {
                    try check(chat.textView(chat.composer,doCommandBy:#selector(NSResponder.cancelOperation(_:))),"ESC routed through host dismiss")
                    try check(host.chatView == nil,"ESC removes current composer")
                    try save(["acceptedPaintReady":host.acceptedPaintKey?.documentGeneration == context.generation,"renderReady":host.textView.renderKey == host.textView.requestedRenderKey],out,"chat-close-seam-precondition-"+String(checks))
                    try await until { host.acceptedPaintKey?.documentGeneration == context.generation && host.acceptedPaintKey == host.textView.renderKey }
                    current = try host.presentChat(await owner.conversation(id)!,actions:owner,context:context)
                    current.presentAccount(.init(signedIn:true,planEnabled:true,homepage:nil,models:["model-M","model-N2"]))
                } else {
                    try await select(host,offset:1) // Different passage: exercise explicit lazy adoption.
                    current = try await ask(host)
                    // A newly authored local draft is newer than any stored recovery text.
                    text(current,n2)
                    try click(current.sendButton)
                    try await until { current.historyButton.isEnabled }
                }
                let recovered = current.recoveryDraft
                let original = recovered?.pendingMessageID?.uuidString.lowercased() == sent["messageID"] && equal(recovered?.pendingQuestion,m) && recovered?.pendingModel == "model-M"
                let latest = equal(recovered?.text,n2) && recovered?.model == "model-N2"
                let beforeRead = await http.records()
                try save(["pendingRecovered":original,"latestDraftAndModel":latest,"draft":recovered?.text ?? "nil","model":recovered?.model ?? "nil","pendingID":recovered?.pendingMessageID?.uuidString ?? "nil","originalSend":sent,"requests":beforeRead],out,mode+"-adopt")
                // Continue the independent oracle even if baseline adoption is broken.
                if mode == "chat-confirmed" || mode == "chat-close" { await http.confirmLost() }
                try click(current.historyButton);try await until { current.historyButton.isEnabled }
                let afterRead = await http.records();let noImplicit = afterRead.filter{$0["operation"]=="send"}.count == 1
                if mode == "chat-unconfirmed", original && latest {
                    try check(!current.sendButton.isEnabled,"Missing history blocks new N2 Send")
                    text(current,m,model:"model-M");try click(current.sendButton)
                    try await until { current.historyButton.isEnabled }
                    let retry = await http.records().filter{$0["operation"]=="send"}
                    try check(retry.count == 2 && retry[0]["messageID"]==retry[1]["messageID"] && retry[1]["question"]==retry[0]["question"] && retry[1]["model"]==retry[0]["model"],"Only explicit original UUID/question/model retry reaches HTTP")
                    try check(await http.providerCount() == 1,"Original UUID retry never duplicates provider dispatch")
                    text(current,n2,model:"model-N2")
                }
                let confirmed = mode != "chat-unconfirmed"
                let preserved = equal(current.composer.string,n2) && current.models.titleOfSelectedItem == "model-N2"
                if confirmed && original && latest {
                    try check(current.recoveryDraft?.pendingMessageID == nil && current.sendButton.isEnabled,"Confirmed history permits next explicit N2")
                    try click(current.dismissButton)
                    try save(["acceptedPaintReady":host.acceptedPaintKey?.documentGeneration == context.generation,"renderReady":host.textView.renderKey == host.textView.requestedRenderKey],out,"chat-close-seam-precondition-"+String(checks))
                    try await until { host.acceptedPaintKey?.documentGeneration == context.generation && host.acceptedPaintKey == host.textView.renderKey }
                    current = try host.presentChat(await owner.conversation(id)!,actions:owner,context:context)
                    current.presentAccount(.init(signedIn:true,planEnabled:true,homepage:nil,models:["model-M","model-N2"]))
                    try check(equal(current.composer.string,n2) && current.recoveryDraft?.pendingMessageID == nil,"Reentry preserves N2 and never resurrects resolved M")
                    try click(current.sendButton);try await until { current.historyButton.isEnabled }
                    try check(await http.records().filter{$0["operation"]=="send"}.count == 2,"New N2 sends exactly once after explicit click")
                    try check(await http.providerCount() == 2,"Two distinct explicit messages, no duplicate provider dispatch")
                    if mode == "chat-close" {
                        text(current,n2,model:"model-N2")
                        let stored = current.recoveryDraft!
                        host.session.acknowledge(ticket:host.store.selection!.ticket)
                        try await host.restoreRecovery(.init(document:host.store.document!,assets:[:],restoration:.initial,drafts:[stored]))
                        host.session.event(.network(true))
                        try await until { host.session.state == .reading && !host.session.isReadOnly && host.textView.renderKey == host.textView.requestedRenderKey }
                        try await select(host)
                        let local = try await ask(host), newer = "N3 — 새 편집 A\u{030A} must win over old recovery"
                        text(local,newer)
                        let beforeAdoption = await http.records().filter{$0["operation"]=="send"}.count
                        try click(local.sendButton);try await until { local.historyButton.isEnabled }
                        try save(["actual":local.composer.string,"expected":newer,"model":local.models.titleOfSelectedItem ?? "nil","requests":await http.records()],out,"chat-recovered-draft")
                        try check(equal(local.composer.string,newer) && local.models.titleOfSelectedItem == "model-N2" && local.recoveryDraft?.pendingMessageID == nil,"Recovered draft adoption preserves newer local text/model and resolved M")
                        try check(await http.records().filter{$0["operation"]=="send"}.count == beforeAdoption,"Recovery adoption itself cannot send")
                    }
                }
                try save(["pendingRecovered":original,"latestDraftAndModel":latest,"noImplicitSend":noImplicit,"newerDraftPreserved":preserved,"requests":await http.records(),"conversation":id.uuidString],out,mode+"-result")
                try check(original && latest && noImplicit && preserved,"C1 actual host adoption/close preserves N2/model and original unknown Send; refresh never sends")
            }
        }
        try check(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy{!$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow},"No GUI/key/main/activation")
        print("\(mode): \(checks) independent host assertions; injected HTTP only")
    }
}
