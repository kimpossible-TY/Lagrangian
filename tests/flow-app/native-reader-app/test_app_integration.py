"""Real frozen-component host composition. Offline fixture input and scratch runtime are explicit test inputs."""
import hashlib
import importlib.util
import json
import os
import sys
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
GUI_ROOT = Path(os.environ.get('FLOW_GUI_FIXTURE_ROOT', DEV / 'test-output/integration/gui-prep-v1/fixtures'))
GUI_SCRIPT = Path(__file__).resolve()


def gui_root(value, *, exists=True):
    import uuid
    path = Path(value)
    if not path.is_absolute() or path == GUI_ROOT or not path.is_relative_to(GUI_ROOT):
        raise ValueError('Fixture root must be a distinct absolute directory below ' + str(GUI_ROOT))
    if '..' in path.parts or any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError('Fixture paths cannot contain symlinks')
    if exists:
        if (path / 'fixture.json').is_symlink():
            raise ValueError('Fixture marker cannot be a symlink')
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
    fixture_id = str(uuid.uuid4())
    identity = dict(owner='lagrangian-native-gui-fixture', fixtureID=fixture_id, root=str(root),
                    source=str(source), entry='gui-native.typ', manager=str(manager))
    owner = Path(__file__).resolve()
    # Self-contained argv-only reentry. The allowlist and immutable fixture
    # identity come from setup, not the app's environment or a mutable marker.
    preamble = ('#!' + __import__('sys').executable + '\n' +
        'import sys\nsys.dont_write_bytecode=True\nimport os,json,hashlib,importlib.util\nfrom pathlib import Path\n' +
        'root=Path(' + repr(str(root)) + ')\nexpected=' + repr(identity) + '\n' +
        'owner=Path(' + repr(str(owner)) + ')\n' +
        'if hashlib.sha256(owner.read_bytes()).hexdigest()!=' + repr(package.digest(owner)) + ': raise ValueError("fixture owner changed")\n' +
        'spec=importlib.util.spec_from_file_location("owned_gui_fixture",owner)\n' +
        'module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)\n' +
        'module.GUI_ROOT=Path(' + repr(str(GUI_ROOT)) + ')\nmodule.gui_root(root)\n' +
        'if (root.stat().st_dev,root.stat().st_ino)!=' + repr((root.stat().st_dev,root.stat().st_ino)) + ': raise ValueError("fixture directory changed")\n' +
        'marker=json.loads((root/"fixture.json").read_text())\n' +
        'if not all(marker.get(k)==v for k,v in expected.items()): raise ValueError("fixture marker changed")\n' +
        'if Path(expected["source"]).is_symlink(): raise ValueError("fixture source changed")\n')
    manager.write_text(preamble + 'print(json.dumps(module.gui_attach(root,sys.argv[1:])))\n')
    manager.chmod(0o700)
    control = root / 'fixture-control'
    control.write_text(preamble +
        'if not sys.argv[1:2] or sys.argv[1] not in ["serve","status","stop","clipboard-helper"]: raise ValueError("owned fixture operations only")\n' +
        'os.environ["FLOW_GUI_FIXTURE_ROOT"]=' + repr(str(GUI_ROOT)) + '\n' +
        'module.gui_cli([sys.argv[1],"--root",str(root)]+sys.argv[2:])\n')
    control.chmod(0o700)
    args = ['--dev-root', str(root / 'app-dev'), '--dev-no-activate', '--native-reader-manager', str(manager)]
    marker = dict(owner='lagrangian-native-gui-fixture', fixtureID=fixture_id, root=str(root), source=str(source),
        entry='gui-native.typ', compiler=str(compiler), compilerSHA256=package.digest(compiler), compilerVersion=gui_command(root,[compiler,'--version']).stdout.strip(),
        script=str(GUI_SCRIPT), scriptSHA256=package.digest(GUI_SCRIPT), sourceRevision=gui_command(root,['git','rev-parse','HEAD']).stdout.strip(), compilerWrapper=str(wrapper),
        sourceHashes={p.name:package.digest(p) for p in source.iterdir()}, packageCacheInput=str(package_cache),
        packageCacheHashes={str(p.relative_to(cache)):package.digest(p) for p in cache.rglob('*') if p.is_file()}, manager=str(manager), appArguments=args,
        privatePasteboard=board, managerRootPrefix=str(GUI_ROOT), managerRootIdentity=[root.stat().st_dev,root.stat().st_ino], managerSHA256=package.digest(manager), fixtureControl=str(control), fixtureControlSHA256=package.digest(control), running=False, originalPDF='integrated service; this fixture run does not verify Original PDF GUI delivery',
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
    process=subprocess.Popen([str(root/'fixture-control'),'serve','--seconds','180'],cwd=ROOT,env={k:v for k,v in os.environ.items() if k!='FLOW_GUI_FIXTURE_ROOT'},stdout=log,stderr=subprocess.STDOUT)
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
        env={'PATH':'/usr/bin:/bin','TMPDIR':os.environ['TMPDIR']}
        cache_scopes=[ROOT/'scripts/__pycache__',ROOT/'tests/flow-app/native-reader-app/__pycache__',ROOT/'tools/flow-reader/flow_reader']
        def cache_observation():
            return {str(p.relative_to(ROOT)):package.digest(p) for scope in cache_scopes if scope.exists() for p in scope.rglob('*.pyc') if p.is_file()}
        cache_before=cache_observation()
        probes=[]
        observation=root.parent/(root.name+'-outside-observation');observation.mkdir()
        (observation/'sentinel').write_bytes(b'owned outside-root sentinel')
        def observed():
            return {str(p.relative_to(observation)):('symlink' if p.is_symlink() else package.digest(p) if p.is_file() else 'directory') for p in observation.rglob('*')}
        outside_before=observed()
        def manager_probe(arguments,success,optimize=False):
            argv=[m['manager'],*arguments];started=time.monotonic()
            result=subprocess.run(argv,env=dict(env,**({"PYTHONOPTIMIZE":"1"} if optimize else {})),capture_output=True,text=True,timeout=15)
            probes.append(dict(argv=argv,exit=result.returncode,elapsed=time.monotonic()-started,stdout=result.stdout,stderr=result.stderr,fixtureRootEnvironmentPresent=False,bytecodeEnvironmentPresent=False,pythonPathEnvironmentPresent=False,optimized=optimize))
            assert (result.returncode==0)==success,(arguments,result.stderr)
            return result
        result=manager_probe(args,True);assert json.loads(result.stdout)==m['attachment']
        manager_probe(['--attach','--root',str(root.parent),'--entry',m['entry']],False,optimize=True)
        # A marker mutation cannot change the immutable wrapper identity.
        original=(root/'fixture.json').read_bytes()
        tampered=dict(m,fixtureID=str(uuid4()));gui_save(root/'fixture.json',tampered)
        try:manager_probe(args,False)
        finally:(root/'fixture.json').write_bytes(original)
        real_source=root/'source-retained';(root/'source').rename(real_source)
        (root/'source').symlink_to(real_source,target_is_directory=True)
        before={str(p.relative_to(real_source)):package.digest(p) for p in real_source.rglob('*') if p.is_file()}
        try:manager_probe(args,False)
        finally:(root/'source').unlink();real_source.rename(root/'source')
        assert before=={str(p.relative_to(root/'source')):package.digest(p) for p in (root/'source').rglob('*') if p.is_file()}
        manager_probe(args,True)
        root_retained=root.with_name(root.name+'-retained');root.rename(root_retained)
        root.symlink_to(root_retained,target_is_directory=True)
        try:manager_probe(args,False)
        finally:root.unlink();root_retained.rename(root)
        # Guard the marker itself too, without following an external symlink.
        retained=root/'marker-retained.json';(root/'fixture.json').rename(retained)
        (root/'fixture.json').symlink_to(observation/'sentinel')
        try:manager_probe(args,False)
        finally:(root/'fixture.json').unlink();retained.rename(root/'fixture.json')
        outside_after=observed();assert outside_after==outside_before
        cache_after=cache_observation();assert cache_before==cache_after
        for arguments,success in [(['status'],True),(['unsafe-operation'],False)]:
            control_result=subprocess.run([str(root/'fixture-control'),*arguments],env=dict(env,PYTHONOPTIMIZE='1'),capture_output=True,text=True,timeout=15)
            assert (control_result.returncode==0)==success,control_result.stderr
            probes.append(dict(argv=[str(root/'fixture-control'),*arguments],exit=control_result.returncode,optimized=True,environmentKeys=list(env),stdout=control_result.stdout,stderr=control_result.stderr))
        assert cache_before==cache_observation()
        gui_save(root/'manager-probes.json',dict(probes=probes,observedOutsideScope=str(observation),
            outsideBefore=outside_before,outsideAfter=outside_after,outsideScopeUnchanged=True,sourceHashesUnchanged=True,cacheScopes=list(map(str,cache_scopes)),cacheBefore=cache_before,cacheAfter=cache_after,cacheUnchanged=True))
        checks.append('argv-only fixed manager/no env: own real HTTP attach; other root/marker/symlink rejected; sources unchanged')
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



# Production AppKit controls, exercised offscreen through their real target/action.
FEATURE_SWIFT = SWIFT.split('@main struct HostIntegration')[0] + r'''

@MainActor final class StorageGate {
  var blocked=false, entered=false
  var continuation:CheckedContinuation<Void,Never>?
  func wait()async { if blocked { entered=true; await withCheckedContinuation{continuation=$0} } }
  func release(){blocked=false;continuation?.resume();continuation=nil}
}
@MainActor func featurePaint(_ view:NSView,_ url:URL)throws->String{
  let size=view.bounds.size
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  let context=NSGraphicsContext(bitmapImageRep:bitmap)!
  view.displayIgnoringOpacity(view.bounds,in:context)
  let data=bitmap.representation(using:.png,properties:[:])!;try data.write(to:url);return NativeReaderRecoverySnapshot.digest(data)
}
@MainActor func featureViews(_ view:NSView)->[NSView]{[view]+view.subviews.flatMap{featureViews($0)}}
@MainActor struct FeatureControl {
  let isEnabled: Bool
  let actionBlock: () -> Void
  func performClick(_ sender: Any? = nil) { actionBlock() }
}
@MainActor func featureMenuItem(_ menu:NSMenu,_ action:String)->NSMenuItem?{
  for item in menu.items {
    if item.action.map(NSStringFromSelector) == action { return item }
    if let sub = item.submenu, let found = featureMenuItem(sub, action) { return found }
  }
  return nil
}
@MainActor func featureButton(_ root:NSView,_ title:String)throws->FeatureControl{
  let selectors = ["Source":"sourceSelected", "Highlight":"highlightSelected", "Ask":"askSelected", "Locate Source":"locateSelected", "Check Editor Result":"editorReceipt", "Last Edit":"lastEdit", "Account":"account", "Copy":"copySelected", "Reflow":"reflowMode", "Original PDF":"pageMode", "Previous":"previousPage", "Next":"nextPage", "Release selection":"releasePageSelection", "Mark for review":"markSelected", "Undo review":"undoReviewExplicitly", "Clear review":"clearReviewExplicitly", "Save Offline":"saveOfflineExplicitly", "Refresh Saved":"refreshSavedExplicitly", "Open Saved":"openSavedMenuEntry:", "Cancel":"cancelStorageExplicitly", "Export PDF":"exportPDFExplicitly", "Manage Account":"manageAccountExplicitly", "Back":"returnFromReference", "Zoom +":"zoomIn", "Zoom −":"zoomOut", "Fit":"fitPage", "Aa":"toggleDisplayPopover", "More":"toggleTools", "Light":"selectLightTheme", "Dark":"selectDarkTheme", "Automatic":"selectAutomaticTheme", "Font -":"decreaseFontSize", "Font +":"increaseFontSize"]
  if let b=featureViews(root).compactMap({$0 as? NSButton}).first(where:{ $0.title==title || (selectors[title] != nil && $0.identifier?.rawValue==selectors[title]) }) {
    if !b.isHiddenOrHasHiddenAncestor {
      _ = b.scrollToVisible(b.bounds);root.layoutSubtreeIfNeeded()
      let bounds=b.convert(b.bounds,to:root)
      try check(!bounds.isEmpty && root.bounds.contains(bounds),"laid-out reachable control "+title)
      try check(b.target != nil && b.action != nil,"real target/action for "+title)
      return FeatureControl(isEnabled: b.isEnabled) { b.performClick(nil) }
    }
    if b.identifier?.rawValue == "releasePageSelection" {
      try check(b.target != nil && b.action != nil,"real target/action for "+title)
      return FeatureControl(isEnabled: b.isEnabled) { if b.isEnabled { _ = NSApp.sendAction(b.action!, to: b.target, from: b) } }
    }
  }
  if let hostWindow = root.window?.windowController as? NativeReaderHostWindow {
    let popView = hostWindow.displayPopoverContentView
    popView.layoutSubtreeIfNeeded()
    if let b=featureViews(popView).compactMap({$0 as? NSButton}).first(where:{ $0.title==title || (selectors[title] != nil && $0.identifier?.rawValue==selectors[title]) || (selectors[title] != nil && $0.action.map(NSStringFromSelector)==selectors[title]) }) {
      let bounds=b.convert(b.bounds,to:popView)
      try check(!b.isHiddenOrHasHiddenAncestor && !bounds.isEmpty && popView.bounds.contains(bounds),"laid-out reachable popover control "+title)
      try check(b.target != nil && b.action != nil,"real target/action for "+title)
      return FeatureControl(isEnabled: b.isEnabled) { if b.isEnabled { _ = NSApp.sendAction(b.action!, to: b.target, from: b) } }
    }
    if title == "Open Saved" {
      if let item = featureMenuItem(hostWindow.moreMenu, "openSavedMenuEntry:") {
        try check(item.target != nil && item.action != nil,"real menu target/action for "+title)
        return FeatureControl(isEnabled: item.isEnabled) { if item.isEnabled { _ = NSApp.sendAction(item.action!, to: item.target, from: item) } }
      }
      if hostWindow.moreMenu.items.contains(where: { $0.title == "저장 문서 열기" }) {
        return FeatureControl(isEnabled: false) {}
      }
    }
    if let selector = selectors[title], let item = featureMenuItem(hostWindow.moreMenu, selector) {
      try check(item.target != nil && item.action != nil,"real menu target/action for "+title)
      return FeatureControl(isEnabled: item.isEnabled) { if item.isEnabled { _ = NSApp.sendAction(item.action!, to: item.target, from: item) } }
    }
  }
  throw FlowError(message:"Missing delivered control: "+title)
}
@MainActor func featurePopup(_ root:NSView,_ label:String)throws->NSPopUpButton{
  let ids=["Contents":"contents","Recovered drafts":"recoveredDrafts"]
  guard let p=featureViews(root).compactMap({$0 as? NSPopUpButton}).first(where:{$0.accessibilityLabel()==label || (ids[label] != nil && $0.identifier?.rawValue==ids[label])}),p.action != nil,p.target != nil else {throw FlowError(message:"Missing reachable popup: "+label)}
  _ = p.scrollToVisible(p.bounds);return p
}
@MainActor func featureSelect(_ popup:NSPopUpButton,_ index:Int)throws{
  popup.selectItem(at:index);try check(NSApp.sendAction(popup.action!,to:popup.target,from:popup),"native popup target/action")
}
@main struct FeatureWiringTests {
  @MainActor static func main()async {do{try await run()}catch{fputs("FEATURE FAILURE: \(error)\n",stderr);exit(1)}}
  @MainActor static func run()async throws{
    _ = NSApplication.shared;NSApp.setActivationPolicy(.prohibited);FindPasteboardIsolation.install()
    let args=CommandLine.arguments,out=URL(fileURLWithPath:args[3]),mode=args[1]
    let fixture=URL(fileURLWithPath:mode=="long" ? args[7] : args[2]),provider=NativeReaderFixtureProvider(url:fixture)
    let runtime=NativeReaderRuntime(node:URL(fileURLWithPath:args[4]),helper:URL(fileURLWithPath:args[5]),runtime:URL(fileURLWithPath:args[6]))
    let disk=NativeReaderRecoveryStore(root:out.appendingPathComponent("owned-storage")),gate=StorageGate()
    var invalidReview: NativeReaderRecoverySnapshot?
    let storage=NativeReaderOfflineStorage(save:{snapshot in await gate.wait();try Task.checkCancellation();try await disk.save(snapshot)},list:{try await disk.list()},load:{identity in await gate.wait();try Task.checkCancellation();if let invalidReview { return invalidReview };return try await disk.load(identity:identity)})
    let host=NativeReaderWindowController(provider:provider,target:{_ in try await provider.load().identity},assets:{doc,_ in
      var result=[String:Data]();for a in doc.assets{result[a.id]=try Data(contentsOf:fixture.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(a.id))};return result
    },runtime:runtime,show:false,avoidActivation:true,offlineStorage:storage)
    defer{host.dispose()}
    let profile=Profile(id:"feature",name:"Owned feature fixture",root:out.path,entry:"main.typ",fonts:[],packages:"",port:24650,publicURL:"",label:"test.feature")
    _ = host.open(profile){_ in};try await until{host.session.state == .reading || host.session.failure != nil}
    try check(host.session.failure==nil,"actual compiler snapshot accepted")
    let root=host.hostWindow.window!.contentView!,text=host.textView,document=host.store.document!,logical=text.logicalText
    root.layoutSubtreeIfNeeded();try await ready(host)
    try check(!host.hostWindow.isDisplayPopoverOpen,"Aa popover starts closed before baseline")
    await Task.yield();try await ready(host)
    func click(_ title:String)throws {let b=try featureButton(root,title);try check(b.isEnabled,"active "+title);b.performClick(nil)}
    func firstSelection()throws{
      let block=document.blocks.first{$0.kind == .paragraph && !$0.displayText.isEmpty}!
      try text.select(from:.init(blockID:block.id,utf16:0,affinity:.upstream),to:.init(blockID:block.id,utf16:block.displayText.utf16.count,affinity:.downstream))
    }
    func storageIdle()async throws{try await until{(try? featureButton(root,"Cancel").isEnabled)==false}}
    func fileBytes()throws->Data{let urls=try FileManager.default.contentsOfDirectory(at:disk.root,includingPropertiesForKeys:nil);return try Data(contentsOf:urls.first{$0.pathExtension=="json"}!)}
    switch mode {
    case "review":
      try firstSelection();let held=host.store.selection!,ax=text.bodyTextView.accessibilityValue()
      let before=try featurePaint(text.bodyTextView,out.appendingPathComponent("review-before.png"))
      try click("Mark for review");try check(host.localReview.marks.count==1,"review owner receives selected mark")
      let after=try featurePaint(text.bodyTextView,out.appendingPathComponent("review-after.png"));try check(after != before,"actual native strike pixels")
      try check(text.logicalText==logical && text.bodyTextView.accessibilityValue()==ax && host.store.selection==held,"review preserves exact text AX selection")
      try click("Undo review");try check(host.localReview.marks.isEmpty,"UI undo")
      let undone=try featurePaint(text.bodyTextView,out.appendingPathComponent("review-undo.png"));try check(undone==before,"undo removes native paint")
      try click("Mark for review");try click("Mark for review");try click("Clear review");try check(host.localReview.marks.isEmpty,"UI clear")
      try click("Mark for review");try text.setAppearance(.init(fontSize:18,zoom:1,theme:.dark));host.hostWindow.onAppearance?();try await ready(host)
      try check(host.localReview.marks.count==1 && host.store.selection==held,"marks survive current-key reflow with selection")
      _ = try featurePaint(text.bodyTextView,out.appendingPathComponent("review-reflow.png"))
      host.refresh();try await until{host.session.state == .reading || host.session.failure != nil}
      try check(host.localReview.marks.count==1 && host.store.document==document,"held refresh retains accepted marks")
      try click("Release selection");try await until{host.store.document?.generation != document.generation};try await ready(host)
      try check(host.localReview.marks.isEmpty,"new accepted snapshot revokes old review")
      try firstSelection();try click("Mark for review");host.cancel();try check(host.localReview.marks.isEmpty,"cancel invalidates review paint")
    case "restore-resize", "restore-hold", "restore-cancel", "restore-close":
      if mode == "restore-hold", let w = host.hostWindow.window { w.setContentSize(NSSize(width: w.contentLayoutRect.width, height: 420)); w.contentView?.layoutSubtreeIfNeeded(); try await ready(host) }
      try firstSelection();try click("Mark for review");try click("Save Offline");try await storageIdle()
      let saved=try await disk.load(identity:document.identity),originalBytes=try fileBytes(),oldKey=text.renderKey
      let pending=UUID(),draft=NativeReaderRecoveredDraft(conversationID:UUID(),version:2,text:"newer N",pendingMessageID:pending,model:"fixture-model",pendingQuestion:"uncertain M",pendingModel:"fixture-model")
      let restoration=NativeReaderRestoration(blockID:saved.restoration.blockID,offset:0.4,zoom:1.5,selectionTicket:saved.restoration.selectionTicket,fragments:saved.restoration.fragments)
      var candidate=NativeReaderRecoverySnapshot(document:saved.document,assets:saved.assets,restoration:restoration,drafts:[draft]);candidate.reviewMarks=saved.reviewMarks
      try await disk.save(candidate)
      try click("Release selection")
      let blocker=out.appendingPathComponent("helper-block"),wrapper=out.appendingPathComponent("gated-node")
      try Data().write(to:blocker)
      let script="#!/bin/sh\ni=0\nwhile [ -e '"+blocker.path+"' ] && [ \"$i\" -lt 1000 ]; do /bin/sleep 0.01; i=$((i+1)); done\nexec '"+runtime.node.path+"' \"$@\"\n"
      try script.write(to:wrapper,atomically:true,encoding:.utf8);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:wrapper.path)
      host.runtime=NativeReaderRuntime(node:wrapper,helper:runtime.helper,runtime:runtime.runtime)
      try click("Refresh Saved");try await storageIdle();try click("Open Saved")
      try await until{host.preparingKey != nil};try await Task.sleep(nanoseconds:40_000_000)
      if mode=="restore-resize"{text.frame.size.width-=63;var a=text.textAppearance;a.fontSize=18;try text.setAppearance(a);host.hostWindow.onAppearance?()}
      else {try firstSelection()}
      try check(host.store.document==document,"C1 A retained during candidate preparation")
      if mode=="restore-cancel"{try click("Cancel")}
      if mode=="restore-close"{host.hostWindow.window!.close()}
      try FileManager.default.removeItem(at:blocker)
      if mode=="restore-cancel" || mode=="restore-close"{
        try await Task.sleep(nanoseconds:300_000_000)
        try check(host.store.document==document && (mode=="restore-close" || text.renderKey==oldKey),"C1 cancelled/closed restore cannot adopt late B")
      }else{
        if mode=="restore-hold"{
          try await until{host.preparingKey==nil};try check(host.store.document==document && host.store.selection != nil,"C1 held B keeps A selection")
          try check((try? featureButton(root,"Cancel").isEnabled)==true,"C1 held restore remains cancellable")
          try click("Release selection")
        }
        try await until{host.store.document?.generation != document.generation && host.session.state == .offline};try await ready(host)
        try check(host.localReview.marks.map(\.id)==candidate.reviewMarks.map(\.id),"C1 marks bound to adopted B once")
        try check(host.store.selection?.fragments==saved.restoration.fragments.map{.init(blockID:$0.blockID,rangeUTF16:$0.start..<$0.end,exact:$0.exact)},"C1 exact restored B selection")
        try check(text.textAppearance.zoom==1.5,"C1 saved B zoom")
        try await storageIdle();try click("Save Offline");try await storageIdle()
        let again=try await disk.load(identity:document.identity)
        try check(again.drafts.count==1 && again.drafts[0].text==draft.text && again.drafts[0].pendingMessageID==pending && again.drafts[0].pendingQuestion==draft.pendingQuestion && again.drafts[0].pendingModel==draft.pendingModel,"C1 candidate drafts/pending restored through actual Open/Save controls")
        try check(again.reviewMarks.count==1 && again.restoration.zoom==1.5 && abs(again.restoration.offset-0.4)<0.15,"C1 viewport/zoom/marks survive resave")
      }
      try check(originalBytes.count>0,"C1 initial real stored file exists")
    case "invalid-review":
      try firstSelection();try click("Mark for review");try click("Save Offline");try await storageIdle()
      let saved=try await disk.load(identity:document.identity),priorBytes=try fileBytes(),priorKey=text.renderKey
      var bad=saved;bad.reviewMarks=[saved.reviewMarks[0],saved.reviewMarks[0]];invalidReview=bad
      try click("Release selection");try click("Refresh Saved");try await storageIdle();try click("Open Saved");try await storageIdle()
      try check(host.hostWindow.notice.stringValue.contains("실패") || host.hostWindow.notice.stringValue.contains("failed"),"invalid review snapshot is explicitly rejected")
      try check(host.store.document==document && text.renderKey==priorKey && host.localReview.marks.count==1,"invalid review snapshot cannot replace painted accepted A before failing")
      let afterBytes=try fileBytes();try check(afterBytes==priorBytes,"invalid review preserves durable file")
    case "navigation":
      let popup=try featurePopup(root,"Contents");try check(popup.numberOfItems==text.outline.count && popup.numberOfItems>0,"typed outline reaches native control")
      let anchor=text.viewportAnchor();try featureSelect(popup,popup.numberOfItems-1)
      try check(text.focusedNodeID==text.outline.last?.id,"outline uses canonical node mapping")
      try click("Back");try check(!text.canReturnFromReference,"one native reference return consumed")
      if let anchor{try check(text.viewportAnchor()?.position.blockID==anchor.position.blockID,"native return viewport")}
      try featureSelect(popup,0);host.refresh();try await until{host.session.state == .reading};try await ready(host)
      try check(!text.canReturnFromReference,"replacement invalidates old reference return")
    case "lifecycle":
      let owned=out.appendingPathComponent("native-input");try FileManager.default.copyItem(at:fixture.deletingLastPathComponent(),to:owned)
      let input=owned.appendingPathComponent(fixture.lastPathComponent)
      try Data("Owned Read validation".utf8).write(to:out.appendingPathComponent("main.typ"))
      let environment=AppEnvironment(variables:[:],userHome:out.appendingPathComponent("home"),executable:out.appendingPathComponent("Lagrangian"))
      let app=FlowApp(environment:environment,isolated:true,fixture:input,noActivate:true,nativeRuntime:runtime,showNativeWindow:false)
      app.buildWindow();app.settings=Settings(selectedID:profile.id,profiles:[profile]);app.populate()
      defer{app.applicationWillTerminate(Notification(name:NSApplication.willTerminateNotification));app.window.close()}
      app.networkChanged(true);app.powerChanged(true);app.sleepChanged(true);app.sleepChanged(false)
      try check(app.nativeWindow==nil,"F14 unread profile never automatically Reads")
      var targetCalls=0,preparations=0
      let observed=NativeReaderFixtureProvider(url:input)
      app.nativeProfile=profile
      app.nativeWindow=NativeReaderWindowController(provider:observed,target:{_ in targetCalls+=1;return try await observed.load().identity},assets:{doc,_ in
        preparations+=1;var result=[String:Data]();for asset in doc.assets{result[asset.id]=try Data(contentsOf:owned.appendingPathComponent("assets").appendingPathComponent(asset.id))};return result
      },runtime:runtime,show:false,avoidActivation:true)
      func step(_ label:String)throws{
        let value:[String:Any] = ["step":label,"mutating":app.mutating,"active":app.active?.id ?? "none","readEnabled":app.controls[#selector(FlowApp.openPreview)]?.isEnabled ?? false,"nativeState":app.nativeWindow.map{String(describing:$0.session.state)} ?? "none","targetCalls":targetCalls,"preparations":preparations]
        try JSONSerialization.data(withJSONObject:value,options:.prettyPrinted).write(to:out.appendingPathComponent("lifecycle-stage.json"))
      }
      let read=app.controls[#selector(FlowApp.openPreview)]!;try step("initial-read");try await until{read.isEnabled};read.performClick(nil)
      try await until{app.nativeWindow?.session.state == .reading};let native=app.nativeWindow!;try await ready(native)
      _ = try featurePaint(native.textView.bodyTextView,out.appendingPathComponent("lifecycle-initial.png"));try await until{read.isEnabled}
      let a=native.store.document!,oldContext=native.session.context!
      let beforeSleepTarget=targetCalls,beforeSleepPreparation=preparations
      app.sleepChanged(true);let sleepingGeneration=native.store.generation
      app.networkChanged(false);app.networkChanged(true)
      try await Task.sleep(nanoseconds:150_000_000)
      try check(native.session.state == .sleeping && native.store.generation==sleepingGeneration && targetCalls==beforeSleepTarget && preparations==beforeSleepPreparation && native.store.document==a,"F14 online signals cannot prepare or adopt before wake")
      try check(native.session.state == .sleeping && native.store.document==a,"F14 sleep retains accepted A")
      app.networkChanged(false);app.sleepChanged(false)
      try await Task.sleep(nanoseconds:30_000_000)
      try check(native.store.document==a && native.session.isReadOnly,"F14 offline wake retains read-only A")
      app.networkChanged(true);let generation=native.store.generation
      app.networkChanged(true);try check(native.store.generation==generation,"F14 duplicate online event coalesces loading")
      try await until{native.store.document?.generation != a.generation && native.session.state == .reading};try await ready(native)
      try check(native.session.context != oldContext,"F14 production composition prepares/adopts fresh request")
      // A real missing fixture exercises Session's constrained retry delay,
      // rather than a successful command or a fabricated readiness response.
      let bytes=try Data(contentsOf:input);try FileManager.default.removeItem(at:input)
      let beforeFailure=native.store.generation
      app.networkChanged(true);try await until{native.store.generation >= beforeFailure+2}
      let failedGeneration=native.store.generation,backoffStart=Date()
      try await Task.sleep(nanoseconds:1_500_000_000)
      try check(native.store.generation==failedGeneration && native.store.document != nil,"F14 constrained backoff retains accepted view without immediate duplicate retry")
      try bytes.write(to:input);try await until{native.session.state == .reading && native.session.failure==nil};try await ready(native)
      try check(Date().timeIntervalSince(backoffStart)>=3.5,"F14 pre-Read constrained power uses actual 4s rather than 1s retry")
      _ = try featurePaint(native.textView.bodyTextView,out.appendingPathComponent("lifecycle-recovered.png"));try await until{read.isEnabled}
      let recovered=native.store.document!
      native.cancel();app.networkChanged(true);app.sleepChanged(true);app.sleepChanged(false)
      try await Task.sleep(nanoseconds:30_000_000);try check(native.store.document==recovered && native.session.state != .loading,"F14 cancel rejects late events")
      try step("read-after-cancel");try await until{read.isEnabled};read.performClick(nil);try await until{native.session.state == .reading};try await ready(native)
      native.hostWindow.window!.close();let closed=native.store.generation,closedTarget=targetCalls,closedPreparation=preparations
      app.networkChanged(true);app.sleepChanged(true);app.sleepChanged(false)
      try await Task.sleep(nanoseconds:30_000_000);try check(native.store.generation==closed && targetCalls==closedTarget && preparations==closedPreparation && native.paintedKey==nil,"F14 close cannot revive Read")
      var other=profile;other.id="other";other.port+=1;other.label="test.other"
      try step("profile-switch");app.settings.profiles.append(other);app.populate();app.picker.selectItem(at:1);app.selectProfile()
      try await until{!app.mutating && app.active?.id==other.id}
      app.networkChanged(true);app.sleepChanged(true);app.sleepChanged(false)
      try step("profile-switched");try check(app.nativeProfile==profile && native.store.generation==closed,"F14 selected unread profile cannot reuse old intent")
    case "D1":
      try check(text.textAppearance.theme == .light && host.hostWindow.selectedThemeIndex==0,"D1 independent Light initial")
      try click("Aa");try check(host.hostWindow.isDisplayPopoverOpen,"Aa popover opens")
      try click("Dark");try await ready(host)
      host.refresh();try await until{host.store.document?.generation != document.generation};try await ready(host)
      try check(text.textAppearance.theme == .dark && host.hostWindow.selectedThemeIndex==1 && host.hostWindow.window?.appearance?.name == .darkAqua,"D1 refresh keeps immediate Dark")
      let anchorBefore = text.viewportAnchor()
      try click("Font +");try click("Font +");try await ready(host)
      try check(anchorBefore != nil && text.viewportAnchor()?.position.blockID == anchorBefore?.position.blockID,"D1 font step preserves viewport anchor block identity")
      try check(text.textAppearance.theme == .dark && text.textAppearance.fontSize==18,"D1 subsequent font step keeps displayed Dark theme")
      try click("Font +");try await ready(host)
      try check(text.textAppearance.theme == .dark && text.textAppearance.fontSize==24,"D1 font step to 24pt keeps displayed Dark theme")
      try check((featureViews(host.hostWindow.displayPopoverContentView).compactMap{$0 as? NSTextField}.first{$0.identifier?.rawValue=="fontSizeLabel"}?.stringValue)=="24pt","Aa font size label updates immediately")
      try click("Aa");try check(!host.hostWindow.isDisplayPopoverOpen,"Aa popover closes")
    case "display-preview":
      for removed in ["previewDisplayExplicitly","applyDisplayExplicitly","cancelDisplayExplicitly"] {
        try check(!featureViews(root).contains{$0.identifier?.rawValue==removed} && !featureViews(host.hostWindow.displayPopoverContentView).contains{$0.identifier?.rawValue==removed},"Obsolete display preview control removed: "+removed)
      }
      try firstSelection();let selected=host.store.selection!
      try click("Aa");try check(host.hostWindow.isDisplayPopoverOpen,"F15 immediate Aa popover opens")
      let themeTitles = ["themeLight","themeDark","themeAutomatic"].compactMap { id in featureViews(host.hostWindow.displayPopoverContentView).compactMap{$0 as? NSButton}.first{$0.identifier?.rawValue==id}?.title }
      try check(themeTitles==["밝게","어둡게","자동"],"F15 real theme choices")
      try click("Dark");try click("Font +");try click("Font +");try click("Zoom +");try await ready(host)
      try check(text.textAppearance.theme == .dark && text.textAppearance.fontSize==18 && text.textAppearance.zoom>1,"F15 immediate Aa popover applies theme/font/zoom")
      try check(host.store.selection==selected && text.logicalText==logical,"F15 immediate Aa preserves exact canonical selection/logical text")
      try click("Automatic");try click("Font +");try click("Zoom +");try await ready(host)
      try check(host.hostWindow.window!.appearance==nil && host.hostWindow.selectedThemeIndex==2,"F15 Automatic inherits this window only")
      try click("Aa");try check(!host.hostWindow.isDisplayPopoverOpen,"Aa popover closes")
      try click("Fit");try await ready(host);try check(text.textAppearance.zoom==1 && host.hostWindow.window!.appearance==nil && text.textAppearance.fontSize==24,"F15 reflow Fit uses existing zoom1 owner while keeping committed Automatic")
    case "appearance":
      try firstSelection();let selected=host.store.selection!
      try click("Aa");try click("Dark");try await ready(host)
      try check(text.textAppearance.theme == .dark && host.hostWindow.window?.appearance?.name == .darkAqua,"window-local theme")
      try click("Font +");try click("Font +");try await ready(host);try check(text.textAppearance.fontSize==18,"font control binds render key")
      try click("Aa")
      try click("Zoom +");try await ready(host);try check(text.textAppearance.zoom==1.25,"native reflow zoom")
      try click("Zoom −");try await ready(host);try click("Fit");try await ready(host)
      try check(text.textAppearance.zoom==1 && text.logicalText==logical && host.store.selection==selected,"appearance retains logical AX selection")
    case "offline", "cancel":
      try firstSelection();try click("Mark for review");try click("Save Offline");try await storageIdle()
      let saved=try await disk.load(identity:document.identity),bytes=try fileBytes()
      try check(saved.reviewMarks.count==1 && saved.restoration.fragments.count==1,"UI save includes review/selection")
      try click("Refresh Saved");try await storageIdle()
      let savedSub=host.hostWindow.moreMenu.items.first{$0.title=="저장 문서 열기"}?.submenu
      try check(host.hostWindow.savedDocuments.numberOfItems==1 && savedSub?.items.count==1,"UI validated list")
      if mode=="cancel"{
        gate.blocked=true;try click("Save Offline");try await until{gate.entered};var tick=false;Task{@MainActor in tick=true};await Task.yield();try check(tick,"storage wait leaves main runloop responsive")
        try click("Cancel");gate.release();try await Task.sleep(nanoseconds:30_000_000)
        let currentBytes=try fileBytes();try check(currentBytes==bytes,"cancelled write preserves prior atomic file")
      }
      var calls=0,events=[NativeReadProgress]()
      let resolver=NativeReaderManagedResolver(attach:{_ in calls+=1;throw NativeReaderOperationFailure.unavailable},network:.init(send:{_,_ in calls+=1;throw NativeReaderOperationFailure.unavailable},stream:{_ in AsyncThrowingStream{$0.finish()}}))
      let managed=NativeReaderManagedClient(resolver:resolver,root:out.path,entry:"main.typ")
      let restored=NativeReaderWindowController(provider:managed,target:{_ in calls+=1;return try await managed.target()},assets:{_,_ in calls+=1;throw NativeReaderOperationFailure.unavailable},runtime:runtime,actions:{calls+=1;throw NativeReaderOperationFailure.unavailable},show:false,avoidActivation:true,offlineStorage:storage)
      var nativeDraws=0
      let originalPaint=restored.textView.callbacks.painted
      restored.textView.callbacks.painted={key in nativeDraws+=1;originalPaint(key)}
      defer{restored.dispose()};restored.openOfflineLibrary(profile){events.append($0)}
      let rr=restored.hostWindow.window!.contentView!
      try await until{(try? featureButton(rr,"Open Saved").isEnabled)==true}
      if mode=="cancel"{
        gate.entered=false;gate.blocked=true;try featureButton(rr,"Open Saved").performClick(nil);try await until{gate.entered}
        restored.hostWindow.window!.close();gate.release();try await Task.sleep(nanoseconds:30_000_000)
        try check(restored.store.document==nil,"closed view rejects late disk load")
        restored.openOfflineLibrary(profile){events.append($0)};try await until{(try? featureButton(rr,"Open Saved").isEnabled)==true}
      }
      try featureButton(rr,"Open Saved").performClick(nil)
      try await until{restored.store.document != nil && restored.session.state == .offline};try await ready(restored)
      try check(calls==0 && restored.session.isReadOnly,"fresh managed offline UI uses zero target/network/assets/actions")
      try check(restored.localReview.marks.count==1 && restored.store.selection?.fragments==host.store.selection?.fragments,"UI restoration preserves marks/selection")
      try check(restored.textView.bodyTextView.selectedRange().length>0,"restored native selection presentation")
      let acknowledgments=events.filter{if case .painted=$0{return true};return false}.count
      try check(acknowledgments<=nativeDraws,"accepted/layout cannot acknowledge without actual native draw callback")
      _ = try featurePaint(restored.textView.bodyTextView,out.appendingPathComponent("offline-painted.png"))
      try check(events.contains{if case .painted=$0{return true};return false},"visible-mode native draw acknowledgment")
      for title in ["Source","Highlight","Ask","Locate Source","Last Edit","Account"]{let b=try featureButton(rr,title);try check(!b.isEnabled,"offline disabled "+title);b.performClick(nil)}
      try check(calls==0,"read-only UI creates no source/chat/account calls")
      var bad=saved.assets;let asset=document.assets[0];bad[asset.id]=Data("bad".utf8)
      do{try await disk.save(.init(document:document,assets:bad,restoration:.initial,drafts:[]));throw FlowError(message:"corrupt save accepted")}catch NativeReaderContractError.invalidDocument{}
      let currentBytes=try fileBytes();try check(currentBytes==bytes,"invalid asset save retains previous bytes")
    case "long":
      try click("Save Offline");try await storageIdle();let bytes=try fileBytes()
      let first=document.blocks[0],last=document.blocks[32]
      try text.select(from:.init(blockID:first.id,utf16:0,affinity:.upstream),to:.init(blockID:last.id,utf16:last.displayText.utf16.count,affinity:.downstream))
      try check(host.store.selection?.fragments.count==33,"actual compiler33 local display selection")
      try click("Save Offline");try check(host.hostWindow.notice.stringValue.contains("32개 블록") || host.hostWindow.notice.stringValue.contains("32 blocks"),"explicit stored-selection cap rejection")
      let currentBytes=try fileBytes();try check(currentBytes==bytes && host.store.selection?.fragments.count==33,"over-cap save retains file and full display selection")
      try click("Release selection");var appearance=text.textAppearance;appearance.zoom=0.25;try text.setAppearance(appearance);host.hostWindow.onAppearance?();try await ready(host)
      try click("Save Offline");let quarterBytes=try fileBytes();try check(quarterBytes==bytes,"display0.25 does not relax typed recovery0.5")
    case "drafts":
      let id=UUID(),pending=UUID();let draft=NativeReaderRecoveredDraft(conversationID:id,version:2,text:"newer private question N",pendingMessageID:pending,model:"fixture-model",pendingQuestion:"original uncertain question M",pendingModel:"fixture-model")
      var assets=[String:Data]();for a in document.assets{assets[a.id]=try Data(contentsOf:fixture.deletingLastPathComponent().appendingPathComponent("assets").appendingPathComponent(a.id))}
      try await disk.save(.init(document:document,assets:assets,restoration:.initial,drafts:[draft]))
      try click("Refresh Saved");try await storageIdle();try click("Open Saved");try await until{host.session.state == .offline};try await ready(host)
      let picker=try featurePopup(root,"Recovered drafts");try featureSelect(picker,0)
      try check(featureViews(root).compactMap{$0 as? NSTextField}.contains{$0.stringValue.contains("newer private question N")},"recovered newer draft visible through native control")
      try click("Save Offline");try await storageIdle();let again=try await disk.load(identity:document.identity)
      try check(again.drafts.count==1 && again.drafts[0].pendingMessageID==pending && again.drafts[0].pendingQuestion=="original uncertain question M" && again.drafts[0].text==draft.text && again.drafts[0].pendingModel==draft.pendingModel,"typed pending UUID/question/model independent of newer draft survives UI open/save")
    case "remote", "remote-reopen":
      let marker=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[8]))) as! [String:Any]
      let attachment=try JSONSerialization.data(withJSONObject:marker["attachment"]!)
      let remoteProfile=try JSONDecoder().decode(Profile.self,from:JSONSerialization.data(withJSONObject:marker["profile"]!))
      let http=NativeReaderNetwork.urlSession();var requests=[[String:String]]();var lostSend=false
      let observed=NativeReaderNetwork(send:{request,limit in requests.append(["method":request.httpMethod ?? "GET","path":request.url!.path]);let response=try await http.send(request,limit);if mode=="remote-reopen", !lostSend, request.url!.path.hasSuffix("native-chat"), let body=request.httpBody, (try JSONSerialization.jsonObject(with:body) as? [String:Any])?["operation"] as? String == "send" {lostSend=true;throw URLError(.networkConnectionLost)};return response},stream:http.stream)
      let managed=NativeReaderManagedClient(resolver:.init(attach:{_ in attachment},network:observed),root:remoteProfile.root,entry:remoteProfile.entry)
      let remote=NativeReaderWindowController(provider:managed,target:{_ in try await managed.target()},assets:{doc,context in
        let actions=try await managed.currentActions();var bytes=[String:Data]();for a in doc.assets{bytes[a.id]=try await actions.transport.asset(a,context:context)};return bytes
      },runtime:runtime,actions:{try await managed.currentActions()},show:false,avoidActivation:true,offlineStorage:NativeReaderOfflineStorage(owner:disk))
      defer{remote.dispose()};var opened=[URL]();remote.openHomepage={opened.append($0)}
      _ = remote.open(remoteProfile){_ in};try await until{remote.session.state == .reading || remote.session.failure != nil}
      try check(remote.session.failure==nil,"production scoped backend accepted in actual host");try await ready(remote)
      let rr=remote.hostWindow.window!.contentView!
      try featureButton(rr,"Account").performClick(nil)
      try await until{requests.filter{$0["path"]?.hasSuffix("/api/chat/auth")==true}.count==2}
      try await until{remote.hostWindow.moreMenu.items.contains{$0.title=="계정: 계정 연결됨" || $0.title=="계정: 이용 가능한 플랜이 없습니다" || $0.title=="계정: 설정된 홈페이지에서 로그인하세요."}}
      try check(opened.isEmpty,"status/models do not open account or authenticate")
      let manage=try featureButton(rr,"Manage Account");if manage.isEnabled{manage.performClick(nil);try check(opened.count==1,"explicit configured Homepage callback only")}
      try featureButton(rr,"Last Edit").performClick(nil)
      try await until{remote.hostWindow.notice.stringValue.contains("No saved edit location")}
      try check(requests.contains{$0["path"]?.hasSuffix("/api/native-action")==true},"Last Edit reaches existing guarded production route")
      let probe=remote.store.document!.blocks.first{$0.kind == .paragraph && $0.displayText.contains("Source and chat probe")}!
      try remote.textView.select(from:.init(blockID:probe.id,utf16:0,affinity:.upstream),to:.init(blockID:probe.id,utf16:probe.displayText.utf16.count,affinity:.downstream))
      try featureButton(rr,"Ask").performClick(nil)
      try await until{remote.chatView != nil}
      try check(remote.chatView!.models.numberOfItems==0,"Ask opens local composer without eager account/model calls")
      var chat=remote.chatView!
      if mode=="remote-reopen"{
        chat.composer.string="uncertain original M";chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
        try await until{chat.sendButton.isEnabled};try featureButton(rr,"Send").performClick(nil)
        try await until{chat.recoveryDraft?.pendingMessageID != nil && chat.historyButton.isEnabled};fputs("C2 lost ack ready\n",stderr)
        chat.composer.string="newer draft N";chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
        try await ready(remote);try await until{(try? featureButton(rr,"Save Offline").isEnabled)==true}
        try featureButton(rr,"Save Offline").performClick(nil);try await until{(try? featureButton(rr,"Cancel").isEnabled)==false}
        let savedPending=try await disk.load(identity:remote.store.document!.identity);fputs("C2 saved pending\n",stderr)
        try check(savedPending.drafts.first?.pendingQuestion=="uncertain original M","C2 real lost ack captures original question separately")
        try featureButton(rr,"Release selection").performClick(nil);try await remote.restoreRecovery(savedPending);try await ready(remote)
        try featureButton(rr,"Release selection").performClick(nil);remote.refresh();fputs("C2 live refresh issued\n",stderr)
        try await until{remote.session.state == .reading};try await ready(remote);fputs("C2 live accepted\n",stderr)
        let p=remote.store.document!.blocks.first{$0.id==probe.id}!
        try remote.textView.select(from:.init(blockID:p.id,utf16:0,affinity:.upstream),to:.init(blockID:p.id,utf16:p.displayText.utf16.count,affinity:.downstream))
        try featureButton(rr,"Ask").performClick(nil);try await until{remote.chatView != nil}
        chat=remote.chatView!
        try check(chat.models.numberOfItems==0 && !chat.historyButton.isEnabled,"C2 Ask after refresh opens local composer without eager network calls")
        chat.composer.string="newer draft N";chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
        try await until{chat.sendButton.isEnabled};try featureButton(rr,"Send").performClick(nil)
        try await until{chat.models.numberOfItems>0 && chat.historyButton.isEnabled && chat.recoveryDraft?.pendingMessageID != nil}
        try featureButton(rr,"Refresh conversation").performClick(nil);fputs("C2 history issued\n",stderr)
        try await until{chat.historyButton.isEnabled && chat.recoveryDraft?.pendingMessageID==nil};fputs("C2 history resolved\n",stderr)
        chat.composer.string="latest draft N2";chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
        try await Task.sleep(nanoseconds:400_000_000)
        try featureButton(rr,"Refresh conversation").performClick(nil)
        try await until{chat.historyButton.isEnabled && chat.notice.stringValue=="Conversation refreshed."};try await ready(remote)
        try remote.textView.select(from:.init(blockID:p.id,utf16:0,affinity:.upstream),to:.init(blockID:p.id,utf16:p.displayText.utf16.count,affinity:.downstream))
        let old=chat;try featureButton(rr,"Ask").performClick(nil);do{try await until{remote.chatView !== old && remote.chatView != nil}}catch{throw FlowError(message:"C2 reopen failed: "+remote.hostWindow.notice.stringValue+" selected=\(remote.store.selection != nil)")}
        chat=remote.chatView!
        try check(chat.models.numberOfItems>0,"C2 resumed composer restores model choices")
        try check(chat.composer.string=="latest draft N2" && chat.recoveryDraft?.pendingMessageID==nil && chat.recoveryDraft?.pendingQuestion==nil,"C2 reopened same conversation preserves N2 and resolved pending M")
      }else{chat.composer.string="New live private draft from native composer"}

      chat.textDidChange(Notification(name:NSText.didChangeNotification,object:chat.composer))
      try await ready(remote)
      try await until{(try? featureButton(rr,"Save Offline").isEnabled)==true}
      try featureButton(rr,"Save Offline").performClick(nil);try await until{(try? featureButton(rr,"Cancel").isEnabled)==false}
      let composerSnapshot=try await disk.load(identity:remote.store.document!.identity)
      if mode=="remote-reopen"{
        try check(composerSnapshot.drafts.count==1 && composerSnapshot.drafts[0].text==chat.composer.string && composerSnapshot.drafts[0].model=="fixture-model","actual native composer getter is wired to UI offline save without Send")
      }else{
        try check(composerSnapshot.drafts.isEmpty && chat.composer.string=="New live private draft from native composer","local composer draft stays local without server conversation before Send")
      }
      let paragraph=remote.store.document!.blocks.first{$0.kind == .paragraph && !$0.displayText.isEmpty}!
      try remote.textView.select(from:.init(blockID:paragraph.id,utf16:0,affinity:.upstream),to:.init(blockID:paragraph.id,utf16:paragraph.displayText.utf16.count,affinity:.downstream))
      try featureButton(rr,"Mark for review").performClick(nil);try check(remote.localReview.marks.count==1,"local review on production HTTP publication")
      try featureButton(rr,"Aa").performClick(nil);try featureButton(rr,"Dark").performClick(nil);try featureButton(rr,"Aa").performClick(nil);try await ready(remote)
      try featureButton(rr,"Save Offline").performClick(nil)
      try await until{(try? featureButton(rr,"Cancel").isEnabled)==false}
      let saved=try await disk.list();try check(saved.count==1,"actual HTTP publication saved by native control")
      try JSONSerialization.data(withJSONObject:requests,options:.prettyPrinted).write(to:out.appendingPathComponent("owned-http-requests.json"))
    case "isolation":
      let environment=AppEnvironment(variables:["FLOW_DATA_DIR":out.appendingPathComponent("data").path,"FLOW_LOG_DIR":out.appendingPathComponent("logs").path],userHome:out.appendingPathComponent("user"),executable:out.appendingPathComponent("Lagrangian"))
      let one=NativeReaderRecoveryStore(root:environment.nativeRecoveryRoot(for:profile));var other=profile;other.id="other";let two=NativeReaderRecoveryStore(root:environment.nativeRecoveryRoot(for:other))
      try check(one.root != two.root,"profile/target namespace isolation")
      try await host.saveRecovery(to:one)
      let delegate=FlowApp(environment:environment,isolated:true,noActivate:true,nativeRuntime:runtime)
      delegate.settings.profiles=[profile];delegate.settings.selectedID=profile.id;delegate.buildWindow()
      defer{delegate.offlineWindow?.dispose();delegate.window.close()}
      try featureButton(delegate.window.contentView!,"오프라인 문서").performClick(nil)
      try await until{delegate.offlineWindow != nil}
      try check(delegate.nativeWindow==nil,"Home offline entry avoids live Read/provider")
      let offline=delegate.offlineWindow!,localRoot=offline.hostWindow.window!.contentView!
      try await until{(try? featureButton(localRoot,"Open Saved").isEnabled)==true}
      try featureButton(localRoot,"Open Saved").performClick(nil);try await until{offline.store.document != nil && offline.session.state == .offline};try await ready(offline)
      try check(offline.store.document?.identity==document.identity,"Home action opens saved profile snapshot")
      delegate.settings.profiles.append(other);delegate.settings.selectedID=other.id
      try featureButton(delegate.window.contentView!,"오프라인 문서").performClick(nil)
      let different=delegate.offlineWindow!;try await until{different.hostWindow.notice.stringValue.contains("저장된 문서가 없습니다") || different.hostWindow.notice.stringValue.contains("No saved")}
      try check(different.store.document==nil,"other profile Home action cannot open prior namespace")
      let empty=try await two.list();try check(empty.isEmpty,"other profile cannot enumerate saved namespace")
    default:throw FlowError(message:"unknown feature")
    }
    try check(NSApp.windows.allSatisfy{!$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow},"activation prohibited and visibleWindows0")
    try JSONSerialization.data(withJSONObject:["case":mode,"assertions":assertions,"visibleWindows":0,"actualControls":true,"GUIAcceptance":false],options:.prettyPrinted).write(to:out.appendingPathComponent("result.json"))
    print("feature pass "+mode+" assertions=\(assertions)")
  }
  @MainActor static func ready(_ host:NativeReaderWindowController)async throws{try await until{host.textView.renderKey != nil && host.textView.renderKey==host.textView.requestedRenderKey && host.acceptedPaintKey==host.textView.renderKey}}
}

'''

class FeatureWiringUI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output=Path(os.environ['NA06_PREP_OUTPUT'])/('features-'+str(time.time_ns()));cls.output.mkdir()
        cls.commands=[];swift=cls.output/'FeatureWiringTests.swift';swift.write_text(FEATURE_SWIFT)
        cls.binary=cls.output/'FeatureWiringTests'
        sys.path.insert(0,str(ROOT/'tools/flow-reader'))
        import shutil
        from flow_reader.compiler.build import compile_project
        from flow_reader.compiler.project import Project,document_identity
        from flow_reader.document.sections import split_document
        from flow_reader.document.native_document import import_accepted_document
        long=cls.output/'long';source=long/'source';source.mkdir(parents=True)
        shutil.copyfile(DEV/'test-output/long-selection-independent-v1/fixture-33/source/main.typ',source/'main.typ')
        wrapper=long/'offline-typst';compiler=shutil.which('typst')
        if not compiler:raise RuntimeError('explicit prebuilt compiler missing')
        sandbox="(version 1)(allow default)(deny network*)"
        wrapper.write_text('#!'+sys.executable+'\nimport os,sys\nos.execv("/usr/bin/sandbox-exec",["sandbox-exec","-p",'+repr(sandbox)+','+repr(compiler)+']+sys.argv[1:])\n');wrapper.chmod(0o700)
        cache=long/'typst-packages'
        shutil.copytree(Path(os.environ['FLOW_TEST_PACKAGE_CACHE']),cache)
        os.environ['TYPST_PACKAGE_CACHE_PATH']=str(cache)
        report=compile_project(Project(source,Path('main.typ'),ROOT/'tools/flow-reader/packages',compiler=str(wrapper)),long/'compiled',map_sources=False)
        (long/'compiler-report.json').write_text(json.dumps(report,indent=2))
        if report['exitCode']!=0 or not report['contentGatePassed']:raise RuntimeError('actual compiler fixture failed')
        bundle=split_document((long/'compiled/document.html').read_text(),report['revision'],max_blocks=16)
        model=import_accepted_document(bundle,document_id=document_identity(source,Path('main.typ')),service_id='offline-no-service',generation=1,identity_scope='fixture').document
        cls.longFixture=long/'native.json';cls.longFixture.write_text(json.dumps(model,ensure_ascii=False,indent=2))

        sources=[p for p in package.swift_sources() if p.name!='main.swift']
        if fixed := os.environ.get('FEATURE_WIRING_FIXED_SOURCES'):
            fixed=Path(fixed).resolve()
            if not any(fixed.is_relative_to(DEV/'test-output'/name) for name in ['feature-wiring-v1','closure-review-fixes-v2','native-app-corrections-v4']):raise RuntimeError('Fixed counterexample inputs must remain isolated')
            sources=[fixed/p.name for p in sources]
        cls.command(['/usr/bin/swiftc',*package.swift_flags(),*sources,swift,'-o',cls.binary])
    @classmethod
    def command(cls,argv):
        inputs={str(x):package.digest(Path(x)) for x in argv if str(x).endswith('.swift')}
        started=time.monotonic();p=subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True,text=True,timeout=180)
        cls.commands.append(dict(argv=list(map(str,argv)),cwd=str(ROOT),exit=p.returncode,elapsed=time.monotonic()-started,stdout=p.stdout,stderr=p.stderr,sourceBefore=inputs,sourceAfter={x:package.digest(Path(x)) for x in inputs},environment={k:os.environ.get(k) for k in ['TMPDIR','CLANG_MODULE_CACHE_PATH','SWIFT_MODULECACHE_PATH']}))
        (cls.output/'commands.json').write_text(json.dumps(cls.commands,indent=2))
        if p.returncode:raise AssertionError(p.stdout+p.stderr)
        return p
    def scenario(self,name):
        out=self.output/('case-'+name);out.mkdir()
        p=self.command([self.binary,name,os.environ['FLOW_NATIVE_FIXTURE'],out,os.environ['FLOW_TEST_NODE'],ROOT/'tools/flow-reader/native/math_layout.mjs',os.environ['FLOW_TEST_NATIVE_RUNTIME'],self.longFixture])
        self.assertIn('feature pass '+name,p.stdout)
    def test_production_http_account_history_and_local_controls(self):self.remote_scenario('remote')
    def test_C2_restored_pending_history_reopen_latest_draft(self):self.remote_scenario('remote-reopen')
    def remote_scenario(self,mode):
        import shutil
        root=GUI_ROOT/('feature-remote-'+str(time.time_ns()))
        gui_setup(root,shutil.which('typst'),os.environ['FLOW_TEST_PACKAGE_CACHE'])
        log=(root/'serve.log').open('w')
        argv=[sys.executable,'-B',str(GUI_SCRIPT),'gui-fixture','serve','--root',str(root),'--seconds','120']
        proc=subprocess.Popen(argv,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        started=time.monotonic();marker=None
        try:
            while time.monotonic()-started<30:
                marker=json.loads((root/'fixture.json').read_text())
                if marker.get('running'):break
                if proc.poll() is not None:raise AssertionError((root/'serve.log').read_text())
                time.sleep(.05)
            if not marker or not marker.get('running'):raise AssertionError('owned backend did not become ready')
            out=self.output/('case-'+mode);out.mkdir()
            self.command([self.binary,mode,os.environ['FLOW_NATIVE_FIXTURE'],out,os.environ['FLOW_TEST_NODE'],ROOT/'tools/flow-reader/native/math_layout.mjs',os.environ['FLOW_TEST_NATIVE_RUNTIME'],self.longFixture,root/'fixture.json'])
            effects=json.loads((root/'effects.json').read_text())
            self.assertEqual(len(effects['inference']),1 if mode=='remote-reopen' else 0,'only one explicit M Send may infer; history/reopen/local operations zero inference')
        finally:
            try:gui_stop(root)
            finally:
                try:code=proc.wait(timeout=15)
                except subprocess.TimeoutExpired:proc.terminate();code=proc.wait(timeout=5)
                log.close()
                (root/'process-result.json').write_text(json.dumps(dict(argv=argv,pid=proc.pid,exit=code,elapsed=time.monotonic()-started,root=str(root)),indent=2))
        self.assertEqual(code,0)
        for port in marker['ports']:
            import socket
            with socket.socket() as sock:
                sock.settimeout(.2);self.assertNotEqual(sock.connect_ex(('127.0.0.1',port)),0,'owned backend port remains open')

    def test_F14_FlowApp_native_lifecycle_recovery(self):self.scenario('lifecycle')
    def test_D1_refresh_rebases_display_preview(self):self.scenario('D1')
    def test_F15_preview_cancel_commit_automatic(self):self.scenario('display-preview')
    def test_C1_restore_resize(self):self.scenario('restore-resize')
    def test_C1_restore_hold_release(self):self.scenario('restore-hold')
    def test_C1_restore_cancel(self):self.scenario('restore-cancel')
    def test_C1_restore_close(self):self.scenario('restore-close')
    def test_invalid_review_snapshot_rejected_before_adoption(self):self.scenario('invalid-review')
    def test_native_review_buttons(self):self.scenario('review')
    def test_native_outline_and_return_controls(self):self.scenario('navigation')
    def test_native_appearance_controls(self):self.scenario('appearance')
    def test_native_offline_save_list_open_controls(self):self.scenario('offline')
    def test_native_storage_cancel_close_and_late_load(self):self.scenario('cancel')
    def test_native_recovery_limits_preserve_long_selection(self):self.scenario('long')
    def test_native_recovered_pending_and_newer_draft(self):self.scenario('drafts')
    def test_native_home_offline_profile_isolation(self):self.scenario('isolation')


# v5 feedback regression: reuse the read-only existing composition fixture in an
# owned instrumented copy. This does not launch the packaged app or order windows.
class IdentityHomeFeedbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import tempfile
        if not os.environ.get('LAGRANGIAN_NATIVE_SWIFT_LOCK_HELD'):
            raise RuntimeError('Wrap this Swift-containing top-level command once with the shared lock')
        if explicit := os.environ.get('NATIVE_IDENTITY_UI_OUTPUT'):
            root=Path(explicit).resolve()
            if not root.is_relative_to(DEV/'test-output/native-reader-identity-ui-v5'):
                raise RuntimeError('v5 UI evidence root only')
            root.mkdir(parents=True,exist_ok=True)
        else:
            cls.temp=tempfile.TemporaryDirectory(prefix='identity-ui-');cls.addClassCleanup(cls.temp.cleanup);root=Path(cls.temp.name)
        cls.out=root/('controls-'+str(time.time_ns()));cls.out.mkdir()
        original=ROOT/'tests/flow-app/FlowAppTests.swift'
        text=original.read_text()
        cases=r'''
    case "identity-loading", "identity-empty", "identity-services", "identity-isolated":
      delegate.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      defer { NSStatusBar.system.removeStatusItem(delegate.statusItem) }
      delegate.buildMenu();delegate.render(delegate.snapshot!)
      verifyMinimalHome(delegate, profile: profile)
      verifyStatusMenu(delegate)
      var observations: [[String: Any]] = []
      func homeText() -> String {
        allDescendants(of: delegate.window.contentView!).filter { !$0.isHiddenOrHasHiddenAncestor }.compactMap {
          if let field = $0 as? NSTextField { return field.stringValue }
          return ($0 as? NSButton)?.title
        }.joined(separator: "\n")
      }
      func capture(_ name: String) {
        let text = homeText()
        check(!text.contains(profile.root) && !text.contains(profile.url) && !text.contains("owned load failure"), "Home leaked raw path, URL or English exception")
        check(delegate.statusItem.button?.title == "" && delegate.statusItem.button?.image?.isTemplate == true, "icon-only template menubar")
        check(delegate.overflowButton.toolTip == "더 보기" && !delegate.overflowButton.isHidden, "unified overflow must remain available")
        verifyOverflow(delegate)
        let controls: [NativeDesignButton] = [delegate.serviceToggleButton,
          delegate.controls[#selector(FlowApp.openExternalPreview)] as! NativeDesignButton,
          delegate.controls[#selector(FlowApp.copyPreviewAddress)] as! NativeDesignButton]
        observations.append(["state":name,"home":text,"status":delegate.status.stringValue,
          "brand":delegate.brandMark.phase.rawValue,"brandTooltip":delegate.brandMark.toolTip!,
          "windowHeight":delegate.window.frame.height,"services":services.actions,"probes":probes.count,
          "buttons":controls.map { ["symbol":$0.symbolName!,"enabled":$0.isEnabled,"targetMatches":$0.target === delegate,"action":NSStringFromSelector($0.action!)] },
          "mainWindowVisible":delegate.window.isVisible,"activationProhibited":NSApp.activationPolicy() == .prohibited])
        try! JSONSerialization.data(withJSONObject:observations,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
      }
      if CommandLine.arguments[1] == "identity-loading" {
        let entered=DispatchSemaphore(value:0);let releaseLoad=DispatchSemaphore(value:0)
        delegate.settings=Settings();delegate.populate()
        delegate.mutate("프로젝트 설정을 불러오는 중…",work:{
          entered.signal();_ = releaseLoad.wait(timeout:.now()+5)
          return Settings(selectedID:profile.id,profiles:[profile,other])
        },success:{ delegate.settings=$0;delegate.populate() })
        var didEnter=false
        waitUntil("storage load entered") { if !didEnter { didEnter=entered.wait(timeout:.now()) == .success };return didEnter }
        capture("loading")
        check(!delegate.picker.isEnabled && !delegate.controls[#selector(FlowApp.openPreview)]!.isEnabled,"loading controls")
        check(homeText().contains("불러오는") && delegate.brandMark.phase == .busy && delegate.window.frame.height == 272,"loading banner")
        check(services.actions.isEmpty && probes.isEmpty,"loading must not start services")
        releaseLoad.signal();waitUntil("ready after load") { !delegate.mutating && delegate.snapshot?.phase == .stopped }
        capture("ready-after-load")
        check(delegate.picker.isEnabled && delegate.controls[#selector(FlowApp.openPreview)]!.isEnabled,"ready controls")
        check(delegate.status.isHiddenOrHasHiddenAncestor && delegate.window.frame.height == 228,"ready banner collapse")
        let failedLoad=DispatchSemaphore(value:0);let failRelease=DispatchSemaphore(value:0)
        delegate.mutate("프로젝트 설정을 불러오는 중…",work:{ () throws -> Bool in
          failedLoad.signal();_ = failRelease.wait(timeout:.now()+5);throw FlowError(message:"owned load failure")
        },success:{ _ in fatalError("failed load adopted") })
        var didFailEnter=false
        waitUntil("failing load entered") { if !didFailEnter { didFailEnter=failedLoad.wait(timeout:.now()) == .success };return didFailEnter }
        capture("loading-existing-profile");failRelease.signal()
        waitUntil("load error") { !delegate.mutating && delegate.snapshot?.phase == .failed }
        capture("error-after-load")
        check(delegate.status.stringValue == "작업을 완료하지 못했습니다. 로그를 확인해 주세요.","Korean error summary")
        check(delegate.snapshot!.detail.contains("owned load failure"),"diagnostic remains available to session")
        check(delegate.controls[#selector(FlowApp.openPreview)]!.title == "다시 읽기" && delegate.controls[#selector(FlowApp.openPreview)]!.isEnabled,"retry action")
        check(delegate.brandMark.phase == .error && delegate.serviceToggleButton.symbolName == "exclamationmark.triangle.fill","error icon transitions")
        let logs=delegate.controls[#selector(FlowApp.openLogs)]!
        check(!logs.isHiddenOrHasHiddenAncestor && logs.action == #selector(FlowApp.openLogs) && logs.toolTip == "로그 보기","inline logs action")
        check(services.actions.isEmpty && probes.isEmpty,"load error emitted service effect")
      } else if CommandLine.arguments[1] == "identity-empty" {
        delegate.settings=Settings();delegate.populate();capture("empty")
        check(!delegate.controls[#selector(FlowApp.openPreview)]!.isEnabled && delegate.controls[#selector(FlowApp.addProject)]!.isEnabled,"empty controls")
        check(delegate.brandMark.phase == .idle && delegate.brandMark.toolTip == "Lagrangian · 프로젝트 없음","empty identity")
        check(delegate.picker.title.contains("추가") && delegate.window.frame.height == 228,"empty next step")
        verifyStatusMenu(delegate)
        delegate.session.reportFailure(FlowError(message:"owned load failure"));capture("empty-error")
        check(!delegate.controls[#selector(FlowApp.openPreview)]!.isEnabled,"empty retry disabled")
        check(!delegate.status.isHiddenOrHasHiddenAncestor && delegate.window.frame.height == 272 && delegate.brandMark.phase == .error,"empty error banner")
        check(services.actions.isEmpty && probes.isEmpty,"empty error emitted effect")
      } else if CommandLine.arguments[1] == "identity-isolated" {
        let isolated=FlowApp(environment:environment,projectService:ProjectService(store:storage,launchAgents:services),isolated:true,showNativeWindow:false)
        var progress:((NativeReadProgress)->Void)?
        isolated.session=ReadingSessionController(launchAgents:services,onChange:{ [weak isolated] in isolated?.render($0) },openBrowser:{ _ in fatalError("isolated browser") },nativeRead:{ _,callback in progress=callback;return {} },probe:{ _,_ in fatalError("native legacy probe") })
        isolated.settings=Settings(selectedID:profile.id,profiles:[profile]);isolated.buildWindow();isolated.populate()
        defer { isolated.session.dispose();isolated.settingsWindow?.close();isolated.window.close() }
        let read=isolated.controls[#selector(FlowApp.openPreview)]!
        read.performClick(nil);waitUntil("native preparation") { progress != nil }
        check(!read.isEnabled && !isolated.serviceToggleButton.isEnabled && isolated.picker.isEnabled,"isolated busy controls")
        check(isolated.brandMark.phase == .busy && !isolated.status.isHiddenOrHasHiddenAncestor && isolated.status.stringValue.contains("준비"),"native progress banner")
        let login=delegate.statusItem.menu!.items.first { $0.action == #selector(FlowApp.toggleLogin) }!
        check(!isolated.validateMenuItem(login),"isolated login must remain disabled")
        check(services.actions.isEmpty && !isolated.window.isVisible,"isolated service/window effect")
        progress?(.accepted);progress?(.windowInitialized);progress?(.painted)
        waitUntil("native paint") { isolated.snapshot?.phase == .painted }
        check(isolated.window.frame.height == 228 && isolated.status.isHiddenOrHasHiddenAncestor,"paint collapses progress")
        capture("isolated-completed")
      } else {
        capture("ready")
        let slot=delegate.serviceToggleButton
        let external=delegate.controls[#selector(FlowApp.openExternalPreview)]!
        let copy=delegate.controls[#selector(FlowApp.copyPreviewAddress)]!
        check(slot.symbolName == "play.fill" && slot.action == #selector(FlowApp.start),"stopped slot")
        check(!external.isEnabled && !copy.isEnabled,"stopped dock permission")
        var commandCount=0
        for selector in [#selector(FlowApp.start),#selector(FlowApp.stop),#selector(FlowApp.restart)] {
          if selector == #selector(FlowApp.restart) {
            let item=delegate.overflowMenu().items.first { $0.action == selector }!
            check(item.title == "미리보기 재시작" && delegate.validateMenuItem(item),"restart menu")
            check(NSApp.sendAction(selector,to:item.target,from:item),"restart target/action")
          } else {
            check(slot.action == selector && slot.isEnabled && slot.target === delegate,"dynamic service slot wiring")
            slot.performClick(nil)
          }
          check(!slot.isEnabled && slot.symbolName == "arrow.triangle.2.circlepath","busy slot transition")
          commandCount += 1
          waitUntil("service effect") { services.actions.count == commandCount }
          if selector != #selector(FlowApp.stop) {
            let expectedProbes=commandCount == 1 ? 1 : 2
            waitUntil("readiness probe") { probes.count == expectedProbes };probes.last?(.ready)
          }
          waitUntil("service settled") { delegate.snapshot?.isBusy == false && delegate.snapshot?.phase == (selector == #selector(FlowApp.stop) ? .stopped : .ready) }
          let running=selector != #selector(FlowApp.stop)
          check(slot.symbolName == (running ? "stop.fill" : "play.fill") && slot.showsRunningIndicator == running,"service icon/dot")
          check(external.isEnabled == running && copy.isEnabled == running,"dynamic dock availability")
          check(delegate.brandMark.phase == (running ? .completed : .offline),"dynamic header")
          capture(NSStringFromSelector(selector)+"-settled")
        }
        check(services.actions == ["start","stop","restart"] && opens.isEmpty && delegate.readingIntent == 3,"service effects")
        let read=delegate.controls[#selector(FlowApp.openPreview)]!
        read.performClick(nil);waitUntil("explicit Read probe") { probes.count == 3 }
        capture("reading-busy")
        check(!read.isEnabled && !slot.isEnabled && delegate.picker.isEnabled,"reading control policy")
        check(!delegate.status.isHiddenOrHasHiddenAncestor && delegate.window.frame.height == 272,"reading banner")
        probes.last?(.ready);waitUntil("Read completes") { opens.count == 1 }
        capture("read-ready")
        check(services.actions == ["start","stop","restart","start"] && delegate.readingIntent == 4,"explicit Read lifecycle")
      }
      check(!delegate.window.isVisible && NSApp.activationPolicy() == .prohibited,"offscreen policy")
'''
        text=text.replace('    case "timeline-owner":',cases+'\n    case "timeline-owner":',1)
        if text==original.read_text():raise RuntimeError('Existing fixture instrumentation point changed')
        source=cls.out/'FlowAppTests.swift';source.write_text(text);cls.binary=cls.out/'FeedbackTests'
        sources=package.swift_sources();sources=[p for p in sources if p.name!='main.swift']
        if before := os.environ.get('NATIVE_IDENTITY_UI_FIXED_FLOWAPP'):
            before=Path(before).resolve()
            if not before.is_relative_to(DEV/'test-output/native-reader-identity-ui-v5'):raise RuntimeError('Frozen FlowApp evidence root only')
            sources=[before if p.name=='FlowApp.swift' else p for p in sources]
        argv=['/usr/bin/swiftc',*package.swift_flags(),'-parse-as-library',*sources,source,'-o',cls.binary]
        start=time.monotonic();result=subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True,text=True,timeout=180)
        (cls.out/'compile.json').write_text(json.dumps(dict(argv=list(map(str,argv)),exit=result.returncode,elapsed=time.monotonic()-start,stdout=result.stdout,stderr=result.stderr,productionInputs={str(p):package.digest(p) for p in sources},originalReadOnlyFixture=dict(path=str(original),sha256=package.digest(original)),instrumentedHarness=dict(path=str(source),sha256=package.digest(source)),environment={k:os.environ.get(k) for k in ['TMPDIR','CLANG_MODULE_CACHE_PATH','SWIFT_MODULECACHE_PATH']}),indent=2))
        if result.returncode:raise RuntimeError(result.stderr)

    def scenario(self,name):
        folder=self.out/(name+'-'+str(time.time_ns()));folder.mkdir()
        argv=[str(self.binary),'identity-'+name,str(folder/'controls.json')]
        start=time.monotonic();r=subprocess.run(argv,cwd=ROOT,capture_output=True,text=True,timeout=20)
        (folder/'command.json').write_text(json.dumps(dict(argv=argv,exit=r.returncode,elapsed=time.monotonic()-start,stdout=r.stdout,stderr=r.stderr,actualGUI=False),indent=2))
        self.assertEqual(r.returncode,0,r.stdout+r.stderr)
    def test_loading_ready_error_controls(self):self.scenario('loading')
    def test_empty_error_controls(self):self.scenario('empty')
    def test_service_labels_and_actual_actions(self):self.scenario('services')
    def test_isolated_busy_feedback(self):self.scenario('isolated')
    def test_editor_consent_close_paths(self):
        result=subprocess.run([str(self.binary),'editor-consent-menu'],cwd=ROOT,capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

if __name__ == '__main__':
    import sys
    if sys.argv[1:2]==['gui-fixture']:gui_cli(sys.argv[2:])
    else:unittest.main()
