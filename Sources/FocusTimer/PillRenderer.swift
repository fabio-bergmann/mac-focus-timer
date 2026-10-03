import AppKit
import FocusTimerCore

/// How the menu bar item is set to look.
struct PillStyle: Equatable {
    /// The bar colour, alpha included.
    var bar: NSColor
    var weight: PillFontWeight = .semibold
    var width: PillWidth = .fixed(PillWidth.defaultFixed)
}

extension PillFontWeight {
    var fontWeight: NSFont.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Draws the menu bar item: the time centred in a rounded rectangle with a
/// white outline, and a translucent bar behind it that drains as time runs out.
enum PillRenderer {
    static let height: CGFloat = 18
    private static let cornerRadius: CGFloat = 5
    private static let lineWidth: CGFloat = 1.25

    /// - Parameter darkMenuBar: whether the menu bar wants light content.
    /// - Parameter devMarker: adds an orange dot, so the dev build can be told
    ///   from the installed one sitting next to it.
    static func image(for content: PillContent, style: PillStyle, darkMenuBar: Bool, devMarker: Bool = false) -> NSImage {
        let pill = pill(for: content, style: style, darkMenuBar: darkMenuBar)
        guard devMarker else { return pill }
        return NSImage(size: pill.size, flipped: false) { rect in
            pill.draw(in: rect)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 5, height: 5)).fill()
            return true
        }
    }

    private static func pill(for content: PillContent, style: PillStyle, darkMenuBar: Bool) -> NSImage {
        let bar = style.bar
        let foreground: NSColor = darkMenuBar ? .white : NSColor(white: 0, alpha: 0.85)
        let strength: CGFloat = content.dimmed ? 0.5 : 1

        guard let text = content.text else {
            // No time to show: the same outline as a small square. Empty when
            // idle, filled with the bar colour for a moment after a timer ends.
            return NSImage(size: NSSize(width: height, height: height), flipped: false) { rect in
                let outline = NSBezierPath(
                    roundedRect: rect.insetBy(dx: 1.5, dy: 1.5),
                    xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5
                )
                if content.fraction > 0 {
                    bar.setFill()
                    outline.fill()
                }
                outline.lineWidth = lineWidth
                foreground.withAlphaComponent(0.85).setStroke()
                outline.stroke()
                return true
            }
        }

        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: style.weight.fontWeight),
            .foregroundColor: foreground.withAlphaComponent(strength),
        ])
        let textSize = label.size()
        let size = NSSize(width: style.width.width(forText: textSize.width), height: height)

        return NSImage(size: size, flipped: false) { rect in
            let frame = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let outline = NSBezierPath(roundedRect: frame, xRadius: cornerRadius, yRadius: cornerRadius)

            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            let alpha = bar.alphaComponent * (content.dimmed ? 0.6 : 1)
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
