import Foundation

/// What a line of typed input asks for: a countdown length and an optional label.
public struct ParsedTimer: Equatable {
    public var seconds: Int
    /// Set when the input named a clock time ("until 15:30") instead of a length.
    public var endsAt: Date?
    public var label: String?

    public init(seconds: Int, endsAt: Date? = nil, label: String? = nil) {
        self.seconds = seconds
        self.endsAt = endsAt
        self.label = label
    }
}

/// Turns free text into a timer. Understands lengths ("34m", "1h30", "1.5h",
/// "90s", "2:30", "an hour and a half") and clock times ("until 15:30", "3pm").
/// A bare number is minutes. Whatever follows the time becomes the label:
/// "25m write report".
public enum DurationParser {
    public static let maxSeconds = 24 * 60 * 60

    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedTimer? {
        let lexemes = lex(input)
        guard !lexemes.isEmpty else { return nil }
        return parseClockTime(input, lexemes, now: now, calendar: calendar) ?? parseLength(input, lexemes)
    }

    // MARK: - Lexing

    private enum Unit {
        case hour, minute, second

        init?(_ word: String) {
            switch word {
            case "h", "hr", "hrs", "hour", "hours": self = .hour
            case "m", "min", "mins", "minute", "minutes": self = .minute
            case "s", "sec", "secs", "second", "seconds": self = .second
            default: return nil
            }
        }

        var seconds: Double {
            switch self {
            case .hour: 3600
            case .minute: 60
            case .second: 1
            }
        }

        /// The unit a bare trailing number falls into: "1h30" is thirty minutes.
        var smaller: Unit? {
            switch self {
            case .hour: .minute
            case .minute: .second
            case .second: nil
            }
        }
    }

    private struct Lexeme {
        enum Kind {
            case number(Double, raw: String)
            case clock([Int])
            case word(String)
        }

        let kind: Kind
        let start: String.Index
        /// False when the lexeme touches the one before it, as in "1h30".
        let gapBefore: Bool

        var word: String? {
            if case .word(let word) = kind { return word }
            return nil
        }
    }

    private static func lex(_ text: String) -> [Lexeme] {
        var lexemes: [Lexeme] = []
        var index = text.startIndex
        var gap = true

        func isDigit(_ i: String.Index) -> Bool {
            i < text.endIndex && text[i].isASCII && text[i].isNumber
        }
        func endOfDigits(from i: String.Index) -> String.Index {
            var end = i
            while isDigit(end) { end = text.index(after: end) }
            return end
        }

        while index < text.endIndex {
            let character = text[index]
            let start = index
            if isDigit(index) {
                var end = endOfDigits(from: index)
                var parts = [String(text[start..<end])]
                while end < text.endIndex, text[end] == ":", isDigit(text.index(after: end)) {
                    let partStart = text.index(after: end)
                    end = endOfDigits(from: partStart)
                    parts.append(String(text[partStart..<end]))
                }
                if parts.count > 1 {
                    lexemes.append(Lexeme(kind: .clock(parts.map { Int($0) ?? .max }), start: start, gapBefore: gap))
                } else {
                    if end < text.endIndex, text[end] == "." || text[end] == ",", isDigit(text.index(after: end)) {
                        end = endOfDigits(from: text.index(after: end))
                    }
                    let raw = String(text[start..<end])
                    let value = Double(raw.replacingOccurrences(of: ",", with: ".")) ?? .infinity
                    lexemes.append(Lexeme(kind: .number(value, raw: raw), start: start, gapBefore: gap))
                }
                index = end
                gap = false
            } else if character.isLetter {
                var end = index
                while end < text.endIndex, text[end].isLetter { end = text.index(after: end) }
                lexemes.append(Lexeme(kind: .word(text[start..<end].lowercased()), start: start, gapBefore: gap))
                index = end
                gap = false
            } else {
                // Whitespace and punctuation only separate, except "@15:30".
                if character == "@" {
                    lexemes.append(Lexeme(kind: .word("@"), start: start, gapBefore: gap))
                }
                index = text.index(after: index)
                gap = character != "@"
            }
        }
        return lexemes
    }

    // MARK: - Lengths

    private static let fillers: Set<String> = ["timer", "set", "start", "for", "in"]

    private static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90,
    ]

    private static func parseLength(_ text: String, _ lexemes: [Lexeme]) -> ParsedTimer? {
        let count = lexemes.count
        func wordAt(_ i: Int) -> String? { word(lexemes, i) }
        func unitAt(_ i: Int) -> Unit? { wordAt(i).flatMap(Unit.init) }
        func articleAt(_ i: Int) -> Bool { wordAt(i) == "a" || wordAt(i) == "an" }
        func halfAt(_ i: Int) -> Bool { wordAt(i) == "half" }

        var index = 0
        while let filler = wordAt(index), fillers.contains(filler) { index += 1 }

        var total = 0.0
        var lastUnit: Unit?
        var matched = false

        // Consume "<amount> <unit>" groups from the front; the first thing that
        // isn't part of a length starts the label.
        scan: while index < count {
            var i = index
            if matched, wordAt(i) == "and" { i += 1 }
            guard i < count else { break }

            switch lexemes[i].kind {
            case .clock(let parts):
                guard !matched, let seconds = clockLength(parts) else { break scan }
                total = seconds
                matched = true
                index = i + 1
                break scan

            case .number(let value, _):
                if let unit = unitAt(i + 1) {
                    total += value * unit.seconds
                    lastUnit = unit
                    index = i + 2
                } else if wordAt(i + 1) == "and", articleAt(i + 2), halfAt(i + 3), let unit = unitAt(i + 4) {
                    // "1 and a half hours"
                    total += (value + 0.5) * unit.seconds
                    lastUnit = unit
                    index = i + 5
                } else if let smaller = lastUnit?.smaller, !lexemes[i].gapBefore || i == count - 1 {
                    // "1h30" or a closing "1h 30"; a spaced number mid-sentence
                    // ("25m 3 emails") belongs to the label instead.
                    total += value * smaller.seconds
                    index = i + 1
                    break scan
                } else if !matched {
                    total = value * 60
                    matched = true
                    index = i + 1
                    break scan
                } else {
                    break scan
                }
                matched = true

            case .word(let word):
                if word == "half" {
                    // "half an hour", "half hour"
                    let next = articleAt(i + 1) ? i + 2 : i + 1
                    guard let unit = unitAt(next) else { break scan }
                    total += 0.5 * unit.seconds
                    lastUnit = unit
                    index = next + 1
                } else if word == "a" || word == "an" {
                    if halfAt(i + 1), let unit = unitAt(i + 2) {
                        // "a half hour"
                        total += 0.5 * unit.seconds
                        lastUnit = unit
                        index = i + 3
                    } else if halfAt(i + 1), let last = lastUnit {
                        // "an hour and a half"
                        total += 0.5 * last.seconds
                        index = i + 2
                    } else if let unit = unitAt(i + 1) {
                        total += unit.seconds
                        lastUnit = unit
                        index = i + 2
                    } else {
                        break scan
                    }
                } else if var value = numberWords[word] {
                    // "twenty five"
                    var next = i + 1
                    if value >= 20, let ones = wordAt(next).flatMap({ numberWords[$0] }), ones < 10 {
                        value += ones
                        next += 1
                    }
                    if let unit = unitAt(next) {
                        total += value * unit.seconds
                        lastUnit = unit
                        index = next + 1
                    } else if wordAt(next) == "and", articleAt(next + 1), halfAt(next + 2), let unit = unitAt(next + 3) {
                        total += (value + 0.5) * unit.seconds
                        lastUnit = unit
                        index = next + 4
                    } else {
                        break scan
                    }
                } else {
                    break scan
                }
                matched = true
            }
        }

        guard matched, total.isFinite, total >= 0.5, total <= Double(maxSeconds) else { return nil }
        return ParsedTimer(seconds: Int(total.rounded()), label: label(in: text, from: index, lexemes))
    }

    private static func word(_ lexemes: [Lexeme], _ i: Int) -> String? {
        i < lexemes.count ? lexemes[i].word : nil
    }

    /// "2:30" is two and a half minutes, "1:30:00" an hour and a half.
    private static func clockLength(_ parts: [Int]) -> Double? {
        guard parts.allSatisfy({ $0 >= 0 && $0 < 100_000 }) else { return nil }
        switch parts.count {
        case 2 where parts[1] < 60:
            return Double(parts[0] * 60 + parts[1])
        case 3 where parts[1] < 60 && parts[2] < 60:
            return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default:
            return nil
        }
    }

    private static func label(in text: String, from index: Int, _ lexemes: [Lexeme]) -> String? {
        var index = index
        if word(lexemes, index) == "for" { index += 1 }
        guard index < lexemes.count else { return nil }
        let label = text[lexemes[index].start...].trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    // MARK: - Clock times

    private static let clockPrefixes: Set<String> = ["until", "till", "til", "at", "by", "@"]

    private static func parseClockTime(_ text: String, _ lexemes: [Lexeme], now: Date, calendar: Calendar) -> ParsedTimer? {
        var index = 0
        let hasPrefix = lexemes[0].word.map(clockPrefixes.contains) ?? false
        if hasPrefix { index += 1 }
        guard index < lexemes.count else { return nil }

        var hour = 0
        var minute = 0
        switch lexemes[index].kind {
        case .clock(let parts) where parts.count == 2:
            hour = parts[0]
            minute = parts[1]
        case .number(_, let raw):
            // "15.30" is how some locales write 15:30.
            let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
            guard pieces.count <= 2, let parsedHour = Int(pieces[0]) else { return nil }
            hour = parsedHour
            if pieces.count == 2 {
                guard pieces[1].count == 2, let parsedMinute = Int(pieces[1]) else { return nil }
                minute = parsedMinute
            }
        default:
            return nil
        }
        index += 1

        var meridiem: String?
        if let word = word(lexemes, index), word == "am" || word == "pm" {
            meridiem = word
            index += 1
        }
        guard hasPrefix || meridiem != nil else { return nil }
        // "at 5 min" is an oddly prefixed length, not five o'clock.
        if meridiem == nil, word(lexemes, index).flatMap(Unit.init) != nil { return nil }
        guard (0...59).contains(minute) else { return nil }

        let hours: [Int]
        switch meridiem {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            hours = [hour % 12]
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            hours = [hour % 12 + 12]
        default:
            guard (0...23).contains(hour) || (hour == 24 && minute == 0) else { return nil }
            // Without am/pm a small hour means whichever comes next: at 14:00,
            // "until 3" is 15:00.
            hours = (1...12).contains(hour) ? [hour % 12, hour % 12 + 12] : [hour % 24]
        }

        let startOfDay = calendar.startOfDay(for: now)
        let candidates = [0, 1].flatMap { day in
            hours.compactMap { hour -> Date? in
                guard let date = calendar.date(byAdding: .day, value: day, to: startOfDay) else { return nil }
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
            }
        }
        guard let target = candidates.filter({ $0 > now }).min() else { return nil }
        let seconds = max(1, Int(target.timeIntervalSince(now).rounded(.up)))
        return ParsedTimer(seconds: seconds, endsAt: target, label: label(in: text, from: index, lexemes))
    }
}
