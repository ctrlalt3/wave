import Foundation
import WidgetKit

extension LocalSong {
    func widgetPlayable(root: URL) -> PlaybackSong? {
        guard file == (file as NSString).lastPathComponent, !file.hasPrefix("."),
              FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path) else { return nil }
        if let cloudPath, let cloudServer, WaveAPI.safePath(cloudPath), let api = try? WaveAPI(server: cloudServer) {
            let track = WaveTrack(name: name, artist: artist, duration: duration, relPath: cloudPath, filename: originalFilename ?? file)
            return PlaybackSong(track: track, url: root.appendingPathComponent(file), source: "local", identity: api.base.absoluteString + cloudPath, serverBase: api.base)
        }
        return PlaybackSong(track: track, url: root.appendingPathComponent(file), source: "local", identity: "local:" + id)
    }
}
extension WavePlayer {
    func chooseWidgetSong(source: WaveWidgetLibrarySource, id: String, serverID: String) async {
        guard !choosingWidgetSong else { return }
        choosingWidgetSong = true
        defer { choosingWidgetSong = false; publishWidgetSnapshot(force: true) }
        do {
            _ = await widgetLikePreferences()
            if source == .local {
                let songs = try await LocalLibraryStorage(root: WavePlaybackStorage.root).read()
                guard let selected = songs.first(where: { $0.id == id && !$0.hidden }),
                      let playable = selected.widgetPlayable(root: WavePlaybackStorage.root) else {
                    throw WaveAPI.Failure(message: "Esta canción ya no está en tu biblioteca. Actualiza el selector.")
                }
                let queue = songs.filter { $0.folder == selected.folder && !$0.hidden }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .compactMap { $0.widgetPlayable(root: WavePlaybackStorage.root) }
                play(playable, queue: queue)
            } else {
                let value = UserDefaults.standard.string(forKey: "wave.server") ?? ""
                let api = try WaveAPI(server: value)
                guard WaveWidgetBrowserStorage.key(api.base.absoluteString) == serverID,
                      WaveAPI.safePath(id) else { throw WaveAPI.Failure(message: "El servidor ha cambiado. Actualiza el selector antes de reproducir.") }
                let folder = id.split(separator: "/").dropLast().joined(separator: "/")
                let songs = try await api.tracks(folder: folder)
                guard let selected = songs.first(where: { $0.id == id }) else { throw WaveAPI.Failure(message: "La canción ya no está disponible en esta carpeta.") }
                play(selected, queue: songs, api: api)
            }
        } catch { self.error = error.localizedDescription }
    }
}
