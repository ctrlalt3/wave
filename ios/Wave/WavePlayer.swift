import AVFoundation
import Combine
import MediaPlayer

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
final class WavePlayer: ObservableObject {
    @Published private(set) var current: PlaybackSong?
    @Published private(set) var playing = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var queue: [PlaybackSong] = []
    @Published var shuffle = false {
        didSet { if current?.mediaItem != nil { music.shuffleMode = shuffle ? .songs : .off } }
    }
    @Published var repeatQueue = false {
        didSet { if current?.mediaItem != nil { music.repeatMode = repeatQueue ? .all : .none } }
    }
    @Published var error: String?
    private let player = AVPlayer()
    private lazy var music = MPMusicPlayerController.applicationQueuePlayer
    private var deviceNotificationsStarted = false
    private var timer: AnyCancellable?
    private var interruptedWhilePlaying = false
    private var observations = Set<AnyCancellable>()
    private var itemObservation: NSKeyValueObservation?

    init() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            if self.current?.mediaItem != nil { self.syncDevicePlayback(); return }
            let seconds = self.player.currentTime().seconds
            self.elapsed = seconds.isFinite ? max(0, seconds) : 0
            let length = self.player.currentItem?.duration.seconds ?? 0
            if length.isFinite && length > 0 { self.duration = length }
            self.updateNowPlaying()
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

    func play(_ song: PlaybackSong, queue: [PlaybackSong]) {
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
                        else { self.music.play(); self.syncDevicePlayback() }
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
            player.play()
            updateNowPlaying()
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
        if current?.mediaItem != nil { music.currentPlaybackTime = min(max(0, seconds), duration); syncDevicePlayback(); return }
        player.seek(to: CMTime(seconds: min(max(0, seconds), duration), preferredTimescale: 600))
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

    private func updateNowPlaying() {
        guard let current else { return }
        guard current.mediaItem == nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.track.name,
            MPMediaItemPropertyArtist: current.track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0),
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0
        ]
    }

    private func syncDevicePlayback() {
        guard current?.mediaItem != nil else { return }
        if let item = music.nowPlayingItem, let song = queue.first(where: { $0.mediaItem?.persistentID == item.persistentID }) {
            current = song
            duration = song.track.duration
        }
        playing = music.playbackState == .playing
        let time = music.currentPlaybackTime
        elapsed = time.isFinite ? max(0, time) : 0
    }
}
