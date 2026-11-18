import AppKit
import Foundation
import UniformTypeIdentifiers

// Injected OS operations. These counters never access the general pasteboard,
// external applications, panels, or a real engine/service.
enum FixtureEffects {
  static var external = 0, reveals = 0, panels = 0, abouts = 0, general = 0, engines = 0, descriptors = 0
  static var windowDisplays = [String]()
  static func display(_ kind: String) { windowDisplays.append(kind) }
  static var blockEngine = true
  static var children = [[String:Any]]()
  static func observeChild(_ path: String, _ environment: [String:String]?) {
    let keys = ["HOME","CFFIXED_USER_HOME","TMPDIR","XDG_CACHE_HOME","FLOW_READER_DATA_DIR","PATH"]
    children.append(["executable":path,"explicitEnvironment":environment != nil,"environment":(environment ?? [:]).filter { keys.contains($0.key) }])
  }
  @discardableResult static func open(_ url: URL) -> Bool { external += 1; return true }
  static func descriptor(_ url: URL) throws -> NativeReaderManagedEditor { descriptors += 1; return try NativeReaderManagedEditor.consentedDescriptor(url) }
  static func reveal(_ urls: [URL]) { reveals += 1 }
  static func about(options: [NSApplication.AboutPanelOptionKey: Any]) { abouts += 1 }
  final class Panel {
    var canChooseDirectories = false, allowsMultipleSelection = false
    var message = "", title = ""
    var allowedContentTypes = [UTType]()
    var url: URL? = nil
    func runModal() -> NSApplication.ModalResponse { FixtureEffects.panels += 1; return .cancel }
    func begin(completionHandler: (NSApplication.ModalResponse) -> Void) { FixtureEffects.panels += 1; completionHandler(.cancel) }
  }
}

@MainActor @main struct NativeFixtureIsolationTests {
  static func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views($0) } }
  static var trace: URL?
  static var diagnostic: () -> [String: Any] = { [:] }
  static func mark(_ stage: String) {
    var row = diagnostic();row["stage"] = stage
    if let trace, let data = try? JSONSerialization.data(withJSONObject:row,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:trace) }
  }
  static func wait(line: UInt = #line, _ ready: () -> Bool) async throws {
    mark("wait-\(line)")
    for _ in 0..<1000 { if ready() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
    mark("timeout-\(line)")
    throw FlowError(message: "fixture host readiness timeout at \(line): \(diagnostic())")
  }
  static func main() async {
    do { try await run() } catch { FileHandle.standardError.write(Data((String(describing:error)+"\n").utf8)); exit(1) }
  }
  static func run() async throws {
    let a = Array(CommandLine.arguments.dropFirst()), out = URL(fileURLWithPath:a[0]), exe = URL(fileURLWithPath:a[1])
    trace = out.appendingPathComponent("progress.json")
    let ordinary = URL(fileURLWithPath:a[2]), arguments = Array(a.dropFirst(3))
    let config = try FlowRuntimeConfiguration(arguments:arguments,variables:ProcessInfo.processInfo.environment,userHome:ordinary,executable:exe)
    let env = config.environment, dev = env.userHome.deletingLastPathComponent()
    let ioOnly = config.fixture!.lastPathComponent == "io-native.json"
    var checks = [String: Bool](), observations = [String: Any]()
    func expect(_ yes: Bool, _ name: String) { checks[name] = yes }
    expect(config.arguments.isEmpty && config.isolated && config.noActivate && config.fixture != nil,"exact three existing arguments")
    #if !FIXTURE_BASELINE
    try env.prepareFixtureDirectories()
    #endif
    let profile = Profile(id:"fixture",name:"Fixture",root:config.fixture!.deletingLastPathComponent().appendingPathComponent("source").path,entry:"main.typ",fonts:[],packages:"",port:23818,publicURL:"",label:"owned.fixture.integration")
    let store = SettingsStore(directory:env.support)
    let beforeCanary = try Data(contentsOf:ordinary.appendingPathComponent("canary.txt"))
    let runtimeRoot = URL(fileURLWithPath:a[0]).deletingLastPathComponent().appendingPathComponent("runtime-input")
    #if !FIXTURE_BASELINE
    let delivered = FileManager.default.isExecutableFile(atPath:exe.path) ? try env.nativeMathBundle() : nil
    let runtime = delivered.map { NativeReaderRuntime(node:$0.node,helper:$0.helper,runtime:$0.runtime) }
      ?? NativeReaderRuntime(node:runtimeRoot.appendingPathComponent("node/bin/node"),helper:runtimeRoot.appendingPathComponent("helper.mjs"),runtime:runtimeRoot)
    #else
    let runtime = NativeReaderRuntime(node:runtimeRoot.appendingPathComponent("node/bin/node"),helper:runtimeRoot.appendingPathComponent("helper.mjs"),runtime:runtimeRoot)
    #endif
    _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
    let timeline = NativeStartupTimeline(root:dev)
    let flow = FlowApp(environment:env,isolated:config.isolated,fixture:config.fixture,noActivate:config.noActivate,startupTimeline:timeline,nativeRuntime:ioOnly ? nil : runtime,nativeManager:ordinary.appendingPathComponent("must-not-execute-manager"),showNativeWindow:false)
    diagnostic = { [weak flow] in ["snapshot":String(describing:flow?.snapshot?.phase),"message":flow?.snapshot?.message ?? "nil","detail":flow?.snapshot?.detail ?? "nil","nativeDiagnostic":flow?.nativeWindow?.diagnostic ?? "nil","windowDisplays":FixtureEffects.windowDisplays,"visibleWindows":NSApp.windows.filter{$0.isVisible}.count] }
    defer { diagnostic = { [:] };flow.session.dispose();flow.nativeWindow?.dispose();flow.offlineWindow?.dispose();flow.offlineWindow?.hostWindow.window?.close();flow.window?.close() }
    flow.settings = try store.load();flow.buildWindow();flow.populate()
    try await wait { flow.snapshot?.phase == .stopped }
    expect(flow.managedResolver == nil,"fixture has no manager resolver even with direct explicit manager")
    let blocked: [Selector] = [NSSelectorFromString("connectEditor"),#selector(FlowApp.disconnectEditor),#selector(FlowApp.addProject),#selector(FlowApp.openLogs),#selector(FlowApp.revealSettings),#selector(FlowApp.guide),#selector(FlowApp.openExternalPreview),#selector(FlowApp.about)]
    expect(blocked.allSatisfy{ !flow.enabled($0) },"external controls disabled")
    for selector in blocked { _ = NSApp.sendAction(selector,to:flow,from:nil) }
    flow.saveProfile(readAfterSaving:true,external:true)
    var consent = 0, directRejected = false
    do { _ = try await flow.connectEditor(descriptor:ordinary.appendingPathComponent("invalid-descriptor.json"),for:profile,consent:{consent += 1;return true}) }
    catch { if let failure = error as? NativeReaderOperationFailure { if case .unavailable = failure { directRejected = true } } }
    expect(directRejected && consent == 0 && FixtureEffects.descriptors == 0,"direct editor call rejected before descriptor/consent")
    expect(FixtureEffects.external == 0 && FixtureEffects.reveals == 0 && FixtureEffects.panels == 0 && FixtureEffects.abouts == 0,"forced external targets have zero OS effects")
    let board = NSPasteboard(name:FlowApp.isolatedCopyBoard(home:env.userHome))
    mark("before-private-board")
    board.clearContents()
    _ = NSApp.sendAction(#selector(FlowApp.copyURL),to:flow,from:nil)
    expect(board.string(forType:.string)==profile.url && FixtureEffects.general==0,"home address copy uses private board")
    // Observe real same-owner profile save and recovery persistence under dev root.
    flow.fields["name"]!.stringValue = "N2 최신 Unicode A\u{030A} 🧪"
    _ = NSApp.sendAction(#selector(FlowApp.save),to:flow,from:nil)
    try await wait { !flow.mutating }
    expect(try store.load().profiles.first?.name == "N2 최신 Unicode A\u{030A} 🧪","profile write stays in dev root")
    let beforeFailedSave = try Data(contentsOf:store.file)
    let permissions = try FileManager.default.attributesOfItem(atPath:store.file.path)[.posixPermissions] as? NSNumber
    expect(permissions?.intValue == 0o600,"settings file remains private 0600")
    try FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:store.directory.path)
    var failedSave = false
    do { try flow.store.save(Settings(selectedID:profile.id,profiles:[profile])) } catch { failedSave = true }
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:store.directory.path)
    let afterFailedSave = try Data(contentsOf:store.file)
    expect(failedSave && afterFailedSave == beforeFailedSave,"failed replacement preserves previous settings bytes")
    expect(try FileManager.default.contentsOfDirectory(atPath:store.directory.path).allSatisfy{ !$0.hasPrefix(".profiles-") },"private settings temporary files are cleaned")
    flow.fields["name"]!.stringValue = flow.active!.name
    _ = NSApp.sendAction(#selector(FlowApp.openPreview),to:flow,from:nil)
    try await wait { flow.nativeWindow?.store.document != nil && flow.nativeWindow?.textView.renderKey == flow.nativeWindow?.textView.requestedRenderKey }
    let host = flow.nativeWindow!, doc = host.store.document!
    let block = doc.blocks.first{$0.displayText.utf16.count>5}!
    try host.textView.select(from:.init(blockID:block.id,utf16:0,affinity:.downstream),to:.init(blockID:block.id,utf16:4,affinity:.upstream))
    let selected = host.textView.plainSelectedText!
    let generalBeforeBodyCopy = FixtureEffects.general
    _ = NSApp.sendAction(#selector(NSText.copy(_:)),to:host.textView.bodyTextView,from:nil)
    expect(board.string(forType:.string) == selected && FixtureEffects.general == generalBeforeBodyCopy,"actual body Copy uses same private board")
    let assets = try Dictionary(uniqueKeysWithValues:doc.assets.map{ asset in (asset.id,try Data(contentsOf:config.fixture!.deletingLastPathComponent().appendingPathComponent("assets/"+asset.id))) })
    let recovery = NativeReaderRecoveryStore(root:env.nativeRecoveryRoot(for:profile))
    let draft = NativeReaderRecoveredDraft(conversationID:UUID(),version:0,text:"unsent N2 A\u{030A} 🧪",pendingMessageID:UUID(),model:"model2",pendingQuestion:"M",pendingModel:"model1")
    try await recovery.save(.init(document:doc,assets:assets,restoration:.initial,drafts:[draft]))
    let recovered = try await recovery.load(identity:doc.identity)
    expect(recovered.drafts.first?.text == draft.text && recovered.drafts.first?.pendingMessageID == draft.pendingMessageID && recovered.drafts.first?.model == draft.model,"draft and unknown intent persist in dev recovery")
    expect(flow.enabled(#selector(FlowApp.openOffline)),"local offline library remains enabled")
    _ = NSApp.sendAction(#selector(FlowApp.openOffline),to:flow,from:nil)
    try await wait { flow.offlineWindow?.hostWindow.savedDocuments.numberOfItems == 1 }
    let offline = flow.offlineWindow!
    let offlineViews = views(offline.hostWindow.window!.contentView!)
    let openSaved = offlineViews.compactMap { $0 as? NSButton }.first { $0.action == NSSelectorFromString("openSavedExplicitly") }!
    try await wait { openSaved.isEnabled }
    _ = NSApp.sendAction(openSaved.action!,to:openSaved.target,from:openSaved)
    try await wait { offlineViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains(draft.text) } }
    expect(offline.store.document?.identity==doc.identity && offlineViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains(draft.text) },"actual local offline target loads dev-root snapshot and recovered draft")
    flow.offlineWindow?.dispose();flow.offlineWindow?.hostWindow.window?.close()
    try FileManager.default.createDirectory(at:env.logRoot,withIntermediateDirectories:true)
    try Data("fixture log\n".utf8).write(to:env.logRoot.appendingPathComponent("fixture.log"))
    timeline.record("fixture-isolation-observed")
    try await wait { FileManager.default.fileExists(atPath:dev.appendingPathComponent("startup-timeline.jsonl").path) }
    var runtimeCommands = [String]()
    if !ioOnly {
    let worker = NativeMathWorker(node:runtime.node,helper:runtime.helper,runtime:runtime.runtime) { record in
      // Actual child argv/exit already fixed by the worker; no inherited environment is logged.
      let data = try! JSONEncoder().encode(record)
      try! data.write(to:out.appendingPathComponent("math-child.json"))
    }
    let object = NativeObjectContext(identity:doc.identity,snapshotGeneration:host.session.context!.generation,generation:1,width:320,fontSize:18,fontName:"system",theme:.light,mode:.reflow,pageHeight:800)
    let math = try await worker.prepare(tex:"\\frac{1}{2}",display:false,context:object)
    expect(!math.math.normalizedText.isEmpty && math.layout.whole.svg.contains("<svg") && math.image.width>0,"actual Swift math semantic SVG and image")
    runtimeCommands.append(math.math.normalizedText)
    }
    #if FIXTURE_BASELINE
    let childText = try CommandRunner().run("/usr/bin/env",[])
    #else
    let childText = try CommandRunner(environment:env.fixtureChildEnvironment).run("/usr/bin/env",[])
    #endif
    let allowed = ["HOME","CFFIXED_USER_HOME","TMPDIR","XDG_CACHE_HOME","FLOW_READER_DATA_DIR","PATH"]
    var child = [String: String]()
    for line in childText.split(separator:"\n") { let fields=line.split(separator:"=",maxSplits:1).map(String.init);if fields.count==2 && allowed.contains(fields[0]) { child[fields[0]]=fields[1] } }
    expect(child["HOME"]==env.userHome.path && child["CFFIXED_USER_HOME"]==env.userHome.path && child["TMPDIR"]==dev.appendingPathComponent("tmp").path+"/" && child["XDG_CACHE_HOME"]==dev.appendingPathComponent("cache").path && child["FLOW_READER_DATA_DIR"]==dev.appendingPathComponent("reader-data").path,"real child has explicit dedicated environment")
    observations["childEnvironment"] = child
    observations["verificationChildren"] = FixtureEffects.children
    #if !FIXTURE_BASELINE
    if delivered != nil {
      let seals = FixtureEffects.children.filter { ($0["executable"] as? String)=="/usr/bin/codesign" }
      expect(seals.count==1 && seals.allSatisfy { ($0["environment"] as? [String:String])==env.fixtureChildEnvironment?.filter { allowed.contains($0.key) } },"actual bundled seal child has dedicated environment before execution")
      var refusedManager = false
      do { _ = try env.nativeReaderBundle() } catch { refusedManager = true }
      expect(refusedManager && flow.managedResolver == nil,"actual bundled fixture creates no manager binding")
    }
    #endif
    // Parser and direct CLI entry must both refuse execution; the injected engine cannot execute.
    var parserRejected = true
    for unsafe in [["--serve","fixture"],["--control","start","fixture"],["--login","on"],["--background"],["--native-reader-manager",ordinary.appendingPathComponent("manager").path]] {
      do { _ = try FlowRuntimeConfiguration(arguments:arguments+unsafe,variables:ProcessInfo.processInfo.environment,userHome:ordinary,executable:exe);parserRejected=false } catch {}
    }
    expect(parserRejected,"fixture parser rejects external execution and explicit manager")
    let escape = out.appendingPathComponent("symlink-dev")
    try FileManager.default.createDirectory(at:escape,withIntermediateDirectories:true)
    try FileManager.default.createSymbolicLink(at:escape.appendingPathComponent("home"),withDestinationURL:ordinary)
    var rejectedHome = false
    do { var bad = arguments;bad[1] = escape.path;_ = try FlowRuntimeConfiguration(arguments:bad,variables:ProcessInfo.processInfo.environment,userHome:ordinary,executable:exe) } catch { rejectedHome = true }
    expect(rejectedHome,"existing dev-home symlink refusal preserved")
    #if !FIXTURE_BASELINE
    let childRoot = out.appendingPathComponent("child-symlink-dev")
    try FileManager.default.createDirectory(at:childRoot,withIntermediateDirectories:true)
    try FileManager.default.createSymbolicLink(at:childRoot.appendingPathComponent("cache"),withDestinationURL:ordinary)
    var rejectedChild = false
    do { try AppEnvironment(variables:[:],userHome:childRoot.appendingPathComponent("home"),executable:exe,fixtureRoot:childRoot).prepareFixtureDirectories() } catch { rejectedChild = true }
    expect(rejectedChild,"dedicated child cache symlink refusal")
    #endif
    do { try FlowCLI(environment:env).run(["--serve","fixture"]) } catch {}
    expect(FixtureEffects.engines == 0,"direct fixture CLI serve does not dispatch engine")
    let normalEnv = AppEnvironment(variables:[:],userHome:out.appendingPathComponent("normal-home"),executable:exe)
    let previousExternal = FixtureEffects.external, previousReveal = FixtureEffects.reveals
    let normal = FlowApp(environment:normalEnv,nativeManager:ordinary.appendingPathComponent("fake-manager"),showNativeWindow:false)
    normal.settings=Settings(selectedID:profile.id,profiles:[profile]);normal.openLogs();normal.revealSettings();normal.session.dispose()
    expect(normal.managedResolver != nil && FixtureEffects.external-previousExternal == 1 && FixtureEffects.reveals-previousReveal == 1,"normal manager and external owners remain reachable through injected operations")
    expect(try Data(contentsOf:ordinary.appendingPathComponent("canary.txt"))==beforeCanary && !FileManager.default.fileExists(atPath:ordinary.appendingPathComponent("Library/Application Support/Lagrangian/reader/control.lock").path),"virtual ordinary home remains unchanged; manager lock absent")
    expect(FixtureEffects.windowDisplays.isEmpty,"all display operations blocked by facade and offscreen owner")
    observations["windowDisplayFacadeCalls"] = FixtureEffects.windowDisplays
    mark("complete")
    expect(NSApp.activationPolicy() == .prohibited && NSApp.windows.allSatisfy{ !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow },"prohibited with visible key main zero")
    observations["checks"]=checks;observations["ordinaryHome"]=ordinary.path;observations["devRoot"]=dev.path;observations["privateBoard"]=FlowApp.isolatedCopyBoard(home:env.userHome).rawValue;observations["mathSemantic"]=runtimeCommands;observations["ioOnlyParentSandbox"]=ioOnly;observations["generalBoardCalls"]=FixtureEffects.general;observations["fixtureArguments"]=arguments
    try JSONSerialization.data(withJSONObject:observations,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("observations.json"))
    try require(checks.values.allSatisfy{$0},"fixture oracle failed: "+checks.filter{!$0.value}.keys.sorted().joined(separator:", "))
    print("fixture isolation: \(checks.count) independent expectations passed; actual offscreen target/action, no GUI")
  }
}
