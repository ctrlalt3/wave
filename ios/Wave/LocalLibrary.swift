import AVFoundation
import Combine
import Foundation

struct LocalSong: Codable, Identifiable {
    let id: String
    let file: String
    let folder: String
    let name: String
    let artist: String
    let duration: Double
    var originalFilename: String? = nil
    var hidden = false

    var track: WaveTrack {
        WaveTrack(name: name, artist: artist, duration: duration, relPath: id, filename: originalFilename ?? file)
    }
}

struct ImportReport {
    let songs: [LocalSong]
    let failures: [String]
}

// File coordination and copying happen off the main actor. The app owns the
// imported copies, so playback does not depend on a provider or a bookmark.
actor LocalLibraryStorage {
    let root: URL
    private let manager = FileManager.default
    private static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "opus", "webm"]

    init(root: URL) { self.root = root }

    func read() throws -> [LocalSong] {
        let manifest = root.appendingPathComponent("library.json")
        guard manager.fileExists(atPath: manifest.path) else { return [] }
        return try JSONDecoder().decode([LocalSong].self, from: Data(contentsOf: manifest))
    }

    func save(_ songs: [LocalSong]) throws {
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(songs).write(to: root.appendingPathComponent("library.json"), options: .atomic)
    }

    func importFiles(_ urls: [URL]) async throws -> ImportReport {
        var songs = try read()
        var failures: [String] = []
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        for selected in urls {
            let scoped = selected.startAccessingSecurityScopedResource()
            defer { if scoped { selected.stopAccessingSecurityScopedResource() } }
            do {
                let directory = try selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                var files: [(URL, String)] = []
                if directory {
                    guard let enumerator = manager.enumerator(at: selected, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, _ in
                        failures.append("No se pudo leer \(url.lastPathComponent).")
                        return true
                    }) else { throw WaveAPI.Failure(message: "No se pudo abrir la carpeta.") }
                    for case let file as URL in enumerator {
                        let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                              Self.extensions.contains(file.pathExtension.lowercased()) else { continue }
                        let parent = file.deletingLastPathComponent().path
                        let suffix = String(parent.dropFirst(selected.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        files.append((file, selected.lastPathComponent + (suffix.isEmpty ? "" : "/" + suffix)))
                    }
                } else { files = [(selected, "Importadas")] }

                for (source, folder) in files.sorted(by: { $0.0.path < $1.0.path }) {
                    let id = UUID().uuidString
                    let filename = id + "." + source.pathExtension.lowercased()
                    let destination = root.appendingPathComponent(filename)
                    do {
                        guard Self.extensions.contains(source.pathExtension.lowercased()) else {
                            throw WaveAPI.Failure(message: "Formato de archivo no admitido.")
                        }
                        try coordinatedCopy(source, destination: destination)
                        let asset = AVURLAsset(url: destination)
                        guard try await asset.load(.isPlayable) else {
                            throw WaveAPI.Failure(message: "Este audio no se puede reproducir en iOS.")
                        }
                        let duration = try await asset.load(.duration).seconds
                        var name = source.deletingPathExtension().lastPathComponent
                        var artist = "Música local"
                        if let metadata = try? await asset.load(.commonMetadata) {
                            for item in metadata {
                                if item.commonKey == .commonKeyTitle, let value = try? await item.load(.stringValue), !value.isEmpty { name = value }
                                if item.commonKey == .commonKeyArtist, let value = try? await item.load(.stringValue), !value.isEmpty { artist = value }
                            }
                        }
                        var updated = songs
                        updated.append(LocalSong(id: id, file: filename, folder: folder, name: name, artist: artist, duration: duration.isFinite ? max(0, duration) : 0, originalFilename: source.lastPathComponent))
                        try save(updated)
                        songs = updated
                    } catch {
                        try? manager.removeItem(at: destination)
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if files.isEmpty { failures.append("\(selected.lastPathComponent): no contiene archivos de audio.") }
            } catch { failures.append("\(selected.lastPathComponent): \(error.localizedDescription)") }
        }
        return ImportReport(songs: songs, failures: failures)
    }

    private func coordinatedCopy(_ source: URL, destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            do { try manager.copyItem(at: readable, to: destination) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
}

@MainActor
final class LocalLibrary: ObservableObject {
    @Published private(set) var songs: [LocalSong] = []
    @Published private(set) var importing = false
    @Published var notice: String?
    let root: URL
    private let storage: LocalLibraryStorage
    private var saving = false

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WaveMusic", isDirectory: true)
        storage = LocalLibraryStorage(root: root)
    }

    func load() async {
        do { songs = try await storage.read() }
        catch { notice = "No se pudo leer la biblioteca local: \(error.localizedDescription)" }
    }

    func importFiles(_ urls: [URL]) async {
        guard !importing && !saving else { return }
        importing = true
        notice = nil
        let originalCount = songs.count
        defer { importing = false }
        do {
            let report = try await storage.importFiles(urls)
            songs = report.songs
            let count = songs.count - originalCount
            notice = "\(count) canciones importadas." + (report.failures.isEmpty ? "" : "\n" + report.failures.joined(separator: "\n"))
        } catch { notice = error.localizedDescription }
    }

    func setHidden(_ id: String, hidden: Bool) async {
        guard !importing && !saving, let index = songs.firstIndex(where: { $0.id == id }) else { return }
        saving = true
        defer { saving = false }
        var updated = songs
        updated[index].hidden = hidden
        do { try await storage.save(updated); songs = updated }
        catch { notice = error.localizedDescription }
    }

    func playable(_ song: LocalSong) -> PlaybackSong {
        PlaybackSong(track: song.track, url: root.appendingPathComponent(song.file), source: "local", identity: "local:" + song.id)
    }

    func reorder(_ paths: [String]) async {
        guard !importing && !saving, Set(paths).count == paths.count else { return }
        saving = true
        defer { saving = false }
        let wanted = Set(paths)
        let byID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let reordered = paths.compactMap { byID[$0] }
        guard reordered.count == paths.count else { return }
        var iterator = reordered.makeIterator()
        let updated = songs.map { song in wanted.contains(song.id) ? (iterator.next() ?? song) : song }
        do { try await storage.save(updated); songs = updated }
        catch { notice = error.localizedDescription }
    }
}
