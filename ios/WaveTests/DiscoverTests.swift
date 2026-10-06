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

@MainActor
final class DiscoverFavoritesTests: XCTestCase {
    func testDiscoverSaveSelectsFolderHeartAndPersistsWithoutMovingSong() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        let preferences = LibraryPreferences(storage: storage)
        await preferences.load()
        let track = WaveTrack(name: "Song", artist: "Artist", duration: 10,
                              relPath: "House/song.mp3", filename: "song.mp3")
        let song = PlaybackSong(track: track, url: nil, source: "local", identity: "local:42")
        let session = DiscoverSession(folder: "House", songs: [song])
        XCTAssertEqual(session.remainingSongs(favorites: preferences.state.favorites).map(\.id), [song.id])
        let saved = await preferences.saveLike(song)
        XCTAssertTrue(saved)
        XCTAssertTrue(preferences.liked(song.id))
        XCTAssertTrue(session.remainingSongs(favorites: preferences.state.favorites).isEmpty)
        let restored = LibraryPreferences(storage: storage)
        await restored.load()
        XCTAssertTrue(restored.liked(song.id))
        XCTAssertEqual(song.track.relPath, "House/song.mp3")
        await preferences.toggle(song)
        XCTAssertFalse(preferences.liked(song.id))
        XCTAssertEqual(session.remainingSongs(favorites: preferences.state.favorites).map(\.id), [song.id])
    }

    func testServerFolderAndDiscoverShareCanonicalHeartAndKeepOtherFolders() throws {
        let api = try WaveAPI(server: "https://example.com/wave")
        let track = WaveTrack(name: "Song", artist: "Artist", duration: 10,
                              relPath: "House/song.mp3", filename: "song.mp3")
        let other = WaveTrack(name: "Other", artist: "Artist", duration: 10,
                              relPath: "House/other.mp3", filename: "other.mp3")
        let song = try PlaybackSong.server(track, api: api)
        let next = try PlaybackSong.server(other, api: api)
        let session = DiscoverSession(folder: "House", songs: [song, next])
        var state = LibraryPreferencesState()
        state.favorites.insert(api.base.absoluteString + track.id)
        XCTAssertEqual(session.remainingSongs(favorites: state.favorites).map(\.id), [next.id])
        XCTAssertEqual(song.id, api.base.absoluteString + track.id)
    }
}
