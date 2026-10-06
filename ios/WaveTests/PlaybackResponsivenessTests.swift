import Foundation
import XCTest
@testable import Wave

@MainActor
final class PlaybackResponsivenessTests: XCTestCase {
    func testSeekPublishesLatestPositionImmediatelyAndKeepsQueue() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: file) }
        var audio = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { audio.append(contentsOf: $0) }
        }
        let pcmSize = 44_100 * 2 * 2
        append(UInt32(36 + pcmSize)); audio.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(44_100)); append(UInt32(88_200)); append(UInt16(2)); append(UInt16(16))
        audio.append(Data("data".utf8)); append(UInt32(pcmSize)); audio.append(Data(count: pcmSize))
        try audio.write(to: file)
        let player = WavePlayer()
        let track = WaveTrack(name: "Test", artist: "Wave", duration: 120, relPath: "test.wav", filename: "test.wav")
        let song = PlaybackSong(track: track, url: file, source: "local", identity: "local:seek-test")
        player.play(song, queue: [song])
        player.seek(35)
        XCTAssertEqual(player.progress.elapsed, 35)
        player.seek(80)
        XCTAssertEqual(player.progress.elapsed, 80)
        XCTAssertEqual(player.current?.id, song.id)
        XCTAssertEqual(player.queue.map(\.id), [song.id])
        player.seek(200)
        XCTAssertEqual(player.progress.elapsed, 120)
        player.seek(-20)
        XCTAssertEqual(player.progress.elapsed, 0)
        player.seek(.nan)
        XCTAssertEqual(player.progress.elapsed, 0)
        player.pause()
    }
}

final class FolderSummaryTests: XCTestCase {
    func testCountsAndCoverMatchRecursiveVisibleSongOrder() {
        let songs = [
            LocalSong(id: "b1", file: "b.wav", folder: "Root/B", name: "B", artist: "", duration: 10),
            LocalSong(id: "a1", file: "a.wav", folder: "Root/A", name: "A", artist: "", duration: 10),
            LocalSong(id: "a2", file: "a2.wav", folder: "Root/A", name: "A2", artist: "", duration: 10),
            LocalSong(id: "hidden", file: "h.wav", folder: "Root", name: "Hidden", artist: "", duration: 10, hidden: true),
            LocalSong(id: "other", file: "o.wav", folder: "Rootish", name: "Other", artist: "", duration: 10)
        ]
        let summaries = LocalFolderSummary.build(songs)
        XCTAssertEqual(summaries["Root"]?.count, 3)
        XCTAssertEqual(summaries["Root"]?.first.id, "a1")
        XCTAssertEqual(summaries["Root/A"]?.count, 2)
        XCTAssertEqual(summaries["Root/B"]?.count, 1)
        XCTAssertEqual(summaries["Rootish"]?.count, 1)
        let reordered = [songs[2], songs[1], songs[0]]
        XCTAssertEqual(LocalFolderSummary.build(reordered)["Root"]?.first.id, "a2")
        XCTAssertTrue(LocalFolderSummary.build([]).isEmpty)
    }
}
