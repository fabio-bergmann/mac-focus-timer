import XCTest
@testable import FocusTimerCore

final class DurationParserTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-03 14:00:00 UTC
    private var afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 14))!
    }

    private func seconds(_ input: String) -> Int? {
        DurationParser.parse(input, now: afternoon, calendar: calendar)?.seconds
    }

    private func parse(_ input: String) -> ParsedTimer? {
        DurationParser.parse(input, now: afternoon, calendar: calendar)
    }

    func testBareNumberIsMinutes() {
        XCTAssertEqual(seconds("1"), 60)
        XCTAssertEqual(seconds("25"), 25 * 60)
        XCTAssertEqual(seconds(" 90 "), 90 * 60)
        XCTAssertEqual(seconds("1.5"), 90)
    }

    func testUnits() {
        XCTAssertEqual(seconds("34m"), 34 * 60)
        XCTAssertEqual(seconds("34M"), 34 * 60)
        XCTAssertEqual(seconds("34 min"), 34 * 60)
        XCTAssertEqual(seconds("34 minutes"), 34 * 60)
        XCTAssertEqual(seconds("1h"), 3600)
        XCTAssertEqual(seconds("1H"), 3600)
        XCTAssertEqual(seconds("2 hours"), 7200)
        XCTAssertEqual(seconds("1 hr"), 3600)
        XCTAssertEqual(seconds("90s"), 90)
        XCTAssertEqual(seconds("45 sec"), 45)
    }

    func testDecimals() {
        XCTAssertEqual(seconds("1.5h"), 5400)
        XCTAssertEqual(seconds("1,5h"), 5400)
        XCTAssertEqual(seconds("0.5m"), 30)
        XCTAssertEqual(seconds("2.5 hours"), 9000)
    }

    func testCombinations() {
        XCTAssertEqual(seconds("1h30"), 5400)
        XCTAssertEqual(seconds("1h30m"), 5400)
        XCTAssertEqual(seconds("1h 30m"), 5400)
        XCTAssertEqual(seconds("1h 30"), 5400)
        XCTAssertEqual(seconds("1 hour 30 minutes"), 5400)
        XCTAssertEqual(seconds("1 hour and 30 minutes"), 5400)
        XCTAssertEqual(seconds("1h, 30m"), 5400)
        XCTAssertEqual(seconds("2m30"), 150)
        XCTAssertEqual(seconds("2m30s"), 150)
        XCTAssertEqual(seconds("1h2m3s"), 3723)
    }

    func testColonLengths() {
        XCTAssertEqual(seconds("2:30"), 150)
        XCTAssertEqual(seconds("25:00"), 1500)
        XCTAssertEqual(seconds("1:30:00"), 5400)
        XCTAssertNil(seconds("1:75"))
    }

    func testWords() {
        XCTAssertEqual(seconds("an hour"), 3600)
        XCTAssertEqual(seconds("a minute"), 60)
        XCTAssertEqual(seconds("half an hour"), 1800)
        XCTAssertEqual(seconds("half hour"), 1800)
        XCTAssertEqual(seconds("an hour and a half"), 5400)
        XCTAssertEqual(seconds("1 and a half hours"), 5400)
        XCTAssertEqual(seconds("two hours"), 7200)
        XCTAssertEqual(seconds("twenty five minutes"), 1500)
        XCTAssertEqual(seconds("forty-five min"), 2700)
        XCTAssertEqual(seconds("timer for 20 minutes"), 1200)
        XCTAssertEqual(seconds("in 10 min"), 600)
    }

    func testLabels() {
        XCTAssertEqual(parse("25m write report"), ParsedTimer(seconds: 1500, label: "write report"))
        XCTAssertEqual(parse("25 Write Report"), ParsedTimer(seconds: 1500, label: "Write Report"))
        XCTAssertEqual(parse("1h30 deep work"), ParsedTimer(seconds: 5400, label: "deep work"))
        XCTAssertEqual(parse("45m for lunch"), ParsedTimer(seconds: 2700, label: "lunch"))
        XCTAssertEqual(parse("25m a quick call"), ParsedTimer(seconds: 1500, label: "a quick call"))
        // A spaced number in the middle of a sentence is label, not seconds.
        XCTAssertEqual(parse("25m 3 emails"), ParsedTimer(seconds: 1500, label: "3 emails"))
        XCTAssertNil(parse("25m")?.label)
    }

    func testRejectsNonsense() {
        XCTAssertNil(seconds(""))
        XCTAssertNil(seconds("   "))
        XCTAssertNil(seconds("hello"))
        XCTAssertNil(seconds("0"))
        XCTAssertNil(seconds("0m"))
        XCTAssertNil(seconds("m"))
        XCTAssertNil(seconds("25h"))
        XCTAssertNil(seconds("99999999999999999999999"))
        XCTAssertNil(seconds("a"))
        XCTAssertNil(seconds("half"))
    }

    func testClockTimes() {
        let until = parse("until 15:30")
        XCTAssertEqual(until?.seconds, 90 * 60)
        XCTAssertEqual(until?.endsAt, afternoon.addingTimeInterval(90 * 60))

        XCTAssertEqual(seconds("til 15:30"), 90 * 60)
        XCTAssertEqual(seconds("at 15.30"), 90 * 60)
        XCTAssertEqual(seconds("@15:30"), 90 * 60)
        XCTAssertEqual(seconds("3pm"), 60 * 60)
        XCTAssertEqual(seconds("3:30 pm"), 90 * 60)
        XCTAssertEqual(seconds("until 3:30pm"), 90 * 60)
    }

    func testClockTimeWithoutMeridiemPicksTheNextOne() {
        // At 14:00, "3" is 15:00 today and "1" is 01:00 tomorrow.
        XCTAssertEqual(seconds("until 3"), 60 * 60)
        XCTAssertEqual(seconds("until 1"), 11 * 3600)
        // A time that has passed today rolls to tomorrow.
        XCTAssertEqual(seconds("until 13:00"), 23 * 3600)
        XCTAssertEqual(seconds("until 9am"), 19 * 3600)
        XCTAssertEqual(seconds("until 0:30"), 10 * 3600 + 30 * 60)
    }

    func testClockTimeLabelsAndLimits() {
        XCTAssertEqual(parse("until 15:30 standup")?.label, "standup")
        XCTAssertNil(seconds("until 25:00"))
        XCTAssertNil(seconds("until 15:75"))
        XCTAssertNil(parse("13pm")?.endsAt)
        XCTAssertNil(seconds("until"))
        // An oddly prefixed length is not a clock time.
        XCTAssertNil(parse("at 5 min")?.endsAt)
        // Without a prefix or am/pm, "15:30" stays a length.
        XCTAssertNil(parse("15:30")?.endsAt)
        XCTAssertEqual(seconds("15:30"), 15 * 60 + 30)
    }
}
