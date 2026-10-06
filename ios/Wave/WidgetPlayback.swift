import AVFoundation
import CryptoKit
import Foundation
import MediaPlayer
import UIKit
import WidgetKit

// The queue remains in the app's private container. Widgets receive metadata only.
struct WaveSavedPlaybackSong: Codable {
    let identity: String
    let name: String
    let artist: String
    let duration: Double
    let path: String
    let filename: String
    let source: String
    let remoteURL: URL?
    let localFile: String?
    let mediaID: UInt64?
    let coverURL: URL?
    let serverBase: URL?
    init(_ song: PlaybackSong) {
        identity = song.id; name = song.track.name; artist = song.track.artist
        duration = song.track.duration; path = song.track.relPath; filename = song.track.filename; source = song.source
        remoteURL = song.url?.scheme == "https" ? song.url : nil
        localFile = song.source == "local" ? song.url?.lastPathComponent : nil
        mediaID = song.mediaItem?.persistentID; coverURL = song.coverURL; serverBase = song.serverBase
    }
    func restore(root: URL, mediaItems: [MPMediaItem]) -> PlaybackSong? {
        let track = WaveTrack(name: name, artist: artist, duration: duration, relPath: path, filename: filename)
        if let mediaID, let item = mediaItems.first(where: { $0.persistentID == mediaID }) {
            return PlaybackSong(track: track, url: item.assetURL, source: source, identity: identity, mediaItem: item, coverURL: coverURL, serverBase: serverBase)
        }
        if let localFile, localFile == (localFile as NSString).lastPathComponent, !localFile.hasPrefix(".") {
            let file = root.appendingPathComponent(localFile)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return PlaybackSong(track: track, url: file, source: source, identity: identity, coverURL: coverURL, serverBase: serverBase)
        }
        if let remoteURL, remoteURL.scheme == "https", let serverBase,
           let api = try? WaveAPI(server: serverBase.absoluteString), let trusted = try? api.audioURL(track), trusted == remoteURL {
            return PlaybackSong(track: track, url: trusted, source: source, identity: identity, coverURL: coverURL, serverBase: serverBase)
        }
        return nil
    }
}
struct WaveSavedPlayback: Codable {
    let currentID: String
    let elapsed: Double
    let songs: [WaveSavedPlaybackSong]
    let shuffle: Bool
    let repeatQueue: Bool
}
enum WavePlaybackStorage {
    static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WaveMusic", isDirectory: true) }
    static var file: URL { root.appendingPathComponent("widget-playback.json") }
    static func read() -> WaveSavedPlayback? {
        guard let data = try? Data(contentsOf: file), data.count < 8 * 1024 * 1024 else { return nil }
        return try? JSONDecoder().decode(WaveSavedPlayback.self, from: data)
    }
    static func write(_ value: WaveSavedPlayback) {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { /* Playback continues if private persistence is temporarily unavailable. */ }
    }
}

extension WavePlayer {
    func publishWidgetLibrary(localCount: Int, favoritesCount: Int, playlistsCount: Int) {
        guard widgetLocalCount != localCount || widgetFavoritesCount != favoritesCount || widgetPlaylistsCount != playlistsCount else { return }
        widgetLocalCount = localCount; widgetFavoritesCount = favoritesCount; widgetPlaylistsCount = playlistsCount
        publishWidgetSnapshot(force: true)
    }
    func publishWidgetSnapshot(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastWidgetPublication) >= 30 else { return }
        lastWidgetPublication = .now
        var snapshot = WaveWidgetSnapshot()
        snapshot.localCount = widgetLocalCount; snapshot.favoritesCount = widgetFavoritesCount; snapshot.playlistsCount = widgetPlaylistsCount
        if let current {
            snapshot.songID = current.id; snapshot.title = current.track.name; snapshot.artist = current.track.artist
            snapshot.isPlaying = playing; snapshot.isLiked = widgetCurrentLiked
            snapshot.elapsed = elapsed.isFinite ? max(0, elapsed) : 0; snapshot.duration = duration.isFinite ? max(0, duration) : 0
            snapshot.artworkFilename = widgetArtworkFilename
            if let index = queue.firstIndex(where: { $0.id == current.id }) {
                snapshot.queue = queue.dropFirst(index + 1).prefix(3).map { WaveWidgetQueueItem(title: $0.track.name, artist: $0.track.artist) }
            }
            let signature = queue.map(\.id)
            if persistedWidgetQueue != signature || persistedWidgetCurrentID != current.id {
                persistedWidgetQueue = signature; persistedWidgetCurrentID = current.id
                widgetSavedSongs = queue.map(WaveSavedPlaybackSong.init)
            }
            WavePlaybackStorage.write(WaveSavedPlayback(currentID: current.id, elapsed: snapshot.elapsed, songs: widgetSavedSongs, shuffle: shuffle, repeatQueue: repeatQueue))
        }
        snapshot.message = error
        if WaveWidgetStore.write(snapshot), force { WidgetCenter.shared.reloadAllTimelines() }
    }
    func cacheWidgetArtwork(_ artwork: MPMediaItemArtwork?) {
        guard let artwork, let current, let root = WaveWidgetStore.container else { return }
        let key = SHA256.hash(data: Data(current.id.utf8)).map { String(format: "%02x", $0) }.joined()
        let filename = "cover-" + key + ".jpg"
        guard let image = artwork.image(at: CGSize(width: 256, height: 256)) else { return }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            let scale = max(256 / max(image.size.width, 1), 256 / max(image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (256 - size.width) / 2, y: (256 - size.height) / 2, width: size.width, height: size.height))
        }
        guard let data = thumbnail.jpegData(compressionQuality: 0.75) else { return }
        do {
            try data.write(to: root.appendingPathComponent(filename), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            widgetArtworkFilename = filename
            let cached = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("cover-") && $0.pathExtension == "jpg" }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in cached.dropFirst(20) where old.lastPathComponent != filename { try? FileManager.default.removeItem(at: old) }
            publishWidgetSnapshot(force: true)
        } catch { }
    }
    @discardableResult func restoreWidgetQueue() async -> Bool {
        if current != nil { return true }
        guard !restoringWidgetPlayback else { return false }
        restoringWidgetPlayback = true
        defer { restoringWidgetPlayback = false }
        guard let saved = WavePlaybackStorage.read() else {
            error = "Abre Wave y elige una canción para activar los controles del widget."
            publishWidgetSnapshot(force: true); return false
        }
        let mediaItems = MPMediaLibrary.authorizationStatus() == .authorized ? (MPMediaQuery.songs().items ?? []) : []
        let restored = saved.songs.compactMap { $0.restore(root: WavePlaybackStorage.root, mediaItems: mediaItems) }
        guard let song = restored.first(where: { $0.id == saved.currentID }) ?? restored.first else {
            error = "La última canción ya no está disponible. Elige otra en Wave."
            publishWidgetSnapshot(force: true); return false
        }
        let preferences = await widgetLikePreferences()
        // A scene may have started playback while preferences were loading.
        guard current == nil else { return true }
        let songs = (try? await LocalLibraryStorage(root: WavePlaybackStorage.root).read()) ?? []
        guard current == nil else { return true }
        publishWidgetLibrary(localCount: songs.count, favoritesCount: preferences.state.favorites.count, playlistsCount: preferences.state.visiblePlaylists.count)
        shuffle = saved.shuffle; repeatQueue = saved.repeatQueue
        play(song, queue: restored, autoPlay: false)
        if song.id == saved.currentID { seek(saved.elapsed) }
        publishWidgetSnapshot(force: true)
        return current != nil
    }
    func performWidgetCommand(_ command: WaveWidgetPlaybackCommand) async {
        guard await restoreWidgetQueue() else { return }
        switch command {
        case .toggle: toggle()
        case .previous: previous()
        case .next: next()
        }
        publishWidgetSnapshot(force: true)
    }
}
