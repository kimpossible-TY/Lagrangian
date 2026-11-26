import AppKit

private actor Input: NativeReaderDocumentProviding {
    let document: NativeReaderDocument
    var calls = 0
    init(_ document: NativeReaderDocument) { self.document = document }
    func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
        calls += 1; return document.rebinding(generation: context.generation)
    }
    func count() -> Int { calls }
}
@MainActor private final class RecoveryGate {
    var entries = 0
    var continuations = [UUID: CheckedContinuation<Void, Error>]()
    func enter() async throws {
        try Task.checkCancellation()
        entries += 1
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    c.resume(throwing: CancellationError())
                } else {
                    continuations[id] = c
                }
            }
        } onCancel: {
            Task { @MainActor in
                if let c = self.continuations.removeValue(forKey: id) {
                    c.resume(throwing: CancellationError())
                }
            }
        }
    }
    func fail() {
        let pending = continuations.values
        continuations.removeAll()
        for c in pending { c.resume(throwing: NativeReaderOperationFailure.unavailable) }
    }
}
private actor Effects {
    var requests = 0
    func hit() { requests += 1 }
    func count() -> Int { requests }
}
private actor FakeChatHTTP {
    let document: NativeReaderDocument
    var authorized = true
    var operations = [String]()
    let conversation = UUID()
    var gateOperation: String?
    var gateEntered = false
    var gateContinuation: CheckedContinuation<Void, Never>?
    var sentQuestions = [String]()
    var sentModels = [String]()
    var catalog = ["fixture-model"]
    func allowAlternativeModel() { catalog.append("fixture-alternative") }
    func modelsSent() -> [String] { sentModels }
    func gate(_ operation: String) { gateOperation = operation; gateEntered = false }
    func entered() -> Bool { gateEntered }
    func releaseGate() { let c = gateContinuation; gateContinuation = nil; c?.resume() }
    func questions() -> [String] { sentQuestions }
    init(_ document: NativeReaderDocument) { self.document = document }
    func deny() { authorized = false }
    func counts() -> [String] { operations }
    func send(_ request: URLRequest) async throws -> NativeReaderHTTPResponse {
        let fields = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let operation = fields["operation"] as? String ?? "document"
        operations.append(operation)
        if operation == "send", let question = fields["question"] as? String {
            sentQuestions.append(question); sentModels.append(fields["model"] as? String ?? "")
        }
        if operation == gateOperation {
            gateOperation = nil; gateEntered = true
            await withCheckedContinuation { gateContinuation = $0 }
        }
        var object: [String: Any]
        if request.url!.path.hasSuffix("native-document") {
            let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            let generation = Int(query.first { $0.name == "generation" }!.value!)!
            object = try JSONSerialization.jsonObject(with:JSONEncoder().encode(document.rebinding(generation:generation))) as! [String:Any]
        } else if request.url!.path.hasSuffix("chat/auth") {
            object = ["signedIn":authorized,"planEnabled":authorized,"models":catalog.map { ["id":$0,"label":$0] }]
        } else {
            object = fields
            let messages: [[String: Any]] = operation == "send" ? [["id":fields["messageID"]!,"role":"user","text":fields["question"]!,"status":"complete"]] : []
            object["conversations"] = [["conversation_id":conversation.uuidString.lowercased(),"version":operation == "send" ? 2 : 1,
                "sequence":operation == "send" ? 2 : 1,"thread":messages,"draft":"","status":"idle","attachment":["state":"attached"]]]
        }
        return NativeReaderHTTPResponse(status:200,headers:["content-type":"application/json","x-native-input-id":String(repeating:"a",count:64)],data:try JSONSerialization.data(withJSONObject:object))
    }
}
@main struct NativeFloatingCapsuleTests {
    @MainActor static var checks = 0
    @MainActor static func check(_ value: Bool, _ message: String) throws {
        checks += 1; if !value { throw FlowError(message: message) }
    }
    @MainActor static func until(_ condition: () -> Bool) async throws {
        for _ in 0..<1200 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        throw FlowError(message: "Condition timed out")
    }
    @MainActor static func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views($0) } }
    @MainActor static func labels(_ root: NSView) -> String { views(root).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n") }
    @MainActor static func button(_ root: NSView, _ action: String) throws -> NSButton {
        guard let result = views(root).compactMap({ $0 as? NSButton }).first(where: { $0.action.map(NSStringFromSelector) == action }) else { throw FlowError(message: "Missing " + action) }; return result
    }
    @MainActor static func click(_ button: NSButton) throws {
        try check(button.isEnabled, "Enabled native action \(button.title)")
        try check(NSApp.sendAction(button.action!, to: button.target, from: button), "Actual native target/action")
    }
    @MainActor static func save(_ value: [String: Any], _ out: URL, _ name: String) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent(name + ".json"))
    }
    @MainActor static func main() async {
        do { try await run() } catch { fputs("NA19 FAILURE: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1]), mode = CommandLine.arguments[2], out = URL(fileURLWithPath: CommandLine.arguments[3])
        let document = try NativeReaderDocument.decode(Data(contentsOf: fixture.appendingPathComponent(["long", "r19-occlusion"].contains(mode) ? "long-document.json" : "document.json")))
        #if NATIVE_CHAT_RECOVERY
        if mode.hasPrefix("chat-") { try await ChatRecoveryScenarios.run(document:document, fixture:fixture, mode:mode, out:out); return }
        #endif
        let input = Input(document), effects = Effects()
        let attachment = try NativeReaderAttachment(data: JSONSerialization.data(withJSONObject: ["url":"http://127.0.0.1:12345/", "documentID":document.identity.documentID, "service":["pid":1,"startedAt":1]]))
        let network = NativeReaderNetwork(send: { _, _ in await effects.hit(); throw URLError(.unsupportedURL) }, stream: { _ in AsyncThrowingStream { $0.finish() } })
        let actions = NativeReaderActions(transport: NativeReaderTransport(attachment: attachment, network: network))
        var resolutions = 0, targets = 0, pages = 0
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("publication.json"))) as! [String: Any]
        let pdf = try Data(contentsOf: fixture.appendingPathComponent("publication.pdf"))
        let host = NativeReaderWindowController(provider: input, target: { _ in targets += 1; return document.identity }, actions: { resolutions += 1; return actions }, originalPages: { context in
            pages += 1; var value = raw
            value["generation"] = context.generation; value["viewID"] = context.viewID.uuidString.lowercased(); value["requestID"] = context.requestID.uuidString.lowercased()
            return NativeOriginalPageDelivery(publication: try JSONDecoder().decode(NativeOriginalPagePublication.self, from: JSONSerialization.data(withJSONObject: value)), data: pdf)
        }, show: false, avoidActivation: true)
        defer { host.dispose() }
        let profile = Profile(id:"cream",name:"크림 검증",root:fixture.path,entry:"main.typ",fonts:[],packages:"",port:23620,publicURL:"",label:"owned.cream")
        _ = host.open(profile) { _ in }
        try await until { host.session.state == .reading && host.textView.renderKey != nil && host.textView.renderKey == host.textView.requestedRenderKey }
        let window = host.hostWindow.window!, root = window.contentView!
        window.setFrame(NSRect(x:0,y:0,width:980,height:900),display:false);root.layoutSubtreeIfNeeded()
        try await until { host.textView.renderKey == host.textView.requestedRenderKey }
        try await Task.sleep(nanoseconds: 100_000_000)
        if mode == "recovery" {
            let accepted = host.store.document, context = host.session.context, key = host.textView.renderKey, current = host.visibleMode, logical = host.textView.logicalText
            let counts = [await input.count(), targets, pages]
            let snapshot = NativeReaderRecoverySnapshot(document: document, assets: [:], restoration: .initial, drafts: [])
            try snapshot.validate()
            let gate = RecoveryGate()
            let task = Task { try await host.session.restore(snapshot, matching: document.identity, prepare: { _, _ in
                try await gate.enter(); throw NativeReaderOperationFailure.unavailable
            }) }
            try await until { gate.entries >= 1 }
            root.layoutSubtreeIfNeeded(); try await Task.sleep(nanoseconds: 50_000_000)
            let loadingLabels = labels(root), loadingOK = loadingLabels.contains("복원 준비 중") && !loadingLabels.contains("오프라인 복원본에서는")
            try check(host.session.hasPendingRecovery && host.session.hasRecoveryCopy && host.session.state == .loading, "Actual pending recovery state")
            gate.fail(); _ = try? await task.value
            try await until { host.session.failure != nil }
            let failureLabels = labels(root)
            let failureOK = failureLabels.contains("복원하지 못했습니다") && failureLabels.contains("이전 읽기 결과") && !failureLabels.contains("‘새로고침’을 누르세요")
            let currentKey = host.textView.renderKey
            let sameKeyContent = currentKey?.identity == key?.identity && currentKey?.documentGeneration == key?.documentGeneration && currentKey?.viewID == key?.viewID && currentKey?.width == key?.width && currentKey?.appearance == key?.appearance
            let unchanged = host.store.document == accepted && host.session.context == context && host.visibleMode == current && sameKeyContent && host.textView.logicalText == logical
            let liveCalls = [await input.count(), targets, pages]
            let denied = (try? host.session.authorize(context!)) == nil
            let refresh = try button(root,"refreshDocument"), modeButton = try button(root,"pageMode")
            try save(["loadingLabels":loadingLabels,"failureLabels":failureLabels,"loadingExpected":loadingOK,"failureExpected":failureOK,
                "samePublicationAndContext":unchanged,"sourceDenied":denied,"liveBefore":counts,"liveAfter":liveCalls,
                "modeDisabled":!modeButton.isEnabled,"refreshDisabled":!refresh.isEnabled,"visibleWindows":NSApp.windows.filter(\.isVisible).count],out,"UI9-observations")
            try check(loadingOK, "UI9-C1 pending recovery preparation must precede generic restriction")
            try check(failureOK, "UI9-C1 recovery failure/prior result must precede generic restriction")
            try check(unchanged && denied && counts == liveCalls && !modeButton.isEnabled && !refresh.isEnabled, "Preserved content/authority/live0")
            #if !NA19_BEFORE
            let beforeRetry = gate.entries
            try click(try button(root,"retryRecovery")); try await until { gate.entries == beforeRetry + 1 }
            gate.fail(); try await until { host.session.failure != nil }
            try click(try button(root,"cancelRecovery"))
            try check(!host.session.hasPendingRecovery && host.session.isReadOnly && host.store.document == accepted, "Actual recovery cancel retains previous content and revokes pending")
            try check([await input.count(),targets,pages] == counts, "Recovery commands have no live calls")
            #endif
        }
        #if !NA19_BEFORE
        if ["r19-account", "r19-open", "r19-model"].contains(mode) {
            let service = document.identity.serviceID.split(separator: ":")
            let attachmentData = try JSONSerialization.data(withJSONObject: ["url":"http://127.0.0.1:12345/", "documentID":document.identity.documentID,
                "service":["pid":Int64(service[1])!,"startedAt":Int64(service[2])!]])
            let http = FakeChatHTTP(document)
            await http.gate(mode == "r19-open" ? "open" : "status")
            if mode == "r19-model" { await http.allowAlternativeModel() }
            let transport = NativeReaderTransport(attachment:try NativeReaderAttachment(data:attachmentData), network:NativeReaderNetwork(
                send:{request,_ in try await http.send(request)},stream:{_ in AsyncThrowingStream { $0.finish() }}))
            let context = host.session.context!
            _ = try await transport.document(for:context)
            let owner = NativeReaderActions(transport:transport)
            let block = document.blocks.first { $0.displayText.utf16.count > 4 }!
            let selection = NativeReaderSelection(ticket:UUID(),blockID:block.id,rangeUTF16:0..<4,exact:String(block.displayText.prefix(4)))
            let chat = NativeReaderChatView(resolveActions:{owner},context:context,selection:selection,authorize:{})
            defer { chat.dispose() }
            let questionA = "Question A — 첫 명시 전송 의도"
            let questionB = mode == "r19-model" ? questionA : "Question B — 새 초안 A\u{030A}"
            if mode == "r19-model" {
                chat.presentAccount(.init(signedIn:true,planEnabled:true,homepage:nil,models:["fixture-model","fixture-alternative"]))
                chat.models.selectItem(withTitle:"fixture-model");chat.modelChanged()
            }
            chat.composer.string = questionA;chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
            try click(chat.sendButton)
            var entered = false
            for _ in 0..<1000 { if await http.entered() { entered = true;break };try await Task.sleep(nanoseconds:10_000_000) }
            try check(entered,"Actual account/open HTTP response gate reached")
            if mode == "r19-model" { chat.models.selectItem(withTitle:"fixture-alternative");chat.modelChanged() }
            else { chat.composer.string = questionB;chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer)) }
            await http.releaseGate()
            for _ in 0..<1000 {
                let sent = await http.questions()
                if chat.sendButton.isEnabled || !sent.isEmpty { break }
                try await Task.sleep(nanoseconds:10_000_000)
            }
            try await Task.sleep(nanoseconds:100_000_000)
            let automatic = await http.questions()
            try save(["gate":mode,"questionA":questionA,"questionB":questionB,"sentBeforeSecondClick":automatic,
                "composer":chat.composer.string,"sendEnabled":chat.sendButton.isEnabled,"notice":chat.notice.stringValue,
                "operations":await http.counts(),"injectedHTTP":true],out,mode+"-before-second-click")
            try check(automatic.isEmpty,"R19-1 no question may be sent after editing while initial Send waits")
            try check(chat.composer.string == questionB && chat.sendButton.isEnabled,"R19-1 current B draft retained and no endless busy")
            try click(chat.sendButton)
            for _ in 0..<1000 { if await http.questions().count == 1 { break };try await Task.sleep(nanoseconds:10_000_000) }
            let explicit = await http.questions()
            try save(["questions":explicit,"operations":await http.counts(),"questionB":questionB],out,mode+"-after-second-click")
            try check(explicit == [questionB],"R19-1 second explicit Send sends exactly current question once")
            if mode == "r19-model" { try check(await http.modelsSent() == ["fixture-alternative"],"R19-1 only second explicit Send uses newly selected model") }
        } else if mode == "r19-stale" {
            let block = host.store.document!.blocks.first { $0.displayText.utf16.count > 6 }!
            try host.textView.select(from:.init(blockID:block.id,utf16:0,affinity:.downstream),to:.init(blockID:block.id,utf16:4,affinity:.upstream))
            host.hostWindow.showSelectionActions()
            try await until { host.hostWindow.capsule.binding != nil }
            let firstTicket = host.store.selection!.ticket
            try click(host.hostWindow.capsule.buttons[.ask]!)
            let chat = host.chatView!, draft = "선택이 바뀌어도 보존할 아직 보내지 않은 질문 B"
            chat.composer.string = draft;chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
            let requestsBefore = await effects.count()
            try host.textView.select(from:.init(blockID:block.id,utf16:1,affinity:.downstream),to:.init(blockID:block.id,utf16:5,affinity:.upstream))
            try await Task.sleep(nanoseconds:150_000_000)
            host.session.acknowledge(ticket:firstTicket)
            let retained = host.chatView === chat && chat.superview != nil && !chat.isHiddenOrHasHiddenAncestor
            try save(["visibleSameComposer":retained,"draft":chat.composer.string,"expectedDraft":draft,"sendEnabled":chat.sendButton.isEnabled,
                "notice":chat.notice.stringValue,"oldTicket":firstTicket.uuidString,"newTicket":host.store.selection!.ticket.uuidString,
                "requestsBefore":requestsBefore,"requestsAfter":await effects.count()],out,"r19-stale-observations")
            try check(retained && chat.composer.string == draft,"R19-2 selection change/old ack must preserve visible unsent draft")
            try check(!chat.sendButton.isEnabled && chat.notice.stringValue.contains("선택"),"R19-2 stale intent blocks Send with explicit reason")
            let requestsAfter = await effects.count()
            try check(requestsAfter == requestsBefore,"R19-2 selection change/old ack do not send")
            _ = NSApp.sendAction(chat.sendButton.action!,to:chat.sendButton.target,from:chat.sendButton)
            try await Task.sleep(nanoseconds:50_000_000)
            try check(await effects.count() == requestsBefore,"R19-2 forced stale Send cannot dispatch")
        } else if mode == "r19-occlusion" {
            let block = host.store.document!.blocks.first!
            try host.textView.select(from:.init(blockID:block.id,utf16:0,affinity:.downstream),to:.init(blockID:block.id,utf16:4,affinity:.upstream))
            host.hostWindow.showSelectionActions()
            try await until { host.textView.renderKey == host.textView.requestedRenderKey && host.hostWindow.capsule.binding != nil }
            root.layoutSubtreeIfNeeded()
            let body = host.textView.bodyTextView, manager = body.layoutManager!, container = body.textContainer!
            let used = manager.usedRect(for:container).offsetBy(dx:body.textContainerOrigin.x,dy:body.textContainerOrigin.y).intersection(body.visibleRect)
            let usedInRoot = body.convert(used,to:root)
            let capsule = host.hostWindow.capsule, frame = capsule.convert(capsule.bounds,to:root)
            let viewport = host.textView.scrollView.contentView.convert(host.textView.scrollView.contentView.bounds,to:root)
            let selected = host.textView.visibleSelectionRects(in:root)
            let major = try button(root,"refreshDocument"), majorFrame = major.convert(major.bounds,to:root)
            try save(["capsule":NSStringFromRect(frame),"usedBody":NSStringFromRect(usedInRoot),"viewport":NSStringFromRect(viewport),
                "selectionRects":selected.map(NSStringFromRect),"intersectsBody":frame.intersects(usedInRoot),"intersectsMajorControl":frame.intersects(majorFrame),
                "separateDock":!frame.intersects(viewport),"selectionIsShort":host.store.selection!.fragments.count == 1],out,"r19-occlusion-observations")
            try check(host.store.selection!.fragments.count == 1 && !selected.isEmpty,"Actual filled viewport with only first short phrase selected")
            try check(viewport.contains(frame) && abs(frame.minY - viewport.minY - 16) < 1 && !frame.intersects(majorFrame) && !selected.contains { frame.intersects($0) },"Bottom capsule stays inside viewport and clears selection and primary controls")
            if frame.intersects(viewport) {
                let selectedHeight = window.frame.size.height
                window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: window.frame.size.width, height: selectedHeight - 80), display: false)
                host.hostWindow.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
                root.layoutSubtreeIfNeeded()
                try check(abs(window.frame.size.height - (selectedHeight - 80)) <= 0.5, "Floating capsule must preserve manual vertical shrink")
                window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: window.frame.size.width, height: selectedHeight - 40), display: false)
                host.hostWindow.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
                root.layoutSubtreeIfNeeded()
                try check(abs(window.frame.size.height - (selectedHeight - 40)) <= 0.5, "Floating capsule must preserve subsequent manual vertical resize")
            }
            window.makeFirstResponder(host.textView.bodyTextView)
            let escEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
            window.sendEvent(escEvent)
            try check(host.hostWindow.capsule.isHidden && host.store.selection != nil, "R09 Fix #3 body-focused Esc dismisses capsule via window.sendEvent without releasing selection")
        } else if mode == "home" {
            let env = AppEnvironment(variables:[:],userHome:out.appendingPathComponent("isolated-home"))
            try SettingsStore(directory: env.support).save(Settings(selectedID: profile.id, profiles: [profile]))
            let flow = FlowApp(environment:env,isolated:true,noActivate:true,showNativeWindow:false)
            flow.settings = try SettingsStore(directory: env.support).load()
            flow.buildWindow()
            flow.populate()
            defer { flow.settingsWindow?.close();flow.window.close();flow.session.dispose() }
            let root = flow.window.contentView!
            let settings = try JSONEncoder().encode(flow.settings)
            let settingsObject = try JSONSerialization.jsonObject(with: settings)
            let canonicalBefore = try JSONSerialization.data(withJSONObject: settingsObject, options: [.sortedKeys])
            try settings.write(to: out.appendingPathComponent("home-settings-before-raw.json"))
            try check(root is NativeDesignSurface && views(root).contains { $0 is NativeBrandMarkView },"Production home consumes solid cream and exact vector")
            try check(flow.controls.values.allSatisfy { $0 is NativeDesignButton && $0.target as AnyObject? === flow },"Home retains native selectors/targets in common buttons")
            try check(!flow.isSettingsPresented && flow.settingsWindow != nil,"Separated settings sheet/window starts closed")
            try check(NSApp.sendAction(#selector(FlowApp.showSettings),to:flow,from:nil),"Actual settings selector")
            try check(flow.isSettingsPresented,"Actual separated settings sheet/window opens")
            try check(flow.settingsWindow?.contentView.map { views($0).contains { $0 === flow.fields["name"] } } == true,"Settings fields live in separated settings window")
            let settingsAfter = try JSONEncoder().encode(flow.settings)
            try settingsAfter.write(to: out.appendingPathComponent("home-settings-after-raw.json"))
            let canonicalAfter = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: settingsAfter), options: [.sortedKeys])
            try save(["rawBytesEqual": settingsAfter == settings, "semanticSchemaAndTypesEqual": canonicalBefore == canonicalAfter,
                      "before": settingsObject, "after": try JSONSerialization.jsonObject(with: settingsAfter)], out, "home-settings-comparison")
            try check(canonicalBefore == canonicalAfter,"Chrome/settings navigation does not mutate settings schema, types or values")
            let rawVariants = try (0..<16).map { _ in try JSONEncoder().encode(flow.settings) }
            let canonicalVariants = try rawVariants.map { try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with:$0),options:[.sortedKeys]) }
            try save(["rawVariants":rawVariants.compactMap { String(data:$0,encoding:.utf8) },"distinctRawOrders":Set(rawVariants).count,
                "allSchemasTypesValuesEqual":canonicalVariants.allSatisfy { $0 == canonicalBefore }],out,"home-json-order-observations")
            try check(canonicalVariants.allSatisfy { $0 == canonicalBefore },"All observed raw key orders retain exact JSON types/schema/values")
            try save(["homeCreamSurface":true,"originalVector":true,"settingsPresented":flow.isSettingsPresented,"settingsUnchanged":true,"servicesCalled":0],out,"home-observations")
        } else if mode == "long" {
            let blocks = host.store.document!.blocks
            try check(blocks.count >= 36,"Independent compiler emitted 36 selected paragraphs")
            let first = blocks.first!
            try host.textView.select(from:.init(blockID:first.id,utf16:0,affinity:.downstream),to:.init(blockID:first.id,utf16:4,affinity:.upstream))
            host.hostWindow.showSelectionActions()
            try await until { host.hostWindow.capsule.binding != nil }
            let initialTicket = host.store.selection!.ticket
            window.setFrame(NSRect(x:0,y:0,width:640,height:900),display:false);root.layoutSubtreeIfNeeded()
            try await until { host.textView.renderKey == host.textView.requestedRenderKey && host.hostWindow.capsule.binding?.ticket == initialTicket }
            try check(root.bounds.contains(host.hostWindow.capsule.convert(host.hostWindow.capsule.bounds,to:root)),"Actual resize repositions/clamps current capsule")
            let clip = host.textView.scrollView.contentView
            let bottom = max(0,host.textView.bodyTextView.bounds.height - clip.bounds.height)
            try check(bottom > 0,"Real long fixture scroll extent")
            clip.scroll(to:NSPoint(x:0,y:bottom));host.textView.scrollView.reflectScrolledClipView(clip)
            try await until { host.hostWindow.capsule.isHidden }
            try check(host.store.selection?.ticket == initialTicket,"Scroll hides offscreen anchor without releasing selection")
            clip.scroll(to:.zero);host.textView.scrollView.reflectScrolledClipView(clip)
            try await until { host.hostWindow.capsule.binding?.ticket == initialTicket }

            try host.textView.select(from:.init(blockID:blocks.first!.id,utf16:0,affinity:.downstream),to:.init(blockID:blocks.last!.id,utf16:blocks.last!.displayText.utf16.count,affinity:.upstream))
            // Full selections retain their ticket while tools float at the bottom.
            host.hostWindow.showSelectionActions()
            let capsule = host.hostWindow.capsule
            try check(host.store.selection!.fragments.count > 32,"Actual native over-limit selection retained")
            try check(!capsule.buttons[.copy]!.isHidden && capsule.buttons[.copy]!.isEnabled,"Over-limit exposes ordinary copy")
            for unsupported in [NativeFloatingCapsule.Action.source, .highlight, .ask, .editor] {
                try check(capsule.buttons[unsupported]!.isHidden && !capsule.buttons[unsupported]!.isEnabled,"Over-limit hides and disables unsupported \(unsupported.rawValue)")
            }
            try check(capsule.reason.stringValue.contains("32") && capsule.buttons[.ask]!.toolTip!.contains("32"),"Independent over-limit reason")
            let before = await effects.count()
            _ = NSApp.sendAction(capsule.buttons[.ask]!.action!,to:capsule.buttons[.ask]!.target,from:capsule.buttons[.ask]!)
            let after = await effects.count()
            try check(host.chatView == nil && after == before,"Forced disabled over-limit Ask cannot dispatch")
            try save(["selectedBlocks":host.store.selection!.fragments.count,"requests":await effects.count(),"retained":true],out,"long-observations")
        } else if mode == "send" {
            let service = document.identity.serviceID.split(separator:":")
            let data = try JSONSerialization.data(withJSONObject:["url":"http://127.0.0.1:12345/","documentID":document.identity.documentID,"service":["pid":Int64(service[1])!,"startedAt":Int64(service[2])!]])
            for denied in [false,true] {
                let http = FakeChatHTTP(document)
                if denied { await http.deny() }
                let network = NativeReaderNetwork(send:{request,_ in try await http.send(request)},stream:{_ in AsyncThrowingStream { $0.finish() }})
                let transport = NativeReaderTransport(attachment:try NativeReaderAttachment(data:data),network:network)
                let context = host.session.context!
                _ = try await transport.document(for:context)
                let actions = NativeReaderActions(transport:transport)
                let block = document.blocks.first { $0.displayText.utf16.count > 4 }!
                let selection = NativeReaderSelection(ticket:UUID(),blockID:block.id,rangeUTF16:0..<4,exact:String(block.displayText.prefix(4)))
                try selection.validate(in:document)
                var resolved = 0
                let chat = NativeReaderChatView(resolveActions:{resolved += 1;return actions},context:context,selection:selection,authorize:{})
                defer { chat.dispose() }
                chat.composer.string = "질문하기 means a question, never a saved automatic Send"
                chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
                chat.modelChanged()
                try await Task.sleep(nanoseconds:350_000_000)
                try check(await http.counts() == ["document"] && resolved == 0,"Actual local composer/edit/model has zero pre-Send owner/network calls")
                try click(chat.sendButton)
                try await until { denied ? chat.notice.stringValue.contains("전송하지 않았습니다") : chat.answer.string.contains("질문하기 means") }
                // Give the established owner task its completion turn; never wait for a live provider.
                try await Task.sleep(nanoseconds:100_000_000)
                let operations = await http.counts()
                try check(operations.filter { $0 == "send" }.count == (denied ? 0 : 1),"Only explicit Send can invoke existing send owner; permission denial sends0")
                try check(operations.filter { $0 == "open" }.count == (denied ? 0 : 1),"Conversation creation occurs only after explicit Send and allowed account")
                try save(["denied":denied,"operations":operations,"injectedHTTP":true,"actualProvider":false],out,denied ? "send-denied" : "send-accepted")
            }
        } else if mode == "capsule" {
            let block = host.store.document!.blocks.first { $0.displayText.utf16.count > 4 }!
            let position = NativeReaderTextPosition(blockID:block.id,utf16:0,affinity:.downstream)
            let end = NativeReaderTextPosition(blockID:block.id,utf16:4,affinity:.upstream)
            let body = host.textView.bodyTextView.attributedString(), identity = host.store.document!.identity
            try host.textView.select(from:position,to:end)
            try await until { host.hostWindow.capsule.binding != nil }
            let capsule = host.hostWindow.capsule, ticket = host.store.selection!.ticket
            try check(capsule.binding?.ticket == ticket && capsule.binding?.context == host.session.context, "Actual selection/context binding")
            try check(!capsule.isHidden && capsule.footnote.isHidden, "Reflow capsule visible without PDF footnote")
            for action in NativeFloatingCapsule.Action.allCases {
                let button = capsule.buttons[action]!
                try check(button.isHidden == !button.isEnabled, "Reflow capsule hides unsupported action \(action.rawValue)")
            }
            try check(!capsule.buttons[.copy]!.isHidden && !capsule.buttons[.source]!.isHidden && !capsule.buttons[.ask]!.isHidden, "Reflow capsule exposes available actions")
            try check(!host.textView.visibleSelectionRects(in:root).isEmpty, "Actual renderer geometry seam")
            var copies = [String](); host.copyText = { copies.append($0); return true }
            try click(capsule.buttons[.copy]!)
            try check(copies == [host.textView.plainSelectedText!] && host.store.selection?.ticket == ticket, "Copy callback with retained selection; no general clipboard")
            let before = await effects.count(), resolutionBefore = resolutions
            try click(capsule.buttons[.ask]!)
            try check(host.chatView != nil && host.store.selection?.ticket == ticket, "Ask opens actual local composer and retains selected context")
            let chat = host.chatView!
            chat.composer.string = "이 선택에 대한 질문 A\u{030A} — explain this passage"
            chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
            try await Task.sleep(nanoseconds:400_000_000)
            try check(await effects.count() == before && resolutions == resolutionBefore, "Ask/edit/model/draft before Send have zero requests")
            try check(chat.sendButton.isEnabled, "Actual local explicit Send available")
            try click(chat.sendButton)
            try await until { resolutions > resolutionBefore }
            try check(host.store.selection?.ticket == ticket, "Explicit Send retains selection even on owner preflight refusal")
            _ = chat.textView(chat.composer, doCommandBy:#selector(NSResponder.cancelOperation(_:)))
            try check(host.chatView == nil && host.store.selection?.ticket == ticket && window.firstResponder === host.textView.bodyTextView, "Escape dismisses composer, restores original body focus, keeps selection")
            let showActions = try button(root,"showSelectionActions")
            try check(showActions.isEnabled, "Keyboard showSelectionActions remains enabled for retained selection")
            try click(showActions);try check(!capsule.isHidden && capsule.binding?.ticket == ticket,"Keyboard control reopens dismissed capsule")
            let old = capsule.binding!
            capsule.dismissExplicitly();try check(capsule.isHidden && host.store.selection?.ticket == ticket,"Dismiss differs from selection release")
            try host.textView.select(from: .init(blockID:block.id,utf16:1,affinity:.downstream),to:.init(blockID:block.id,utf16:5,affinity:.upstream))
            try await until { capsule.binding != nil && capsule.binding != old }
            let newer = host.store.selection!.ticket
            capsule.onDismiss?(old); host.session.acknowledge(ticket:ticket)
            try check(capsule.binding?.ticket == newer && host.store.selection?.ticket == newer,"Late old dismiss/ack cannot close newer selection")
            try check(host.store.document?.identity == identity && host.textView.bodyTextView.attributedString().isEqual(to:body),"Chrome preserves exact attributed body and identity")
            try save(["requestsBeforeSend":before,"requestsAfter":await effects.count(),"retainedSelection":true,"sameBody":true,"nativeGUI":false],out,"capsule-observations")
        } else if mode == "restrictions" {
            try click(try button(root,"pageMode")); try await until { host.visibleMode == .originalPages && host.originalPageView.isPreparedForPaint }
            let findField = views(root).compactMap { $0 as? NSSearchField }.first!
            findField.stringValue = "Search needle"
            try check(NSApp.sendAction(findField.action!, to: findField.target, from: findField), "Actual PDF search target/action")
            try await until { host.hostWindow.capsule.binding != nil && !host.hostWindow.capsule.isHidden }
            let capsule = host.hostWindow.capsule
            let pdfViewport = host.originalPageView.enclosingScrollView!.contentView.convert(host.originalPageView.enclosingScrollView!.contentView.bounds, to: root)
            let capsuleRect = capsule.convert(capsule.bounds, to: root)
            try check(pdfViewport.contains(capsuleRect) && abs(capsuleRect.minY - pdfViewport.minY - 16) < 1, "PDF search-hit capsule floats at viewport bottom")
            try check(!capsule.buttons[.copy]!.isHidden && capsule.buttons[.copy]!.isEnabled && !capsule.closeButton.isHidden, "PDF search-hit capsule exposes copy and close")
            try check(capsule.buttons[.source]!.isHidden && !capsule.buttons[.source]!.isEnabled && capsule.buttons[.highlight]!.isHidden && !capsule.buttons[.highlight]!.isEnabled && capsule.buttons[.ask]!.isHidden && !capsule.buttons[.ask]!.isEnabled && capsule.buttons[.editor]!.isHidden && !capsule.buttons[.editor]!.isEnabled && capsule.releaseSelectionButton.isHidden,"PDF only copy/search/navigation and hides 4 unsupported buttons")
            try check(capsule.footnote.stringValue == "원본 PDF · 복사·검색만 지원" && !capsule.footnote.isHidden, "Live PDF capsule shows online footer note")
            capsule.present(.init(context: host.session.context!, ticket: UUID(), originalPDF: true, offlineOriginalPDF: true), unavailable: [.source: "x", .highlight: "x", .ask: "x", .editor: "x"], summary: "오프라인 PDF 선택")
            try check(capsule.footnote.stringValue == "오프라인 PDF · 복사·검색만 지원" && !capsule.footnote.isHidden, "Offline PDF capsule shows offline footer note")
            try check(views(root).compactMap({ $0 as? NSButton }).filter({ !$0.isHiddenOrHasHiddenAncestor && $0.title.contains("복사") }).count == 1, "No duplicate copy button alongside capsule")
            host.originalPageView.releaseSelection();try click(try button(root,"reflowMode"));try await until{host.visibleMode == .nativeReflow}
            let snapshot = NativeReaderRecoverySnapshot(document:document,assets:[:],restoration:.initial,drafts:[])
            try await host.restoreRecovery(snapshot)
            let block = host.store.document!.blocks.first { $0.displayText.utf16.count > 4 }!
            try host.textView.select(from:.init(blockID:block.id,utf16:0,affinity:.downstream),to:.init(blockID:block.id,utf16:4,affinity:.upstream))
            try await until { capsule.binding != nil }
            try check(!capsule.buttons[.copy]!.isHidden && capsule.buttons[.copy]!.isEnabled && capsule.buttons[.ask]!.isHidden && !capsule.buttons[.ask]!.isEnabled && capsule.footnote.isHidden,"Recovered selection cannot acquire source/chat authority and hides unsupported actions")
            for width: CGFloat in [320,640,980] { for size: CGFloat in [13,32] {
                window.setFrame(NSRect(x:0,y:0,width:width,height:1100),display:false)
                for control in views(capsule).compactMap({$0 as? NSControl}) { control.font = .systemFont(ofSize:size) }
                capsule.reason.stringValue = "긴 한국어 선택 작업과 명시 전송 전 대기 상태 — A long English explanation of selection actions"
                host.hostWindow.placeCapsule(viewport:NSRect(x:16,y:16,width:width-32,height:400),avoiding:[NSRect(x:20,y:180,width:100,height:24)])
                root.layoutSubtreeIfNeeded();capsule.layoutSubtreeIfNeeded()
                for control in (Array(capsule.buttons.values) + [capsule.closeButton]) where !control.isHidden {
                    try check(control.frame.height >= 32 && control.frame.width <= capsule.bounds.width,"32pt/narrow native hit targets")
                }
            } }
            let viewport = NSRect(x:0,y:0,width:320,height:220), selected = NSRect(x:0,y:0,width:320,height:220)
            try check(NativeFloatingCapsule.placement(size:NSSize(width:300,height:150),viewport:viewport,avoiding:[selected]) == nil,"Oversized capsule cannot fit in viewport")
            try save(["pdfAndRecoveryRestricted":true,"layoutWidths":[320,640,980],"fontSizes":[13,32],"pdfBytesPreserved":true],out,"restrictions-observations")
        }
        #endif
        try check(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "No visible/key/main window or activation")
        print("\(mode): \(checks) assertions passed; offscreen native component only")
    }
}
