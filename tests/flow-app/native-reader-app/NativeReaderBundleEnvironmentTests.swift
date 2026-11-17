import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

func checkDelivery(_ value: Bool, _ message: String) throws {
  if !value { throw FlowError(message: message) }
}

@main struct DeliveryInstalledProbe {
  static func main() async {
    do { try await run() } catch { fputs("DELIVERY PROBE: \(error)\n", stderr); exit(1) }
  }
  @MainActor static func run() async throws {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
    let app = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    let executable = app.appendingPathComponent("Contents/MacOS/Lagrangian")
    guard let environment = try NativeReaderBundleEnvironment.load(executable: executable) else {
      throw FlowError(message: "required default bundled environment absent")
    }
    try checkDelivery(environment.manager.path.hasPrefix(app.path + "/"), "manager escaped relocated app")
    let paths = [environment.node, environment.helper, environment.runtime, environment.manager]
    try checkDelivery(paths.allSatisfy { $0.path.hasPrefix(app.path + "/") }, "runtime escaped relocated app")
    let bytes = try Data(contentsOf: output.appendingPathComponent("math.json"))
    let sample = try NativeReaderDocument.decode(Data(contentsOf: output.appendingPathComponent("document.json")))
    let identity = sample.identity
    let context = NativeObjectContext(identity: identity, snapshotGeneration: 1, generation: 1,
      width: 320, fontSize: 20, fontName: "system", theme: .light, mode: .reflow, pageHeight: 1200)
    let math = try JSONDecoder().decode(NativeMath.self, from: Data(contentsOf: output.appendingPathComponent("paint-math.json")))
    let layout = try NativeMathLayout.decode(bytes, math: math, context: context, width: 320)
    let whole = layout.whole
    let scene = try NativeVectorScene.decode(Data(whole.svg.utf8), dark: false)
    try checkDelivery(scene.image == nil && !scene.shapes.isEmpty, "native glyph paths missing")
    let scale = 4.0, width = Int(ceil(whole.width * scale + 24)), height = Int(ceil((whole.ascent + whole.descent) * scale + 24))
    guard let graphics = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw FlowError(message: "paint context")
    }
    graphics.setFillColor(CGColor(gray: 1, alpha: 1)); graphics.fill(CGRect(x: 0, y: 0, width: width, height: height))
    graphics.translateBy(x: 0, y: CGFloat(height)); graphics.scaleBy(x: 1, y: -1)
    scene.draw(in: graphics, rect: CGRect(x: 12, y: 12, width: whole.width * scale, height: (whole.ascent + whole.descent) * scale))
    let pixels = graphics.data!.assumingMemoryBound(to: UInt8.self)
    let axis = 12 + whole.ascent * scale - 0.25 * 20 * scale
    var above = 0, below = 0, rule = 0
    for y in 0..<height { for x in 0..<width {
      if pixels[y * graphics.bytesPerRow + x * 4] < 128 {
        if Double(y) < axis - 2 { above += 1 } else if Double(y) > axis + 2 { below += 1 } else { rule += 1 }
      }
    } }
    try checkDelivery(above > 10 && below > 10 && rule > 10, "fraction lacks numerator/rule/denominator ink")
    guard let image = graphics.makeImage(), let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent("installed-native-math.png") as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw FlowError(message: "PNG output")
    }
    CGImageDestinationAddImage(dest, image, nil); try checkDelivery(CGImageDestinationFinalize(dest), "PNG persistence")
    var result: [String: Any] = ["defaultBundleEnvironment": true, "sourceRevision": environment.sourceRevision,
      "above":above, "below":below, "rule":rule, "nativeShapes":scene.shapes.count,
      "GUI":false, "macOS13Execution":"unverified", "requiredSkip":0]
    if CommandLine.arguments.count > 3 {
      let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("attachment.json"))) as! [String: Any]
      let attachment = try JSONSerialization.data(withJSONObject: fixture["attachment"]!)
      let project = fixture["root"] as! String
      let resolver = NativeReaderManagedResolver(attach: { arguments in
        try checkDelivery(arguments == ["--attach", "--root", project, "--entry", "main.typ"], "unexpected attach contract")
        return attachment
      }, network: .urlSession())
      let client = NativeReaderManagedClient(resolver: resolver, root: project, entry: "main.typ")
      let target = try await client.target()
      let request = NativeReaderRequestContext(requestID: UUID(), viewID: UUID(), generation: 1, target: target)
      let document = try await client.document(for: request)
      try checkDelivery(document.identity == target && target == sample.identity && !document.blocks.isEmpty && document.blocks.flatMap(\.orderedNodes).contains { $0.math == math }, "scoped native document missing")
      result["nativeDocumentBlocks"] = document.blocks.count
      result["nativeDocumentID"] = target.documentID
      result["managedAttachProcessProvider"] = "contract fake; actual loopback backend"
      let pages = try await client.originalPages(for: request)
      let supplement = try await pages.supplement(context: request, viewGeneration: 0)
      let preparer = NativeOriginalPagePreparer()
      var limits = NativeOriginalPageLimits(); limits.lazy = true
      let prepared = try await preparer.prepare(supplement, expected: supplement.binding, limits: limits)
      let view = NativeReaderOriginalPageView(viewID: request.viewID)
      let ticket = try view.store.begin(expected: supplement.binding)
      try view.store.adopt(prepared, for: ticket)
      view.installed()
      for _ in 0..<500 {
        if view.isPreparedForPaint { break }
        try await Task.sleep(nanoseconds: 10_000_000)
      }
      try checkDelivery(view.isPreparedForPaint, "original PDF raster unavailable")
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw FlowError(message: "original PDF bitmap")
      }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try checkDelivery(view.paintCount > 0 && view.store.paintAcknowledgment != nil, "original PDF did not paint")
      try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("installed-original-page.png"))
      try pages.data.write(to: output.appendingPathComponent("installed-original.pdf"))
      try JSONEncoder().encode(pages.publication).write(to: output.appendingPathComponent("installed-original-publication.json"))
      result["originalPDFPages"] = supplement.binding.pages.count
      result["originalPDFSHA256"] = pages.publication.pdfSHA256
      result["originalPDFPaintCount"] = view.paintCount
      result["originalSourceAnchors"] = pages.publication.sourceAnchors
      result["originalDelivery"] = pages.publication.delivery
      view.dispose()
      await client.dispose()
    }
    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("installed-native-results.json"))
    print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
  }
}
