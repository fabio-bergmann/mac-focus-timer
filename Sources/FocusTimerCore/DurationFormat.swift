import Foundation

/// How the remaining time reads in the menu bar.
public enum DisplayStyle: String, Codable, CaseIterable {
    /// "25m", "1h 5m", and seconds only in the last minute.
    case compact
    /// "24:59", "1:04:59".
    case precise
}

public enum DurationFormat {
    /// "1 hr 30 min", "34 min", "45 sec"
    public static func spoken(_ seconds: Int) -> String {
        join(seconds) { value, unit in
            switch unit {
            case .hour: "\(value) hr"
            case .minute: "\(value) min"
            case .second: "\(value) sec"
            }
        }
    }

    /// "1 hour 30 minutes"
    public static func long(_ seconds: Int) -> String {
        join(seconds) { value, unit in
            let name: String
            switch unit {
            case .hour: name = "hour"
            case .minute: name = "minute"
            case .second: name = "second"
            }
            return "\(value) \(name)\(value == 1 ? "" : "s")"
        }
    }

    /// "1h30m"
    public static func compact(_ seconds: Int) -> String {
        join(seconds, separator: "") { value, unit in
            switch unit {
            case .hour: "\(value)h"
            case .minute: "\(value)m"
            case .second: "\(value)s"
            }
        }
    }

    /// The text inside the menu bar pill. Rounds up, so a fresh 25 minute timer
    /// reads "25m" rather than "24m".
    public static func menuBar(_ remaining: TimeInterval, style: DisplayStyle) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        switch style {
        case .precise:
            let (hours, minutes, seconds) = split(total)
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%d:%02d", minutes, seconds)
        case .compact:
            if total < 60 { return "\(total)s" }
            let minutes = (total + 59) / 60
            if minutes < 60 { return "\(minutes)m" }
            return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
        }
    }

    private enum Part { case hour, minute, second }

    private static func split(_ seconds: Int) -> (hours: Int, minutes: Int, seconds: Int) {
        (seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }

    private static func join(_ seconds: Int, separator: String = " ", _ format: (Int, Part) -> String) -> String {
        let (hours, minutes, rest) = split(max(0, seconds))
        var parts: [String] = []
        if hours > 0 { parts.append(format(hours, .hour)) }
        if minutes > 0 { parts.append(format(minutes, .minute)) }
        if rest > 0 || parts.isEmpty { parts.append(format(rest, .second)) }
        return parts.joined(separator: separator)
    }
}
