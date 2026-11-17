"""Real frozen-component host composition. Offline fixture input and scratch runtime are explicit test inputs."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
DEV = Path('/Volumes/devSSD/Developer/lagrangian-native-20261117')
spec = importlib.util.spec_from_file_location('prep_package', ROOT / 'scripts/flow-app.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
SWIFT = r'''
import AppKit
import Foundation
import ObjectiveC

@MainActor var assertions = 0
@MainActor func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
  assertions += 1
  if !value() { throw FlowError(message: message) }
}
@MainActor func until(_ condition: () -> Bool) async throws {
  for _ in 0..<3000 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
  throw FlowError(message: "host wait timed out")
}
actor MutableFixture: NativeReaderDocumentProviding {
  let fixture: NativeReaderFixtureProvider
  var delay = false
  init(_ url: URL) { fixture = .init(url: url) }
  func setDelay(_ value: Bool) { delay = value }
  func document(for context: NativeReaderRequestContext) async throws -> NativeReaderDocument {
    if delay { try? await Task.sleep(nanoseconds: 300_000_000) }
    return try await fixture.document(for: context)
  }
}
@MainActor private enum FindPasteboardIsolation {
    static let findName = "dev.lagrangian.NA06.find." + UUID().uuidString
    static let generalName = "dev.lagrangian.NA06.general." + UUID().uuidString
    static var findCalls = 0
    static func install() {
        let named = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("pasteboardWithName:"))!
        let substitute = class_getClassMethod(NSPasteboard.self, #selector(NSPasteboard.na06_namedPasteboard(_:)))!
        method_exchangeImplementations(named, substitute)
        let general = class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!
        let isolated = class_getClassMethod(NSPasteboard.self, #selector(NSPasteboard.na06_generalPasteboard))!
        method_exchangeImplementations(general, isolated)
    }
}
extension NSPasteboard {
    @MainActor @objc dynamic class func na06_namedPasteboard(_ name: NSString) -> NSPasteboard {
        var isolated = name as String
        if isolated == NSPasteboard.Name.find.rawValue {
            FindPasteboardIsolation.findCalls += 1
            isolated = FindPasteboardIsolation.findName
        } else if isolated == NSPasteboard.Name.general.rawValue {
            isolated = FindPasteboardIsolation.generalName
        }
        // After exchange this calls the original public factory.
        return na06_namedPasteboard(isolated as NSString)
    }
    @MainActor @objc dynamic class func na06_generalPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(FindPasteboardIsolation.generalName))
    }
}


final class WorkerRecords: @unchecked Sendable {
  let lock = NSLock()
  var entries = [NativeMathExecution]()
  func append(_ item: NativeMathExecution) { lock.lock(); entries.append(item); lock.unlock() }
  func save(_ url: URL) throws { lock.lock(); defer { lock.unlock() }; try JSONEncoder().encode(entries).write(to: url) }
}
@main struct HostIntegration {
  @MainActor static func main() async {
    do { try await run() } catch { fputs("HOST FAILURE: \(error)\n", stderr); exit(1) }
  }
  @MainActor static func run() async throws {
    FindPasteboardIsolation.install()
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let out = URL(fileURLWithPath: CommandLine.arguments[2])
    let records = WorkerRecords()
    let runtime = NativeReaderRuntime(node: URL(fileURLWithPath: CommandLine.arguments[3]),
      helper: URL(fileURLWithPath: CommandLine.arguments[4]), runtime: URL(fileURLWithPath: CommandLine.arguments[5]), record: { records.append($0) })
    let sample = try NativeReaderDocument.decode(Data(contentsOf: fixtureURL))
    try check(sample.blocks.flatMap(\.orderedNodes).contains { $0.kind == .math }, "real math missing")
    try check(sample.blocks.flatMap(\.orderedNodes).contains { $0.kind == .table }, "real table missing")
    try check(!sample.assets.isEmpty, "real figure assets missing")
    let provider = MutableFixture(fixtureURL)
    let loader = NativeReaderFixtureProvider(url: fixtureURL)
    let host = NativeReaderWindowController(provider: provider, target: { _ in try await loader.load().identity },
      assets: { document, _ in
        try await Task.detached {
          var bytes = [String: Data]()
          for asset in document.assets { bytes[asset.id] = try Data(contentsOf: fixtureURL.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(asset.id)) }
          return bytes
        }.value
      }, runtime: runtime, show: false, avoidActivation: true)
    defer { host.dispose() }
    var events = [String]()
    let profile = Profile(id: "fixture", name: "actual fixture", root: out.path, entry: "main.typ", fonts: [], packages: "", port: 24650, publicURL: "", label: "test.host")
    let cancel = host.open(profile) { event in
      switch event { case .accepted: events.append("accepted"); case .windowInitialized: events.append("initialized"); case .painted: events.append("painted"); case .failed(let reason): events.append("failed:"+reason) }
    }
    try await until { host.session.state != .loading }
    try check(host.session.failure == nil, "prepare/adopt failed: \(host.diagnostic ?? host.session.failure ?? "unknown")")
    try check(host.store === host.session.store && host.store === host.textView.store, "multiple stores")
    try check(host.store.document == host.textView.textMap?.document, "store published before native body")
    try check(host.acceptedPaintKey == host.textView.renderKey && host.paintedKey == nil, "adopt/layout pretended paint")
    try check(events == ["accepted", "initialized"], "unexpected pre-paint stages: \(events)")
    try check(host.textView.bodyTextView.textStorage?.containsAttachments == true, "object adapter did not compose native attachments")
    let body = host.textView.bodyTextView
    let rect = body.bounds
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw FlowError(message: "bitmap") }
    body.displayIgnoringOpacity(rect, in: graphics)
    try check(host.paintedKey == host.acceptedPaintKey && events.last == "painted", "draw did not acknowledge exact key")
    try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("native-host.png"))
    var otherProfile = profile
    otherProfile.entry = "other.typ"
    let profileGeneration = host.store.generation
    var otherRejected = false
    _ = host.open(otherProfile) { if case .failed = $0 { otherRejected = true } }
    try check(otherRejected && host.store.generation == profileGeneration, "different profile reused bound target/store")
    let oldKey = host.textView.renderKey!
    var appearance = host.textView.textAppearance
    appearance.fontSize = 18; appearance.theme = .dark
    try host.textView.setAppearance(appearance)
    try await until { host.textView.renderKey?.appearance == appearance && host.acceptedPaintKey == host.textView.renderKey }
    try check(host.textView.renderKey != oldKey && (host.paintedKey == nil || host.paintedKey == host.textView.renderKey), "appearance used an obsolete paint/cache key")
    try check(host.store === host.textView.store && host.store.document == host.textView.textMap?.document, "reflow changed store/adoption")
    // Candidate's layout changes during async preparation must revoke its old key.
    await provider.setDelay(true)
    host.refresh()
    host.textView.setFrameSize(NSSize(width: 720, height: 600))
    try await until { host.session.state == .reading && host.textView.renderKey?.width == host.textView.requestedRenderKey?.width }
    await provider.setDelay(false)
    let initial = host.store.document!
    let oldText = body.string
    let block = initial.blocks.first { !$0.displayText.isEmpty && $0.kind == .paragraph }!
    let end = block.graphemeBoundariesUTF16[1]
    let exact = String(block.displayText[Range(NSRange(location: 0, length: end), in: block.displayText)!])
    let selection = NativeReaderSelection(ticket: UUID(), blockID: block.id, rangeUTF16: 0..<end, exact: exact)
    try host.session.hold(selection)
    host.refresh()
    try await until { host.session.state != .loading }
    try check(host.store.document == initial && body.string == oldText, "held replacement published")
    try check(host.store.selection?.ticket == selection.ticket, "network adoption released selection")
    host.textView.releaseSelection(ticket: selection.ticket)
    try await until { host.session.state == .reading && host.store.document?.generation != initial.generation }
    try check(host.store.selection == nil && host.store.document == host.textView.textMap?.document, "explicit release did not commit candidate")
    let accepted = host.store.document!
    let render = host.textView.renderKey
    host.runtime = nil
    host.refresh()
    try await until { host.session.failure != nil }
    try check(host.diagnostic?.contains("math-runtime-not-delivered") == true, "missing runtime hidden")
    try check(host.store.document == accepted && host.textView.renderKey == render && body.string == oldText, "missing runtime destroyed prior accepted view")
    host.runtime = runtime
    await provider.setDelay(true)
    host.refresh(); cancel()
    try await Task.sleep(nanoseconds: 500_000_000)
    let count = events.count
    body.displayIgnoringOpacity(rect, in: graphics)
    try check(events.count == count && host.paintedKey == nil && host.store.document == accepted, "cancelled candidate/draw acknowledged")
    // Start the real helper through an explicitly test-only delayed wrapper;
    // cancelling/closing while it runs must revoke adoption and draw receipts.
    await provider.setDelay(false)
    let delayed = out.appendingPathComponent("slow-helper.mjs")
    let importURL = URL(fileURLWithPath: CommandLine.arguments[4]).absoluteString
    try ("await new Promise(resolve => setTimeout(resolve, 600)); await import(" + String(data: try JSONEncoder().encode(importURL), encoding: .utf8)! + ");\n").write(to: delayed, atomically: true, encoding: .utf8)
    host.runtime = NativeReaderRuntime(node: runtime.node, helper: delayed, runtime: runtime.runtime, record: { records.append($0) })
    _ = host.open(profile) { _ in events.append("after-close") }
    try await until { host.preparingKey != nil }
    try await Task.sleep(nanoseconds: 80_000_000)
    host.hostWindow.window?.close()
    let afterClose = events.count
    try await Task.sleep(nanoseconds: 800_000_000)
    body.displayIgnoringOpacity(rect, in: graphics)
    try check(events.count == afterClose && host.store.document == accepted, "closed window adopted late helper response")
    try records.save(out.appendingPathComponent("worker-executions.json"))
    let windows = NSApp.windows
    try check(windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "headless test ordered/activated window")
    let result: [String: Any] = ["assertions": assertions, "actualFixture": true, "sharedStore": true,
      "nativeObjectTextPaint": true, "heldReplacement": true, "missingRuntimePreserved": true,
      "cancelCloseNoAck": true, "visibleWindows": 0, "GUIAcceptance": false,
      "runtimeScope": "explicit scratch test runtime only; no delivery/TeX/F04 claim", "events": events]
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("host-results.json"))
    print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
  }
}
'''


class HostComposition(unittest.TestCase):
    def test_actual_native_host(self):
        output = Path(os.environ['NA06_PREP_OUTPUT']) / ('host-' + str(time.time_ns()))
        output.mkdir()
        fixture = Path(os.environ.get('FLOW_NATIVE_FIXTURE', str(DEV / 'test-output/contract/final-contract/native.json')))
        runtime = Path(os.environ.get('FLOW_TEST_NATIVE_RUNTIME', str(DEV / 'dependencies/mathjax413')))
        node = Path(os.environ.get('FLOW_TEST_NODE', '/opt/homebrew/bin/node'))
        helper = ROOT / 'tools/flow-reader/native/math_layout.mjs'
        for path in (fixture, runtime / 'node_modules/@mathjax/src/package.json', node, helper):
            self.assertTrue(path.is_file(), 'missing explicit host prerequisite: ' + str(path))
        swift = output / 'HostIntegration.swift'
        swift.write_text(SWIFT)
        binary = output / 'HostIntegration'
        commands = []
        def command(argv):
            started = time.monotonic()
            result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, timeout=180)
            commands.append(dict(argv=list(map(str, argv)), exit=result.returncode, elapsed=time.monotonic()-started, stdout=result.stdout, stderr=result.stderr))
            (output / 'commands.json').write_text(json.dumps(commands, indent=2))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        command(['/usr/bin/swiftc', *package.swift_flags(), *[p for p in package.swift_sources() if p.name != 'main.swift'], swift, '-o', binary])
        command([binary, fixture, output, node, helper, runtime])
        (output / 'input-binding.json').write_text(json.dumps(dict(fixture=str(fixture), fixtureSHA256=package.digest(fixture),
          sourceSHA256={str(p.relative_to(ROOT)):package.digest(p) for p in package.swift_sources()},
          helperSHA256=package.digest(helper), nodeSHA256=package.digest(node), runtime=str(runtime),
          scope='reused actual compiler semantic snapshot, freshly prepared/adopted/painted offscreen; not GUI or production delivery'), indent=2))

# Review reproductions run the same real view/session/host used above. The
# placement variants retain an actual compiler image and use the review's
# independently specified accepted-HTML display:block / inline inputs.
CORE_SWIFT = SWIFT.split('@main struct HostIntegration')[0] + r'''
@MainActor func coreWait(_ condition: () -> Bool) async throws {
  for _ in 0..<400 { if condition() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
  throw FlowError(message: "review regression condition did not become true")
}
@MainActor func drawCore(_ view: NativeReaderTextView, to url: URL) throws {
  let body = view.bodyTextView, rect = view.bodyTextView.bounds
  guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw FlowError(message: "bitmap") }
  body.displayIgnoringOpacity(rect, in: graphics)
  try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
@main struct CoreReviewMain {
  @MainActor static func main() async {
    do {
      FindPasteboardIsolation.install(); _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
      let mode = CommandLine.arguments[1], fixture = URL(fileURLWithPath: CommandLine.arguments[2]), out = URL(fileURLWithPath: CommandLine.arguments[3])
      let runtime = NativeReaderRuntime(node: URL(fileURLWithPath: CommandLine.arguments[4]), helper: URL(fileURLWithPath: CommandLine.arguments[5]), runtime: URL(fileURLWithPath: CommandLine.arguments[6]))
      let loader = NativeReaderFixtureProvider(url: fixture)
      let host = NativeReaderWindowController(provider: loader, target: { _ in try await loader.load().identity }, assets: { document, _ in
        try await Task.detached {
          var bytes = [String: Data]()
          for asset in document.assets { bytes[asset.id] = try Data(contentsOf: fixture.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(asset.id)) }
          return bytes
        }.value
      }, runtime: runtime, show: false, avoidActivation: true)
      defer { host.dispose() }
      let profile = Profile(id: "review", name: "Review", root: out.path, entry: "main.typ", fonts: [], packages: "", port: 24650, publicURL: "", label: "test.review")
      let oldCancel = host.open(profile) { _ in }
      try await coreWait { host.session.state != .loading }
      try check(host.session.failure == nil, host.diagnostic ?? "initial host failure")
      let view = host.textView, document = host.store.document!
      try drawCore(view, to: out.appendingPathComponent("before.png"))
      if mode == "F1" || mode == "F3" {
        let block = document.blocks.first { $0.kind == .paragraph && !$0.displayText.isEmpty }!
        try view.select(from: .init(blockID: block.id, utf16: 0, affinity: .upstream),
          to: .init(blockID: block.id, utf16: block.graphemeBoundariesUTF16[1], affinity: .downstream))
        let selected = host.store.selection!
        if mode == "F1" {
          host.refresh(); try await coreWait { host.session.state != .loading }
          view.setFrameSize(NSSize(width: 780, height: 620))
          var appearance = view.textAppearance; appearance.fontSize = 18; appearance.theme = .dark
          try view.setAppearance(appearance)
          _ = view.performFindAction(.showFindInterface)
          try await coreWait { view.renderKey == view.requestedRenderKey && view.textMap != nil && host.acceptedPaintKey == view.renderKey }
          try check(host.store.document == document && host.store.selection == selected && !view.accessibilityNodes.isEmpty, "F1 retained body/AX/selection lost")
          try check(view.plainSelectedText == selected.fragments.map(\.exact).joined(separator: "\n"), "F1 selection changed during reflow")
          try drawCore(view, to: out.appendingPathComponent("retained.png"))
          do { try host.session.authorize(view.context!, selection: selected.ticket); throw FlowError(message: "stale source was authorized") }
          catch NativeReaderContractError.staleGeneration {}
          view.releaseSelection(ticket: selected.ticket)
          try await coreWait { host.store.document?.generation == host.store.generation && view.renderKey == view.requestedRenderKey }
          try check(host.store.selection == nil && view.textMap?.document == host.store.document, "F1 pending candidate not committed on explicit release")
        } else {
          let oldClose = host.hostWindow.onClose
          host.hostWindow.window?.close()
          _ = host.open(profile) { _ in }
          try await coreWait { host.session.state == .reading && host.acceptedPaintKey != nil }
          let newContext = host.session.context
          oldCancel(); oldClose?()
          try await Task.sleep(nanoseconds: 100_000_000)
          try check(host.session.context == newContext && host.acceptedPaintKey != nil && host.store.selection == nil, "F3 old close/cancel killed reopened view")
          try drawCore(view, to: out.appendingPathComponent("reopened.png"))
        }

      } else if mode == "B-host" {
        let attachment = try NativeReaderAttachment(data: JSONSerialization.data(withJSONObject: ["url": "http://127.0.0.1:1/", "documentID": document.identity.documentID,
          "service": ["pid": 12, "startedAt": 34]]))
        let actions = NativeReaderActions(transport: NativeReaderTransport(attachment: attachment, network: .init(send: { _, _ in
          throw FlowError(message: "Unexpected source/account/inference during host math")
        }, stream: { _ in AsyncThrowingStream { $0.finish() } })))
        let context = host.session.context!
        let conversation = NativeReaderConversation(state: .init(context: context, conversationID: UUID(), version: 1, sequence: 1,
          messages: [.init(id: UUID(), role: .assistant, markdown: "Completed answer $\\frac{1}{2}$", complete: true)]), draft: "", status: "completed", attached: true)
        let chat = try host.presentChat(conversation, actions: actions, context: context)
        try await coreWait { chat.preparedFormulaCount == 1 || chat.mathFailure != nil }
        try check(chat.preparedFormulaCount == 1 && chat.mathFailure == nil && chat.answer.textStorage?.containsAttachments == true, "B host did not inject pinned worker/current object context")
        host.hostWindow.window?.contentView?.layoutSubtreeIfNeeded()
        let clip = chat.answer.enclosingScrollView!.contentView
        guard let bitmap = clip.bitmapImageRepForCachingDisplay(in: clip.bounds) else { throw FlowError(message: "chat bitmap") }
        clip.cacheDisplay(in: clip.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("host-chat.png"))
        let oldCount = chat.mathPreparationCount
        var appearance = view.textAppearance; appearance.theme = .dark; appearance.fontSize = 18
        try view.setAppearance(appearance)
        try await coreWait { view.renderKey == view.requestedRenderKey && chat.mathPreparationCount > oldCount && chat.preparedFormulaCount == 1 }
        try check(chat.mathFailure == nil && host.store === host.session.store && host.store === view.store, "B host reconfiguration/store binding")
        host.runtime = nil
        try view.setAppearance(.init(fontSize: 20, zoom: 1, theme: .light))
        // A missing runtime is explicit and cannot install a successful replacement.
        try await coreWait { host.diagnostic?.contains("runtime") == true || chat.mathFailure != nil }
      } else if mode == "F2" {
        let key = view.renderKey!, map = view.textMap!, context = view.context!, text = view.bodyTextView.string
        let ax = view.accessibilityNodes[0]
        let position = NativeReaderTextPosition(blockID: document.blocks[0].id, utf16: 0, affinity: .downstream)
        let geometry = try view.caretGeometry(at: position)
        view.setLogicalAccessibilityFocus(document.blocks[0].id)
        let focus = view.focusedNodeID, anchor = view.viewportAnchor()
        for badMetrics in [false, true] {
          let generation = try host.store.beginRequest()
          let identity = NativeDocumentIdentity(documentID: "failed-candidate", serviceID: document.identity.serviceID, revision: "failed-revision", scope: .fixture)
          let candidate = NativeReaderDocument(schemaVersion: document.schemaVersion, identity: identity, generation: generation,
            requiredCapabilities: document.requiredCapabilities, blocks: document.blocks, assets: document.assets, diagnostics: document.diagnostics)
          let request = NativeReaderRequestContext(requestID: UUID(), viewID: host.store.viewID, generation: generation, target: identity)
          if badMetrics { view.cachedObject = { _, k in .init(key: k, size: .init(width: CGFloat.infinity, height: 12), baseline: 0, accessibilityLabel: "invalid", draw: { _ in }) } }
          else { view.cachedObject = nil }
          var rejected = false
          do { try view.adopt(candidate, context: request) } catch { rejected = true }
          try check(rejected && view.renderKey == key && view.textMap?.document == map.document && view.context == context,
            "F2 failed B revoked painted A key/map/context")
          try check(view.bodyTextView.string == text && ax.isAccessibilityEnabled() && view.focusedNodeID == focus, "F2 failed B revoked AX/text/focus")
          try view.validateGeometry(geometry)
          try check(view.viewportAnchor()?.identity == anchor?.identity, "F2 viewport changed")
          try drawCore(view, to: out.appendingPathComponent(badMetrics ? "after-invalid.png" : "after-miss.png"))
        }
      } else if mode == "F6" {
        let body = view.bodyTextView, string = body.string as NSString
        let before = string.range(of: "before"), after = string.range(of: "after")
        let image = view.textMap!.spans.first { $0.isObject }!.presentation
        let manager = body.layoutManager!
        func lineY(_ index: Int) -> CGFloat {
          manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: index), effectiveRange: nil).minY
        }
        let ys = [lineY(before.location), lineY(image.location), lineY(after.location)]
        let blockPlacement = document.blocks.flatMap(\.orderedNodes).contains { $0.imageLayout?.placement == .block }
        let data: [String: Any] = ["block": blockPlacement, "glyphLineY": ys.map(Double.init), "presentation": body.string, "logical": view.logicalText]
        try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted]).write(to: out.appendingPathComponent("lines.json"))
        try check(blockPlacement ? ys[0] < ys[1] && ys[1] < ys[2] : ys[0] == ys[1] && ys[1] == ys[2], "F6 block/inline TextKit line boundary lost")
        body.selectAll(nil)
        let logical = document.blocks.map(\.displayText).joined(separator: "\n")
        try check(view.plainSelectedText == logical && body.accessibilitySelectedText() == logical, "F6 presentation LF leaked into logical/AX selection")
        var copied = ""; view.callbacks.copyText = { copied = $0; return true }; _ = view.copyPlainText()
        try check(copied == logical && !logical.contains("\n"), "F6 presentation LF leaked into copy")
        let first = document.blocks[0]
        try view.select(from: .init(blockID: first.id, utf16: 0, affinity: .upstream), to: .init(blockID: first.id, utf16: 6, affinity: .upstream))
        try check(view.plainSelectedText == "before", "F6 before-object logical endpoint")
        try view.select(from: .init(blockID: first.id, utf16: 6, affinity: .downstream), to: .init(blockID: first.id, utf16: 11, affinity: .downstream))
        try check(view.plainSelectedText == "after", "F6 after-object logical endpoint")
      }
      try check(NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "visible/key/main window created")
      print("review pass \(mode); assertions=\(assertions)")
    } catch { fputs("REVIEW FAILURE: \(error)\n", stderr); exit(1) }
  }
}
'''


class CoreReviewRegressions(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import base64, shutil, sys, zlib, struct, re
        cls.out = Path(os.environ['CORE_REVIEW_OUTPUT']) / ('review-' + str(time.time_ns()))
        cls.out.mkdir()
        cls.commands = []
        oracle = Path(__file__).parent / 'fixtures/core-review-regressions.expect.json'
        cls.oracle = json.loads(oracle.read_text())
        (cls.out / 'oracle.json').write_bytes(oracle.read_bytes())
        cls.node = Path(os.environ['FLOW_TEST_NODE'])
        cls.runtime = Path(os.environ['FLOW_TEST_NATIVE_RUNTIME'])
        cls.fixture = DEV / 'test-output/contract/final-contract/native.json'
        cls.helper = ROOT / 'tools/flow-reader/native/math_layout.mjs'
        cls.binary = cls.out / 'CoreReview'
        source = cls.out / 'CoreReview.swift'; source.write_text(CORE_SWIFT)
        cls.command(['/usr/bin/swiftc', *package.swift_flags(), *[p for p in package.swift_sources() if p.name != 'main.swift'], source, '-o', cls.binary])
        sys.path.insert(0, str(ROOT / 'tools/flow-reader'))
        from flow_reader.compiler.build import compile_project
        from flow_reader.compiler.project import Project
        from flow_reader.document.sections import split_document, SectionBundle
        from flow_reader.document.native_document import import_accepted_document
        fixture = cls.out / 'source'; fixture.mkdir()
        shutil.copyfile(Path(__file__).parent / 'fixtures/core-review-regressions.typ', fixture / 'main.typ')
        def chunk(kind, data): return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0'+b'\x20\x60\xc0'*2)*2)) + chunk(b'IEND', b'')
        (fixture / 'blue.png').write_bytes(png)
        compiler = shutil.which('typst'); assert compiler, 'prebuilt Typst missing'
        wrapper = cls.out / 'offline-typst'
        sandbox = '(version 1)(allow default)(deny network*)(deny file-write* (subpath '+json.dumps(str(ROOT))+'))'
        wrapper.write_text('#!'+sys.executable+'\nimport os,sys\nos.execv("/usr/bin/sandbox-exec",["sandbox-exec","-p",'+repr(sandbox)+','+repr(compiler)+']+sys.argv[1:])\n'); wrapper.chmod(0o700)
        report = compile_project(Project(fixture, Path('main.typ'), ROOT / 'tools/flow-reader/packages', compiler=str(wrapper)), cls.out / 'compiled', map_sources=False)
        (cls.out / 'compiler-report.json').write_text(json.dumps(report, default=str, indent=2))
        if report['exitCode'] != 0 or not report['contentGatePassed']: raise RuntimeError('core actual compiler fixture failed: '+str(report))
        html = (cls.out / 'compiled/document.html').read_text()
        img = re.search(r'<img\b[^>]*>', html)
        if not img: raise RuntimeError('actual compiler image missing')
        cls.placements = {}
        for placement in ('block', 'inline'):
            # Review-specified HTML fixture retains the real compiler asset. The
            # input is explicitly fixture-scoped, not server acceptance authority.
            tag = re.sub(r'\s(?:style|width|height)="[^"]*"', '', img.group())
            tag = tag.replace('<img', '<img style="display: '+placement+'; width:24pt; height:12pt"', 1)
            controlled = '<html><body><p>'+cls.oracle['proseBefore']+tag+cls.oracle['proseAfter']+'</p></body></html>'
            bundle = split_document(controlled, hashlib.sha256(controlled.encode()).hexdigest())
            value = import_accepted_document(bundle, document_id='core-'+placement, service_id='isolated', generation=1, identity_scope='fixture')
            folder = cls.out / placement; folder.mkdir(); (folder / 'assets').mkdir()
            for key, data in value.assets.items(): (folder / 'assets' / key).write_bytes(data)
            (folder / 'native.json').write_text(json.dumps(value.document, indent=2))
            (folder / 'accepted.html').write_text(controlled)
            cls.placements[placement] = folder / 'native.json'

    @classmethod
    def command(cls, argv, expect=0):
        start = time.monotonic(); result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, timeout=180)
        cls.commands.append(dict(argv=list(map(str, argv)), cwd=str(ROOT), exit=result.returncode, elapsed=time.monotonic()-start, stdout=result.stdout, stderr=result.stderr))
        (cls.out / 'commands.json').write_text(json.dumps(cls.commands, indent=2))
        if result.returncode != expect: raise AssertionError(result.stdout + result.stderr)
        return result

    def scenario(self, name, fixture=None):
        folder = self.out / (name+'-'+str(time.time_ns())); folder.mkdir()
        self.command([self.binary, name, fixture or self.fixture, folder, self.node, self.helper, self.runtime])
        if name == 'F6':
            lines = json.loads((folder / 'lines.json').read_text())
            self.assertIn(self.oracle['proseBefore'], lines['logical'])
            self.assertIn(self.oracle['proseAfter'], lines['logical'])
            ys = dict(zip(self.oracle['blockLineOrder'], lines['glyphLineY']))
            if lines['block']:
                self.assertLess(ys['before'], ys['image'])
                self.assertLess(ys['image'], ys['after'])
            elif self.oracle['inlineOneLine']:
                self.assertEqual(ys['before'], ys['image'])
                self.assertEqual(ys['image'], ys['after'])

    def test_B_host_pinned_worker_injection_and_reconfiguration(self): self.scenario('B-host')
    def test_F1_retained_reflow_while_candidate_selection_held(self): self.scenario('F1')
    def test_F2_failed_candidate_preserves_painted_A(self): self.scenario('F2')
    def test_F3_close_selected_reopen_and_late_callbacks(self): self.scenario('F3')
    def test_F6_block_image_final_TextKit_lines(self): self.scenario('F6', self.placements['block'])
    def test_F6_inline_image_final_TextKit_lines(self): self.scenario('F6', self.placements['inline'])

# Explicit inspection fixture lifecycle. Production routing/source/chat owners are
# composed here; only auth, inference and managed-process observation are fake.
GUI_ROOT = DEV / 'test-output/integration/gui-prep-v1/fixtures'
GUI_SCRIPT = Path(__file__).resolve()


def gui_root(value, *, exists=True):
    import uuid
    path = Path(value)
    if not path.is_absolute() or path == GUI_ROOT or not path.is_relative_to(GUI_ROOT):
        raise ValueError('Fixture root must be a distinct absolute directory below ' + str(GUI_ROOT))
    if '..' in path.parts or any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError('Fixture paths cannot contain symlinks')
    if exists:
        marker = json.loads((path / 'fixture.json').read_text())
        if marker['owner'] != 'lagrangian-native-gui-fixture' or str(uuid.UUID(marker['fixtureID'])) != marker['fixtureID']:
            raise ValueError('Not an owned inspection fixture')
    return path


def gui_save(path, value):
    import uuid
    if path.is_symlink():
        raise ValueError('Refusing a symlink fixture output')
    temp = path.with_name('.' + path.name + '-' + str(uuid.uuid4()))
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temp.chmod(0o600)
    os.replace(temp, path)


def gui_command(root, argv, *, timeout=120):
    started = time.monotonic()
    result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    with (root / 'commands.jsonl').open('a') as f:
        f.write(json.dumps(dict(argv=list(map(str, argv)), cwd=str(ROOT), exit=result.returncode,
            elapsed=time.monotonic()-started, stdout=result.stdout, stderr=result.stderr,
            environment={k: os.environ.get(k) for k in ['TMPDIR', 'CLANG_MODULE_CACHE_PATH', 'SWIFT_MODULECACHE_PATH']})) + '\n')
    if result.returncode:
        raise RuntimeError('Fixture command failed: ' + result.stderr[-3000:])
    return result


def gui_setup(value, compiler, package_cache):
    import shutil, struct, zlib, uuid
    root = gui_root(value, exists=False)
    if root.exists():
        raise ValueError('Preserve existing fixture; choose a new root')
    compiler = Path(compiler)
    if not compiler.is_absolute() or not compiler.is_file() or not os.access(compiler, os.X_OK):
        raise ValueError('An explicit prebuilt compiler is required')
    root.mkdir(parents=True)
    source = root / 'source'; source.mkdir()
    shutil.copyfile(GUI_SCRIPT.parent / 'fixtures/gui-native.typ', source / 'gui-native.typ')
    (source / 'shape.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="72" height="36" viewBox="0 0 72 36"><rect width="72" height="36" fill="#2060c0"/></svg>')
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0'+b'\x20\x60\xc0'*2)*2)) + chunk(b'IEND', b'')
    (source / 'pixels.png').write_bytes(png)
    package_cache = Path(package_cache)
    if not package_cache.is_absolute() or not package_cache.is_relative_to(DEV) or not package_cache.is_dir():
        raise ValueError('An explicit existing DevSSD offline package cache is required')
    cache = root / 'typst-packages'
    shutil.copytree(package_cache, cache)
    (root / 'toolchain').mkdir()
    wrapper = root / 'toolchain/offline-typst'
    wrapper.write_text('#!' + __import__('sys').executable + '\nimport subprocess,sys,os,json,time\n' +
        'os.environ["TYPST_PACKAGE_CACHE_PATH"]=' + repr(str(cache)) + '\n' +
        'args=[' + repr(str(compiler)) + ']+sys.argv[1:]\n' +
        'start=time.monotonic();r=subprocess.run(args)\n' +
        'with open(' + repr(str(root / 'compiler-commands.jsonl')) + ',"a") as f:f.write(json.dumps(dict(argv=args,exit=r.returncode,elapsed=time.monotonic()-start))+"\\n")\n' +
        'sys.exit(r.returncode)\n')
    wrapper.chmod(0o700)
    home = root / 'app-dev/home'
    board = 'io.github.kimpossible-ty.lagrangian.dev.copy.' + hashlib.sha256(str(home).encode()).hexdigest()
    manager = root / 'fixture-manager'
    manager.write_text('#!' + __import__('sys').executable + '\nimport os,sys\nos.execv(sys.executable,[sys.executable,"-B",' + repr(str(GUI_SCRIPT)) +
        ',"gui-fixture","attach","--fixture-root",' + repr(str(root)) + ']+sys.argv[1:])\n')
    manager.chmod(0o700)
    args = ['--dev-root', str(root / 'app-dev'), '--dev-no-activate', '--native-reader-manager', str(manager)]
    marker = dict(owner='lagrangian-native-gui-fixture', fixtureID=str(uuid.uuid4()), root=str(root), source=str(source),
        entry='gui-native.typ', compiler=str(compiler), compilerSHA256=package.digest(compiler), compilerVersion=gui_command(root,[compiler,'--version']).stdout.strip(),
        script=str(GUI_SCRIPT), scriptSHA256=package.digest(GUI_SCRIPT), sourceRevision=gui_command(root,['git','rev-parse','HEAD']).stdout.strip(), compilerWrapper=str(wrapper),
        sourceHashes={p.name:package.digest(p) for p in source.iterdir()}, packageCacheInput=str(package_cache),
        packageCacheHashes={str(p.relative_to(cache)):package.digest(p) for p in cache.rglob('*') if p.is_file()}, manager=str(manager), appArguments=args,
        privatePasteboard=board, running=False, originalPDF='unverified until accepted C merge and final app stage',
        fake=['auth status/catalog', 'inference provider', 'manager attachment/PID observation'],
        real=['prebuilt Typst compiler', 'ReaderState accepted publication', 'root and registered /d/gui/ HTTP routes', 'native document/assets/source/chat APIs'],
        guiRun=False, paintRun=False, standaloneAppVerified=False,
        copyScope='Reader body Copy/Source only; do not use composer/answer system Cut/Copy/Paste or external links in GUI inspection')
    gui_save(root / 'fixture.json', marker)
    return marker


def gui_request(url, *, fields=None):
    from http.client import HTTPConnection
    from urllib.parse import urlsplit
    parsed = urlsplit(url)
    if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1':
        raise ValueError('Only owned loopback fixture requests')
    conn = HTTPConnection(parsed.hostname, parsed.port, timeout=30)
    body = json.dumps(fields) if fields is not None else None
    try:
        conn.request('POST' if fields is not None else 'GET', parsed.path + ('?' + parsed.query if parsed.query else ''), body,
            {'Host': parsed.netloc, 'Origin': 'http://' + parsed.netloc, 'Content-Type': 'application/json'})
        response = conn.getresponse()
        return response.status, response.read(), dict(response.getheaders())
    finally:
        conn.close()


def gui_serve(value, seconds):
    import signal, socket, sys, threading
    from http.server import ThreadingHTTPServer
    from unittest.mock import patch
    root = gui_root(value)
    marker = json.loads((root / 'fixture.json').read_text())
    if marker['running'] or (root / 'stop.json').exists():
        raise ValueError('Fixture already served; use a new setup root')
    sys.path.insert(0, str(ROOT / 'tools/flow-reader'))
    sys.path.insert(0, str(ROOT / 'tools/flow-reader/tests'))
    from test_homepage import FakeAuth, FakeManager
    from flow_reader.compiler.project import Project
    from flow_reader.server.state import ReaderState
    from flow_reader.server.http import handler_for
    from flow_reader.server import routing
    from flow_reader.services.homepage import HomeInventory
    from flow_reader.services.home_account import HomeAccount
    from flow_reader.services.paragraph_chat import ParagraphChat
    auth = FakeAuth(root); auth.signed_in = True
    effects = dict(inference=[], droppedAcknowledgments=[], auth=auth.calls)
    effectsLock = threading.Lock(); fault = threading.local()
    class AnswerProvider:
        def models(self): return [{'id':'fixture-model','label':'Isolated fixture model'}]
        def run(self, **options):
            question = json.loads(options['history'][-1]['content'])['question']
            with effectsLock:
                effects['inference'].append(dict(question=question, model=options['model']))
                gui_save(root / 'effects.json', effects)
            if not options['cancelled']():
                yield {'type':'delta','text':r'Fixture answer: $\frac{1}{2}$ inline. Display: $$\frac{x^2+1}{y+2}$$'}
    provider = AnswerProvider(); provider.auth = auth
    project = Project(Path(marker['source']), Path(marker['entry']), ROOT / 'tools/flow-reader/packages', compiler=marker['compilerWrapper'])
    state = ReaderState(project, root / 'compiled', '', False, change_file=root / 'owned-change.json')
    servers=[];threads=[];inventory=None
    stop = threading.Event()
    for signum in [signal.SIGTERM, signal.SIGINT]: signal.signal(signum, lambda *_:stop.set())
    try:
        state.compile()
        gui_save(root / 'compiler-report.json', state.report)
        if not state.revision or not state.report.get('contentGatePassed'):
            raise RuntimeError('Actual compiler/acceptance failed; see ' + str(root/'compiled/compile.log'))
        chat = ParagraphChat(state, directory=root / 'chat', provider=provider)
        chat.auth = auth
        original_mutate = chat.mutate
        def mutate(payload, operation):
            result = original_mutate(payload, operation)
            if operation == 'send' and payload.get('question','').startswith('[lost-ack]'):
                with effectsLock:
                    if payload['messageID'] not in effects['droppedAcknowledgments']:
                        effects['droppedAcknowledgments'].append(payload['messageID'])
                        fault.drop = True
                        gui_save(root / 'effects.json', effects)
            return result
        chat.mutate = mutate;state._paragraph_chat = chat
        def owned_handler(*args, **kwargs):
            base = handler_for(*args, **kwargs)
            class Owned(base):
                def respond(self, *a, **kw):
                    if getattr(fault,'drop',False):
                        fault.drop=False;self.close_connection=True
                        try:self.connection.shutdown(socket.SHUT_RDWR)
                        except OSError:pass
                        return
                    return super().respond(*a, **kw)
            return Owned
        inventory = HomeInventory(FakeManager(),loaded=([],[]))
        # No live manager/config observations. This inventory is concrete test input.
        with patch.object(routing, 'handler_for', owned_handler):
            shared = routing.handler_for_reader({'gui':state},inventory,HomeAccount(auth,provider),capability='isolated-fixture')
        for handler in [owned_handler(state),shared]:
            server=ThreadingHTTPServer(('127.0.0.1',0),handler);server.daemon_threads=True
            thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            servers.append(server);threads.append(thread)
        urls=['http://127.0.0.1:'+str(s.server_port)+'/' for s in servers]
        profile=dict(id='gui-native',name='Isolated native inspection',root=str(project.root),entry=marker['entry'],fonts=[],packages=str(project.packages),port=servers[1].server_port,publicURL='',label='test.lagrangian.gui-native')
        profiles=root/'app-dev/home/Library/Application Support/Lagrangian/profiles.json';profiles.parent.mkdir(parents=True,exist_ok=True)
        gui_save(profiles,dict(schemaVersion=1,selectedID=profile['id'],profiles=[profile]))
        marker.update(running=True,pid=os.getpid(),processArgv=sys.argv,rootURL=urls[0],prefixedURL=urls[1]+'d/gui/',ports=[s.server_port for s in servers],
            attachment=dict(url=urls[1]+'d/gui/',documentID=state.document_id,service=state.focus.service),revision=state.revision,
            profilesFile=str(profiles),profile=profile,deadline=time.time()+seconds)
        gui_save(root/'effects.json',effects);gui_save(root/'fixture.json',marker)
        print(json.dumps(marker),flush=True)
        while not stop.wait(.1):
            if time.time()>=marker['deadline'] or (root/'stop.json').exists():break
    finally:
        for s in servers:s.shutdown();s.server_close()
        for t in threads:t.join(timeout=3)
        if inventory:inventory.close()
        state.close()
        marker.update(running=False,stoppedAt=time.time(),closedPorts=[s.server_port for s in servers])
        gui_save(root/'fixture.json',marker);gui_save(root/'effects.json',effects)


def gui_attach(value, args):
    root=gui_root(value);m=json.loads((root/'fixture.json').read_text())
    expected=['--attach','--root',m['source'],'--entry',m['entry']]
    if args != expected or not m['running']:
        raise ValueError('Only this owned fixture exact --attach is supported; no lifecycle actions')
    status,data,_=gui_request(m['prefixedURL']+'api/state')
    state=json.loads(data)
    if status!=200 or state['documentID']!=m['attachment']['documentID'] or state['service']!=m['attachment']['service']:
        raise ValueError('Fixture incarnation changed')
    with (root/'manager-observations.jsonl').open('a') as f:f.write(json.dumps(dict(argv=args,pidObservation='fake; manifest PID only',actualHTTP=True))+'\n')
    return m['attachment']


def gui_stop(value):
    root=gui_root(value);m=json.loads((root/'fixture.json').read_text())
    if m['running']:
        gui_save(root/'stop.json',dict(fixtureID=m['fixtureID'],requestedAt=time.time()))
        for _ in range(100):
            m=json.loads((root/'fixture.json').read_text())
            if not m['running']:break
            time.sleep(.1)
        if m['running']:raise RuntimeError('Owned fixture did not acknowledge cleanup')
    return dict(stopped=True,root=str(root),pid=m.get('pid'),closedPorts=m.get('closedPorts',[]),signalSent=False)


PRIVATE_BOARD_SWIFT = r'''
import AppKit
import ObjectiveC
@MainActor private var generalCalls = 0
extension NSPasteboard {
  @MainActor @objc dynamic class func fixtureGeneral() -> NSPasteboard {
    generalCalls += 1
    return NSPasteboard(name: .init("test.lagrangian.unused-general." + UUID().uuidString))
  }
}
@main struct PrivateBoardProbe {
  @MainActor static func main() async throws {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
    let root = URL(fileURLWithPath: CommandLine.arguments[2])
    let home = root.appendingPathComponent("app-dev/home")
    let board = NSPasteboard(name: FlowApp.isolatedCopyBoard(home: home))
    if CommandLine.arguments[1] == "read" {
      print(board.string(forType: .string) ?? ""); return
    }
    method_exchangeImplementations(class_getClassMethod(NSPasteboard.self, NSSelectorFromString("generalPasteboard"))!,
      class_getClassMethod(NSPasteboard.self, #selector(NSPasteboard.fixtureGeneral))!)
    let config = try FlowRuntimeConfiguration(arguments: ["--dev-root", root.appendingPathComponent("app-dev").path,
      "--dev-no-activate", "--native-reader-manager", root.appendingPathComponent("fixture-manager").path],
      variables: [:], userHome: root.appendingPathComponent("unused-user"), executable: root.appendingPathComponent("not-launched"))
    guard config.isolated, config.noActivate, config.arguments.isEmpty, config.environment.userHome == home,
      config.environment.agents.path.hasPrefix(home.path + "/") else { throw FlowError(message: "isolation/parser binding") }
    for args in [["--dev-no-activate"], ["--native-reader-manager", "/fixture/manager"], ["--dev-root", "/"], ["--dev-root", root.path, "--control", "stop"]] {
      var rejected = false
      do { _ = try FlowRuntimeConfiguration(arguments: args, variables: [:], userHome: root.appendingPathComponent("unused-user"), executable: root.appendingPathComponent("unused")) }
      catch { rejected = true }
      guard rejected else { throw FlowError(message: "dev flag guard") }
    }
    let app = FlowApp(environment: config.environment, isolated: config.isolated, noActivate: config.noActivate)
    let text = "Owned fixture: 한글 e\u{301} 😀 אבג"
    guard app.copyText(text), board.string(forType: .string) == text, generalCalls == 0,
      NSApp.windows.allSatisfy({ !$0.isVisible }) else { throw FlowError(message: "private board composition") }
    // Ordinary composition still chooses general; the getter is substituted before
    // calling it, so this test never reads or writes the user's actual clipboard.
    let ordinary = FlowApp(environment: config.environment)
    guard ordinary.copyText("ordinary destination probe"), generalCalls == 1 else { throw FlowError(message: "ordinary destination changed") }
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fixture.json"))) as! [String: Any]
    let attachment = try NativeReaderAttachment(data: JSONSerialization.data(withJSONObject: fixture["attachment"]!))
    let identity = NativeDocumentIdentity(documentID: attachment.documentID, serviceID: attachment.serviceID,
      revision: fixture["revision"] as! String, scope: .service)
    let context = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: identity)
    let transport = NativeReaderTransport(attachment: attachment, network: .urlSession())
    let document = try await transport.document(for: context)
    var assets = [String: Data]()
    for asset in document.assets { assets[asset.id] = try await transport.asset(asset, context: context) }
    let recovery = NativeReaderRecoveryStore(root: root.appendingPathComponent("typed-recovery"))
    try await recovery.save(.init(document: document, assets: assets, restoration: .initial, drafts: []))
    let restored = try await recovery.load(identity: identity)
    guard restored.document == document, restored.assets == assets, document.blocks.count >= 33 else { throw FlowError(message: "real HTTP typed recovery") }
    await transport.dispose()
    print("private copy/parser guards + production HTTP typed recovery pass; userGeneralAccess=0; visibleWindows=0")
  }
}
'''


def gui_clipboard_helper(value):
    root=gui_root(value)
    if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
        raise RuntimeError('Wrap this Swift-containing command once with with-native-swift-lock.py')
    source=root/'PrivateBoardProbe.swift';source.write_text(PRIVATE_BOARD_SWIFT)
    binary=root/'private-board'
    gui_command(root,['/usr/bin/swiftc',*package.swift_flags(),*[p for p in package.swift_sources() if p.name!='main.swift'],source,'-o',binary])
    gui_command(root,[binary,'probe',root])
    marker=json.loads((root/'fixture.json').read_text());marker['privateBoardReadCommand']=[str(binary),'read',str(root)]
    marker['privateBoardHelperSHA256']=package.digest(binary);gui_save(root/'fixture.json',marker)
    return marker['privateBoardReadCommand']


def gui_smoke(value, compiler, package_cache):
    from urllib.parse import urlencode
    from uuid import uuid4
    root=gui_root(value,exists=False);gui_setup(root,compiler,package_cache)
    log=(root/'serve.log').open('w')
    process=subprocess.Popen([__import__('sys').executable,'-B',str(GUI_SCRIPT),'gui-fixture','serve','--root',str(root),'--seconds','180'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    checks=[]
    try:
        for _ in range(1200):
            m=json.loads((root/'fixture.json').read_text())
            if m['running']:break
            if process.poll() is not None:raise RuntimeError('Fixture startup exit '+str(process.returncode)+': '+(root/'serve.log').read_text()[-2000:])
            time.sleep(.1)
        if not m['running']:raise RuntimeError('Fixture startup deadline')
        assert m['pid']==process.pid
        context=dict(documentID=m['attachment']['documentID'],serviceID='reader:{pid}:{startedAt}'.format(**m['attachment']['service']),revision=m['revision'],schemaVersion=1,capabilities=['semantic-tree-v1','image-layout-v1'],generation=1,requestID=str(uuid4()),viewID=str(uuid4()))
        query={**context,'capabilities':','.join(context['capabilities'])}
        documents=[]
        for base in [m['rootURL'],m['prefixedURL']]:
            code,data,headers=gui_request(base+'api/native-document?'+urlencode(query));assert code==200,(code,data)
            document=json.loads(data);assert len(document['blocks'])>=33
            documents.append(document);checks.append('real native HTTP '+base)
            for asset in document['assets']:
                code,payload,_=gui_request(base+'api/native-assets/'+asset['id']+'?'+urlencode(query));assert code==200 and hashlib.sha256(payload).hexdigest()==asset['sha256']
        assert documents[0]==documents[1]
        context['inputID']=headers['X-Native-Input-ID']
        block=next(b for b in document['blocks'] if b['canonicalText'].startswith('Source and chat probe:'))
        selection=dict(ticket=str(uuid4()),fragments=[dict(blockID=block['id'],rangeUTF16=[0,len(block['canonicalText'].encode('utf-16-le'))//2],exact=block['canonicalText'])])
        base=m['prefixedURL']
        def post(path,**fields):
            code,data,_=gui_request(base+path,fields={**context,**fields});assert code==200,(code,data);return json.loads(data)
        located=post('api/native-action',operation='locate',selection=selection,receiptID=str(uuid4()))
        assert located['status']=='located', located
        # The existing excerpt owner supports complete math expressions only.
        # Prose is used for locate/chat; do not invent a prose source copier.
        math=next(b for b in document['blocks'] if b['kind']=='equation')
        mathSelection=dict(ticket=str(uuid4()),fragments=[dict(blockID=math['id'],rangeUTF16=math['rangeUTF16'],exact=math['canonicalText'])])
        excerpt=post('api/native-action',operation='excerpt',selection=mathSelection,receiptID=str(uuid4()))
        assert excerpt['status']=='located' and excerpt['text'].startswith('$') and 'frac' in excerpt['text'], excerpt
        checks.append('production prose locate and complete-math source excerpt verified')
        opened=post('api/native-chat',operation='open',selection=selection)['conversations'][0]
        assert not json.loads((root/'effects.json').read_text())['inference']
        message=str(uuid4());question='[lost-ack] Show an exact fraction.'
        try:
            post('api/native-chat',operation='send',conversationID=opened['conversation_id'],version=opened['version'],messageID=message,question=question,model='fixture-model')
            raise AssertionError('Expected owned transport fault')
        except __import__('http.client',fromlist=['RemoteDisconnected']).RemoteDisconnected:pass
        for _ in range(100):
            records=post('api/native-chat',operation='list')['conversations'];record=next(c for c in records if c['conversation_id']==opened['conversation_id'])
            if record['status']!='streaming':break
            time.sleep(.02)
        assert any(t['id']==message and t['role']=='user' and t['text']==question for t in record['thread'])
        assert any('\\frac' in t['text'] for t in record['thread'] if t['role']=='assistant')
        effects=json.loads((root/'effects.json').read_text());assert len(effects['inference'])==1 and effects['droppedAcknowledgments']==[message] and effects['auth']==[]
        checks.append('real Send→fake TeX/lost acknowledgment→authoritative history; no resend')
        args=['--attach','--root',m['source'],'--entry',m['entry']]
        result=gui_command(root,[m['manager'],*args]);assert json.loads(result.stdout)==m['attachment']
        checks.append('fake manager observation + real HTTP incarnation')
        gui_clipboard_helper(root);checks.append('actual AppKit private board + actual parser guards + production HTTP typed recovery')
        assert len(json.loads((root/'effects.json').read_text())['inference'])==1
        gui_save(root/'smoke.json',dict(checks=checks,tests=len(checks),skips=0,inferenceCalls=1,guiActivations=0,visibleWindows=0,originalPDFVerified=False,appBuilt=False))
    finally:
        stopped=gui_stop(root)
        exitCode=process.wait(timeout=10);log.close()
        gui_save(root/'cleanup.json',dict(**stopped,actualExit=exitCode,processReaped=process.poll() is not None))
        if exitCode!=0:raise RuntimeError('Owned server exit '+str(exitCode))
    import socket
    for port in m['ports']:
        with socket.socket() as s:assert s.connect_ex(('127.0.0.1',port))!=0
    return dict(root=str(root),checks=checks,exit=0,skips=0,cleanup='own process reaped; both ports closed')


def gui_cli(argv):
    import argparse,sys
    parser=argparse.ArgumentParser(description='Owned native inspection fixture only; never starts the app.')
    sub=parser.add_subparsers(dest='command',required=True)
    for name in ['setup','serve','stop','status','smoke','clipboard-helper']:
        p=sub.add_parser(name);p.add_argument('--root',required=True)
        if name in ['setup','smoke']:
            p.add_argument('--compiler',required=True);p.add_argument('--package-cache',required=True)
        if name=='serve':p.add_argument('--seconds',type=int,default=900,choices=range(1,1801),metavar='1..1800')
    p=sub.add_parser('attach');p.add_argument('--fixture-root',required=True)
    args,extra=parser.parse_known_args(argv)
    if args.command!='attach' and extra:parser.error('unrecognized arguments: '+' '.join(extra))
    if args.command=='setup':result=gui_setup(args.root,args.compiler,args.package_cache)
    elif args.command=='serve':
        root=gui_root(args.root)
        if os.environ.get('LAGRANGIAN_GUI_FIXTURE_SANDBOX') != str(root):
            # Test-process confinement: no user-home files, external network or
            # writes outside this fixture and the explicit DevSSD temporary root.
            profile='(version 1)(allow default)(deny network*)' + \
                '(allow network-inbound (local ip "localhost:*"))' + \
                '(allow network-outbound (remote ip "localhost:*"))' + \
                '(deny file-read* (subpath '+json.dumps(str(Path.home()))+'))(deny file-write*)' + \
                ''.join('(allow file-write* (subpath '+json.dumps(str(p))+'))' for p in [root,Path(os.environ.get('TMPDIR',str(root/'tmp')))])
            gui_save(root/'sandbox.json',dict(profile=profile,userHomeAccessDenied=True,externalNetworkDenied=True))
            env=dict(os.environ,LAGRANGIAN_GUI_FIXTURE_SANDBOX=str(root),PYTHONDONTWRITEBYTECODE='1')
            env.pop('PYTHONPATH',None)
            os.execve('/usr/bin/sandbox-exec',['sandbox-exec','-p',profile,sys.executable,'-B',str(GUI_SCRIPT),'gui-fixture',*argv],env)
        gui_serve(root,args.seconds);return
    elif args.command=='stop':result=gui_stop(args.root)
    elif args.command=='status':result=json.loads((gui_root(args.root)/'fixture.json').read_text())
    elif args.command=='attach':result=gui_attach(args.fixture_root,extra)
    elif args.command=='clipboard-helper':result=gui_clipboard_helper(args.root)
    else:result=gui_smoke(args.root,args.compiler,args.package_cache)
    print(json.dumps(result,ensure_ascii=False,indent=2))


class GUIFixtureGuards(unittest.TestCase):
    def test_rejects_nonowned_roots_before_read_or_stop(self):
        for path in ['relative', '/', str(GUI_ROOT), str(DEV/'not-a-fixture')]:
            with self.assertRaises(ValueError): gui_root(path)
            with self.assertRaises(ValueError): gui_stop(path)

    def test_rejects_symlink_and_preserves_existing_setup(self):
        import tempfile
        GUI_ROOT.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='guards-',dir=GUI_ROOT) as folder:
            root=Path(folder);(root/'link').symlink_to(root,target_is_directory=True)
            with self.assertRaises(ValueError): gui_root(root/'link',exists=False)
            marker=root/'retained';marker.write_text('owned marker')
            with self.assertRaises(ValueError): gui_setup(root, '/missing/compiler', '/missing/cache')
            self.assertEqual(marker.read_text(),'owned marker')


if __name__ == '__main__':
    import sys
    if sys.argv[1:2]==['gui-fixture']:gui_cli(sys.argv[2:])
    else:unittest.main()
