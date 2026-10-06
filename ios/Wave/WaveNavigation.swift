import SwiftUI
import Combine
import UIKit

struct WaveGlassPanel: ViewModifier {
    var radius: CGFloat = 24
    var capsule = false
    @AppStorage("wave.liquidGlass") private var enabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if enabled && !reduceTransparency {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                if capsule { content.glassEffect(.regular.interactive(), in: Capsule()) }
                else { content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: radius)) }
            } else { material(content) }
            #else
            material(content)
            #endif
        } else if capsule {
            content.background(WaveTheme.surface, in: Capsule())
                .overlay { Capsule().stroke(WaveTheme.border.opacity(0.3), lineWidth: 0.5) }
        } else {
            content.background(WaveTheme.surface, in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).stroke(WaveTheme.border.opacity(0.3), lineWidth: 0.5) }
        }
    }
    @ViewBuilder private func material(_ content: Content) -> some View {
        if capsule {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5) }
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.3), lineWidth: 0.5) }
        }
    }
}

struct WaveSongMenu: ViewModifier {
    let song: PlaybackSong
    var queue: [PlaybackSong] = []
    var playQueue: (() -> [PlaybackSong])? = nil
    @EnvironmentObject private var player: WavePlayer
    @EnvironmentObject private var preferences: LibraryPreferences
    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                let songs = playQueue?() ?? queue
                player.play(song, queue: songs.isEmpty ? [song] : songs)
            } label: { Label("Reproducir", systemImage: "play.fill") }
            Button { Task { await preferences.toggle(song) } } label: {
                Label(preferences.liked(song.id) ? "Quitar Me gusta" : "Me gusta", systemImage: preferences.liked(song.id) ? "heart.slash" : "heart.fill")
            }.tint(.red).disabled(!preferences.ready || preferences.pendingLikes.contains(song.id))
            Button { player.enqueue(song, next: true) } label: { Label("Reproducir después", systemImage: "text.line.first.and.arrowtriangle.forward") }.disabled(player.queue.contains { $0.id == song.id })
            Button { player.enqueue(song, next: false) } label: { Label("Añadir a la cola", systemImage: "text.badge.plus") }.disabled(player.queue.contains { $0.id == song.id })
            if player.current?.id == song.id {
                Button { player.toggle() } label: { Label(player.playing ? "Pausar" : "Continuar", systemImage: player.playing ? "pause.fill" : "play.fill") }
            }
        }.simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
    }
}

struct WaveServerSongMenu: ViewModifier {
    let track: WaveTrack
    let tracks: [WaveTrack]
    let api: WaveAPI
    @ViewBuilder func body(content: Content) -> some View {
        if let song = try? PlaybackSong.server(track, api: api) {
            content.modifier(WaveSongMenu(song: song, playQueue: { tracks.compactMap { try? PlaybackSong.server($0, api: api) } }))
        } else { content }
    }
}

// Gestures have a clear direction and a deliberate threshold; no wrap at edges.
enum WaveGestureNavigation {
    static func section(after current: WaveSection, horizontal: CGFloat, vertical: CGFloat) -> WaveSection? {
        guard abs(horizontal) >= 70, abs(horizontal) > abs(vertical) * 1.5,
              let index = WaveSection.allCases.firstIndex(of: current) else { return nil }
        let destination = index + (horizontal < 0 ? 1 : -1)
        guard WaveSection.allCases.indices.contains(destination) else { return nil }
        return WaveSection.allCases[destination]
    }
}
