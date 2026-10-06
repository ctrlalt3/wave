import Foundation
import XCTest
@testable import Wave

final class LibraryPreferencesTests: XCTestCase {
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
