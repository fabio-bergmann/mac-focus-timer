import Foundation

/// What the menu bar item shows, before any drawing.
public struct PillContent: Equatable {
    /// How long a finished timer keeps blinking for attention.
    public static let pulseDuration: TimeInterval = 10

    /// Nil when idle: an empty rounded square.
    public var text: String?
    /// Share of the bar behind the text that is filled, 0...1.
    public var fraction: Double
    /// Paused.
    public var dimmed: Bool
    /// The "on" beat of a finished timer's blink.
    public var highlighted: Bool

    public init(text: String?, fraction: Double = 0, dimmed: Bool = false, highlighted: Bool = false) {
        self.text = text
        self.fraction = fraction
        self.dimmed = dimmed
        self.highlighted = highlighted
    }

    public static func make(state: TimerState, now: Date, style: DisplayStyle) -> PillContent {
        switch state.phase {
        case .idle:
            return PillContent(text: nil)
        case .running, .paused:
            let remaining = state.remaining(now: now) ?? 0
            return PillContent(
                text: DurationFormat.menuBar(remaining, style: style),
                fraction: state.fraction(now: now),
                dimmed: state.isPaused
            )
        case .finished(let at, _, _):
            let elapsed = now.timeIntervalSince(at)
            let blinking = elapsed >= 0 && elapsed < pulseDuration
            return PillContent(text: "Done", fraction: 1, highlighted: blinking && Int(elapsed) % 2 == 0)
        }
    }
}

/// How heavy the time is drawn in the menu bar.
public enum PillFontWeight: String, Codable, CaseIterable, Sendable {
    case light, regular, medium, semibold, bold

    public var title: String { rawValue.capitalized }
}

/// How wide the menu bar item is while it shows a time.
public enum PillWidth: Equatable, Sendable {
    /// As wide as the time needs, so it changes as the timer counts down.
    case automatic
    /// The same width whatever the time, so the menu bar stays still.
    case fixed(Double)

    public static let defaultFixed = 56.0
    public static let fixedRange = 30.0...120.0

    /// The item's width for a time that measures `textWidth`. A fixed width
    /// gives way only when the time wouldn't fit inside it.
    public func width(forText textWidth: Double) -> Double {
        let text = textWidth.rounded(.up)
        switch self {
        case .automatic: return max(30, text + 24)
        case .fixed(let width): return max(width, text + 8)
        }
    }
}

/// An sRGB colour read from "#RRGGBB" (or "#RGB").
public struct RGB: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    public var hex: String {
        func byte(_ component: Double) -> Int { Int((component * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
