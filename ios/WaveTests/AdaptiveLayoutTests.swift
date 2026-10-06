import XCTest
@testable import Wave

final class AdaptiveLayoutTests: XCTestCase {
    func testPhonePortraitUsesTabsAndLandscapeUsesCompactLeftMenu() {
        let portrait = WaveAdaptiveLayout(size: CGSize(width: 390, height: 844))
        let landscape = WaveAdaptiveLayout(size: CGSize(width: 844, height: 390))
        XCTAssertFalse(portrait.usesSidebar)
        XCTAssertEqual(portrait.sidebarWidth, 0)
        XCTAssertTrue(landscape.usesSidebar)
        XCTAssertTrue(landscape.compactSidebar)
        XCTAssertEqual(landscape.sidebarWidth, 76)
        XCTAssertTrue(landscape.compactHeader)
    }
    func testSmallPhoneLandscapeAndNarrowMultitaskingRemainUsable() {
        let smallPhone = WaveAdaptiveLayout(size: CGSize(width: 568, height: 320))
        XCTAssertTrue(smallPhone.usesSidebar)
        XCTAssertGreaterThan(smallPhone.size.width - smallPhone.sidebarWidth, 440)
        let narrowWindow = WaveAdaptiveLayout(size: CGSize(width: 400, height: 700))
        XCTAssertFalse(narrowWindow.usesSidebar)
    }
    func testIPadUsesExpandedSidebarInLandscape() {
        let tablet = WaveAdaptiveLayout(size: CGSize(width: 1194, height: 834))
        XCTAssertTrue(tablet.usesSidebar)
        XCTAssertFalse(tablet.compactSidebar)
        XCTAssertEqual(tablet.sidebarWidth, 216)
        XCTAssertFalse(tablet.compactHeader)
    }
}
