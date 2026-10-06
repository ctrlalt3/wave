import Foundation

struct WaveWidgetQueueItem: Codable, Equatable {
    let title: String
    let artist: String
}
struct WaveWidgetSnapshot: Codable, Equatable {
    var songID: String? = nil
    var title = "Tu música, a mano"
    var artist = "Abre Wave para empezar"
    var isPlaying = false
    var isLiked = false
    var elapsed = 0.0
    var duration = 0.0
    var localCount = 0
    var favoritesCount = 0
    var playlistsCount = 0
    var queue: [WaveWidgetQueueItem] = []
    var artworkFilename: String? = nil
    var updatedAt = Date()
    var message: String? = nil
    var fraction: Double { duration.isFinite && duration > 0 && elapsed.isFinite ? min(1, max(0, elapsed / duration)) : 0 }
    static let empty = WaveWidgetSnapshot()
    static let preview = WaveWidgetSnapshot(songID: "preview", title: "Tu próxima canción", artist: "Wave · Música local", isPlaying: true, elapsed: 42, duration: 240, localCount: 128, favoritesCount: 24, playlistsCount: 6)
}
enum WaveWidgetDestination: String, CaseIterable {
    case player, playlists, local, server, dock
    var url: URL { URL(string: "wave://" + rawValue)! }
    init?(url: URL) {
        guard url.scheme?.lowercased() == "wave", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              let host = url.host, let value = Self(rawValue: host) else { return nil }
        self = value
    }
}
enum WaveWidgetStore {
    static let group = "group.app.wave.music"
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) }
    static var available: Bool { container != nil }
    static func read(from root: URL? = container) -> WaveWidgetSnapshot {
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("widget-state.json")),
              data.count < 256 * 1024, let value = try? JSONDecoder().decode(WaveWidgetSnapshot.self, from: data) else { return .empty }
        return value
    }
    @discardableResult static func write(_ value: WaveWidgetSnapshot, to root: URL? = container) -> Bool {
        guard let root else { return false }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: root.appendingPathComponent("widget-state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }
    static func artworkURL(filename: String?, root: URL? = container) -> URL? {
        guard let filename, filename == (filename as NSString).lastPathComponent, filename.hasSuffix(".jpg"),
              !filename.hasPrefix("."), !filename.contains("\\"), let root else { return nil }
        return root.appendingPathComponent(filename)
    }
}
