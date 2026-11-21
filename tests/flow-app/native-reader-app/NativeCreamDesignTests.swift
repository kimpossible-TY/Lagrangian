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
        // Independent author-fixed light starting colors, evaluated after native sRGB resolution.
        let p = NativeAppDesign.palette(.init(theme: .light))
        for (color, bytes) in [(p.paper, [247,242,232]), (p.ink, [41,39,34]),
                               (p.panel, [255,252,245]), (p.accent, [81,74,131])] {
            try check(zip(components(color), bytes).allSatisfy { abs($0.0 * 255 - Double($0.1)) < 0.001 }, "Light source color")
        }
        for preference in combinations() {
            let p = NativeAppDesign.palette(preference)
            var ratios = [String: Double]()
            for (name, foreground, background, minimum) in [
                ("paperText", p.ink, p.paper, 4.5), ("panelText", p.ink, p.panel, 4.5),
                ("secondary", p.secondaryInk, p.panel, 4.5), ("accent", p.accent, p.paper, 4.5),
                ("selection", p.ink, p.selection, 4.5), ("edgePaper", p.boundary, p.paper, 3.0),
                ("edgePanel", p.boundary, p.panel, 3.0), ("warning", p.warning, p.panel, 4.5),
                ("error", p.error, p.panel, 4.5)] {
                let ratio = contrast(foreground, background); ratios[name] = ratio
                try check(ratio >= minimum, "\(preference) \(name) contrast \(ratio)")
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
}
