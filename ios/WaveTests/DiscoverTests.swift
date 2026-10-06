import XCTest
import Combine
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
    func testRepeatedUpAndDownChangesDirectionWithoutReturningToTop() {
        let chrome = WaveNavigationChrome()
        for _ in 0..<4 {
            chrome.scroll(delta: 24)
            XCTAssertTrue(chrome.compact)
            chrome.scroll(delta: -24)
            XCTAssertFalse(chrome.compact)
        }
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

@MainActor
final class SharedLikeSavingTests: XCTestCase {
    private func fixture(host: String = "likes.example") async throws -> (LibraryPreferences, WaveAPI, PlaybackSong, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LikeSavingProtocol.self]
        let session = URLSession(configuration: configuration)
        let api = try WaveAPI(server: "https://\(host)/\(UUID().uuidString)/", session: session)
        let storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        let preferences = LibraryPreferences(storage: storage, serverSession: session)
        await preferences.load()
        let track = WaveTrack(name: "Song", artist: "Artist", duration: 10,
                              relPath: "House/song.mp3", filename: "song.mp3")
        return (preferences, api, try PlaybackSong.server(track, api: api), root)
    }

    func testServerDiscoverSavePersistsThenListCanRemoveAndAddTheSameHeart() async throws {
        let (preferences, api, song, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = await preferences.saveLike(song)
        XCTAssertTrue(saved)
        XCTAssertTrue(preferences.liked(song.id))
        var remote: [String: Bool] = try await api.get(["api", "likes"])
        XCTAssertEqual(remote[song.track.relPath], true)
        let again = await preferences.saveLike(song)
        XCTAssertTrue(again)
        remote = try await api.get(["api", "likes"])
        XCTAssertEqual(remote[song.track.relPath], true)
        await preferences.toggle(song)
        XCTAssertFalse(preferences.liked(song.id))
        remote = try await api.get(["api", "likes"])
        XCTAssertEqual(remote[song.track.relPath], false)
        await preferences.toggle(song)
        await preferences.synchronizeServer(api)
        XCTAssertTrue(preferences.liked(song.id))
        let restored = LibraryPreferences(storage: LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json")))
        await restored.load()
        XCTAssertTrue(restored.liked(song.id))
    }

    func testLegacyToggleServerAlsoKeepsRepeatedDiscoverSaveSelected() async throws {
        let (preferences, api, song, root) = try await fixture(host: "legacy.example")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = await preferences.saveLike(song)
        let repeated = await preferences.saveLike(song)
        XCTAssertTrue(first)
        XCTAssertTrue(repeated)
        let remote: [String: Bool] = try await api.get(["api", "likes"])
        XCTAssertEqual(remote[song.track.relPath], true)
        XCTAssertTrue(preferences.liked(song.id))
    }

    func testFailedServerSaveDoesNotRemoveSongFromDiscoverOrSelectHeart() async throws {
        let (preferences, _, song, root) = try await fixture(host: "failure.example")
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = await preferences.saveLike(song)
        XCTAssertFalse(saved)
        XCTAssertFalse(preferences.liked(song.id))
        XCTAssertNotNil(preferences.error)
        let feed = DiscoverSession(folder: "House", songs: [song])
        XCTAssertEqual(feed.remainingSongs(favorites: preferences.state.favorites).map(\.id), [song.id])
    }

    func testOldCachedHeartsAreRecoveredOnceWithoutResurrectingLaterUnlikes() async throws {
        let (_, api, song, root) = try await fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        _ = try await storage.favorite(song.id, liked: true)
        _ = try await storage.favorite("local:previously-saved", liked: true)
        let preferences = LibraryPreferences(storage: storage, serverSession: api.session)
        await preferences.load()
        await preferences.synchronizeServer(api)
        var remote: [String: Bool] = try await api.get(["api", "likes"])
        XCTAssertEqual(remote[song.track.relPath], true)
        XCTAssertTrue(preferences.liked("local:previously-saved"))
        XCTAssertTrue(preferences.state.reconciledServers?.contains(api.base.absoluteString) == true)
        try await api.setLike(song.track.relPath, liked: false)
        let restored = LibraryPreferences(storage: storage, serverSession: api.session)
        await restored.load()
        await restored.synchronizeServer(api)
        remote = try await api.get(["api", "likes"])
        XCTAssertEqual(remote[song.track.relPath], false)
        XCTAssertFalse(restored.liked(song.id))
        XCTAssertTrue(restored.liked("local:previously-saved"))
    }

    func testProgressTicksDoNotInvalidateLibrariesObservingPlayer() {
        let player = WavePlayer()
        var playerChanges = 0
        var progressChanges = 0
        let playerSubscription = player.objectWillChange.sink { playerChanges += 1 }
        let progressSubscription = player.progress.objectWillChange.sink { progressChanges += 1 }
        player.progress.elapsed = 5
        player.progress.duration = 120
        XCTAssertEqual(playerChanges, 0)
        XCTAssertEqual(progressChanges, 2)
        withExtendedLifetime((playerSubscription, progressSubscription)) {}
    }
}

private final class LikeSavingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var hearts: [String: [String: Bool]] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let key = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            body = data
        }
        Self.lock.lock()
        var value: [String: Bool] = Self.hearts[key] ?? [:]
        var payload: [String: Any] = value
        if request.httpMethod == "POST", let body,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let track = json["track"] as? String {
            let desired = url.host == "legacy.example" ? nil : json["liked"] as? Bool
            let liked = desired ?? !(value[track] ?? false)
            value[track] = liked
            Self.hearts[key] = value
            payload = ["liked": liked]
        }
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: url.host == "failure.example" ? 500 : 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
