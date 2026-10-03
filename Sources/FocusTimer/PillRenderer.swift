import AppKit
import FocusTimerCore

/// Draws the menu bar item: the time centred in a rounded rectangle with a
/// white outline, and a translucent bar behind it that drains as time runs out.
enum PillRenderer {
    static let height: CGFloat = 18
    private static let cornerRadius: CGFloat = 5
    private static let lineWidth: CGFloat = 1.25

    /// - Parameter bar: the bar colour, alpha included.
    /// - Parameter darkMenuBar: whether the menu bar wants light content.
    /// - Parameter devMarker: adds an orange dot, so the dev build can be told
    ///   from the installed one sitting next to it.
    static func image(for content: PillContent, bar: NSColor, darkMenuBar: Bool, devMarker: Bool = false) -> NSImage {
        let pill = pill(for: content, bar: bar, darkMenuBar: darkMenuBar)
        guard devMarker else { return pill }
        return NSImage(size: pill.size, flipped: false) { rect in
            pill.draw(in: rect)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)).fill()
            return true
        }
    }

    private static func pill(for content: PillContent, bar: NSColor, darkMenuBar: Bool) -> NSImage {
        let foreground: NSColor = darkMenuBar ? .white : NSColor(white: 0, alpha: 0.85)
        let strength: CGFloat = content.dimmed ? 0.5 : 1

        guard let text = content.text else {
            // Idle: the same outline, empty and square.
            return NSImage(size: NSSize(width: height, height: height), flipped: false) { rect in
                let outline = NSBezierPath(
                    roundedRect: rect.insetBy(dx: 1.5, dy: 1.5),
                    xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5
                )
                outline.lineWidth = lineWidth
                foreground.withAlphaComponent(0.85).setStroke()
                outline.stroke()
                return true
            }
        }

        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: foreground.withAlphaComponent(strength),
        ])
        let textSize = label.size()
        let size = NSSize(width: max(30, ceil(textSize.width) + 14), height: height)

        return NSImage(size: size, flipped: false) { rect in
            let frame = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let outline = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)

            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            let alpha = min(1, bar.alphaComponent * (content.dimmed ? 0.6 : 1) + (content.highlighted ? 0.35 : 0))
            bar.withAlphaComponent(alpha).setFill()
            var fill = frame
            fill.size.width = frame.width * min(1, max(0, content.fraction))
            NSBezierPath(rect: fill).fill()
            NSGraphicsContext.restoreGraphicsState()

            outline.lineWidth = lineWidth
            foreground.withAlphaComponent(0.9 * strength).setStroke()
            outline.stroke()

            label.draw(at: NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            ))
            return true
        }
    }
}
