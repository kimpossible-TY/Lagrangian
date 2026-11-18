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
        var object: [String: Any]
        if request.url!.path.hasSuffix("native-document") {
            let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            let generation = Int(query.first { $0.name == "generation" }!.value!)!
            object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.rebinding(generation:generation))) as! [String:Any]
        } else if request.url!.path.hasSuffix("chat/auth") {
            object = ["signedIn":true,"planEnabled":true,"models":[["id":"model-M","label":"model-M"],["id":"model-N2","label":"model-N2"]]]
        } else {
            if operation == "send" {
                providerMessages.insert(fields["messageID"] as! String)
                let message: [String: Any] = ["id":fields["messageID"]!,"role":"user","text":fields["question"]!,"status":"complete"]
                if loseNext { loseNext = false; pending = message; throw URLError(.networkConnectionLost) }
                if !messages.contains(where: { $0["id"] as? String == message["id"] as? String }) { messages.append(message) }
                version += 1
            }
            if operation == "cancel" { streaming = false; version += 1 }
            object = fields
            object["conversations"] = [["conversation_id":id.uuidString.lowercased(),"version":version,"sequence":version,
                "thread":messages,"draft":"server draft must not replace N2","status":streaming ? "streaming" : "idle","attachment":["state":"attached"]]]
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
    private static func setup(_ document: NativeReaderDocument, _ fixture: URL, streaming: Bool) async throws -> (NativeReaderWindowController, RecoveryHTTP, NativeReaderActions) {
        let http = RecoveryHTTP(document); await http.configure(streaming:streaming)
        let service = document.identity.serviceID.split(separator:":")
        let attachment = try NativeReaderAttachment(data:JSONSerialization.data(withJSONObject:["url":"http://127.0.0.1:12345/","documentID":document.identity.documentID,"service":["pid":Int64(service[1])!,"startedAt":Int64(service[2])!]]))
        let transport = NativeReaderTransport(attachment:attachment,network:NativeReaderNetwork(send:{r,_ in try await http.send(r)},stream:{_ in AsyncThrowingStream { _ in }}))
        let actions = NativeReaderActions(transport:transport)
        let host = NativeReaderWindowController(provider:transport,target:{_ in await http.identity()},actions:{await http.factoryResolved();return actions},show:false,avoidActivation:true)
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
