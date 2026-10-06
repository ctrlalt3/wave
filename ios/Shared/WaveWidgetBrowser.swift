import CryptoKit
import Foundation

// Browsing is metadata-only. Audio and local file URLs stay in Wave's private container.
enum WaveWidgetLibrarySource: String, Codable { case local, server }
struct WaveWidgetBrowserItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case folder, song }
    let id: String
    let title: String
    let subtitle: String
    let kind: Kind
    var playbackID: String? = nil
    var folderPath: String? = nil
}
struct WaveWidgetBrowserState: Codable, Equatable {
    var source: WaveWidgetLibrarySource = .local
    var folder = ""
    var offset = 0
    var revision = UUID().uuidString
    var message: String? = nil
}
struct WaveWidgetBrowserPage: Equatable {
    var state = WaveWidgetBrowserState()
    var items: [WaveWidgetBrowserItem] = []
    var total = 0
    var serverID = ""
    var message: String? = nil
    var title: String { state.folder.split(separator: "/").last.map(String.init) ?? (state.source == .local ? "Mi música" : "Servidor") }
    var canGoBack: Bool { state.offset > 0 }
    func canGoForward(rows: Int) -> Bool { state.offset + rows < total }
    static let empty = WaveWidgetBrowserPage()
    static let preview = WaveWidgetBrowserPage(items: [WaveWidgetBrowserItem(id: "Album", title: "Tu playlist", subtitle: "12 canciones", kind: .folder)], total: 1)
}
struct WaveWidgetFolderRecord: Codable {
    let path: String
    let count: Int
    var parent: String { path.split(separator: "/").dropLast().joined(separator: "/") }
    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}
struct WaveWidgetListing: Codable {
    let generation: String
    let count: Int
    let date: Date
}
enum WaveWidgetBrowserStorage {
    static var root: URL? { WaveWidgetStore.container?.appendingPathComponent("browser", isDirectory: true) }
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.count < 1800 && !path.hasPrefix("/") && !path.contains("\\") &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
    static func key(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func read<T: Decodable>(_ type: T.Type, file: URL) -> T? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func state(root: URL? = WaveWidgetBrowserStorage.root) -> WaveWidgetBrowserState {
        guard let root else { return WaveWidgetBrowserState() }
        let file = root.appendingPathComponent("state.json")
        if let existing = read(WaveWidgetBrowserState.self, file: file) { return existing }
        let initial = WaveWidgetBrowserState(); try? write(initial, file: file)
        return initial
    }
    static func serverURL(root: URL? = WaveWidgetBrowserStorage.root) -> URL? {
        guard let root, let value = read(String.self, file: root.appendingPathComponent("server.json")),
              var parts = URLComponents(string: value), parts.scheme == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        return parts.url
    }
    static func listingDirectory(source: WaveWidgetLibrarySource, folder: String, serverID: String, root: URL? = WaveWidgetBrowserStorage.root) -> URL? {
        root?.appendingPathComponent("listings", isDirectory: true).appendingPathComponent(key(source.rawValue + ":" + serverID + ":" + folder), isDirectory: true)
    }
    static func saveListing(_ items: [WaveWidgetBrowserItem], directory: URL) throws {
        let previous = read(WaveWidgetListing.self, file: directory.appendingPathComponent("index.json"))?.generation
        let generation = UUID().uuidString
        let destination = directory.appendingPathComponent(generation, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for start in stride(from: 0, to: items.count, by: 8) {
            try Task.checkCancellation()
            try write(Array(items[start..<min(start + 8, items.count)]), file: destination.appendingPathComponent("page-\(start / 8).json"))
        }
        // Swap the small index only after every page is ready.
        try write(WaveWidgetListing(generation: generation, count: items.count, date: .now), file: directory.appendingPathComponent("index.json"))
        let old = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil && $0.lastPathComponent != generation }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in old where url.lastPathComponent != previous { try? FileManager.default.removeItem(at: url) }
    }
    static func page(state: WaveWidgetBrowserState, serverID: String, rows: Int, root: URL? = WaveWidgetBrowserStorage.root) -> WaveWidgetBrowserPage {
        var result = WaveWidgetBrowserPage(state: state, serverID: serverID, message: state.message)
        guard let directory = listingDirectory(source: state.source, folder: state.folder, serverID: serverID, root: root),
              let index = read(WaveWidgetListing.self, file: directory.appendingPathComponent("index.json")),
              UUID(uuidString: index.generation) != nil, (0...1_000_000).contains(index.count) else { return result }
        result.total = index.count
        result.state.offset = max(0, min(state.offset, max(0, index.count - 1)))
        let end = min(result.state.offset + max(1, min(rows, 48)), index.count)
        guard end > result.state.offset else { return result }
        let generation = directory.appendingPathComponent(index.generation, isDirectory: true)
        var pages: [Int: [WaveWidgetBrowserItem]] = [:]
        for position in result.state.offset..<end {
            let number = position / 8
            if pages[number] == nil { pages[number] = read([WaveWidgetBrowserItem].self, file: generation.appendingPathComponent("page-\(number).json")) ?? [] }
            let index = position % 8
            if let page = pages[number], page.indices.contains(index) { result.items.append(page[index]) }
        }
        if result.items.isEmpty && result.total > 0 { result.message = "La biblioteca ha cambiado. Pulsa Actualizar." }
        return result
    }
    // The widget process and the app both navigate the same browser. Lock only short disk operations, never network I/O.
    static func withStateLock<T>(root: URL? = WaveWidgetBrowserStorage.root, _ action: () throws -> T) throws -> T {
        guard let root else { throw Failure(message: "Conecta los widgets desde la instalación de Wave.") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lockFile = root.appendingPathComponent("state.lock")
        if !FileManager.default.fileExists(atPath: lockFile.path) {
            do {
                try Data().write(to: lockFile, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                // A second process may have created the marker concurrently.
                guard FileManager.default.fileExists(atPath: lockFile.path) else { throw error }
            }
        }
        var coordinationError: NSError?
        var outcome: Result<T, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: lockFile, options: [], error: &coordinationError) { coordinatedURL in
            outcome = Result {
                try Data().write(to: coordinatedURL)
                return try action()
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw Failure(message: "No se pudo coordinar la biblioteca del widget.") }
        return try outcome.get()
    }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
}

enum WaveWidgetBrowseCommand: String { case local, server, toggleSource, location, up, previousPage, nextPage, folder, refresh }
actor WaveWidgetBrowserService {
    static let shared = WaveWidgetBrowserService()
    private let storageRoot: URL?
    private var lastLocalSignature = ""
    func configureServer(_ value: String) throws {
        guard let root = storageRoot else { return }
        let file = root.appendingPathComponent("server.json")
        let old = WaveWidgetBrowserStorage.read(String.self, file: file)
        guard old != value else { return }
        try WaveWidgetBrowserStorage.write(value, file: file)
        try WaveWidgetBrowserStorage.withStateLock(root: storageRoot) {
            var state = WaveWidgetBrowserStorage.state(root: storageRoot)
            if state.source == .server { state.folder = ""; state.offset = 0; state.message = nil; state.revision = UUID().uuidString }
            try WaveWidgetBrowserStorage.write(state, file: root.appendingPathComponent("state.json"))
        }
    }
    func publishLocal(_ items: [WaveWidgetBrowserItem], folders: [String]) throws {
        guard let root = storageRoot else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let signature = WaveWidgetBrowserStorage.key(String(decoding: try encoder.encode(items), as: UTF8.self))
        guard signature != lastLocalSignature else { return }
        let grouped = Dictionary(grouping: items, by: { $0.folderPath ?? "" })
        var allFolders = Set<String>()
        for folder in folders where WaveWidgetBrowserStorage.safePath(folder) {
            let parts = folder.split(separator: "/")
            for length in 1...parts.count { allFolders.insert(parts.prefix(length).joined(separator: "/")) }
        }
        let sortedFolders = allFolders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var counts: [String: Int] = [:]
        for item in items {
            let parts = (item.folderPath ?? "").split(separator: "/")
            for length in parts.indices { counts[parts.prefix(length + 1).joined(separator: "/"), default: 0] += 1 }
        }
        let records = sortedFolders.map { path in WaveWidgetFolderRecord(path: path, count: counts[path] ?? 0) }
        for folder in [""] + sortedFolders {
            let children = records.filter { $0.parent == folder }.map { WaveWidgetBrowserItem(id: $0.path, title: $0.name, subtitle: "\($0.count) canciones", kind: .folder) }
            let songs = (grouped[folder] ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if let directory = WaveWidgetBrowserStorage.listingDirectory(source: .local, folder: folder, serverID: "", root: storageRoot) {
                try WaveWidgetBrowserStorage.saveListing(children + songs, directory: directory)
            }
        }
        try WaveWidgetBrowserStorage.write(records, file: root.appendingPathComponent("local-folders.json"))
        try WaveWidgetBrowserStorage.withStateLock(root: storageRoot) {
            var state = WaveWidgetBrowserStorage.state(root: storageRoot)
            if state.source == .local && !state.folder.isEmpty && !allFolders.contains(state.folder) {
                state.folder = ""; state.offset = 0; state.revision = UUID().uuidString; state.message = nil
                try WaveWidgetBrowserStorage.write(state, file: root.appendingPathComponent("state.json"))
            }
        }
        lastLocalSignature = signature
    }
    func folderOptions() -> [WaveWidgetFolderRecord] {
        guard let root = storageRoot else { return [] }
        let state = WaveWidgetBrowserStorage.state(root: storageRoot)
        let serverID = WaveWidgetBrowserStorage.serverURL(root: storageRoot).map { WaveWidgetBrowserStorage.key($0.absoluteString) } ?? ""
        let filename = state.source == .local ? "local-folders.json" : "server-folders-" + serverID + ".json"
        return WaveWidgetBrowserStorage.read([WaveWidgetFolderRecord].self, file: root.appendingPathComponent(filename)) ?? []
    }
    func snapshot(rows: Int = 6, refresh: Bool = false) async -> WaveWidgetBrowserPage {
        var state = WaveWidgetBrowserStorage.state(root: storageRoot)
        let serverID = state.source == .server ? WaveWidgetBrowserStorage.serverURL(root: storageRoot).map { WaveWidgetBrowserStorage.key($0.absoluteString) } ?? "" : ""
        var page = WaveWidgetBrowserStorage.page(state: state, serverID: serverID, rows: rows, root: storageRoot)
        if state.source == .server && refresh {
            do { try await loadServer(folder: state.folder); page.message = nil }
            catch { page.message = error.localizedDescription }
            let latest = WaveWidgetBrowserStorage.state(root: storageRoot)
            guard latest.revision == state.revision else { return await snapshot(rows: rows) }
            state.message = page.message
            if let root = storageRoot {
                try? WaveWidgetBrowserStorage.withStateLock(root: storageRoot) {
                    if WaveWidgetBrowserStorage.state(root: storageRoot).revision == state.revision {
                        try WaveWidgetBrowserStorage.write(state, file: root.appendingPathComponent("state.json"))
                    }
                }
            }
            page = WaveWidgetBrowserStorage.page(state: state, serverID: serverID, rows: rows, root: storageRoot)
        }
        let directory = WaveWidgetBrowserStorage.listingDirectory(source: state.source, folder: state.folder, serverID: serverID, root: storageRoot)
        let loaded = directory.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.json").path) } ?? false
        if state.source == .server, page.total == 0, page.message == nil { page.message = loaded ? "Esta carpeta está vacía." : "Pulsa Actualizar para cargar esta biblioteca." }
        if state.source == .local, page.total == 0, page.message == nil { page.message = "Importa música en Wave para verla aquí." }
        if storageRoot == nil { page.message = "Configura el App Group de Wave y sus widgets." }
        return page
    }
    func navigate(_ command: WaveWidgetBrowseCommand, item: String = "", revision: String = "", stride: Int = 1) async -> WaveWidgetBrowserPage {
        do {
            guard let root = storageRoot else { return await snapshot() }
            let changed: Bool = try WaveWidgetBrowserStorage.withStateLock(root: storageRoot) {
                var state = WaveWidgetBrowserStorage.state(root: storageRoot)
                guard revision.isEmpty || revision == state.revision else { return false }
                let serverID = state.source == .server ? WaveWidgetBrowserStorage.serverURL(root: storageRoot).map { WaveWidgetBrowserStorage.key($0.absoluteString) } ?? "" : ""
                let existing = WaveWidgetBrowserStorage.page(state: state, serverID: serverID, rows: max(6, min(stride, 48)), root: storageRoot)
                state.offset = existing.state.offset
                switch command {
                case .local: state.source = .local; state.folder = ""; state.offset = 0
                case .server: state.source = .server; state.folder = ""; state.offset = 0
                case .toggleSource: state.source = state.source == .local ? .server : .local; state.folder = ""; state.offset = 0
                case .location:
                    if item.isEmpty { state.folder = ""; state.offset = 0 }
                    else {
                        let filename = state.source == .local ? "local-folders.json" : "server-folders-" + serverID + ".json"
                        let folders = WaveWidgetBrowserStorage.read([WaveWidgetFolderRecord].self, file: root.appendingPathComponent(filename)) ?? []
                        guard WaveWidgetBrowserStorage.safePath(item), folders.contains(where: { $0.path == item }) else { return false }
                        state.folder = item; state.offset = 0
                    }
                case .up: state.folder = state.folder.split(separator: "/").dropLast().joined(separator: "/"); state.offset = 0
                case .previousPage: state.offset = max(0, state.offset - max(1, min(stride, 48)))
                case .nextPage: state.offset = min(max(0, existing.total - 1), state.offset + max(1, min(stride, 48)))
                case .folder:
                    guard WaveWidgetBrowserStorage.safePath(item), item.split(separator: "/").dropLast().joined(separator: "/") == state.folder,
                          existing.items.contains(where: { $0.kind == .folder && $0.id == item }) else { return false }
                    state.folder = item; state.offset = 0
                case .refresh: break
                }
                state.revision = UUID().uuidString; state.message = nil
                try WaveWidgetBrowserStorage.write(state, file: root.appendingPathComponent("state.json"))
                return true
            }
            return await snapshot(rows: max(6, min(stride, 48)), refresh: changed && command != .previousPage && command != .nextPage)
        } catch {
            var page = await snapshot(rows: max(6, min(stride, 48))); page.message = error.localizedDescription; return page
        }
    }
    struct ServerFolder: Decodable { let name: String; let count: Int }
    struct ServerSong: Decodable { let relPath: String; let name: String; let artist: String }
    struct Organization: Decodable { let hidden: [String] }
    private var session: URLSession
    init(root: URL? = WaveWidgetBrowserStorage.root, session: URLSession = .shared) { self.storageRoot = root; self.session = session }
    private func get<T: Decodable>(_ type: T.Type, base: URL, components: [String]) async throws -> T {
        let url = components.reduce(base) { $0.appendingPathComponent($1) }
        var request = URLRequest(url: url); request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, response.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true,
              data.count < 8 * 1024 * 1024 else { throw WaveWidgetBrowserStorage.Failure(message: "No se pudo conectar al servidor. Puedes reintentar aquí.") }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func loadServer(folder: String) async throws {
        guard let base = WaveWidgetBrowserStorage.serverURL(root: storageRoot), let root = storageRoot else { throw WaveWidgetBrowserStorage.Failure(message: "Guarda tu servidor HTTPS en Ajustes de Wave.") }
        let serverID = WaveWidgetBrowserStorage.key(base.absoluteString)
        let indexFile = root.appendingPathComponent("server-folders-" + serverID + ".json")
        let values = try await get([ServerFolder].self, base: base, components: ["api", "folders"])
        var counts: [String: Int] = [:]
        for value in values where WaveWidgetBrowserStorage.safePath(value.name) {
            let parts = value.name.split(separator: "/")
            for length in 1...parts.count { counts[parts.prefix(length).joined(separator: "/"), default: 0] += max(0, value.count) }
        }
        let folders = counts.map { WaveWidgetFolderRecord(path: $0.key, count: $0.value) }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        try WaveWidgetBrowserStorage.write(folders, file: indexFile)
        let children = folders.filter { $0.parent == folder }.map { WaveWidgetBrowserItem(id: $0.path, title: $0.name, subtitle: "\($0.count) canciones", kind: .folder) }
        var songs: [WaveWidgetBrowserItem] = []
        if !folder.isEmpty {
            guard WaveWidgetBrowserStorage.safePath(folder) else { throw WaveWidgetBrowserStorage.Failure(message: "Carpeta no válida.") }
            async let raw = get([ServerSong].self, base: base, components: ["api", "folder", folder, "tracks"])
            async let organization = get(Organization.self, base: base, components: ["api", "desktop", "state"])
            let (tracks, state) = try await (raw, organization)
            let hidden = Set(state.hidden)
            songs = tracks.filter { WaveWidgetBrowserStorage.safePath($0.relPath) && $0.relPath.split(separator: "/").dropLast().joined(separator: "/") == folder && !hidden.contains($0.relPath) }
                .map { WaveWidgetBrowserItem(id: $0.relPath, title: $0.name, subtitle: $0.artist, kind: .song, playbackID: base.absoluteString + $0.relPath) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        if let directory = WaveWidgetBrowserStorage.listingDirectory(source: .server, folder: folder, serverID: serverID, root: storageRoot) {
            try WaveWidgetBrowserStorage.saveListing(children + songs, directory: directory)
        }
    }
}
