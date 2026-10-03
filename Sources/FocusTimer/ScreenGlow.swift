import AppKit

extension NSColor {
    /// "Done" is green whatever colour the bar is set to: the glow around the
    /// screen and the filled square in the menu bar both use it.
    static let timerFinished = NSColor(srgbRed: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1)
}

/// The flourish when a timer ends: a green glow that rises around the edges of
/// every screen once and fades. It sits above everything, menu bar included,
/// and takes neither clicks nor focus.
final class ScreenGlow {
    static let duration: TimeInterval = 3

    /// How far in from the edge the glow reaches, as a share of the screen's
    /// shorter side.
    private static let reach: CGFloat = 0.12
    /// Brightest at the edge, falling away quickly, then trailing off.
    private static let falloff: [(location: Double, alpha: CGFloat)] = [
        (0, 0.8), (0.15, 0.55), (0.35, 0.28), (0.6, 0.1), (1, 0),
    ]

    private var windows: [NSWindow] = []
    private var run = 0

    func play() {
        stop()
        run += 1
        let current = run

        for screen in NSScreen.screens {
            let window = NSPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none

            let layer = Self.layer(size: screen.frame.size)
            // Invisible once the animation has run its course.
            layer.opacity = 0
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.layer = layer
            view.wantsLayer = true
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            layer.add(Self.animation, forKey: "glow")
            windows.append(window)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { [weak self] in
            guard let self, self.run == current else { return }
            self.stop()
        }
    }

    func stop() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    /// Four gradients, one along each edge. Where two meet in a corner they
    /// add up, which rounds the glow off there.
    static func layer(size: CGSize) -> CALayer {
        let color = NSColor.timerFinished
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        let depth = min(size.width, size.height) * reach
        // A view's layers measure up from the bottom, so y = 1 is the top edge.
        let edges: [(frame: CGRect, edge: CGPoint, inward: CGPoint)] = [
            (CGRect(x: 0, y: size.height - depth, width: size.width, height: depth), CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)),
            (CGRect(x: 0, y: 0, width: size.width, height: depth), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
            (CGRect(x: 0, y: 0, width: depth, height: size.height), CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
            (CGRect(x: size.width - depth, y: 0, width: depth, height: size.height), CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)),
        ]
        root.sublayers = edges.map { edge in
            let gradient = CAGradientLayer()
            gradient.frame = edge.frame
            gradient.startPoint = edge.edge
            gradient.endPoint = edge.inward
            gradient.colors = falloff.map { color.withAlphaComponent($0.alpha).cgColor }
            gradient.locations = falloff.map { NSNumber(value: $0.location) }
            return gradient
        }
        return root
    }

    private static var animation: CAAnimation {
        // One pulse: up quickly, a short hold, then a slower fade.
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 1, 0]
        animation.keyTimes = [0, 0.15, 0.45, 1]
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.duration = duration
        return animation
    }
}
