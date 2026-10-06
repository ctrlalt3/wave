import Combine
import Foundation
import SwiftUI
import UIKit

enum FolderPlaylistSource: String, Codable { case local, server }
struct FolderPlaylist: Codable, Identifiable {
    let id: String
    let title: String
    let folder: String
    let source: FolderPlaylistSource
    let server: String?
}
struct LibraryPreferencesState: Codable {
    var favorites: Set<String> = []
    var playlists: [FolderPlaylist] = []
    var localHierarchyVersion: Int? = nil
    var reconciledServers: Set<String>? = nil
    var visiblePlaylists: [FolderPlaylist] {
        playlists.filter { playlist in
            playlist.source != .local || !playlists.contains {
                $0.source == .local && playlist.folder.hasPrefix($0.folder + "/")
            }
        }
    }
}
actor LibraryPreferencesStorage {
    let file: URL
    init(file: URL) { self.file = file }
    func read() throws -> LibraryPreferencesState {
        guard FileManager.default.fileExists(atPath: file.path) else { return LibraryPreferencesState() }
        return try JSONDecoder().decode(LibraryPreferencesState.self, from: Data(contentsOf: file))
    }
    private func save(_ state: LibraryPreferencesState) throws -> LibraryPreferencesState {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: file, options: .atomic)
        return state
    }
    func prepareLocalPlaylists(_ folders: [String], replacements: [String: String]) throws -> LibraryPreferencesState {
        var state = try read()
        let original = state
        if state.localHierarchyVersion == nil {
            state.playlists.removeAll { $0.source == .local }
            for folder in folders {
                state.playlists.append(FolderPlaylist(id: UUID().uuidString, title: folder.split(separator: "/").last.map(String.init) ?? folder, folder: folder, source: .local, server: nil))
            }
            state.localHierarchyVersion = 1
        }
        var seen = Set<[String]>()
        state.playlists = state.playlists.filter { seen.insert([$0.source.rawValue, $0.server ?? "", $0.folder]).inserted }
        for (duplicate, kept) in replacements where state.favorites.contains("local:" + duplicate) {
            state.favorites.remove("local:" + duplicate)
            state.favorites.insert("local:" + kept)
        }
        // Retain the previous preferences for recovery as well as the audio manifest.
        if state.localHierarchyVersion != original.localHierarchyVersion || state.playlists.count != original.playlists.count || state.favorites != original.favorites {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let backup = file.deletingLastPathComponent().appendingPathComponent("preferences-before-playlists-" + UUID().uuidString + ".json")
            try JSONEncoder().encode(original).write(to: backup, options: .atomic)
        }
        return try save(state)
    }

    func favorite(_ id: String, liked: Bool) throws -> LibraryPreferencesState {
        var state = try read()
        if liked { state.favorites.insert(id) } else { state.favorites.remove(id) }
        return try save(state)
    }
    func synchronizeServer(_ base: String, paths: Set<String>, markReconciled: Bool = false) throws -> LibraryPreferencesState {
        var state = try read()
        state.favorites = state.favorites.filter { !$0.hasPrefix(base) }
        state.favorites.formUnion(paths.map { base + $0 })
        if markReconciled {
            var reconciled = state.reconciledServers ?? []
            reconciled.insert(base)
            state.reconciledServers = reconciled
        }
        return try save(state)
    }
    func add(_ playlist: FolderPlaylist) throws -> LibraryPreferencesState {
        var state = try read()
        if !state.playlists.contains(where: { $0.source == playlist.source && $0.folder == playlist.folder && $0.server == playlist.server }) { state.playlists.append(playlist) }
        return try save(state)
    }
    func remove(_ id: String) throws -> LibraryPreferencesState {
        var state = try read()
        state.playlists.removeAll { $0.id == id }
        return try save(state)
    }
}
@MainActor
final class LibraryPreferences: ObservableObject {
    @Published private(set) var state = LibraryPreferencesState()
    @Published private(set) var ready = false
    @Published private(set) var saving = false
    @Published private(set) var pendingLikes: Set<String> = []
    @Published var error: String?
    private let storage: LibraryPreferencesStorage
    private let serverSession: URLSession
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WaveMusic", isDirectory: true)
        storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
        serverSession = .shared
    }
    init(storage: LibraryPreferencesStorage, serverSession: URLSession = .shared) {
        self.storage = storage
        self.serverSession = serverSession
    }
    func load() async {
        guard !ready else { return }
        do { state = try await storage.read(); ready = true }
        catch { self.error = "No se pudieron leer tus likes y playlists: \(error.localizedDescription)" }
    }
    func prepareLocalPlaylists(_ songs: [LocalSong], replacements: [String: String]) async {
        guard ready else { return }
        await beginSaving()
        defer { finishSaving() }
        do { state = try await storage.prepareLocalPlaylists(LocalSong.automaticPlaylists(for: songs), replacements: replacements) }
        catch { self.error = "No se pudieron organizar tus playlists: \(error.localizedDescription)" }
    }
    func liked(_ id: String) -> Bool { state.favorites.contains(id) }
    private func beginSaving() async {
        while saving { await withCheckedContinuation { waiters.append($0) } }
        saving = true
    }
    private func finishSaving() {
        saving = false
        let waiting = waiters
        waiters.removeAll()
        for continuation in waiting { continuation.resume() }
    }
    func toggle(_ song: PlaybackSong) async {
        _ = await writeLike(song, desired: nil)
    }
    // Both the list and Discover use the same serialized persistence operation.
    // Discover sets a heart; saving an existing heart never removes it.
    func saveLike(_ song: PlaybackSong) async -> Bool {
        await writeLike(song, desired: true)
    }
    private func writeLike(_ song: PlaybackSong, desired: Bool?) async -> Bool {
        guard ready, !pendingLikes.contains(song.id) else { return false }
        pendingLikes.insert(song.id)
        await beginSaving()
        defer { pendingLikes.remove(song.id); finishSaving() }
        error = nil
        let liked = desired ?? !state.favorites.contains(song.id)
        do {
            if let base = song.serverBase {
                let api = try WaveAPI(server: base.absoluteString, session: serverSession)
                try await api.setLike(song.track.relPath, liked: liked)
            }
            state = try await storage.favorite(song.id, liked: liked)
            return true
        } catch {
            self.error = "No se pudo guardar Me gusta: \(error.localizedDescription)"
            return false
        }
    }

    func synchronizeServer(_ api: WaveAPI) async {
        guard ready else { return }
        await beginSaving()
        defer { finishSaving() }
        guard !Task.isCancelled else { return }
        do {
            let likes: [String: Bool] = try await api.get(["api", "likes"])
            var paths = Set(likes.filter { $0.value && WaveAPI.safePath($0.key) }.map(\.key))
            let base = api.base.absoluteString
            let recovering = state.reconciledServers?.contains(base) != true
            if recovering {
                let savedPaths = state.favorites.compactMap { id -> String? in
                    guard id.hasPrefix(base) else { return nil }
                    let path = String(id.dropFirst(base.count))
                    return WaveAPI.safePath(path) ? path : nil
                }
                for path in savedPaths where !paths.contains(path) {
                    try Task.checkCancellation()
                    try await api.setLike(path, liked: true)
                    paths.insert(path)
                }
            }
            state = try await storage.synchronizeServer(base, paths: paths, markReconciled: recovering)
        } catch { if !Task.isCancelled { self.error = "No se pudieron actualizar los likes del servidor: \(error.localizedDescription)" } }
    }
    func addFolder(_ folder: String, source: FolderPlaylistSource, server: String? = nil) async {
        guard ready, WaveAPI.safePath(folder) else { return }
        await beginSaving()
        defer { finishSaving() }
        do {
            let canonical: String?
            if source == .server {
                guard let server else { throw WaveAPI.Failure(message: "Falta la dirección del servidor.") }
                canonical = try WaveAPI(server: server).base.absoluteString
            } else { canonical = nil }
            state = try await storage.add(FolderPlaylist(id: UUID().uuidString, title: folder.split(separator: "/").last.map(String.init) ?? folder, folder: folder, source: source, server: canonical))
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ playlist: FolderPlaylist) async {
        guard ready else { return }
        await beginSaving()
        defer { finishSaving() }
        do { state = try await storage.remove(playlist.id) }
        catch { self.error = error.localizedDescription }
    }
}
struct LikeButton: View {
    let song: PlaybackSong
    var compact = false
    @EnvironmentObject private var preferences: LibraryPreferences
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button { UISelectionFeedbackGenerator().selectionChanged(); Task { await preferences.toggle(song) } } label: {
            Image(systemName: preferences.liked(song.id) ? "heart.fill" : "heart")
                .foregroundStyle(preferences.liked(song.id) ? Color.red : (scheme == .dark ? Color.white : Color.black))
                .shadow(color: (scheme == .dark ? Color.white : Color.black).opacity(0.15), radius: 2)
                .frame(width: compact ? 44 : 48, height: compact ? 44 : 56).contentShape(Rectangle())
        }.buttonStyle(.borderless).disabled(!preferences.ready || preferences.pendingLikes.contains(song.id))
            .overlay {
                if preferences.pendingLikes.contains(song.id) { ProgressView().tint(.red).allowsHitTesting(false) }
            }
            .accessibilityLabel(preferences.liked(song.id) ? "Quitar Me gusta" : "Me gusta")
            .accessibilityValue(preferences.liked(song.id) ? "Activado" : "Desactivado")
    }
}
