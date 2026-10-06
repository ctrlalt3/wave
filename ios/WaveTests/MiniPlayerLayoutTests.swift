import Foundation
import XCTest
@testable import Wave

final class MiniPlayerLayoutTests: XCTestCase {
    func testBothDirectionsFitEveryIntermediateWidth() {
        // Placement switches before the system has finished changing width.
        // Validate both placement values over the full path, in both directions.
        for width in stride(from: 0, through: 500, by: 1) {
            for inline in [true, false] {
                let metrics = WaveMiniPlayerMetrics(width: CGFloat(width), inline: inline)
                let controls: CGFloat = metrics.showsDetails ? 3 : 1
                let occupied = metrics.padding * 2 + metrics.openWidth + controls * (metrics.controlWidth + metrics.spacing)
                XCTAssertLessThanOrEqual(occupied, CGFloat(width) + 0.001)
                XCTAssertGreaterThanOrEqual(metrics.titleWidth, 0)
                XCTAssertLessThanOrEqual(metrics.titleWidth, metrics.openWidth)
                if metrics.showsArtwork { XCTAssertGreaterThanOrEqual(metrics.openWidth, 32 + metrics.artworkSpacing + metrics.titleWidth - 0.001) }
            }
        }
    }
    func testExpandedControlsWaitUntilThereIsSpace() {
        XCTAssertFalse(WaveMiniPlayerMetrics(width: 180, inline: false).showsDetails)
        XCTAssertFalse(WaveMiniPlayerMetrics(width: 390, inline: true).showsDetails)
        let expanded = WaveMiniPlayerMetrics(width: 390, inline: false)
        XCTAssertTrue(expanded.showsDetails)
        XCTAssertEqual(expanded.controlWidth, 44)
        XCTAssertGreaterThan(expanded.titleWidth, 0)
    }
    func testInvalidProposalsDoNotProduceInvalidFrames() {
        let invalidWidths: [CGFloat] = [-1, .infinity, .nan]
        for width in invalidWidths {
            let metrics = WaveMiniPlayerMetrics(width: width, inline: false)
            XCTAssertEqual(metrics.width, 0)
            XCTAssertEqual(metrics.openWidth, 0)
            XCTAssertEqual(metrics.titleWidth, 0)
        }
    }
}
