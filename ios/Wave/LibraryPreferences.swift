import Combine
import Foundation
import SwiftUI

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
    func favorite(_ id: String, liked: Bool) throws -> LibraryPreferencesState {
        var state = try read()
        if liked { state.favorites.insert(id) } else { state.favorites.remove(id) }
        return try save(state)
    }
    func synchronizeServer(_ base: String, paths: Set<String>) throws -> LibraryPreferencesState {
        var state = try read()
        state.favorites = state.favorites.filter { !$0.hasPrefix(base) }
        state.favorites.formUnion(paths.map { base + $0 })
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
    @Published var error: String?
    private let storage: LibraryPreferencesStorage
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WaveMusic", isDirectory: true)
        storage = LibraryPreferencesStorage(file: root.appendingPathComponent("preferences.json"))
    }
    func load() async {
        guard !ready else { return }
        do { state = try await storage.read(); ready = true }
        catch { self.error = "No se pudieron leer tus likes y playlists: \(error.localizedDescription)" }
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
        guard ready else { return }
        await beginSaving()
        defer { finishSaving() }
        do {
            let liked: Bool
            if let server = song.serverBase { liked = try await WaveAPI(server: server.absoluteString).toggleLike(song.track.relPath) }
            else { liked = !state.favorites.contains(song.id) }
            state = try await storage.favorite(song.id, liked: liked)
        } catch { self.error = "No se pudo guardar Me gusta: \(error.localizedDescription)" }
    }
    func synchronizeServer(_ api: WaveAPI) async {
        guard ready else { return }
        await beginSaving()
        defer { finishSaving() }
        guard !Task.isCancelled else { return }
        do {
            let likes: [String: Bool] = try await api.get(["api", "likes"])
            let paths = Set(likes.filter { $0.value && WaveAPI.safePath($0.key) }.map(\.key))
            state = try await storage.synchronizeServer(api.base.absoluteString, paths: paths)
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
    @EnvironmentObject private var preferences: LibraryPreferences
    var body: some View {
        Button { Task { await preferences.toggle(song) } } label: {
            Image(systemName: preferences.liked(song.id) ? "heart.fill" : "heart").foregroundStyle(WaveTheme.accent).frame(width: 44, height: 44)
        }.buttonStyle(.borderless).disabled(!preferences.ready || preferences.saving)
            .accessibilityLabel(preferences.liked(song.id) ? "Quitar Me gusta" : "Me gusta")
            .accessibilityValue(preferences.liked(song.id) ? "Activado" : "Desactivado")
    }
}
