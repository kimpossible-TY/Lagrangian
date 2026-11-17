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

func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
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
    let result: [String: Any] = ["assertions": 27, "actualFixture": true, "sharedStore": true,
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
