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

        write(pillSheet(bar: settings.barColor), to: directory.appendingPathComponent("menu-bar.png"))

        for dark in [true, false] {
            let suffix = dark ? "dark" : "light"
            let timer = TimerController(defaults: defaults)
            let model = LauncherModel(settings: settings, timer: timer, updates: UpdateService())
            timer.stop()

            snapshot(model, dark: dark, to: directory.appendingPathComponent("panel-presets-\(suffix).png"))
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

    private static func pillSheet(bar: NSColor) -> NSBitmapImageRep {
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
            PillContent(text: "Done", fraction: 1, highlighted: true),
            PillContent(text: "Done", fraction: 1),
        ]
        let scale: CGFloat = 4
        let bandHeight: CGFloat = 32
        let spacing: CGFloat = 16
        let images = { (dark: Bool) in samples.map { PillRenderer.image(for: $0, bar: bar, darkMenuBar: dark) } }
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

    // MARK: - Panel

    private static func snapshot(_ model: LauncherModel, dark: Bool, to url: URL) {
        snapshot(PanelRootView(model: model), size: PanelController.size, dark: dark, to: url)
    }

    private static func snapshot<Content: View>(_ view: Content, size: NSSize, dark: Bool, to url: URL) {
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

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        write(rep, to: url)
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
