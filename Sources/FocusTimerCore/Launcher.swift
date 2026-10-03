import Foundation

public enum LauncherAction: Equatable {
    case start(seconds: Int, label: String?)
    case add(seconds: Int)
    case pause
    case resume
    case stop
}

public struct LauncherRow: Equatable, Identifiable {
    public let id: String
    public let icon: Icon
    public let title: String
    public var subtitle: String?
    public var trailing: String?
    public let action: LauncherAction

    public init(id: String, icon: Icon, title: String, subtitle: String? = nil, trailing: String? = nil, action: LauncherAction) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.action = action
    }
}

/// Decides what the panel lists for a query. The typed time always comes
/// first, so Return starts exactly what was typed; presets that match follow.
public enum Launcher {
    public static func rows(
        query: String,
        presets: [String],
        phase: TimerPhase,
        now: Date = Date(),
        calendar: Calendar = .current,
        clock: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) -> [LauncherRow] {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let commands = commands(for: phase, clock: clock)

        func startRow(id: String, icon: Icon, _ timer: ParsedTimer) -> LauncherRow {
            let length = DurationFormat.spoken(timer.seconds)
            let action = LauncherAction.start(seconds: timer.seconds, label: timer.label)
            if let end = timer.endsAt {
                let subtitle = [length, timer.label].compactMap { $0 }.joined(separator: " · ")
                return LauncherRow(id: id, icon: icon, title: "Until \(clock(end))", subtitle: subtitle, action: action)
            }
            let end = now.addingTimeInterval(TimeInterval(timer.seconds))
            return LauncherRow(id: id, icon: icon, title: length, subtitle: timer.label, trailing: "ends \(clock(end))", action: action)
        }

        let presetRows = presets.enumerated().compactMap { index, raw -> (row: LauncherRow, timer: ParsedTimer, keys: [String])? in
            guard let timer = DurationParser.parse(raw, now: now, calendar: calendar) else { return nil }
            return (startRow(id: "preset.\(index)", icon: .timer, timer), timer, searchKeys(raw: raw, timer: timer))
        }

        guard !text.isEmpty else { return commands.map(\.row) + presetRows.map(\.row) }

        // "+10m" or "add 10m" extends the timer that's running.
        var extends = false
        if text.hasPrefix("+") {
            text.removeFirst()
            extends = phase.isActive
        } else if phase.isActive, text.lowercased().hasPrefix("add ") {
            text.removeFirst(4)
            extends = true
        }

        let typed = DurationParser.parse(text, now: now, calendar: calendar)
        if extends {
            guard let typed else { return commands.filter { $0.row.id == "add" }.map(\.row) }
            var trailing: String?
            if case .running(let end, _, _) = phase {
                trailing = "ends \(clock(end.addingTimeInterval(TimeInterval(typed.seconds))))"
            }
            return [LauncherRow(
                id: "typed", icon: .plus, title: "Add \(DurationFormat.spoken(typed.seconds))",
                trailing: trailing, action: .add(seconds: typed.seconds)
            )]
        }

        var rows: [LauncherRow] = []
        if let typed {
            var row = startRow(id: "typed", icon: .play, typed)
            if phase.isActive, typed.label == nil, typed.endsAt == nil { row.subtitle = "Replaces the running timer" }
            rows.append(row)
        }

        let needle = squash(text)
        guard !needle.isEmpty else { return rows }
        rows += commands.filter { command in command.keywords.contains { $0.hasPrefix(needle) } }.map(\.row)
        rows += presetRows.filter { preset in
            if let typed, typed.endsAt == nil, preset.timer.endsAt == nil,
               typed.seconds == preset.timer.seconds, typed.label == preset.timer.label {
                return false
            }
            return preset.keys.contains { $0.contains(needle) }
        }.map(\.row)
        return rows
    }

    private static func commands(for phase: TimerPhase, clock: (Date) -> String) -> [(row: LauncherRow, keywords: [String])] {
        let stop = (LauncherRow(id: "stop", icon: .stop, title: "Stop timer", action: .stop), ["stop", "cancel", "end", "clear"])
        let addKeywords = ["add", "extend"]
        switch phase {
        case .running(let end, _, _):
            return [
                (LauncherRow(id: "pause", icon: .pause, title: "Pause timer", action: .pause), ["pause", "hold"]),
                (LauncherRow(id: "add", icon: .plus, title: "Add 5 min", trailing: "ends \(clock(end.addingTimeInterval(300)))", action: .add(seconds: 300)), addKeywords),
                stop,
            ]
        case .paused:
            return [
                (LauncherRow(id: "resume", icon: .play, title: "Resume timer", action: .resume), ["resume", "continue", "play"]),
                (LauncherRow(id: "add", icon: .plus, title: "Add 5 min", action: .add(seconds: 300)), addKeywords),
                stop,
            ]
        case .idle, .finished:
            return []
        }
    }

    /// Every way a preset might be typed, without spaces: "1 hr 30 min",
    /// "1 hour 30 minutes" and "1h30m" all find the same preset.
    private static func searchKeys(raw: String, timer: ParsedTimer) -> [String] {
        var keys = [raw]
        if timer.endsAt == nil {
            keys += [DurationFormat.spoken(timer.seconds), DurationFormat.long(timer.seconds), DurationFormat.compact(timer.seconds)]
        }
        if let label = timer.label { keys.append(label) }
        return keys.map(squash)
    }

    private static func squash(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }
}
