import Foundation
import XCTest
@testable import Wave

final class LibraryPreferencesTests: XCTestCase {
    @MainActor func testExplicitWidgetLikeAndUnlikeAreIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        let preferences = LibraryPreferences(storage: storage)
        await preferences.load()
        let track = WaveTrack(name: "Song", artist: "Artist", duration: 10, relPath: "song.wav", filename: "song.wav")
        let song = PlaybackSong(track: track, url: nil, source: "local", identity: "local:widget-heart")
        let first = await preferences.setLike(song, liked: true)
        let second = await preferences.setLike(song, liked: true)
        XCTAssertTrue(first); XCTAssertTrue(second)
        XCTAssertTrue(preferences.liked(song.id))
        let third = await preferences.setLike(song, liked: false)
        let fourth = await preferences.setLike(song, liked: false)
        XCTAssertTrue(third); XCTAssertTrue(fourth)
        XCTAssertFalse(preferences.liked(song.id))
        let persisted = try await storage.read()
        XCTAssertFalse(persisted.favorites.contains(song.id))
    }
    func testFavoritesPersistAndRemainSeparateBySource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("preferences.json")
        let storage = LibraryPreferencesStorage(file: file)
        _ = try await storage.favorite("local:42", liked: true)
        _ = try await storage.favorite("device:42", liked: true)
        _ = try await storage.favorite("https://server.example/wave/folder/song.mp3", liked: true)
        let restored = try await LibraryPreferencesStorage(file: file).read()
        XCTAssertEqual(restored.favorites.count, 3)
        let removed = try await storage.favorite("local:42", liked: false)
        XCTAssertFalse(removed.favorites.contains("local:42"))
        XCTAssertTrue(removed.favorites.contains("device:42"))
    }

    func testFolderPlaylistsDeduplicateAndRemovalPreservesLikes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("preferences.json")
        let storage = LibraryPreferencesStorage(file: file)
        _ = try await storage.favorite("local:42", liked: true)
        let local = FolderPlaylist(id: "local-folder", title: "Colección", folder: "Colección", source: .local, server: nil)
        _ = try await storage.add(local)
        _ = try await storage.add(FolderPlaylist(id: "duplicate", title: "Colección", folder: "Colección", source: .local, server: nil))
        _ = try await storage.add(FolderPlaylist(id: "server-folder", title: "Colección", folder: "Colección", source: .server, server: "https://server.example/wave/"))
        let restored = try await LibraryPreferencesStorage(file: file).read()
        XCTAssertEqual(restored.playlists.count, 2)
        let removed = try await storage.remove("local-folder")
        XCTAssertEqual(removed.playlists.map(\.id), ["server-folder"])
        XCTAssertTrue(removed.favorites.contains("local:42"))
    }

    func testServerSynchronizationKeepsLocalAndOtherServerLikes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        _ = try await storage.favorite("local:42", liked: true)
        _ = try await storage.favorite("https://one.example/wave/old.mp3", liked: true)
        _ = try await storage.favorite("https://two.example/wave/old.mp3", liked: true)
        let state = try await storage.synchronizeServer("https://one.example/wave/", paths: ["folder/new.mp3"])
        XCTAssertEqual(state.favorites, ["local:42", "https://one.example/wave/folder/new.mp3", "https://two.example/wave/old.mp3"])
    }

    func testHierarchyMigrationMovesLikesAndDoesNotRestoreDeletedPlaylists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        _ = try await storage.add(FolderPlaylist(id: "parent", title: "sesion", folder: "sesion", source: .local, server: nil))
        _ = try await storage.favorite("local:copy", liked: true)
        let migrated = try await storage.prepareLocalPlaylists(["sesion/House", "sesion/Techno"], replacements: ["copy": "one"])
        XCTAssertEqual(migrated.playlists.map(\.folder), ["sesion/House", "sesion/Techno"])
        XCTAssertEqual(migrated.favorites, ["local:one"])
        let removed = try XCTUnwrap(migrated.playlists.first)
        _ = try await storage.remove(removed.id)
        let reopened = try await storage.prepareLocalPlaylists(["sesion/House", "sesion/Techno"], replacements: [:])
        XCTAssertEqual(reopened.playlists.map(\.folder), ["sesion/Techno"])
        XCTAssertEqual(reopened.favorites, ["local:one"])
    }

    func testOldPreferenceFormatRetainsPreviouslySavedLocalHearts() throws {
        let data = Data(#"{"favorites":["local:42"],"playlists":[]}"#.utf8)
        let old = try JSONDecoder().decode(LibraryPreferencesState.self, from: data)
        XCTAssertEqual(old.favorites, ["local:42"])
        XCTAssertNil(old.reconciledServers)
    }

    func testCorruptPreferencesAreNotReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("preferences.json")
        let original = Data("corrupt".utf8)
        try original.write(to: file)
        let storage = LibraryPreferencesStorage(file: file)
        do {
            _ = try await storage.favorite("local:42", liked: true)
            XCTFail("Corrupt preferences must be preserved.")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
