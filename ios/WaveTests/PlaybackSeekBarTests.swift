import XCTest
@testable import Wave

final class PlaybackSeekBarTests: XCTestCase {
    func testDurationFallsBackWithoutInvalidSliderRanges() {
        XCTAssertEqual(WaveSeekPosition.duration(0, fallback: 120), 120)
        XCTAssertEqual(WaveSeekPosition.duration(130, fallback: 120), 130)
        XCTAssertEqual(WaveSeekPosition.duration(.nan, fallback: 120), 120)
        XCTAssertEqual(WaveSeekPosition.duration(.infinity, fallback: -.infinity), 0)
    }
    func testSeekPositionAlwaysStaysWithinSongDuration() {
        XCTAssertEqual(WaveSeekPosition.clamp(-5, duration: 120), 0)
        XCTAssertEqual(WaveSeekPosition.clamp(130, duration: 120), 120)
        XCTAssertEqual(WaveSeekPosition.clamp(60, duration: 120), 60)
        XCTAssertEqual(WaveSeekPosition.clamp(.nan, duration: 120), 0)
        XCTAssertEqual(WaveSeekPosition.clamp(60, duration: 0), 0)
    }
}
