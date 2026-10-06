import AVFoundation
import Combine
import MediaPlayer
import UIKit

struct PlaybackSong: Identifiable {
    let track: WaveTrack
    let url: URL?
    let source: String
    let identity: String
    var mediaItem: MPMediaItem? = nil
    var coverURL: URL? = nil
    var serverBase: URL? = nil
    var id: String { identity }

    static func server(_ track: WaveTrack, api: WaveAPI) throws -> PlaybackSong {
        PlaybackSong(track: track, url: try api.audioURL(track), source: "server", identity: api.base.absoluteString + track.id, coverURL: api.artworkURL(for: track), serverBase: api.base)
    }
}

@MainActor
final class WavePlaybackProgress: ObservableObject {
    @Published var elapsed = 0.0
    @Published var duration = 0.0
}

@MainActor
final class WavePlayer: ObservableObject {
    static let shared = WavePlayer()
    var lastWidgetPublication = Date.distantPast
    var widgetLocalCount = 0
    var widgetFavoritesCount = 0
    var widgetPlaylistsCount = 0
    var widgetCurrentLiked = false
    var widgetArtworkFilename: String?
    var persistedWidgetQueue: [String] = []
    var persistedWidgetCurrentID: String?
    var widgetSavedSongs: [WaveSavedPlaybackSong] = []
    var restoringWidgetPlayback = false
    var widgetPreferencesOwner: LibraryPreferences?
    @Published private(set) var current: PlaybackSong? {
        didSet {
            if oldValue?.id != current?.id { loadNowPlayingArtwork() }
            updateRemoteLike()
        }
    }
    @Published private(set) var playing = false { didSet { if oldValue != playing { publishWidgetSnapshot(force: true) } } }
    let progress = WavePlaybackProgress()
    var elapsed: Double {
        get { progress.elapsed }
        set { if progress.elapsed != newValue { progress.elapsed = newValue } }
    }
    var duration: Double {
        get { progress.duration }
        set { if progress.duration != newValue { progress.duration = newValue } }
    }
    @Published private(set) var queue: [PlaybackSong] = []
    @Published var shuffle = false {
        didSet { if current?.mediaItem != nil { music.shuffleMode = shuffle ? .songs : .off }; if oldValue != shuffle { publishWidgetSnapshot(force: true) } }
    }
    @Published var repeatQueue = false {
        didSet { if current?.mediaItem != nil { music.repeatMode = repeatQueue ? .all : .none }; if oldValue != repeatQueue { publishWidgetSnapshot(force: true) } }
    }
    @Published var error: String?
    private let player = AVPlayer()
    private lazy var music = MPMusicPlayerController.applicationQueuePlayer
    private var deviceNotificationsStarted = false
    private var timer: AnyCancellable?
    private var interruptedWhilePlaying = false
    private var observations = Set<AnyCancellable>()
    private var seekGeneration = 0
    private var seeking = false
    private var itemObservation: NSKeyValueObservation?
    private var artworkTask: Task<Void, Never>?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private weak var preferences: LibraryPreferences?
    private var favoritesObservation: AnyCancellable?


    init() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            if self.current?.mediaItem != nil { self.syncDevicePlayback(); return }
            let seconds = self.player.currentTime().seconds
            if !self.seeking { self.elapsed = seconds.isFinite ? max(0, seconds) : 0 }
            let length = self.player.currentItem?.duration.seconds ?? 0
            if length.isFinite && length > 0 { self.duration = length }
            self.updateNowPlaying()
            self.publishWidgetSnapshot()
        }
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard self?.current?.mediaItem == nil else { return }
                self?.playing = status == .playing
                self?.updateNowPlaying()
            }.store(in: &observations)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
                if type == .began {
                    let wasPlaying = self.playing
                    self.pause()
                    self.interruptedWhilePlaying = wasPlaying
                } else {
                    let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                    if self.interruptedWhilePlaying && options.contains(.shouldResume) { self.resume() }
                    self.interruptedWhilePlaying = false
                }
            }.store(in: &observations)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.next()
            }.store(in: &observations)
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let item = notification.object as? AVPlayerItem, item === self.player.currentItem else { return }
                self.error = "No se pudo reproducir este archivo. Revisa la conexión y el formato."
            }.store(in: &observations)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self?.pause()
                }
            }.store(in: &observations)
        let commands = MPRemoteCommandCenter.shared()
        commands.likeCommand.isEnabled = false
        commands.likeCommand.localizedTitle = "Me gusta"
        commands.likeCommand.localizedShortTitle = "Me gusta"
        commands.likeCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self, let song = self.current, let preferences = self.preferences,
                      preferences.ready, !preferences.pendingLikes.contains(song.id) else { return }
                await preferences.toggle(song)
                self.updateRemoteLike()
            }
            return .success
        }
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }; return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }; return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }; return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }; return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(position) }; return .success
        }
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange, .MPMusicPlayerControllerPlaybackStateDidChange] {
            NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.syncDevicePlayback() }.store(in: &observations)
        }
    }

    func play(_ track: WaveTrack, queue: [WaveTrack], api: WaveAPI) {
        do {
            let songs = try queue.map { try PlaybackSong.server($0, api: api) }
            play(try PlaybackSong.server(track, api: api), queue: songs)
        } catch { self.error = error.localizedDescription }
    }

    func play(_ song: PlaybackSong, queue: [PlaybackSong], autoPlay: Bool = true) {
        seekGeneration += 1; seeking = false
        player.currentItem?.cancelPendingSeeks()
        do {
            if let item = song.mediaItem {
                guard MPMediaLibrary.authorizationStatus() == .authorized else {
                    throw WaveAPI.Failure(message: "Permite el acceso a Música para reproducir esta canción.")
                }
                player.pause()
                player.replaceCurrentItem(with: nil)
                itemObservation = nil
                self.queue = queue.filter { $0.mediaItem != nil }
                current = song
                elapsed = 0
                duration = song.track.duration
                error = nil
                publishWidgetSnapshot(force: true)
                if !deviceNotificationsStarted { music.beginGeneratingPlaybackNotifications(); deviceNotificationsStarted = true }
                music.setQueue(with: MPMediaItemCollection(items: self.queue.compactMap(\.mediaItem)))
                music.nowPlayingItem = item
                music.shuffleMode = shuffle ? .songs : .off
                music.repeatMode = repeatQueue ? .all : .none
                music.prepareToPlay { [weak self] failure in
                    let message = failure?.localizedDescription
                    Task { @MainActor in
                        guard let self, self.current?.id == song.id else { return }
                        if let message { self.error = "No se pudo reproducir desde Música: \(message)" }
                        else { if autoPlay { self.music.play() }; self.syncDevicePlayback(); self.publishWidgetSnapshot(force: true) }
                    }
                }
                return
            }
            guard let url = song.url else { throw WaveAPI.Failure(message: "Esta canción no tiene una dirección de audio.") }
            if current?.mediaItem != nil { music.stop() }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            self.queue = queue
            current = song
            elapsed = 0
            duration = song.track.duration
            error = nil
            let item = AVPlayerItem(url: url)
            itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let message = item.error?.localizedDescription ?? "No se pudo reproducir este formato de audio."
                Task { @MainActor in
                    guard self?.current?.id == song.id else { return }
                    self?.error = message
                }
            }
            player.replaceCurrentItem(with: item)
            if autoPlay { player.play() } else { player.pause(); playing = false }
            updateNowPlaying()
            publishWidgetSnapshot(force: true)
        } catch { self.error = error.localizedDescription }
    }

    func resume() {
        guard current != nil else { return }
        if current?.mediaItem != nil { music.play(); syncDevicePlayback(); return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if duration > 0 && elapsed >= duration - 0.1 { player.seek(to: .zero) }
            player.play()
        } catch { self.error = error.localizedDescription }
    }

    func pause() {
        interruptedWhilePlaying = false
        if current?.mediaItem != nil { music.pause(); syncDevicePlayback() }
        else { player.pause() }
    }

    func toggle() { playing ? pause() : resume() }

    func seek(_ seconds: Double) {
        guard seconds.isFinite, duration > 0 else { return }
        let target = min(max(0, seconds), duration)
        elapsed = target
        if current?.mediaItem != nil { music.currentPlaybackTime = target; syncDevicePlayback(); return }
        guard let item = player.currentItem else { return }
        seekGeneration += 1
        let generation = seekGeneration
        seeking = true
        item.cancelPendingSeeks()
        // A small tolerance avoids expensive frame-exact decoding of audio.
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.seekGeneration == generation else { return }
                self.seeking = false
                let actual = self.player.currentTime().seconds
                if actual.isFinite { self.elapsed = max(0, actual) }
                self.updateNowPlaying()
            }
        }
        updateNowPlaying()
        publishWidgetSnapshot(force: true)
    }

    func enqueue(_ song: PlaybackSong, next: Bool) {
        guard let current else { play(song, queue: [song]); return }
        guard !queue.contains(where: { $0.id == song.id }) else { return }
        guard (song.mediaItem != nil) == (current.mediaItem != nil) else {
            error = "La cola debe usar el mismo reproductor (Música o archivos de Wave)."
            return
        }
        if next, let index = queue.firstIndex(where: { $0.id == current.id }) {
            queue.insert(song, at: index + 1)
        } else { queue.append(song) }
        publishWidgetSnapshot(force: true)
        if let item = song.mediaItem {
            let items = MPMediaItemCollection(items: [item])
            let descriptor = MPMusicPlayerMediaItemQueueDescriptor(itemCollection: items)
            if next { music.prepend(descriptor) } else { music.append(descriptor) }
        }
    }

    func next() {
        if current?.mediaItem != nil { music.skipToNextItem(); syncDevicePlayback() }
        else { move(1) }
    }
    func previous() {
        if current?.mediaItem != nil { music.skipToPreviousItem(); syncDevicePlayback() }
        else { move(-1) }
    }
    private func move(_ delta: Int) {
        guard let current, let index = queue.firstIndex(where: { $0.id == current.id }) else { return }
        var destination = index + delta
        if shuffle && delta > 0, let random = queue.indices.filter({ $0 != index }).randomElement() { destination = random }
        if repeatQueue && !queue.isEmpty { destination = (destination + queue.count) % queue.count }
        guard queue.indices.contains(destination) else { return }
        play(queue[destination], queue: queue)
    }

    func connectFavorites(_ preferences: LibraryPreferences) {
        guard self.preferences !== preferences else { return }
        if widgetPreferencesOwner !== preferences { widgetPreferencesOwner = nil }
        self.preferences = preferences
        favoritesObservation = preferences.$state.combineLatest(preferences.$ready, preferences.$pendingLikes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateRemoteLike() }
        updateRemoteLike()
    }

    func widgetLikePreferences() async -> LibraryPreferences {
        if let preferences {
            if !preferences.ready { await preferences.load() }
            return preferences
        }
        let value = LibraryPreferences(); await value.load()
        widgetPreferencesOwner = value; connectFavorites(value)
        return value
    }

    private func updateRemoteLike() {
        let command = MPRemoteCommandCenter.shared().likeCommand
        let liked = current.map { preferences?.liked($0.id) == true } ?? false
        let changed = widgetCurrentLiked != liked
        widgetCurrentLiked = liked
        command.isActive = liked
        command.localizedTitle = liked ? "Quitar Me gusta" : "Me gusta"
        command.localizedShortTitle = command.localizedTitle
        command.isEnabled = current.map {
            preferences?.ready == true && preferences?.pendingLikes.contains($0.id) == false
        } ?? false
        if changed { publishWidgetSnapshot(force: true) }
    }

    private func loadNowPlayingArtwork() {
        artworkTask?.cancel()
        nowPlayingArtwork = current?.mediaItem?.artwork
        widgetArtworkFilename = nil
        cacheWidgetArtwork(nowPlayingArtwork)
        publishWidgetSnapshot(force: true)
        // Clear the previous track's artwork immediately, before any network request.
        updateNowPlaying()
        guard let song = current, song.mediaItem == nil else { return }
        artworkTask = Task { [weak self] in
            let image = await ArtworkCache.shared.image(remote: song.coverURL,
                audio: song.source == "local" ? song.url : nil)
            guard !Task.isCancelled, let self, self.current?.id == song.id, let image else { return }
            self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.cacheWidgetArtwork(self.nowPlayingArtwork)
            self.updateNowPlaying()
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.track.name,
            MPMediaItemPropertyArtist: current.track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
        if let artwork = nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func syncDevicePlayback() {
        guard current?.mediaItem != nil else { return }
        if let item = music.nowPlayingItem, let song = queue.first(where: { $0.mediaItem?.persistentID == item.persistentID }) {
            if current?.id != song.id { current = song }
            duration = song.track.duration
        }
        let isPlaying = music.playbackState == .playing
        if playing != isPlaying { playing = isPlaying }
        let time = music.currentPlaybackTime
        elapsed = time.isFinite ? max(0, time) : 0
        updateNowPlaying()
    }
}
