import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Headless bitmap paint only; no NSApplication, window, browser or GUI automation.
@main struct ObjectProbe {
    static func main() throws {
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = manifestURL.deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        let objects = manifest["objects"] as! [[String: Any]]
        var results = [[String: Any]]()
        for object in objects {
            let id = object["id"] as! String, format = object["format"] as! String
            let file = URL(fileURLWithPath: object["path"] as! String)
            var result: [String: Any] = ["id": id, "format": format, "widthPt": object["widthPt"]!, "status": "unsupported"]
            let width = 1024, height = 1024
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain: "ObjectProbe", code: 1)
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            var painted = false
            if format == "pdf", let pdf = CGPDFDocument(file as CFURL), let page = pdf.page(at: 1) {
                let box = page.getBoxRect(.mediaBox)
                context.saveGState()
                context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: min(box.width, 1000), height: min(box.height, 1000)), rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page); context.restoreGState(); painted = true
                result["decoder"] = "CGPDFDocument/drawPDFPage"
            } else if format == "svg", let image = NSImage(contentsOf: file) {
                // HTML SVG CSS em dimensions are not AppKit point dimensions.
                // Use compiler's explicit point viewport, supplied by the helper.
                if let viewport = object["viewportPt"] as? [Double], viewport.count == 2,
                   viewport.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 8192 }) {
                    image.size = NSSize(width: viewport[0], height: viewport[1])
                    result["viewportPt"] = viewport
                }
                var rect = NSRect(origin: .zero, size: image.size)
                if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: min(rect.width, 1000), height: min(rect.height, 1000)))
                    painted = true; result["decoder"] = "NSImage/cgImage/CGContext.draw"
                }
            }
            if painted, let bytes = context.data?.assumingMemoryBound(to: UInt8.self) {
                var ink = 0, blue = 0
                for index in stride(from: 0, to: width * height * 4, by: 4) {
                    if bytes[index] < 240 || bytes[index + 1] < 240 || bytes[index + 2] < 240 { ink += 1 }
                    if Int(bytes[index + 2]) > Int(bytes[index]) + 20 && Int(bytes[index + 2]) > Int(bytes[index + 1]) + 20 { blue += 1 }
                }
                // Independent shape oracle: fixture specifies a blue 48x24 rectangle.
                let shapeOK = object["kind"] as? String != "shape" || blue >= 500
                result["inkPixels"] = ink; result["bluePixels"] = blue
                result["status"] = ink > 0 && shapeOK ? "pass" : "unsupported"
                if let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(root.appendingPathComponent(id + "-paint.png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "ObjectProbe", code: 2) }
                }
            } else { result["reason"] = "native decoder unavailable for this compiler artifact" }
            results.append(result)
        }
        let output: [String: Any] = ["scope": "actual compiler object paint on current host; no formula fidelity/inline breaking/selection/AX/GUI/macOS13 runtime claim", "results": results]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("native-paint.json"))
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
        if results.contains(where: { $0["status"] as? String != "pass" }) { exit(2) }
    }
}
