import XCTest
@testable import FocusTimerCore

final class LauncherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let presets = ["5m", "15m", "25m", "30m", "45m", "1h", "1h 30m", "2h"]

    private func rows(_ query: String, phase: TimerPhase = .idle, presets: [String]? = nil) -> [LauncherRow] {
        Launcher.rows(query: query, presets: presets ?? self.presets, phase: phase, now: now, clock: { _ in "12:00" })
    }

    private var running: TimerPhase {
        .running(end: now.addingTimeInterval(600), total: 1200, label: nil)
    }

    func testEmptyQueryListsEveryPreset() {
        let rows = rows("")
        XCTAssertEqual(rows.map(\.title), ["5 min", "15 min", "25 min", "30 min", "45 min", "1 hr", "1 hr 30 min", "2 hr"])
        XCTAssertEqual(rows.first?.action, .start(seconds: 300, label: nil))
    }

    func testTypedTimeComesFirstThenMatchingPresets() {
        let rows = rows("1")
        XCTAssertEqual(rows.map(\.title), ["1 min", "15 min", "1 hr", "1 hr 30 min"])
        XCTAssertEqual(rows.first?.id, "typed")
        XCTAssertEqual(rows.first?.action, .start(seconds: 60, label: nil))
    }

    func testTypedTimeIsNotRepeatedAsAPreset() {
        XCTAssertEqual(rows("25").map(\.title), ["25 min"])
        XCTAssertEqual(rows("1h").map(\.title), ["1 hr", "1 hr 30 min"])
        XCTAssertEqual(rows("34m").map(\.title), ["34 min"])
    }

    func testPresetsMatchHoweverTheyAreSpelled() {
        XCTAssertEqual(rows("hour").map(\.title), ["1 hr", "1 hr 30 min", "2 hr"])
        XCTAssertEqual(rows("90m").map(\.id), ["typed"])
        XCTAssertEqual(rows("1 hr 3").map(\.title), ["1 hr 3 min", "1 hr 30 min"])
    }

    func testLabelsCarryThrough() {
        let typed = rows("25m write report")[0]
        XCTAssertEqual(typed.subtitle, "write report")
        XCTAssertEqual(typed.action, .start(seconds: 1500, label: "write report"))

        let labelled = rows("pomo", presets: ["25m Pomodoro", "5m Break"])
        XCTAssertEqual(labelled.map(\.subtitle), ["Pomodoro"])
    }

    func testUnparsableQueryStillFiltersPresets() {
        XCTAssertEqual(rows("xyz"), [])
        XCTAssertEqual(rows("min").count, 6)
    }

    func testRunningTimerOffersControlsFirst() {
        let rows = rows("", phase: running)
        XCTAssertEqual(rows.prefix(3).map(\.action), [.pause, .add(seconds: 300), .stop])
        XCTAssertEqual(rows.count, 3 + presets.count)

        let paused = self.rows("", phase: .paused(remaining: 600, total: 1200, label: nil))
        XCTAssertEqual(paused.prefix(3).map(\.action), [.resume, .add(seconds: 300), .stop])
    }

    func testCommandsMatchByPrefix() {
        XCTAssertEqual(rows("st", phase: running).map(\.action), [.stop])
        XCTAssertEqual(rows("pau", phase: running).map(\.action), [.pause])
        XCTAssertEqual(rows("stop"), [])
    }

    func testPlusExtendsARunningTimer() {
        XCTAssertEqual(rows("+10m", phase: running).map(\.action), [.add(seconds: 600)])
        XCTAssertEqual(rows("add 2", phase: running).map(\.action), [.add(seconds: 120)])
        XCTAssertEqual(rows("+", phase: running).map(\.action), [.add(seconds: 300)])
        // With nothing running, "+10m" simply starts ten minutes.
        XCTAssertEqual(rows("+10m").first?.action, .start(seconds: 600, label: nil))
    }

    func testTypingWhileRunningWarnsAboutReplacing() {
        XCTAssertEqual(rows("40m", phase: running).first?.subtitle, "Replaces the running timer")
    }

    func testBrokenPresetsAreSkipped() {
        XCTAssertEqual(rows("", presets: ["10m", "nope", ""]).map(\.title), ["10 min"])
    }
}
