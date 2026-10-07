import AppKit
import FocusTimerCore

/// What shows while the menu bar item is pulled down onto the screen: a line
/// hanging from the menu bar to the pointer, the item's square under the
/// pointer, and beside it the timer that letting go would start. Like the
/// glow, it sits above everything and takes neither clicks nor focus.
final class DragTimerOverlay {
    private var window: NSWindow?
    private var scene: DragTimerScene?
    /// Where the line hangs from, in screen coordinates.
    private var anchor = NSPoint.zero

    /// Starts a pull that began at `start`, a point on the menu bar item.
    func begin(at start: NSPoint, bar: NSColor) {
        end()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(start, $0.frame, false) }) ?? NSScreen.main else { return }
        let frame = screen.frame
        // The bottom of the menu bar, under the press. A menu bar that hides
        // itself takes no room from the visible frame.
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        anchor = NSPoint(x: start.x, y: min(start.y, frame.maxY - (menuBar > 0 ? menuBar : NSStatusBar.system.thickness)))

        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none

        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scene = DragTimerScene(size: frame.size, scale: screen.backingScaleFactor, bar: bar, dark: dark)
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.layer = scene.root
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
        self.window = window
        self.scene = scene
    }

    /// Moves the pull to `pointer` and returns the timer, in seconds, that
    /// letting go there would start, or nil for none.
    @discardableResult
    func follow(_ pointer: NSPoint, now: Date) -> Int? {
        guard let window, let scene else { return nil }
        let frame = window.frame
        // Off this screen, the knob waits at its edge.
        let point = NSPoint(x: min(max(pointer.x, frame.minX), frame.maxX), y: min(max(pointer.y, frame.minY), frame.maxY))
        let seconds = DragDial.seconds(forDistance: hypot(point.x - anchor.x, point.y - anchor.y))
        scene.layout(
            anchor: NSPoint(x: anchor.x - frame.minX, y: anchor.y - frame.minY),
            pointer: NSPoint(x: point.x - frame.minX, y: point.y - frame.minY),
            readout: seconds.map { DragTimerScene.Readout(seconds: $0, now: now) }
        )
        return seconds
    }

    func end() {
        window?.orderOut(nil)
        window = nil
        scene = nil
    }
}

/// The overlay's layers, laid out for one position of the pointer. Apart from
/// the window so the previews can render them too.
final class DragTimerScene {
    struct Readout: Equatable {
        var title: String
        var detail: String

        init(seconds: Int, now: Date, clock: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }) {
            title = DurationFormat.spoken(seconds)
            detail = "ends \(clock(now.addingTimeInterval(TimeInterval(seconds))))"
        }
    }

    let root = CALayer()
    private let casing = CAShapeLayer()
    private let line = CAShapeLayer()
    private let knob = CALayer()
    private let bubble = CALayer()
    private let scale: CGFloat
    private let dark: Bool
    private var drawn: Readout?
    /// The bubble's card, without the room around it for its shadow.
    private var cardSize = CGSize.zero

    private static let knobSize: CGFloat = 18
    /// Between the knob and the bubble.
    private static let gap: CGFloat = 10
    /// Room around a drawing for its shadow.
    private static let shadowMargin: CGFloat = 16

    init(size: CGSize, scale: CGFloat, bar: NSColor, dark: Bool) {
        self.scale = scale
        self.dark = dark
        root.frame = CGRect(origin: .zero, size: size)

        // A white line with a faint dark edge, so it shows on any wallpaper.
        casing.strokeColor = NSColor(white: 0, alpha: 0.2).cgColor
        casing.lineWidth = 4
        line.strokeColor = NSColor.white.cgColor
        line.lineWidth = 2
        for layer in [casing, line] {
            layer.fillColor = nil
            layer.lineCap = .round
        }

        let knobImage = Self.knobImage(bar: bar)
        knob.bounds = CGRect(origin: .zero, size: knobImage.size)
        knob.contents = knobImage.layerContents(forContentsScale: scale)
        knob.contentsScale = scale
        bubble.contentsScale = scale

        root.sublayers = [casing, line, bubble, knob]
    }

    /// Points are in the scene's coordinates, which measure up from the bottom.
    func layout(anchor: CGPoint, pointer: CGPoint, readout: Readout?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        knob.position = pointer
        // Within the dead zone there is nothing to set, so nothing to read.
        guard let readout else {
            casing.path = nil
            line.path = nil
            bubble.isHidden = true
            return
        }
        let path = CGMutablePath()
        path.move(to: anchor)
        path.addLine(to: pointer)
        casing.path = path
        line.path = path

        if readout != drawn {
            let image = Self.bubbleImage(readout, dark: dark)
            let margin = Self.shadowMargin * 2
            cardSize = CGSize(width: image.size.width - margin, height: image.size.height - margin)
            bubble.bounds = CGRect(origin: .zero, size: image.size)
            bubble.contents = image.layerContents(forContentsScale: scale)
            drawn = readout
        }
        bubble.isHidden = false

        // Left of the knob, clear of the pointer, unless the screen ends first.
        let bounds = root.bounds.insetBy(dx: 8, dy: 8)
        let reach = Self.knobSize / 2 + Self.gap
        var x = pointer.x - reach - cardSize.width
        if x < bounds.minX { x = pointer.x + reach }
        let y = min(max(pointer.y - cardSize.height / 2, bounds.minY), bounds.maxY - cardSize.height)
        bubble.frame.origin = CGPoint(x: x - Self.shadowMargin, y: y - Self.shadowMargin)
    }

    /// The menu bar item's idle square, filled with the bar colour.
    private static func knobImage(bar: NSColor) -> NSImage {
        let side = knobSize + shadowMargin * 2
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let square = NSBezierPath(
                roundedRect: NSRect(x: shadowMargin, y: shadowMargin, width: knobSize, height: knobSize),
                xRadius: 5, yRadius: 5
            )
            NSGraphicsContext.saveGraphicsState()
            shadow(blur: 6, drop: 1.5, opacity: 0.35).set()
            bar.withAlphaComponent(1).setFill()
            square.fill()
            NSGraphicsContext.restoreGraphicsState()
            square.lineWidth = 1.5
            NSColor.white.setStroke()
            square.stroke()
            return true
        }
    }

    private static func bubbleImage(_ readout: Readout, dark: Bool) -> NSImage {
        let primary: NSColor = dark ? .white : NSColor(white: 0, alpha: 0.85)
        let secondary: NSColor = dark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.5)
        let title = NSAttributedString(string: readout.title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .medium),
            .foregroundColor: primary,
        ])
        let detail = NSAttributedString(string: readout.detail, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: secondary,
        ])
        let titleSize = title.size()
        let detailSize = detail.size()
        let padding = NSSize(width: 14, height: 9)
        let card = NSSize(
            width: (max(titleSize.width, detailSize.width) + padding.width * 2).rounded(.up),
            height: (titleSize.height + detailSize.height + padding.height * 2).rounded(.up)
        )
        let margin = shadowMargin

        return NSImage(size: NSSize(width: card.width + margin * 2, height: card.height + margin * 2), flipped: false) { _ in
            let frame = NSRect(origin: NSPoint(x: margin, y: margin), size: card)
            let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
            // Opaque, so the shadows only fall outside it: a soft one for depth
            // and a tight one to find the edge on a white page.
            let fill = dark ? NSColor(white: 0.17, alpha: 1) : NSColor(srgbRed: 247 / 255, green: 247 / 255, blue: 247 / 255, alpha: 1)
            for cast in [shadow(blur: 14, drop: 5, opacity: 0.22), shadow(blur: 2, drop: 0.5, opacity: 0.12)] {
                NSGraphicsContext.saveGraphicsState()
                cast.set()
                fill.setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            // The panel's light rim.
            let rim = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 11.5, yRadius: 11.5)
            NSColor(white: 1, alpha: dark ? 0.14 : 0.6).setStroke()
            rim.lineWidth = 1
            rim.stroke()

            detail.draw(at: NSPoint(x: frame.minX + padding.width, y: frame.minY + padding.height))
            title.draw(at: NSPoint(x: frame.minX + padding.width, y: frame.minY + padding.height + detailSize.height))
            return true
        }
    }

    private static func shadow(blur: CGFloat, drop: CGFloat, opacity: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -drop)
        shadow.shadowColor = NSColor(white: 0, alpha: opacity)
        return shadow
    }
}
