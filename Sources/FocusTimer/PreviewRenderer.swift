import AppKit
import FocusTimerCore
import SwiftUI

/// Draws the menu bar pill, the panel and the app icon to PNG files, so the
/// design can be checked, and the icon built, without opening a window.
///
///     swift run FocusTimer --render-previews /tmp/focus-timer-previews
enum PreviewRenderer {
    static func renderPreviews(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Throwaway defaults: previews must not read or touch the real timer.
        let suite = "dev.fabio.focustimer.previews"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = AppSettings(defaults: defaults)

        write(pillSheet(style: settings.pillStyle), to: directory.appendingPathComponent("menu-bar.png"))
        write(screenGlow(), to: directory.appendingPathComponent("screen-glow.png"))
        var fitted = settings.pillStyle
        fitted.width = .automatic
        write(pillSheet(style: fitted), to: directory.appendingPathComponent("menu-bar-fitted.png"))

        for dark in [true, false] {
            let suffix = dark ? "dark" : "light"
            write(dragTimer(style: settings.pillStyle, dark: dark), to: directory.appendingPathComponent("drag-timer-\(suffix).png"))
            let timer = TimerController(defaults: defaults)
            let model = LauncherModel(settings: settings, timer: timer, updates: UpdateService())
            timer.stop()

            snapshot(model, dark: dark, to: directory.appendingPathComponent("panel-presets-\(suffix).png"))
            if let onPage = panelOnPage(model, dark: dark) {
                write(onPage, to: directory.appendingPathComponent("panel-on-page-\(suffix).png"))
            }
            model.query = "1"
            snapshot(model, dark: dark, to: directory.appendingPathComponent("panel-typing-\(suffix).png"))
            model.query = ""
            // A timer nine minutes in, so the bar shows its draining edge. Only a
            // saved state can be backdated, so it goes in the way a relaunch finds it.
            var underway = TimerState()
            underway.start(seconds: 25 * 60, label: "Write report", now: Date().addingTimeInterval(-9 * 60))
            defaults.set(try? JSONEncoder().encode(underway), forKey: TimerController.stateKey)
            let running = LauncherModel(settings: settings, timer: TimerController(defaults: defaults), updates: UpdateService())
            snapshot(running, dark: dark, to: directory.appendingPathComponent("panel-running-\(suffix).png"))
            running.timer.stop()
            model.mode = .settings
            snapshot(model, dark: dark, to: directory.appendingPathComponent("panel-settings-\(suffix).png"))
            // The whole settings page, which scrolls inside the real panel.
            snapshot(
                SettingsView(model: model, settings: settings, updates: model.updates),
                size: NSSize(width: PanelController.size.width, height: 900),
                dark: dark, to: directory.appendingPathComponent("settings-full-\(suffix).png")
            )
        }
        UserDefaults().removePersistentDomain(forName: suite)
        print("Previews written to \(directory.path)")
    }

    // MARK: - Menu bar

    private static func pillSheet(style: PillStyle) -> NSBitmapImageRep {
        let samples = [
            PillContent(text: nil),
            PillContent(text: "25m", fraction: 1),
            PillContent(text: "18m", fraction: 0.72),
            PillContent(text: "1h 5m", fraction: 0.54),
            PillContent(text: "9m", fraction: 0.3),
            PillContent(text: "45s", fraction: 0.03),
            PillContent(text: "24:59", fraction: 0.99),
            PillContent(text: "1:04:59", fraction: 0.6),
            PillContent(text: "12m", fraction: 0.48, dimmed: true),
            PillContent(text: nil, fraction: 1),
        ]
        let scale: CGFloat = 4
        let bandHeight: CGFloat = 32
        let spacing: CGFloat = 16
        let images = { (dark: Bool) in samples.map { PillRenderer.image(for: $0, style: style, darkMenuBar: dark) } }
        let width = images(true).reduce(spacing) { $0 + $1.size.width + spacing }

        return bitmap(width: width, height: bandHeight * 2, scale: scale) {
            for (row, dark) in [(1, true), (0, false)] {
                let band = NSRect(x: 0, y: CGFloat(row) * bandHeight, width: width, height: bandHeight)
                (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.88, alpha: 1)).setFill()
                band.fill()
                var x = spacing
                for image in images(dark) {
                    image.draw(in: NSRect(
                        x: x, y: band.midY - image.size.height / 2,
                        width: image.size.width, height: image.size.height
                    ))
                    x += image.size.width + spacing
                }
            }
        }
    }

    // MARK: - Screen glow

    /// The glow at full strength over a stand-in desktop, half light and half dark.
    private static func screenGlow() -> NSBitmapImageRep {
        let size = NSSize(width: 1280, height: 800)
        return bitmap(width: size.width, height: size.height, scale: 1) {
            NSColor(white: 0.95, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor(white: 0.14, alpha: 1).setFill()
            NSRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height).fill()
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            ScreenGlow.layer(size: size).render(in: context)
        }
    }

    // MARK: - Pulling a timer out of the menu bar

    /// Two pulls side by side on a stand-in screen: a short one with the
    /// bubble on the left, and one at the left edge, where it moves right.
    private static func dragTimer(style: PillStyle, dark: Bool) -> NSBitmapImageRep {
        let size = NSSize(width: 1000, height: 560)
        let menuBar: CGFloat = 24
        let pill = PillRenderer.image(for: PillContent(text: nil), style: style, darkMenuBar: dark)
        let pulls: [(item: CGFloat, pointer: CGPoint)] = [(820, CGPoint(x: 680, y: 340)), (300, CGPoint(x: 60, y: 120))]

        return bitmap(width: size.width, height: size.height, scale: 2) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            NSGradient(
                starting: dark ? NSColor(srgbRed: 0.1, green: 0.16, blue: 0.24, alpha: 1) : NSColor(srgbRed: 0.75, green: 0.84, blue: 0.92, alpha: 1),
                ending: dark ? NSColor(srgbRed: 0.05, green: 0.07, blue: 0.1, alpha: 1) : NSColor(white: 0.97, alpha: 1)
            )?.draw(in: NSRect(origin: .zero, size: size), angle: -90)
            (dark ? NSColor(white: 0, alpha: 0.3) : NSColor(white: 1, alpha: 0.5)).setFill()
            NSRect(x: 0, y: size.height - menuBar, width: size.width, height: menuBar).fill()

            for pull in pulls {
                pill.draw(at: NSPoint(x: pull.item - pill.size.width / 2, y: size.height - (menuBar + pill.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                // The button around the pill, as the menu bar sizes it.
                let button = NSRect(x: pull.item - pill.size.width / 2 - 6, y: size.height - menuBar + 1, width: pill.size.width + 12, height: menuBar - 2)
                let anchor = DragDial.exit(from: button, toward: pull.pointer) ?? pull.pointer
                let seconds = DragDial.seconds(forDistance: hypot(pull.pointer.x - anchor.x, pull.pointer.y - anchor.y))
                let scene = DragTimerScene(size: size, scale: 2, bar: style.bar, dark: dark)
                scene.layout(anchor: anchor, pointer: pull.pointer, readout: seconds.map { DragTimerScene.Readout(seconds: $0, now: Date()) })
                scene.root.render(in: context)
            }
        }
    }

    // MARK: - Panel

    private static func snapshot(_ model: LauncherModel, dark: Bool, to url: URL) {
        snapshot(PanelRootView(model: model), size: PanelController.size, dark: dark, to: url)
    }

    private static func snapshot<Content: View>(_ view: Content, size: NSSize, dark: Bool, to url: URL) {
        if let rep = render(view, size: size, dark: dark) { write(rep, to: url) }
    }

    private static func render<Content: View>(_ view: Content, size: NSSize, dark: Bool) -> NSBitmapImageRep? {
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)

        // Never ordered on screen; the window only gives the view an appearance
        // and something to lay out in.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// The panel as it sits on screen: on a page, with its rim and its shadow.
    /// An approximation: the blur can't be reproduced here, so the glass shows
    /// as a flat fill, and the shadow is PanelShadow's Core Graphics stand-in
    /// for the layers the real window uses.
    private static func panelOnPage(_ model: LauncherModel, dark: Bool) -> NSBitmapImageRep? {
        guard let panel = render(PanelRootView(model: model), size: PanelController.size, dark: dark) else { return nil }
        let margin = PanelShadow.margin
        let page = NSSize(width: PanelController.size.width + margin * 2, height: PanelController.size.height + margin * 2)
        return bitmap(width: page.width, height: page.height, scale: 2) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            (dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white).setFill()
            NSRect(origin: .zero, size: page).fill()
            let frame = NSRect(origin: NSPoint(x: margin, y: margin), size: PanelController.size)
            PanelShadow.draw(around: frame, cornerRadius: PanelController.cornerRadius, scale: 2, in: context)
            NSBezierPath(
                roundedRect: frame, xRadius: PanelController.cornerRadius, yRadius: PanelController.cornerRadius
            ).addClip()
            panel.draw(in: frame)
        }
    }

    // MARK: - Icon

    /// Writes an .iconset folder for `iconutil -c icns`.
    static func renderIconSet(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = CGFloat(points * scale)
                let rep = bitmap(width: pixels, height: pixels, scale: 1) {
                    drawIcon(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                }
                let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                write(rep, to: directory.appendingPathComponent(name))
            }
        }
    }

    /// The pill on a dark plate, drawn on a 1024 grid.
    private static func drawIcon(in rect: NSRect) {
        let unit = rect.width / 1024
        let plate = NSBezierPath(
            roundedRect: NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit),
            xRadius: 185 * unit, yRadius: 185 * unit
        )
        NSGradient(
            starting: NSColor(srgbRed: 0.23, green: 0.18, blue: 0.42, alpha: 1),
            ending: NSColor(srgbRed: 0.09, green: 0.08, blue: 0.17, alpha: 1)
        )?.draw(in: plate, angle: -90)

        let frame = NSRect(x: 222 * unit, y: 382 * unit, width: 580 * unit, height: 260 * unit)
        let pill = NSBezierPath(roundedRect: frame, xRadius: 76 * unit, yRadius: 76 * unit)
        NSGraphicsContext.saveGraphicsState()
        pill.addClip()
        NSColor(hex: AppSettings.defaultBarColorHex, alpha: 0.8)?.setFill()
        NSBezierPath(rect: NSRect(x: frame.minX, y: frame.minY, width: frame.width * 0.62, height: frame.height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        pill.lineWidth = 28 * unit
        NSColor.white.setStroke()
        pill.stroke()
    }

    // MARK: - Bitmaps

    private static func bitmap(width: CGFloat, height: CGFloat, scale: CGFloat, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((width * scale).rounded()), pixelsHigh: Int((height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
