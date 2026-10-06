import XCTest
@testable import Wave

final class ScrollAndIdleTests: XCTestCase {
    func testNavigationHidesAfterDeliberateScrollAndReturnsOnReversal() {
        var policy = WaveScrollChromePolicy()
        XCTAssertFalse(policy.update(delta: 10, offset: 100))
        XCTAssertTrue(policy.update(delta: 20, offset: 120))
        XCTAssertTrue(policy.hidden)
        XCTAssertFalse(policy.update(delta: -5, offset: 115))
        XCTAssertTrue(policy.update(delta: -8, offset: 107))
        XCTAssertFalse(policy.hidden)
    }
    func testTopAndInvalidGeometryDoNotLeaveHeaderHidden() {
        var policy = WaveScrollChromePolicy()
        _ = policy.update(delta: 30, offset: 150)
        XCTAssertTrue(policy.hidden)
        XCTAssertFalse(policy.update(delta: .nan, offset: 10))
        XCTAssertTrue(policy.update(delta: -1, offset: 0))
        XCTAssertFalse(policy.hidden)
        XCTAssertFalse(policy.update(delta: 50, offset: -20))
    }
    func testShortDirectionChangesDoNotFlickerNavigation() {
        var policy = WaveScrollChromePolicy()
        for _ in 0..<10 {
            _ = policy.update(delta: 3, offset: 100)
            _ = policy.update(delta: -3, offset: 100)
        }
        XCTAssertFalse(policy.hidden)
    }
    func testTouchRestartsIdleCountdown() {
        let start = Date(timeIntervalSince1970: 100)
        var policy = WaveDockIdlePolicy(lastActivity: start)
        XCTAssertFalse(policy.shouldDim(at: start.addingTimeInterval(19)))
        XCTAssertTrue(policy.shouldDim(at: start.addingTimeInterval(20)))
        policy.interacted(at: start.addingTimeInterval(25))
        XCTAssertFalse(policy.shouldDim(at: start.addingTimeInterval(30)))
        XCTAssertTrue(policy.shouldDim(at: start.addingTimeInterval(45)))
    }
    func testLargeWidgetUsesAvailableAreaWithSafeCapacity() {
        let phone = WaveWidgetExplorerLayout(width: 340, height: 360)
        let tablet = WaveWidgetExplorerLayout(width: 720, height: 360)
        XCTAssertEqual(phone.columns, 1)
        XCTAssertGreaterThanOrEqual(phone.capacity, 4)
        XCTAssertEqual(tablet.columns, 2)
        XCTAssertEqual(tablet.capacity, phone.capacity * 2)
        XCTAssertLessThanOrEqual(WaveWidgetExplorerLayout(width: 720, height: 10_000).capacity, 24)
        XCTAssertGreaterThan(WaveWidgetExplorerLayout(width: .nan, height: .nan).capacity, 0)
    }
}
