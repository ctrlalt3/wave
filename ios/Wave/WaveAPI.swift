import Foundation

struct WaveFolder: Decodable, Identifiable {
    let name: String
    let count: Int
    var coverUrl: String? = nil
    var id: String { name }
}

struct WaveTrack: Decodable, Identifiable {
    let name: String
    let artist: String
    let duration: Double
    let relPath: String
    let filename: String
    var coverUrl: String? = nil
    var id: String { relPath }
}

struct LibraryState: Decodable {
    let hidden: [String]
    let orders: [String: [String]]
}

struct ServerContents {
    let tracks: [WaveTrack]
    let state: LibraryState
}

struct WaveAPI {
    let base: URL
    let session: URLSession

    init(server: String, session: URLSession = .shared) throws {
        guard var parts = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw Failure(message: "Introduce una dirección HTTPS válida, sin credenciales ni parámetros.")
        }
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        guard let url = parts.url else { throw Failure(message: "Dirección no válida.") }
        base = url
        self.session = session
    }

    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
    }

    func url(_ components: [String]) -> URL {
        components.reduce(base) { $0.appendingPathComponent($1) }
    }

    func audioURL(_ track: WaveTrack) throws -> URL {
        guard Self.safePath(track.relPath) else { throw Failure(message: "Ruta de audio no válida.") }
        return url(["music"] + track.relPath.split(separator: "/").map(String.init))
    }

    func artworkURL(_ path: String?) -> URL? {
        let prefix = "/api/artwork/"
        guard let path, path.hasPrefix(prefix), !path.contains("?"), !path.contains("#"), let decoded = path.removingPercentEncoding else { return nil }
        let relative = String(decoded.dropFirst(prefix.count))
        guard Self.safePath(relative) else { return nil }
        return url(["api", "artwork"] + relative.split(separator: "/").map(String.init))
    }

    func artworkURL(for track: WaveTrack) -> URL? {
        if let path = track.coverUrl { return artworkURL(path) }
        guard Self.safePath(track.relPath) else { return nil }
        return url(["api", "artwork"] + track.relPath.split(separator: "/").map(String.init))
    }

    func get<T: Decodable>(_ components: [String]) async throws -> T {
        try await request(components)
    }

    func post<T: Decodable>(_ components: [String]) async throws -> T {
        try await request(components, method: "POST")
    }

    private func request<T: Decodable>(_ components: [String], method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: url(components))
        request.timeoutInterval = 25
        // Hearts are shared mutable state; a cached read can undo a new save
        // when a folder synchronizes after returning from Discover.
        if components == ["api", "likes"] {
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true else {
            throw Failure(message: "El servidor no ha devuelto datos de Wave. Revisa su dirección.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func folders() async throws -> [WaveFolder] {
        let values: [WaveFolder] = try await get(["api", "folders"])
        return values.filter { Self.safePath($0.name) }
    }

    func tracks(folder: String) async throws -> [WaveTrack] {
        let contents = try await contents(folder: folder)
        let hidden = Set(contents.state.hidden)
        return contents.tracks.filter { !hidden.contains($0.id) }
    }

    func contents(folder: String) async throws -> ServerContents {
        guard Self.safePath(folder) else { throw Failure(message: "Carpeta no válida.") }
        async let tracks: [WaveTrack] = get(["api", "folder", folder, "tracks"])
        async let state: LibraryState = get(["api", "desktop", "state"])
        let (values, organization) = try await (tracks, state)
        return ServerContents(tracks: ordered(values.filter { Self.safePath($0.relPath) && $0.relPath.hasPrefix(folder + "/") }, state: organization, scope: folder), state: organization)
    }

    func allContents() async throws -> ServerContents {
        let folders = try await folders()
        async let state: LibraryState = get(["api", "desktop", "state"])
        let values = try await withThrowingTaskGroup(of: [WaveTrack].self) { group in
            var iterator = folders.makeIterator()
            for _ in 0..<min(3, folders.count) {
                if let folder = iterator.next() { group.addTask { try await self.rawTracks(folder: folder.name) } }
            }
            var result: [WaveTrack] = []
            for try await tracks in group {
                result.append(contentsOf: tracks)
                if let folder = iterator.next() { group.addTask { try await self.rawTracks(folder: folder.name) } }
            }
            return result
        }
        let organization = try await state
        return ServerContents(tracks: ordered(values, state: organization, scope: "*"), state: organization)
    }

    private func rawTracks(folder: String) async throws -> [WaveTrack] {
        let values: [WaveTrack] = try await get(["api", "folder", folder, "tracks"])
        return values.filter { Self.safePath($0.relPath) && $0.relPath.hasPrefix(folder + "/") }
    }

    private func ordered(_ values: [WaveTrack], state: LibraryState, scope: String) -> [WaveTrack] {
        let order = state.orders[scope] ?? []
        let ranks = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        return values.sorted {
                let left = ranks[$0.id] ?? Int.max, right = ranks[$1.id] ?? Int.max
                return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
            }
    }

    func setHidden(_ path: String, hidden: Bool) async throws -> LibraryState {
        guard Self.safePath(path) else { throw Failure(message: "Ruta no válida.") }
        return try await request(["api", "desktop", "state"], method: "POST", body: ["action": "hidden", "paths": [path], "hidden": hidden])
    }

    func saveOrder(scope: String, paths: [String]) async throws -> LibraryState {
        guard (scope == "*" || Self.safePath(scope)), paths.allSatisfy(Self.safePath), Set(paths).count == paths.count else {
            throw Failure(message: "Orden no válido.")
        }
        return try await request(["api", "desktop", "state"], method: "POST", body: ["action": "order", "scope": scope, "paths": paths])
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func toggleLike(_ path: String) async throws -> Bool {
        try await changeLike(path, desired: nil)
    }

    func setLike(_ path: String, liked: Bool) async throws {
        let result = try await changeLike(path, desired: liked)
        if result == liked { return }
        // Older Wave servers accept only toggle. Confirm the desired state
        // with one additional change rather than trusting an unconfirmed save.
        let retry = try await changeLike(path, desired: liked)
        guard retry == liked else {
            throw Failure(message: "El servidor no confirmó Me gusta. Vuelve a intentarlo.")
        }
    }
    private func changeLike(_ path: String, desired: Bool?) async throws -> Bool {
        guard Self.safePath(path) else { throw Failure(message: "Ruta no válida.") }
        struct Response: Decodable { let liked: Bool }
        var body: [String: Any] = ["track": path]
        if let desired { body["liked"] = desired }
        let response: Response = try await request(["api", "like"], method: "POST", body: body)
        return response.liked
    }
}
