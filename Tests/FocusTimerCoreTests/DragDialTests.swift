import XCTest
@testable import FocusTimerCore

final class DragDialTests: XCTestCase {
    /// Every length a pull can set, sampled every half point up to the far
    /// corner of a large screen and beyond.
    private func pulls(step: Int = 1) -> [Int?] {
        stride(from: 0.0, through: 4000, by: 0.5).map { DragDial.seconds(forDistance: $0, step: step) }
    }

    func testDeadZoneSetsNothing() {
        XCTAssertNil(DragDial.seconds(forDistance: 0))
        XCTAssertNil(DragDial.seconds(forDistance: DragDial.deadZone - 0.1))
        XCTAssertEqual(DragDial.seconds(forDistance: DragDial.deadZone), 60)
    }

    func testAnHourAtItsReach() {
        XCTAssertEqual(DragDial.seconds(forDistance: DragDial.deadZone + DragDial.hourReach), 3600)
    }

    func testNeverStepsBack() {
        for step in [1, DragDial.coarseStep] {
            let lengths = pulls(step: step).compactMap { $0 }
            XCTAssertEqual(lengths, lengths.sorted())
        }
    }

    func testEveryMinuteCanBeSet() {
        let reached = Set(pulls().compactMap { $0 }).map { $0 / 60 }.sorted()
        XCTAssertEqual(reached, Array(1...720))
    }

    func testCommandSetsQuarterHours() {
        XCTAssertEqual(DragDial.seconds(forDistance: DragDial.deadZone, step: DragDial.coarseStep), 15 * 60)
        let reached = Set(pulls(step: DragDial.coarseStep).compactMap { $0 }).map { $0 / 60 }.sorted()
        XCTAssertEqual(reached, Array(stride(from: 15, through: 720, by: 15)))
    }

    func testLeavesTheItemOnTheLineFromItsMiddle() {
        let item = CGRect(x: 100, y: 0, width: 40, height: 20)
        // Straight down, out through the bottom edge.
        XCTAssertEqual(DragDial.exit(from: item, toward: CGPoint(x: 120, y: -150)), CGPoint(x: 120, y: 0))
        // Steeply down and left, still through the bottom.
        XCTAssertEqual(DragDial.exit(from: item, toward: CGPoint(x: 40, y: -150)), CGPoint(x: 115, y: 0))
        // Shallowly left, out through the side.
        XCTAssertEqual(DragDial.exit(from: item, toward: CGPoint(x: -40, y: 2)), CGPoint(x: 100, y: 9))
        XCTAssertNil(DragDial.exit(from: item, toward: CGPoint(x: 130, y: 15)))
        XCTAssertNil(DragDial.exit(from: item, toward: CGPoint(x: 120, y: 10)))
        // An item of no size is a point the line starts at.
        XCTAssertEqual(DragDial.exit(from: CGRect(x: 50, y: 50, width: 0, height: 0), toward: CGPoint(x: 0, y: 0)), CGPoint(x: 50, y: 50))
    }

    func testStopsAtTheLongest() {
        XCTAssertEqual(DragDial.seconds(forDistance: 100_000), DragDial.longest)
    }
}
