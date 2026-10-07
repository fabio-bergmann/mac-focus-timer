import XCTest
@testable import FocusTimerCore

final class DragDialTests: XCTestCase {
    /// Every length a pull can set, sampled every half point up to the far
    /// corner of a large screen and beyond.
    private let pulls: [(distance: Double, seconds: Int?)] = stride(from: 0.0, through: 4000, by: 0.5).map {
        ($0, DragDial.seconds(forDistance: $0))
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
        let lengths = pulls.compactMap(\.seconds)
        XCTAssertEqual(lengths, lengths.sorted())
    }

    func testStepsWidenWithTheLength() {
        let reached = Set(pulls.compactMap(\.seconds)).map { $0 / 60 }.sorted()
        let expected = Array(1...15) + Array(stride(from: 20, through: 60, by: 5))
            + Array(stride(from: 75, through: 180, by: 15)) + Array(stride(from: 210, through: 720, by: 30))
        XCTAssertEqual(reached, expected)
    }

    func testStopsAtTheLongest() {
        XCTAssertEqual(DragDial.seconds(forDistance: 100_000), DragDial.longest)
    }
}
