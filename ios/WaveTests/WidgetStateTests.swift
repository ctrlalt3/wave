import Foundation
import XCTest
@testable import Wave

final class WidgetStateTests: XCTestCase {
    func testSharedSnapshotRoundTripAndCorruptFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = WaveWidgetSnapshot.preview
        snapshot.isLiked = true
        snapshot.queue = [WaveWidgetQueueItem(title: "Next", artist: "Artist")]
        XCTAssertTrue(WaveWidgetStore.write(snapshot, to: root))
        XCTAssertEqual(WaveWidgetStore.read(from: root), snapshot)
        try Data("broken".utf8).write(to: root.appendingPathComponent("widget-state.json"))
        XCTAssertNil(WaveWidgetStore.read(from: root).songID)
    }
    func testWidgetLinksRejectUnexpectedURLs() {
        for destination in WaveWidgetDestination.allCases { XCTAssertEqual(WaveWidgetDestination(url: destination.url), destination) }
        for url in ["https://example.com/player", "wave://unknown", "wave://player/more", "wave://user:password@player", "wave://player?command=delete", "wave://player#more"] {
            XCTAssertNil(WaveWidgetDestination(url: URL(string: url)!))
        }
    }
    func testArtworkPathsCannotEscapeSharedContainer() {
        let root = URL(fileURLWithPath: "/tmp/widget-test")
        XCTAssertEqual(WaveWidgetStore.artworkURL(filename: "cover-123.jpg", root: root)?.lastPathComponent, "cover-123.jpg")
        for filename in ["../cover.jpg", "/tmp/cover.jpg", ".secret.jpg", "cover.png", "sub/cover.jpg", "sub\\cover.jpg"] {
            XCTAssertNil(WaveWidgetStore.artworkURL(filename: filename, root: root))
        }
    }
    func testProgressIsFiniteAndClamped() {
        var state = WaveWidgetSnapshot.preview
        state.elapsed = -1; XCTAssertEqual(state.fraction, 0)
        state.elapsed = 1000; XCTAssertEqual(state.fraction, 1)
        state.elapsed = .nan; XCTAssertEqual(state.fraction, 0)
        state.elapsed = 10; state.duration = .infinity; XCTAssertEqual(state.fraction, 0)
    }
    func testSnapshotDoesNotExposePrivatePlaybackURLs() throws {
        let data = try JSONEncoder().encode(WaveWidgetSnapshot.preview)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(keys["remoteURL"])
        XCTAssertNil(keys["localFile"])
        XCTAssertNil(keys["serverBase"])
    }
}
