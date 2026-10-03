import XCTest
@testable import FocusTimerCore

final class TimerStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testRunsDownAndFinishesOnce() {
        var state = TimerState()
        state.start(seconds: 600, label: "tea", now: start)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.remaining(now: start), 600)
        XCTAssertEqual(state.fraction(now: start.addingTimeInterval(150)), 0.75)
        XCTAssertFalse(state.tick(now: start.addingTimeInterval(599)))

        XCTAssertTrue(state.tick(now: start.addingTimeInterval(600)))
        XCTAssertEqual(state.phase, .finished(at: start.addingTimeInterval(600), total: 600, label: "tea"))
        XCTAssertFalse(state.tick(now: start.addingTimeInterval(700)))
        XCTAssertFalse(state.isActive)

        state.acknowledge()
        XCTAssertEqual(state.phase, .idle)
    }

    func testPauseHoldsTheRemainingTime() {
        var state = TimerState()
        state.start(seconds: 600, label: nil, now: start)
        state.pause(now: start.addingTimeInterval(100))

        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(state.remaining(now: start.addingTimeInterval(5000)), 500)
        XCTAssertFalse(state.tick(now: start.addingTimeInterval(5000)))

        state.resume(now: start.addingTimeInterval(5000))
        XCTAssertEqual(state.endDate, start.addingTimeInterval(5500))
    }

    func testAddExtendsWithoutOverfillingTheBar() {
        var state = TimerState()
        state.start(seconds: 600, label: nil, now: start)
        state.add(seconds: 300, now: start)

        XCTAssertEqual(state.remaining(now: start), 900)
        XCTAssertEqual(state.fraction(now: start), 1)

        state.pause(now: start)
        state.add(seconds: 60, now: start)
        XCTAssertEqual(state.remaining(now: start), 960)
    }

    func testStopAndIgnoredTransitions() {
        var state = TimerState()
        state.pause(now: start)
        state.resume(now: start)
        state.add(seconds: 60, now: start)
        XCTAssertEqual(state.phase, .idle)

        state.start(seconds: 60, label: nil, now: start)
        state.stop()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.remaining(now: start))
    }

    func testSurvivesEncoding() throws {
        var state = TimerState()
        state.start(seconds: 1500, label: "write", now: start)
        let decoded = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}

final class FormatTests: XCTestCase {
    func testSpokenAndFriends() {
        XCTAssertEqual(DurationFormat.spoken(5400), "1 hr 30 min")
        XCTAssertEqual(DurationFormat.spoken(2040), "34 min")
        XCTAssertEqual(DurationFormat.spoken(90), "1 min 30 sec")
        XCTAssertEqual(DurationFormat.spoken(0), "0 sec")
        XCTAssertEqual(DurationFormat.long(3660), "1 hour 1 minute")
        XCTAssertEqual(DurationFormat.long(7200), "2 hours")
        XCTAssertEqual(DurationFormat.compact(5400), "1h30m")
    }

    func testCompactMenuBarRoundsUp() {
        XCTAssertEqual(DurationFormat.menuBar(1500, style: .compact), "25m")
        XCTAssertEqual(DurationFormat.menuBar(1499.2, style: .compact), "25m")
        XCTAssertEqual(DurationFormat.menuBar(1440, style: .compact), "24m")
        XCTAssertEqual(DurationFormat.menuBar(60, style: .compact), "1m")
        XCTAssertEqual(DurationFormat.menuBar(59.5, style: .compact), "1m")
        XCTAssertEqual(DurationFormat.menuBar(59, style: .compact), "59s")
        XCTAssertEqual(DurationFormat.menuBar(3600, style: .compact), "1h")
        XCTAssertEqual(DurationFormat.menuBar(3900, style: .compact), "1h 5m")
        XCTAssertEqual(DurationFormat.menuBar(-3, style: .compact), "0s")
    }

    func testPreciseMenuBar() {
        XCTAssertEqual(DurationFormat.menuBar(1499.2, style: .precise), "25:00")
        XCTAssertEqual(DurationFormat.menuBar(1499, style: .precise), "24:59")
        XCTAssertEqual(DurationFormat.menuBar(3899, style: .precise), "1:04:59")
        XCTAssertEqual(DurationFormat.menuBar(5, style: .precise), "0:05")
    }

    func testPillContent() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var state = TimerState()
        XCTAssertNil(PillContent.make(state: state, now: start, style: .compact).text)

        state.start(seconds: 1200, label: nil, now: start)
        let running = PillContent.make(state: state, now: start.addingTimeInterval(300), style: .compact)
        XCTAssertEqual(running, PillContent(text: "15m", fraction: 0.75))

        state.pause(now: start.addingTimeInterval(300))
        XCTAssertTrue(PillContent.make(state: state, now: start.addingTimeInterval(900), style: .compact).dimmed)

        state.resume(now: start.addingTimeInterval(300))
        _ = state.tick(now: start.addingTimeInterval(1200))
        let done = PillContent.make(state: state, now: start.addingTimeInterval(1200.5), style: .compact)
        XCTAssertEqual(done, PillContent(text: "Done", fraction: 1, highlighted: true))
        XCTAssertFalse(PillContent.make(state: state, now: start.addingTimeInterval(1201.5), style: .compact).highlighted)
        XCTAssertFalse(PillContent.make(state: state, now: start.addingTimeInterval(1260), style: .compact).highlighted)
    }

    func testPillWidth() {
        // Fitted: the text plus room either side, never narrower than 30.
        XCTAssertEqual(PillWidth.automatic.width(forText: 25.2), 50)
        XCTAssertEqual(PillWidth.automatic.width(forText: 3), 30)
        // Fixed: the chosen width, until the time would not fit.
        XCTAssertEqual(PillWidth.fixed(56).width(forText: 25.2), 56)
        XCTAssertEqual(PillWidth.fixed(56).width(forText: 48), 56)
        XCTAssertEqual(PillWidth.fixed(56).width(forText: 51.4), 60)
        XCTAssertEqual(PillWidth.defaultFixed, 56)
    }

    func testHexColours() {
        XCTAssertEqual(RGB(hex: "#A855F7")?.hex, "#A855F7")
        XCTAssertEqual(RGB(hex: "a855f7")?.hex, "#A855F7")
        XCTAssertEqual(RGB(hex: "#fff")?.hex, "#FFFFFF")
        XCTAssertNil(RGB(hex: "#12345"))
        XCTAssertNil(RGB(hex: "purple"))
    }
}
