import AppKit
import CoreText

private struct Failure: Error { let message: String }
private final class InvalidationProbe: NSView {
    var invalidations = 0
    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set { if newValue { invalidations += 1 }; super.needsDisplay = newValue }
    }
}
private final class Actions: NSObject {
    var count = 0
    @objc func activate(_ sender: Any?) { count += 1 }
}

@main struct NativeCreamDesignTests {
    @MainActor static var checks = 0
    @MainActor static func check(_ value: Bool, _ reason: String) throws {
        checks += 1; if !value { throw Failure(message: reason) }
    }
    static func components(_ color: NSColor) -> [Double] {
        let c = color.usingColorSpace(.sRGB)!
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
    }
    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            let linear = components(color).prefix(3).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    @MainActor static func save(_ value: [String: Any], _ output: URL, _ name: String) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent(name + ".json"))
    }
    @MainActor static func main() {
        do {
            _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
            let output = URL(fileURLWithPath: CommandLine.arguments[1]), mode = CommandLine.arguments[2]
            switch mode {
            case "palette": try palette(output)
            case "foundation": try foundation(output)
#if NATIVE_DESIGN_PARITY
            case "reader-parity": try readerParity(output)
            case "interaction-regressions": try interactionRegressions(output)
            case "importer-presentation": try importerPresentation(output)
#endif
            case "vector": try vector(output)
            case "controls": try controls(output)
            case "fonts": try fonts(output)
            case "paint": try paint(output)
            case "preferences": try preferences(output)
            default: throw Failure(message: "Unknown mode")
            }
            print("\(mode): \(checks) checks passed; offscreen component evidence only")
        } catch { fputs("NA18 FAILURE: \(error)\n", stderr); exit(1) }
    }
    @MainActor static func combinations() -> [NativeAppDesign.Preferences] {
        NativeAppDesign.Theme.allCases.flatMap { theme in
            [false, true].flatMap { high in [false, true].flatMap { transparency in
                [false, true].map { NativeAppDesign.Preferences(theme: theme, increasedContrast: high,
                    reduceTransparency: transparency, reduceMotion: $0) }
            } }
        }
    }
    @MainActor static func palette(_ output: URL) throws {
        var observations = [[String: Any]]()
        let tokens: [(KeyPath<NativeAppDesign.Palette, NSColor>, [UInt32])] = [
            (\.paper, [0xF7F2E8, 0x24231F, 0xF7F2E8, 0x24231F]),
            (\.panel, [0xFFFCF5, 0x302E29, 0xFFFCF5, 0x2E2C27]),
            (\.track, [0xEAE3D5, 0x1C1B18, 0xE4DCCB, 0x181714]),
            (\.pdfCanvas, [0xEDE7DA, 0x1C1B18, 0xE6DFD0, 0x181714]),
            (\.codeBg, [0xEFE9DC, 0x2E2C27, 0xEAE3D3, 0x34322C]),
            (\.ink, [0x292722, 0xF7F2E8, 0x1A1916, 0xFFFDF8]),
            (\.secondaryInk, [0x625D53, 0xD0C9BC, 0x433F37, 0xE5DFD2]),
            (\.disabledInk, [0x71695E, 0xC0B9AB, 0x575147, 0xCFC8BA]),
            (\.accent, [0x514A83, 0xC6BEFF, 0x3B3469, 0xDCD6FF]),
            (\.accentHover, [0x3E376B, 0xDBD5FF, 0x2B2552, 0xECE8FF]),
            (\.onAccent, [0xFFFCF5, 0x24231F, 0xFFFFFF, 0x181714]),
            (\.boundary, [0x81786A, 0xA59D90, 0x292722, 0xEEE8DC]),
            (\.rule, [0xDED8CB, 0x3D3A33, 0x81786A, 0xA59D90]),
            (\.wash, [0xEEE8F5, 0x403C49, 0xE4DBF2, 0x464152]),
            (\.pressed, [0xDED5ED, 0x514A62, 0xD1C4EA, 0x59526B]),
            (\.selection, [0xE6DEF4, 0x49405E, 0xD9CEEE, 0x54496E]),
            (\.highlight, [0xF0DFAA, 0x54472A, 0xEBD48E, 0x61512C]),
            (\.highlightEdge, [0x8F6A1E, 0xDFC070, 0x6E4F12, 0xF0D589]),
            (\.warning, [0x785517, 0xF2CF8C, 0x5E410E, 0xF9DC9E]),
            (\.error, [0x9C302C, 0xFFB5AE, 0x821E1B, 0xFFC7C2]),
            (\.reviewInk, [0xA82828, 0xFF9894, 0x8A1D1D, 0xFFB3AE]),
            (\.sage, [0x56765B, 0xA9C6AA, 0x3B5940, 0xC2DFC3])]
        for (index, preferences) in [NativeAppDesign.Preferences(theme: .light), .init(theme: .dark),
            .init(theme: .light, increasedContrast: true), .init(theme: .dark, increasedContrast: true)].enumerated() {
            let palette = NativeAppDesign.palette(preferences)
            for (path, expected) in tokens {
                try check(components(palette[keyPath: path]) == components(NativeAppDesign.color(expected[index])), "Four-mode sRGB contract \(path)")
            }
        }
        // Independent author-fixed light starting colors, evaluated after native sRGB resolution.
        let p = NativeAppDesign.palette(.init(theme: .light))
        for (color, bytes) in [(p.paper, [247,242,232]), (p.ink, [41,39,34]),
                               (p.panel, [255,252,245]), (p.accent, [81,74,131])] {
            try check(zip(components(color), bytes).allSatisfy { abs($0.0 * 255 - Double($0.1)) < 0.001 }, "Light source color")
        }
        for preference in combinations() {
            let p = NativeAppDesign.palette(preference)
            let dark = preference.theme == .dark, hc = preference.increasedContrast
            let solid = hc || preference.reduceTransparency
            for (actual, expected) in [
                (p.glassEdge, NativeAppDesign.color(dark ? (hc ? 0xEEE8DC : 0xF7F2E8) : 0x292722).withAlphaComponent(hc ? 1 : 0.14)),
                (p.glassSpecular, hc ? .clear : NativeAppDesign.color(dark ? 0xFFFDF8 : 0xFFFFFF).withAlphaComponent(dark ? 0.10 : 0.55)),
                (p.scrim, NativeAppDesign.color(dark ? 0 : 0x292722).withAlphaComponent(hc ? (dark ? 0.52 : 0.28) : (dark ? 0.36 : 0.14))),
                (p.glassTintDrawer, p.panel.withAlphaComponent(solid ? 1 : (dark ? 0.86 : 0.84))),
                (p.glassTintCapsule, p.panel.withAlphaComponent(solid ? 1 : (dark ? 0.90 : 0.88)))] {
                try check(components(actual) == components(expected), "Glass and scrim sRGB/alpha contract")
            }
            var ratios = [String: Double]()
            for (name, foreground, background, minimum) in [
                ("paperText", p.ink, p.paper, 4.5), ("panelText", p.ink, p.panel, 4.5),
                ("secondary", p.secondaryInk, p.panel, 4.5), ("accent", p.accent, p.paper, 4.5),
                ("selection", p.ink, p.selection, 4.5), ("edgePaper", p.boundary, p.paper, 3.0),
                ("edgePanel", p.boundary, p.panel, 3.0), ("warning", p.warning, p.panel, 4.5),
                ("error", p.error, p.panel, 4.5),
                ("secondaryPaper", p.secondaryInk, p.paper, 4.5), ("accentHover", p.accentHover, p.paper, 4.5),
                ("highlight", p.ink, p.highlight, 4.5), ("code", p.ink, p.codeBg, 4.5),
                ("disabled", p.disabledInk, p.panel, 4.5), ("accentPanel", p.accent, p.panel, 4.5),
                ("onAccent", p.onAccent, p.accent, 4.5), ("wash", p.ink, p.wash, 4.5),
                ("activeOutline", p.accent, p.wash, 4.5), ("pressed", p.ink, p.pressed, 4.5),
                ("reviewPanel", p.reviewInk, p.panel, 4.5), ("reviewPaper", p.reviewInk, p.paper, 4.5),
                ("sage", p.sage, p.panel, 4.5), ("track", p.secondaryInk, p.track, 4.5),
                ("highlightEdge", p.highlightEdge, p.paper, 3.0)] {
                let ratio = contrast(foreground, background); ratios[name] = ratio
                try check(ratio >= minimum, "\(preference) \(name) contrast \(ratio)")
            }
            if !preference.increasedContrast && !preference.reduceTransparency {
                for tint in [p.glassTintDrawer, p.glassTintCapsule] {
                    let alpha = components(tint)[3], backdrop = components(p.ink), source = components(p.panel)
                    let values = zip(source, backdrop).prefix(3).map { $0 * alpha + $1 * (1 - alpha) }
                    let composite = NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: 1)
                    for ink in [p.ink, p.secondaryInk, p.accent] {
                        try check(contrast(ink, composite) >= 4.5, "Worst opposite-polarity glass backdrop")
                    }
                }
            }
            for role in [NativeAppDesign.ButtonRole.standard, .primary] {
                for enabled in [false, true] { for hover in [false, true] { for pressed in [false, true] {
                    let paint = NativeAppDesign.buttonPaint(preference, role: role, enabled: enabled, hovered: hover, pressed: pressed)
                    try check(contrast(paint.ink, paint.fill) >= 4.5, "Native state text contrast")
                    try check(components(paint.fill)[3] == 1, "Solid baseline")
                } } }
            }
            observations.append(["theme": preference.theme.rawValue, "highContrast": preference.increasedContrast,
                "reduceTransparency": preference.reduceTransparency, "reduceMotion": preference.reduceMotion, "contrast": ratios])
        }
        try save(["combinations": observations], output, "palette-observations")
    }
    @MainActor static func vector(_ output: URL) throws {
        let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("oracle.json"))) as! [String: Any]
        let reference = oracle["coordinates"] as! [Double], widths = oracle["widths"] as! [Double]
        var actual = [Double](), types = [CGPathElementType]()
        NativeBrandMark.path.applyWithBlock { pointer in
            let element = pointer.pointee; types.append(element.type)
            let count = element.type == .moveToPoint ? 1 : 3
            for index in 0..<count { actual += [Double(element.points[index].x), Double(element.points[index].y)] }
        }
        try check(actual == reference, "Every original cubic coordinate in exact order")
        try check(types.first == .moveToPoint && types.dropFirst().allSatisfy { $0 == .addCurveToPoint }, "Original topology")
        let busy = NativeBrandMark.layers(phase: .busy, preferences: .init(theme: .light))
        try check([Double(busy.base.width), Double(busy.halo!.width), Double(busy.beam!.width)] == widths, "CSS width hierarchy")
        try check(busy.base.opacity == 0.62 && busy.halo?.opacity == 0.3 && busy.beam?.opacity == 1, "CSS busy layer alpha")
        for p in combinations() { for phase in NativeBrandMark.Phase.allCases {
            let layers = NativeBrandMark.layers(phase: phase, preferences: p)
            try check((layers.halo != nil) == (phase == .busy && !p.reduceMotion && !p.increasedContrast && !p.reduceTransparency), "Halo visibility")
            try check((layers.beam != nil) == (phase == .busy && !p.reduceMotion), "Beam visibility")
            if p.increasedContrast || p.reduceTransparency || p.reduceMotion { try check(layers.base.opacity == 1, "Strong static base") }
            try check(layers.base.dash.isEmpty == (phase != .offline && phase != .reconnecting), "Static offline/reconnect dash")
        } }
        // Independent high-resolution cubic quadrature, not production's segment count.
        var previous = CGPoint(x: reference[0], y: reference[1]), length = 0.0
        for index in stride(from: 2, to: reference.count, by: 6) {
            let start = previous
            for step in 1...4096 {
                let t = Double(step) / 4096, u = 1 - t
                let x = u*u*u*start.x + 3*u*u*t*reference[index] + 3*u*t*t*reference[index+2] + t*t*t*reference[index+4]
                let y = u*u*u*start.y + 3*u*u*t*reference[index+1] + 3*u*t*t*reference[index+3] + t*t*t*reference[index+5]
                length += hypot(x - previous.x, y - previous.y); previous = CGPoint(x: x, y: y)
            }
        }
        try check(abs(Double(NativeBrandMark.length) - length) < 0.01, "SVG pathLength conversion")
        for rect in [NSRect(x: 7, y: 9, width: 24, height: 24), NSRect(x: 0, y: 0, width: 480, height: 80)] {
            let transform = NativeBrandMark.transform(in: rect), center = CGPoint(x: 120, y: 110).applying(transform)
            try check(transform.a == transform.d && transform.b == 0 && transform.c == 0, "Uniform scale")
            try check(abs(center.x - rect.midX) < 0.001 && abs(center.y - rect.midY) < 0.001, "Centered fit")
        }
        try save(["coordinates": actual, "referenceLength": length, "nativeLength": NativeBrandMark.length], output, "vector-observations")
    }
    @MainActor static func mouse(_ button: NSButton, releaseOutside: Bool) throws {
        let window = button.window!, start = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let end = releaseOutside ? NSPoint(x: -100, y: -100) : start
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: end, modifierFlags: [], timestamp: 1.1,
            windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true)
        if releaseOutside {
            let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: end, modifierFlags: [], timestamp: 1.05,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            NSApp.postEvent(drag, atStart: true)
        }
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [], timestamp: 1,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        button.mouseDown(with: down)
    }
    @MainActor static func controls(_ output: URL) throws {
        let actions = Actions(), button = NativeDesignButton(title: "질문 작성", target: actions, action: #selector(Actions.activate(_:)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        button.frame = NSRect(x: 20, y: 30, width: 180, height: 40); window.contentView!.addSubview(button)
        let originalTarget = button.target as AnyObject?, originalAction = button.action
        button.performClick(nil); try check(actions.count == 1, "Platform performClick")
        let referenceActions = Actions(), referenceButton = NSButton(title: "질문 작성", target: referenceActions, action: #selector(Actions.activate(_:)))
        referenceButton.frame = NSRect(x: 220, y: 30, width: 150, height: 40); window.contentView!.addSubview(referenceButton)
        let referencePress = referenceButton.accessibilityPerformPress(), nativePress = button.accessibilityPerformPress()
        try check(nativePress == referencePress && actions.count - 1 == referenceActions.count, "Hidden native AX dispatch matches platform reference")
        // Hidden AX dispatch may be unavailable. Continue concrete semantic activation separately.
        button.performClick(nil)
        let activationBase = actions.count
        try check(activationBase == 2 + referenceActions.count, "No duplicate AX/control dispatch")
        button.keyEquivalent = "k"; button.keyEquivalentModifierMask = .command
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 2,
            windowNumber: window.windowNumber, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        try check(button.performKeyEquivalent(with: key), "Native keyboard equivalent")
        try check(actions.count == activationBase + 1, "One keyboard activation one action")
        button.refusesFirstResponder = false
        try check(window.makeFirstResponder(button) && window.firstResponder === button, "Actual hidden-window keyboard focus")
        try check(button.focusRingType == .exterior && button.focusRingMaskBounds == button.bounds, "Native focus mask")
        try mouse(button, releaseOutside: true)
        try check(actions.count == activationBase + 1 && button.cell?.isHighlighted == false, "Canceled mouse tracking count=\(actions.count), base=\(activationBase), highlighted=\(String(describing: button.cell?.isHighlighted))")
        try mouse(button, releaseOutside: false)
        try check(actions.count == activationBase + 2 && button.cell?.isHighlighted == false, "Mouse tracking commits once")
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, subtype: 0, data1: 0, data2: 0)!
        button.mouseEntered(with: event); try check(button.isHovered, "Hover feedback")
        button.highlight(true); try check(button.cell?.isHighlighted == true, "Press feedback")
        button.cancelOperation(nil)
        try check(!button.isHovered && button.cell?.isHighlighted == false && actions.count == activationBase + 2, "Cancel clears without dispatch")
        button.mouseEntered(with: event); button.highlight(true); button.isEnabled = false
        button.performClick(nil); _ = button.performKeyEquivalent(with: key)
        try check(actions.count == activationBase + 2 && !button.isHovered && button.cell?.isHighlighted == false, "Disabled rejects and clears")
        button.isEnabled = true
        for _ in 0..<20 { button.performClick(nil) }
        try check(actions.count == activationBase + 22 && button.cell?.isHighlighted == false, "Rapid activation no duplicate/stuck state")
        try check((button.target as AnyObject?) === originalTarget && button.action == originalAction, "Paint preserved target/action")
        try check(button.accessibilityRole() == referenceButton.accessibilityRole() && button.isAccessibilityElement() == referenceButton.isAccessibilityElement(), "Native AX semantics role=\(String(describing: button.accessibilityRole())) refRole=\(String(describing: referenceButton.accessibilityRole())) element=\(button.isAccessibilityElement()) refElement=\(referenceButton.isAccessibilityElement())")
        try check(button.accessibilityTitle() == referenceButton.accessibilityTitle(), "Native AX title preserved")
        try save(["nativeAXRole": button.accessibilityRole()?.rawValue ?? "nil",
                  "referenceAXRole": referenceButton.accessibilityRole()?.rawValue ?? "nil",
                  "nativeAXPress": nativePress, "referenceAXPress": referencePress,
                  "actualAXInputVerified": false, "targetActionCount": actions.count,
                  "mouseTracking": "release-inside and drag-out cancellation", "keyboard": "command-k and native first responder"], output, "control-observations")
        let small = button.intrinsicContentSize
        button.font = NativeAppDesign.Typography.font(.control, scale: 2)
        button.title = "긴 한국어 이름과 설정 — A\u{030A} ∑"
        let large = button.intrinsicContentSize
        try check(large.height >= 32 && large.height > small.height && large.width > small.width, "Real native label sizing")
        button.removeFromSuperview()
        try check(!button.isHovered && button.cell?.isHighlighted == false, "Detach clears feedback")
        try check(!window.isVisible, "No visible user window")
        try save(["actionCount": actions.count, "visible": window.isVisible, "focus": true,
                  "small": [small.width, small.height], "large": [large.width, large.height]], output, "control-observations")
    }
    @MainActor static func fonts(_ output: URL) throws {
        var observations = [[String: Any]]()
        for role in NativeAppDesign.Typography.Role.allCases {
            for sample in ["Lagrangian", "한글 연구 노트", "한글 A\u{030A} e\u{0301}", "∑ ∫ → ± Ω 𝛼"] {
                let font = NativeAppDesign.Typography.font(role)
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: sample, attributes: [.font: font]))
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                var names = [String](), glyphCount = 0
                for run in runs {
                    let count = CTRunGetGlyphCount(run); var glyphs = [CGGlyph](repeating: 0, count: count)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    try check(count > 0 && !glyphs.contains(0), "Actual fallback must contain no .notdef: \(sample)")
                    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                    names.append(CTFontCopyPostScriptName(runFont) as String); glyphCount += count
                }
                try check(CTLineGetTypographicBounds(line, nil, nil, nil) > 0 && glyphCount > 0, "Actual shaped line")
                observations.append(["role": String(describing: role), "sample": sample, "requestedFont": font.fontName,
                                     "actualFonts": names, "glyphs": glyphCount])
            }
        }
        try save(["runs": observations], output, "font-observations")
    }
    @MainActor static func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "Bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap); return bitmap
    }
    @MainActor static func paint(_ output: URL) throws {
        var counts = [String: Int]()
        for theme in NativeAppDesign.Theme.allCases {
            let p = NativeAppDesign.Preferences(theme: theme), palette = NativeAppDesign.palette(p)
            let surface = NativeDesignSurface(frame: NSRect(x: 0, y: 0, width: 240, height: 220))
            surface.preferencesOverride = p; surface.role = .paper
            let logo = NativeBrandMarkView(frame: surface.bounds); logo.preferencesOverride = p; surface.addSubview(logo)
            let idle = try bitmap(surface)
            let busy: NSBitmapImageRep
            logo.phase = .busy; busy = try bitmap(surface)
            try check(idle.bitmapData != nil && idle.pixelsWide == 240, "Actual native pixels")
            var changed = 0
            for y in 0..<220 { for x in 0..<240 {
                if contrast(idle.colorAt(x: x, y: y)!, palette.paper) > 1.2 { changed += 1 }
            } }
            try check(changed > 1000 && changed < 20000, "Vector occupies bounded actual bitmap")
            try check(idle.representation(using: .png, properties: [:]) != busy.representation(using: .png, properties: [:]), "Busy layer actual pixels differ")
            try idle.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("logo-\(theme.rawValue).png"))
            try busy.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("logo-\(theme.rawValue)-busy.png"))
            // Independent CGContext reference uses original SVG coordinates + explicit round caps/joins.
            let oracle = try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("oracle.json"))) as! [String: Any]
            let values = oracle["coordinates"] as! [Double]
            let reference = CGMutablePath(); reference.move(to: CGPoint(x: values[0], y: values[1]))
            for i in stride(from: 2, to: values.count, by: 6) {
                reference.addCurve(to: CGPoint(x: values[i+4], y: values[i+5]), control1: CGPoint(x: values[i], y: values[i+1]), control2: CGPoint(x: values[i+2], y: values[i+3]))
            }
            func render(_ native: Bool) -> Data {
                let context = CGContext(data: nil, width: 480, height: 440, bitsPerComponent: 8, bytesPerRow: 480 * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.scaleBy(x: 2, y: 2)
                if native { NativeBrandMark.draw(in: NSRect(x: 0, y: 0, width: 240, height: 220), context: context, phase: .idle, preferences: p) }
                else {
                    context.setLineCap(.round); context.setLineJoin(.round); context.setLineWidth(11)
                    context.setStrokeColor(palette.ink.withAlphaComponent(0.9).cgColor); context.addPath(reference); context.strokePath()
                }
                return Data(bytes: context.data!, count: 480 * 440 * 4)
            }
            try check(render(true) == render(false), "Round cap/join/width/alpha original-path pixel equivalence")
            let button = NativeDesignButton(title: "設定 · 질문", target: nil, action: nil)
            button.preferencesOverride = p; button.frame = NSRect(x: 0, y: 0, width: 180, height: 44)
            let rest = try bitmap(button); button.highlight(true); let pressed = try bitmap(button)
            try check(rest.representation(using: .png, properties: [:]) != pressed.representation(using: .png, properties: [:]), "Production pressed paint")
            try rest.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("button-\(theme.rawValue).png"))
            counts[theme.rawValue] = changed
        }
        // Exercise actual reusable surface/cell consumers for every preference combination.
        for preference in combinations() {
            let surface = NativeDesignSurface(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
            surface.preferencesOverride = preference
            let image = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)!
            surface.cacheDisplay(in: surface.bounds, to: image)
            let resolvedPanel = NativeAppDesign.palette(preference).panel
            try check(zip(components(image.colorAt(x: 40, y: 30)!), components(resolvedPanel)).allSatisfy { abs($0 - $1) < 0.01 }, "Actual opaque panel pixel in preference matrix")
            let button = NativeDesignButton(title: "상태", target: nil, action: nil)
            button.preferencesOverride = preference; button.frame = NSRect(x: 0, y: 0, width: 160, height: 44)
            for role in [NativeAppDesign.ButtonRole.standard, .primary] {
                button.designRole = role
                for enabled in [true, false] { for pressed in [false, true] {
                    button.isEnabled = enabled; button.highlight(pressed)
                    let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
                    button.cacheDisplay(in: button.bounds, to: bitmap)
                    try check(zip(components(bitmap.colorAt(x: 20, y: 10)!), components(button.paint.fill)).allSatisfy { abs($0 - $1) < 0.015 }, "Actual control fill agrees with semantic state")
                } }
            }
        }
        try save(["paintedPixels": counts, "nativePreferencePaintCombinations": 16, "guiVerified": false], output, "paint-observations")
    }
    @MainActor static func preferences(_ output: URL) throws {
        let view = NativeDesignSurface(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.orderOut(nil) }
        view.appearance = NSAppearance(named: .aqua)
        try check(view.preferences.theme == .light, "Effective native Aqua")
        view.appearance = NSAppearance(named: .darkAqua)
        try check(view.preferences.theme == .dark, "Effective native Dark Aqua")
        let actual = NativeAppDesign.Preferences.current(appearance: view.effectiveAppearance), workspace = NSWorkspace.shared
        try check(actual.increasedContrast == workspace.accessibilityDisplayShouldIncreaseContrast &&
                  actual.reduceMotion == workspace.accessibilityDisplayShouldReduceMotion &&
                  actual.reduceTransparency == workspace.accessibilityDisplayShouldReduceTransparency, "Actual read-only OS preferences")
        let probe = InvalidationProbe(frame: .zero)
        let observation = NativeDesignObservation(view: probe)
        let before = probe.invalidations
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        try check(probe.invalidations > before, "Workspace notification reaches the production observer")
        withExtendedLifetime(observation) {}
        try save(["OS": ProcessInfo.processInfo.operatingSystemVersionString, "increasedContrast": actual.increasedContrast,
                  "reduceMotion": actual.reduceMotion, "reduceTransparency": actual.reduceTransparency,
                  "runtimeMacOS13Verified": false], output, "preference-observations")
    }
    @MainActor static func foundation(_ output: URL) throws {
        for preference in combinations() {
            for style in [NativeFloatingGlassView.Style.drawer, .capsule] {
                let glass = NativeFloatingGlassView(style: style)
                glass.frame = NSRect(x: 0, y: 0, width: 120, height: 80)
                glass.preferencesOverride = preference; glass.layoutSubtreeIfNeeded()
                let solid = preference.increasedContrast || preference.reduceTransparency
                try check(!glass.isOpaque && glass.layer?.masksToBounds == false, "Transparent unclipped shadow host")
                try check(glass.contentView.layer?.masksToBounds == true && glass.contentView.layer?.cornerCurve == .continuous, "Continuous inner clip")
                try check(glass.effectView.isHidden == solid, "Blur fallback follows both accessibility preferences")
                try check(glass.effectView.material == .popover && glass.effectView.blendingMode == .withinWindow &&
                          glass.effectView.state == .followsWindowActiveState, "Window-local popover material")
                let outside = NSColor(cgColor: glass.layer!.backgroundColor!)!
                try check(outside.alphaComponent == 0, "Host never fills paper outside clip")
                if solid {
                    let inside = NSColor(cgColor: glass.contentView.layer!.backgroundColor!)!
                    try check(components(inside) == components(NativeAppDesign.palette(preference).panel), "Opaque panel fallback inside clip")
                    // Render the actual clipped layer with shadows suppressed so
                    // the material's corners can be measured independently.
                    glass.layer!.sublayers!.forEach { $0.shadowOpacity = 0 }
                    let pixels = try bitmap(glass)
                    for (x, y) in [(0, 0), (119, 0), (0, 79), (119, 79)] {
                        try check(pixels.colorAt(x: x, y: y)!.alphaComponent == 0, "Fallback corner has zero material alpha")
                    }
                    try check(pixels.colorAt(x: 60, y: 40)!.alphaComponent == 1, "Fallback center is fully opaque")
                }
                let paths = glass.layer!.sublayers!.compactMap(\.shadowPath)
                try check(paths.count == 2 && paths.allSatisfy { $0.boundingBox.width == 120 }, "Ambient/contact shadow paths")
                glass.frame.size.width = 160; glass.layoutSubtreeIfNeeded()
                try check(glass.layer!.sublayers!.compactMap(\.shadowPath).allSatisfy { $0.boundingBox.width == 160 }, "Shadow paths follow layout")
            }
        }
        for role in [NativeDesignSurface.Role.paper, .panel, .floating] {
            let surface = NativeDesignSurface(frame: NSRect(x: 0, y: 0, width: 80, height: 60)); surface.role = role
            try check(surface.isOpaque, "Home and Aa surfaces retain opacity")
        }
        let brand = NativeBrandMarkControl(frame: NSRect(x: 0, y: 0, width: 40, height: 32))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        container.addSubview(brand); brand.frame.origin = NSPoint(x: 100, y: 40)
        try check(container.hitTest(NSPoint(x: 120, y: 56)) === brand, "Brand hit target survives toolbar placement")
        var homes = 0, refreshes = 0
        brand.onOpenHome = { homes += 1 }; brand.onRefresh = { refreshes += 1 }
        brand.beginPress(at: .zero, timestamp: 0); brand.dragPress(to: NSPoint(x: 17, y: 2))
        brand.completeHold(); try check(homes == 1, "Swipe commits exactly once and cancels hold")
        brand.beginPress(at: .zero, timestamp: 0); brand.dragPress(to: NSPoint(x: 11, y: 20)); brand.completeHold()
        try check(homes == 1, "Movement cancels hold without horizontal swipe")
        brand.cancelOperation(nil)
        brand.preferencesOverride = .init(theme: .light, reduceMotion: true)
        brand.beginPress(at: .zero, timestamp: 0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.55))
        try check(homes == 2, "500ms hold timer fires with Reduce Motion")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 1,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        brand.keyDown(with: key); try check(refreshes == 1, "Shift Return refresh")
        brand.isOfflineRecoveryCopy = true; brand.keyDown(with: key)
        try check(refreshes == 1, "Offline recovery never dispatches refresh")
        brand.cancelOperation(nil)
        brand.beginPress(at: .zero, timestamp: 0); brand.isEnabled = false; brand.completeHold()
        try check(homes == 2, "Disabled control cancels an outstanding hold")
        try save(["checks": checks, "guiVerified": false], output, "foundation-observations")
    }
#if NATIVE_DESIGN_PARITY
    @MainActor static func importerPresentation(_ output: URL) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
        let document = try NativeReaderDocument.decode(data)
        let store = NativeReaderDocumentStore(), generation = try store.beginRequest()
        let reader = NativeReaderTextView(store: store)
        defer { reader.dispose() }
        reader.setFrameSize(NSSize(width: 800, height: 600))
        try reader.adopt(document, context: .init(requestID: UUID(), viewID: store.viewID,
            generation: generation, target: document.identity))
        try check(reader.bodyTextView.string == CommandLine.arguments[4],
                  "Actual importer presentation: \(reader.bodyTextView.string.debugDescription)")
        try check(store.document == document, "Presentation preserves the accepted importer document")
        let map = reader.textMap!, displayed = reader.bodyTextView.string as NSString
        for span in map.spans {
            let block = document.blocks.first { $0.id == span.blockID }!
            let logical = NSRange(location: span.logical.lowerBound, length: span.logical.count)
            try check(!span.isObject && displayed.substring(with: span.presentation) ==
                      (block.canonicalText as NSString).substring(with: logical), "UTF16 span retains exact canonical text")
        }
        let selection = try map.selection(for: NSRange(location: 0, length: displayed.length))
        try check(selection?.fragments.map(\.exact) == document.blocks.map(\.canonicalText),
                  "Full copy preserves canonical newlines and excludes presentation separators")
        for block in document.blocks {
            for offset in block.graphemeBoundariesUTF16 {
                let logical = NativeReaderTextPosition(blockID: block.id, utf16: offset, affinity: .downstream)
                let presentation = try map.presentation(of: logical)
                let roundTrip = try map.logical(at: presentation, affinity: .downstream)
                try check(roundTrip == logical, "Canonical grapheme offset round trip")
            }
        }
        try save(["checks": checks, "guiVerified": false], output, "importer-observations")
    }

    @MainActor static func interactionRegressions(_ output: URL) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func pointer(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 1,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        for compact in [false, true] {
            let width: CGFloat = compact ? 80 : 140
            let control = NativeModeMorphSwitch(frame: NSRect(x: 100, y: 100, width: width, height: 32))
            control.compact = compact; control.preferencesOverride = .init(theme: .light, reduceMotion: true)
            window.contentView!.addSubview(control); control.layoutSubtreeIfNeeded()
            defer { control.removeFromSuperview() }
            var requests = 0
            control.onRequestMode = { _ in requests += 1 }
            let pdf = NSPoint(x: width * 0.75, y: 16)
            for release in [NSPoint(x: pdf.x, y: 150), NSPoint(x: pdf.x, y: 24), NSPoint(x: width + 10, y: 16)] {
                control.mouseDown(with: pointer(.leftMouseDown, pdf, in: control))
                control.mouseDragged(with: pointer(.leftMouseDragged, release, in: control))
                control.mouseUp(with: pointer(.leftMouseUp, release, in: control))
                control.layoutSubtreeIfNeeded()
                try check(requests == 0 && control.requestedMode == nil, "Vertical/outside release cancels mode intent")
                try check(control.layer!.sublayers![1].frame.minX == 3, "Canceled thumb returns to accepted mode")
            }
            // A release without an intermediate drag event must cancel too.
            control.mouseDown(with: pointer(.leftMouseDown, pdf, in: control))
            control.mouseUp(with: pointer(.leftMouseUp, NSPoint(x: pdf.x, y: 150), in: control))
            try check(requests == 0, "Outside mouseUp alone cannot activate a segment")
            let body = NSPoint(x: 10, y: 16), dragged = NSPoint(x: width - 10, y: 16)
            control.mouseDown(with: pointer(.leftMouseDown, body, in: control))
            control.mouseDragged(with: pointer(.leftMouseDragged, dragged, in: control)); control.layoutSubtreeIfNeeded()
            try check(control.layer!.sublayers![1].frame.minX > 3, "Available drag moves thumb")
            control.allowsModeSwitch = false
            control.mouseDragged(with: pointer(.leftMouseDragged, dragged, in: control)); control.layoutSubtreeIfNeeded()
            try check(control.layer!.sublayers![1].frame.minX == 3, "Disabling during drag immediately pins accepted thumb")
            control.allowsModeSwitch = true
            control.mouseUp(with: pointer(.leftMouseUp, dragged, in: control))
            try check(requests == 0, "Reenabling cannot revive the canceled gesture")
            control.mouseDown(with: pointer(.leftMouseDown, pdf, in: control))
            control.mouseUp(with: pointer(.leftMouseUp, pdf, in: control))
            try check(requests == 1 && control.requestedMode == .originalPages, "Fresh click works after cancellation")
            control.requestedMode = nil
            control.mouseDown(with: pointer(.leftMouseDown, body, in: control))
            control.mouseDragged(with: pointer(.leftMouseDragged, dragged, in: control))
            control.mouseUp(with: pointer(.leftMouseUp, dragged, in: control)); control.layoutSubtreeIfNeeded()
            try check(requests == 2 && control.layer!.sublayers![1].frame.minX == 3, "Horizontal swipe requests once and awaits acceptance")
        }
        let drawer = NativeOutlineDrawerView(frame: window.contentView!.bounds)
        drawer.preferencesOverride = .init(theme: .light, reduceMotion: true)
        drawer.entries = [.init(id: "one", title: "첫 장", depth: 0)]
        let body = NSTextView(frame: window.contentView!.bounds)
        body.string = "문단😀선택"; window.contentView!.addSubview(body)
        window.contentView!.addSubview(drawer); window.makeFirstResponder(body)
        let selection = NSRange(location: 0, length: 4); body.setSelectedRange(selection)
        drawer.present()
        func click(_ point: NSPoint) throws {
            guard let hit = drawer.hitTest(drawer.convert(point, to: drawer.superview)) else {
                throw Failure(message: "Missing drawer hit target")
            }
            hit.mouseDown(with: pointer(.leftMouseDown, point, in: drawer))
        }
        for inside in [NSPoint(x: 4, y: drawer.glass.bounds.midY), NSPoint(x: 10, y: drawer.glass.bounds.midY),
                       NSPoint(x: drawer.glass.bounds.midX, y: drawer.glass.bounds.height - 4)] {
            try click(drawer.glass.convert(inside, to: drawer))
            try check(!drawer.isHidden && body.selectedRange() == selection, "Panel padding/header keeps drawer and body selection")
        }
        try click(NSPoint(x: 700, y: 300))
        try check(drawer.isHidden && body.selectedRange() == selection && window.firstResponder === body,
                  "Scrim dismisses and restores focus without changing selection")
        drawer.present()
        try click(drawer.glass.convert(NSPoint(x: 1, y: 1), to: drawer))
        try check(drawer.isHidden, "Transparent rounded corner is scrim")
        try check(!window.isVisible, "Regression events stay offscreen")
        try save(["checks": checks, "guiVerified": false], output, "interaction-regressions-observations")
    }

    @MainActor static func readerParity(_ output: URL) throws {
        let control = NativeModeMorphSwitch(frame: NSRect(x: 0, y: 0, width: 140, height: 32))
        control.preferencesOverride = .init(theme: .light, reduceMotion: true)
        var modes: [NativeModeMorphSwitch.Mode] = []
        control.onRequestMode = { modes.append($0) }
        control.pageButton.performClick(nil); control.layoutSubtreeIfNeeded()
        try check(modes == [.originalPages] && control.displayMode == .nativeReflow && control.requestedMode == .originalPages,
                  "Requested PDF does not move accepted selection")
        try check(control.reflowButton.state == .on && control.pageButton.state == .off, "AX selection follows accepted display")
        let thumb = control.layer!.sublayers![1]
        try check(thumb.frame.minX == 3, "Pending request keeps thumb pinned")
        control.displayMode = .originalPages
        try check(control.requestedMode == nil && control.pageButton.state == .on, "Acceptance commits thumb and clears loading")
        control.heldSelection = true; control.reflowButton.performClick(nil)
        try check(modes.count == 1 && control.displayMode == .originalPages, "Held selection rejects requests")
        control.heldSelection = false; control.allowsModeSwitch = false; control.reflowMode()
        try check(modes.count == 1, "Unavailable mode blocks dispatch")
        control.compact = true
        try check(control.intrinsicContentSize == NSSize(width: 80, height: 32) && control.reflowButton.title.isEmpty, "Compact geometry")
        try check(control.accessibilityRole() == .radioGroup && control.pageButton.accessibilityRole() == .radioButton, "Radio AX contract")
        control.frame.size.width = 80; control.layoutSubtreeIfNeeded()
        control.allowsModeSwitch = true
        func pointer(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 16), modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        control.mouseDown(with: pointer(.leftMouseDown, 58))
        control.mouseDragged(with: pointer(.leftMouseDragged, 40)); control.layoutSubtreeIfNeeded()
        try check(thumb.frame.minX == 22, "Thumb tracks horizontal drag one-to-one")
        control.mouseUp(with: pointer(.leftMouseUp, 40)); control.layoutSubtreeIfNeeded()
        try check(modes == [.originalPages, .nativeReflow] && thumb.frame.minX == 40, "Threshold swipe requests mode and returns to accepted slot")
        let drawer = NativeOutlineDrawerView(frame: NSRect(x: 0, y: 0, width: 800, height: 700))
        drawer.preferencesOverride = .init(theme: .light, reduceMotion: true)
        drawer.toolbarBottom = 40
        drawer.entries = [.init(id: "a", title: "시작", depth: 0), .init(id: "b", title: "한글", depth: 3)]
        var navigated: String?
        drawer.onNavigate = { navigated = $0 }; drawer.present(); drawer.layoutSubtreeIfNeeded()
        try check(drawer.glass.frame.minX == 14 && drawer.glass.frame.minY == 50 && drawer.glass.frame.width == 320,
                  "Floating drawer placement")
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        drawer.tableView.keyDown(with: key(125)); drawer.tableView.keyDown(with: key(36))
        try check(navigated == "b" && drawer.isHidden, "Down Return navigates and dismisses")
        drawer.present(); drawer.tableView.keyDown(with: key(53))
        try check(drawer.isHidden && drawer.isAccessibilityModal(), "Escape and AX modal semantics")
        let canvas = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let pdfView = NativeReaderOriginalPageView(viewID: UUID())
        defer { pdfView.dispose() }
        canvas.documentView = pdfView
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            pdfView.appearance = NSAppearance(named: appearance)
            let preferences = NativeAppDesign.Preferences.current(appearance: pdfView.effectiveAppearance)
            try check(components(canvas.backgroundColor) == components(NativeAppDesign.palette(preferences).pdfCanvas), "PDF outer canvas follows palette")
        }
        func node(_ id: String, _ kind: NativeReaderNode.Kind, _ text: String, _ start: Int,
                  children: [NativeReaderNode] = [], level: Int? = nil, link: String? = nil) -> NativeReaderNode {
            NativeReaderNode(id: id, sectionID: "s", kind: kind, canonicalText: text, displayText: text,
                rangeUTF16: [start, start + text.utf16.count], offsets: NativeTextOffsets(text), children: children,
                anchors: [], annotationTargets: [], visible: true, mapping: .unmapped, passageKey: nil,
                direction: nil, language: nil, headingLevel: level, math: nil, cell: nil, link: link, assetID: nil, alt: nil)
        }
        let first = node("p1", .paragraph, "한글😀", 0, children: [node("t1", .text, "한글😀", 0)])
        let second = node("p2", .paragraph, "link", 4, children: [node("l", .link, "link", 4,
            children: [node("t2", .text, "link", 4)], link: "https://example.com")])
        let group = node("group", .group, "한글😀link", 0, children: [first, second, node("br", .break, "", 8)])
        let h2 = node("h2", .heading, "Heading", 0, children: [node("ht", .text, "Heading", 0)], level: 2)
        let store = NativeReaderDocumentStore(), generation = try store.beginRequest()
        let identity = NativeDocumentIdentity(documentID: "d", serviceID: "s", revision: "r", scope: .fixture)
        let document = NativeReaderDocument(schemaVersion: 1, identity: identity, generation: generation,
            requiredCapabilities: ["semantic-tree-v1"], blocks: [group, h2], assets: [], diagnostics: [])
        let reader = NativeReaderTextView(store: store)
        defer { reader.dispose() }
        reader.setFrameSize(NSSize(width: 1000, height: 600))
        try reader.adopt(document, context: .init(requestID: UUID(), viewID: store.viewID, generation: generation, target: identity))
        try check(reader.bodyTextView.string == "한글😀\nlink\n\nHeading", "Group and break separators are presentation-only")
        try check(store.document?.blocks[0].canonicalText == "한글😀link", "Canonical UTF16 remains unchanged")
        let map = reader.textMap!
        let offset = try map.presentation(of: .init(blockID: "group", utf16: 4, affinity: .downstream))
        try check(offset == 5, "UTF16 offset maps across presentation separator")
        let selection = try map.selection(for: NSRange(location: 0, length: 9))
        try check(selection?.fragments.first?.exact == "한글😀link" && selection?.fragments.first?.rangeUTF16 == 0..<8,
                  "Copy and selection exclude presentation newlines")
        let storage = reader.bodyTextView.textStorage!
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        try check(style.lineHeightMultiple == 1.65 && style.paragraphSpacing == 12 && style.hyphenationFactor == 0, "Editorial paragraph rhythm")
        try check(reader.textAppearance.fontSize == 15 && reader.renderKey?.width == 680, "Default body and centered measure")
        try check(reader.bodyTextView.textContainerInset.width == floor((reader.bodyTextView.bounds.width - 680) / 2), "Centered reading column")
        try check(!reader.scrollView.automaticallyAdjustsContentInsets && reader.scrollView.contentInsets.bottom == 104, "Bottom selection clearance")
        try check(storage.attribute(.link, at: 5, effectiveRange: nil) == nil, "Link never grants NSLink authority")
        let p = reader.designPalette
        try check(components(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as! NSColor) == components(p.accent), "Semantic accent links")
        let manager = reader.bodyTextView.layoutManager!, textContainer = reader.bodyTextView.textContainer!
        manager.ensureLayout(for: textContainer)
        let glyph = manager.glyphRange(forCharacterRange: NSRange(location: 5, length: 1), actualCharacterRange: nil)
        let linkRect = manager.boundingRect(forGlyphRange: glyph, in: textContainer)
        let hoverPoint = reader.bodyTextView.convert(NSPoint(x: linkRect.midX + reader.bodyTextView.textContainerOrigin.x,
            y: linkRect.midY + reader.bodyTextView.textContainerOrigin.y), to: nil)
        let hover = NSEvent.mouseEvent(with: .mouseMoved, location: hoverPoint, modifierFlags: [], timestamp: 1,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        reader.bodyTextView.mouseMoved(with: hover)
        try check(components(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as! NSColor) == components(p.accentHover), "Hover uses accentHover")
        let underline = storage.attribute(.underlineColor, at: 5, effectiveRange: nil) as! NSColor
        try check(abs(underline.alphaComponent - (reader.designPreferences.increasedContrast ? 1 : 0.88)) < 0.001, "Hover underline opacity")
        reader.bodyTextView.mouseExited(with: hover)
        try check(storage.attribute(.link, at: 5, effectiveRange: nil) == nil &&
            components(storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as! NSColor) == components(p.accent), "Hover exit restores semantic link without NSLink")
        try check(components(reader.bodyTextView.backgroundColor) == components(p.paper) &&
                  components(reader.scrollView.backgroundColor) == components(p.paper), "Unified paper")
        // TextKit resolves the leading Korean run to the cascade font itself.
        // Inspect the requested descriptor as well as the actual shaped runs.
        let descriptor = reader.textAppearance.bodyFont().fontDescriptor
        try check(descriptor.object(forKey: .cascadeList) != nil, "Korean CoreText cascade")
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "한글본문", attributes: [.font: reader.textAppearance.bodyFont()]))
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            try check((CTFontCopyPostScriptName(runFont) as String).contains("AppleSDGothicNeo"), "Korean shapes with explicit cascade")
        }
        let h2Font = storage.attribute(.font, at: 11, effectiveRange: nil) as! NSFont
        try check(abs(h2Font.pointSize - 22.2) < 0.01, "H2 editorial scale")
        let codeFont = reader.textAppearance.codeAttributes(palette: p)[.font] as! NSFont
        try check(abs(codeFont.pointSize - 13.2) < 0.01, "Monospaced code uses 0.88 scale")
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let window = NSWindow(contentRect: root.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = root
        defer { window.close() }
        root.addSubview(reader); root.addSubview(drawer); drawer.frame = root.bounds
        window.makeFirstResponder(reader.bodyTextView)
        reader.bodyTextView.setSelectedRange(NSRange(location: 0, length: 4))
        // Downstream affinity includes the presentation separator at this
        // paragraph edge. Its canonical selection still contains only text.
        let bodySelection = reader.bodyTextView.selectedRange(), selectionTicket = store.selection?.ticket
        try check(window.firstResponder === reader.bodyTextView && bodySelection == NSRange(location: 0, length: 5) &&
                  store.selection?.fragments.first?.exact == "한글😀", "Body selection before drawer excludes the logical separator")
        drawer.present()
        try check(window.firstResponder === drawer.tableView, "Drawer owns keyboard focus")
        try check(reader.bodyTextView.selectedRange() == bodySelection && store.selection?.ticket == selectionTicket, "Drawer focus keeps body selection")
        drawer.mouseDown(with: pointer(.leftMouseDown, 700))
        try check(reader.bodyTextView.selectedRange() == bodySelection && store.selection?.ticket == selectionTicket &&
            window.firstResponder === reader.bodyTextView, "Scrim dismissal restores body focus and preserves selection")
        try check(!window.isVisible, "All component checks stay offscreen")
        var saved = NativeReaderTextAppearance(); saved.fontSize = 14; try reader.setAppearance(saved)
        try check(reader.textAppearance.fontSize == 14, "Saved 14pt remains valid")
        reader.setFrameSize(NSSize(width: 640, height: 480))
        try check(reader.bodyTextView.textContainerInset.width == 20, "Narrow window padding")
        reader.setFrameSize(NSSize(width: 1001, height: 600))
        try check(reader.renderKey?.width == 680, "Odd viewport width retains canonical measure")
        var editorial = saved; editorial.fontSize = 15; editorial.theme = .dark
        try reader.setAppearance(editorial)
        reader.bodyTextView.setSelectedRange(NSRange(location: 0, length: 0))
        let headings = (1...6).map { (level: Int) in
            node("heading\(level)", .heading, "Title", 0,
                children: [node("headingText\(level)", .text, "Title", 0)], level: level)
        }
        let caption = node("caption", .caption, "12345", 0, children: [node("captionText", .text, "12345", 0)])
        let equationNumber = node("number", .equationNumber, "(1)", 0, children: [node("numberText", .text, "(1)", 0)])
        let annotation = node("annotation", .annotation, "highlight", 0, children: [node("highlightText", .text, "highlight", 0)])
        let nextGeneration = try store.beginRequest()
        let typographyDocument = NativeReaderDocument(schemaVersion: 1, identity: identity, generation: nextGeneration,
            requiredCapabilities: ["semantic-tree-v1"], blocks: headings + [caption, equationNumber, annotation], assets: [], diagnostics: [])
        try reader.adopt(typographyDocument, context: .init(requestID: UUID(), viewID: store.viewID, generation: nextGeneration, target: identity))
        let styled = reader.bodyTextView.textStorage!, dark = reader.designPalette
        for (index, scale) in [CGFloat(1.8), 1.48, 1.24, 1.08, 1.08, 1.08].enumerated() {
            let font = styled.attribute(.font, at: index * 6, effectiveRange: nil) as! NSFont
            try check(abs(font.pointSize - 15 * scale) < 0.01, "Heading \(index + 1) typography scale")
            let color = styled.attribute(.foregroundColor, at: index * 6, effectiveRange: nil) as! NSColor
            try check(components(color) == components(index >= 4 ? dark.secondaryInk : dark.ink), "Heading ink hierarchy")
        }
        for offset in [36, 42] {
            let font = styled.attribute(.font, at: offset, effectiveRange: nil) as! NSFont
            try check(abs(font.pointSize - 13.05) < 0.01, "Caption and equation number use 0.87 scale")
            let widths = (0...9).map {
                CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: String($0), attributes: [.font: font])), nil, nil, nil)
            }
            try check(widths.allSatisfy { abs($0 - widths[0]) < 0.01 }, "Caption and equation number shape actual tabular digits")
            let style = styled.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as! NSParagraphStyle
            try check(style.lineHeightMultiple == 1.5, "Caption rhythm")
        }
        var proportional = NativeReaderTextAppearance(); proportional.fontName = "Georgia"
        let tabular = proportional.tabularFont(size: 13.05)
        let one = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: "111", attributes: [.font: tabular])), nil, nil, nil)
        let eight = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: "888", attributes: [.font: tabular])), nil, nil, nil)
        try check(abs(one - eight) < 0.01, "Proportional custom font gets tabular caption fallback")
        try check(components(styled.attribute(.backgroundColor, at: 46, effectiveRange: nil) as! NSColor) == components(dark.highlight), "Dark palette highlight")
        try check(components(reader.bodyTextView.selectedTextAttributes[.backgroundColor] as! NSColor) == components(dark.selection), "Dark selection palette")
        try save(["checks": checks, "guiVerified": false], output, "reader-parity-observations")
    }
#endif

}
