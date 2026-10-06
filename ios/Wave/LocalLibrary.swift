import AVFoundation
import Combine
import CryptoKit
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

    // Include intermediate folders that only contain nested albums.
    static func playlistFolders(for songs: [LocalSong]) -> [String] {
        let paths = songs.flatMap { song -> [String] in
            let parts = song.folder.split(separator: "/").map(String.init)
            return parts.indices.map { parts.prefix($0 + 1).joined(separator: "/") }
        }
        return Array(Set(paths)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func childFolders(in folder: String?, songs: [LocalSong]) -> [String] {
        let prefix = folder.map { $0 + "/" } ?? ""
        return playlistFolders(for: songs).filter { path in
            guard path.hasPrefix(prefix) else { return false }
            let relative = path.dropFirst(prefix.count)
            return !relative.isEmpty && !relative.contains("/")
        }
    }

    static func automaticPlaylists(for songs: [LocalSong]) -> [String] {
        childFolders(in: nil, songs: songs).flatMap { root -> [String] in
            let children = childFolders(in: root, songs: songs)
            return children.isEmpty ? [root] : children
        }
    }

    var track: WaveTrack {
        WaveTrack(name: name, artist: artist, duration: duration, relPath: id, filename: originalFilename ?? file)
    }
}

struct LocalFolderSummary {
    var count: Int
    var first: LocalSong
    static func build(_ songs: [LocalSong]) -> [String: LocalFolderSummary] {
        var result: [String: LocalFolderSummary] = [:]
        for song in songs where !song.hidden {
            let parts = song.folder.split(separator: "/").map(String.init)
            for index in parts.indices {
                let folder = parts.prefix(index + 1).joined(separator: "/")
                if var summary = result[folder] {
                    summary.count += 1
                    if song.folder.localizedStandardCompare(summary.first.folder) == .orderedAscending { summary.first = song }
                    result[folder] = summary
                } else { result[folder] = LocalFolderSummary(count: 1, first: song) }
            }
        }
        return result
    }
}

struct ImportReport {
    let songs: [LocalSong]
    let failures: [String]
    var skipped = 0
    var playlistFolders: [String] = []
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

    private func fingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // Preserve every audio file and a recoverable manifest before hiding duplicates.
    func repairDuplicates() throws -> (songs: [LocalSong], replacements: [String: String]) {
        let original = try read()
        var seen: [[String]: String] = [:]
        var kept: [LocalSong] = []
        var replacements: [String: String] = [:]
        for song in original {
            guard let hash = try? fingerprint(root.appendingPathComponent(song.file)) else { kept.append(song); continue }
            let key = [song.folder, song.originalFilename ?? song.name + " " + song.artist, hash]
            if let existing = seen[key] {
                replacements[song.id] = existing
                if let index = kept.firstIndex(where: { $0.id == existing }) { kept[index].hidden = kept[index].hidden && song.hidden }
            } else { seen[key] = song.id; kept.append(song) }
        }
        if !replacements.isEmpty {
            let backup = root.appendingPathComponent("library-before-dedup-" + UUID().uuidString + ".json")
            try JSONEncoder().encode(original).write(to: backup, options: .atomic)
            // Keep the ID mapping recoverable across an interrupted launch.
            let mappingFile = root.appendingPathComponent("duplicate-replacements.json")
            var mapping = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: mappingFile))) ?? [:]
            mapping.merge(replacements) { _, new in new }
            try JSONEncoder().encode(mapping).write(to: mappingFile, options: .atomic)
            try save(kept)
        }
        let mapping = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: root.appendingPathComponent("duplicate-replacements.json")))) ?? [:]
        return (kept, mapping)
    }

    func importFiles(_ urls: [URL]) async throws -> ImportReport {
        var songs = try read()
        var failures: [String] = []
        var skipped = 0
        var playlistFolders = Set<String>()
        var known = Set<[String]>()
        for song in songs {
            if let hash = try? fingerprint(root.appendingPathComponent(song.file)) {
                known.insert([song.folder, song.originalFilename ?? song.name + " " + song.artist, hash])
            }
        }
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

                if directory {
                    let rootFolder = selected.lastPathComponent
                    let existing = songs.filter { $0.folder == rootFolder || $0.folder.hasPrefix(rootFolder + "/") }
                    let discovered = files.map { LocalSong(id: "", file: "", folder: $0.1, name: "", artist: "", duration: 0) }
                    playlistFolders.formUnion(LocalSong.automaticPlaylists(for: existing + discovered))
                }
                for (source, folder) in files.sorted(by: { $0.0.path < $1.0.path }) {
                    let id = UUID().uuidString
                    let filename = id + "." + source.pathExtension.lowercased()
                    let destination = root.appendingPathComponent(filename)
                    do {
                        guard Self.extensions.contains(source.pathExtension.lowercased()) else {
                            throw WaveAPI.Failure(message: "Formato de archivo no admitido.")
                        }
                        let hash = try fingerprint(source)
                        let key = [folder, source.lastPathComponent, hash]
                        if known.contains(key) { skipped += 1; continue }
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
                        known.insert(key)
                    } catch {
                        try? manager.removeItem(at: destination)
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                if files.isEmpty { failures.append("\(selected.lastPathComponent): no contiene archivos de audio.") }
            } catch { failures.append("\(selected.lastPathComponent): \(error.localizedDescription)") }
        }
        let validFolders = Set(LocalSong.playlistFolders(for: songs))
        return ImportReport(songs: songs, failures: failures, skipped: skipped, playlistFolders: playlistFolders.filter { validFolders.contains($0) }.sorted())
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
    @Published private(set) var songs: [LocalSong] = [] {
        didSet { folderSummaries = LocalFolderSummary.build(songs) }
    }
    private(set) var folderSummaries: [String: LocalFolderSummary] = [:]
    @Published private(set) var importing = false
    @Published private(set) var ready = false
    @Published var notice: String?
    @Published private(set) var duplicateReplacements: [String: String] = [:]
    let root: URL
    private let storage: LocalLibraryStorage
    private var saving = false

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WaveMusic", isDirectory: true)
        storage = LocalLibraryStorage(root: root)
    }

    func load() async {
        do {
            let repaired = try await storage.repairDuplicates()
            songs = repaired.songs
            duplicateReplacements = repaired.replacements
            ready = true
        }
        catch { notice = "No se pudo leer la biblioteca local: \(error.localizedDescription)" }
    }

    @discardableResult
    func importFiles(_ urls: [URL]) async -> [String] {
        guard !importing && !saving else { return [] }
        importing = true
        notice = nil
        let originalCount = songs.count
        defer { importing = false }
        do {
            let report = try await storage.importFiles(urls)
            songs = report.songs
            let count = songs.count - originalCount
            notice = "\(count) canciones importadas." + (report.failures.isEmpty ? "" : "\n" + report.failures.joined(separator: "\n"))
            if report.skipped > 0 { notice = (notice ?? "") + "\n\(report.skipped) canciones ya importadas; se han evitado los duplicados." }
            return report.playlistFolders
        } catch { notice = error.localizedDescription; return [] }
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

    func liked(_ song: LocalSong, in preferences: LibraryPreferences) -> Bool { preferences.liked("local:" + song.id) }

    // Single source of truth for "which songs live under this folder": Descubre, las
    // playlists y el filtro de favoritos deben coincidir siempre en este cálculo.
    func songs(in folder: String?, recursive: Bool, advanced: Bool = false) -> [LocalSong] {
        songs.filter { song in
            let matchesFolder = folder.map { song.folder == $0 || (recursive && song.folder.hasPrefix($0 + "/")) } ?? true
            return matchesFolder && (advanced || !song.hidden)
        }
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
