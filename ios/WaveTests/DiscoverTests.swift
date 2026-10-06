import XCTest
@testable import Wave

final class DiscoverTests: XCTestCase {
    func testHorizontalSwipesSaveRightAndPassLeft() {
        XCTAssertEqual(DiscoverSwipe.action(horizontal: 100, vertical: 20), .save)
        XCTAssertEqual(DiscoverSwipe.action(horizontal: -100, vertical: 20), .next)
    }
    func testVerticalBrowsingDoesNotSaveAnAccidentalDiagonalDrag() {
        XCTAssertEqual(DiscoverSwipe.action(horizontal: 100, vertical: -180), .next)
        XCTAssertEqual(DiscoverSwipe.action(horizontal: 100, vertical: 180), .previous)
    }
    func testSmallGesturesDoNotChangeTheSongOrLikes() {
        XCTAssertEqual(DiscoverSwipe.action(horizontal: 50, vertical: 10), .none)
        XCTAssertEqual(DiscoverSwipe.action(horizontal: 10, vertical: -30), .none)
        XCTAssertEqual(DiscoverSwipe.action(horizontal: 0, vertical: 0), .none)
    }
}

@MainActor
final class NavigationChromeTests: XCTestCase {
    func testScrollUpExpandsWithoutReturningToTheTop() {
        let chrome = WaveNavigationChrome()
        chrome.scroll(delta: 20)
        XCTAssertTrue(chrome.compact)
        chrome.scroll(delta: -18)
        XCTAssertFalse(chrome.compact)
    }
    func testSmallJitterDoesNotCollapseNavigation() {
        let chrome = WaveNavigationChrome()
        chrome.scroll(delta: 4)
        chrome.scroll(delta: -4)
        XCTAssertFalse(chrome.compact)
    }
}
