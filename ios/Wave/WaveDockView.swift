import SwiftUI
import UIKit

struct WaveDockView: View {
    let onClose: () -> Void
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("wave.dock.dimWhenIdle") private var dimWhenIdle = true
    @State private var idle = WaveDockIdlePolicy()
    @State private var dimmed = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                WaveDockLibraryView(onClose: onClose).frame(maxWidth: .infinity, maxHeight: .infinity)
                if let song = player.current {
                    Divider().overlay(Color.white.opacity(0.12))
                    footer(song)
                }
            }.padding(.horizontal, 6).padding(.bottom, 4)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.background(Color(white: 0.035).ignoresSafeArea())
            .foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
            .background(WaveDockActivityObserver { wake() })
            .overlay {
                if dimmed {
                    Color.black.opacity(0.78).ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture { wake() }
                        .accessibilityLabel("Pantalla atenuada. Toca para iluminar")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .task(id: dimWhenIdle && phase == .active) {
                guard dimWhenIdle && phase == .active else { dimmed = false; return }
                while !Task.isCancelled {
                    if dimWhenIdle && phase == .active && !UIAccessibility.isVoiceOverRunning && idle.shouldDim(at: .now) && !dimmed {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { dimmed = true }
                    }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .onChange(of: phase) { _, _ in wake() }
            .onChange(of: dimWhenIdle) { _, _ in wake() }
            .onAppear { wake() }
            .accessibilityIdentifier("wave.dock")
    }
    private func footer(_ song: PlaybackSong) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                nowPlaying(song).frame(minWidth: 100, maxWidth: .infinity)
                WavePlaybackSeekBar(song: song, onArtwork: true).frame(width: 180)
                transport(song)
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) { nowPlaying(song); transport(song) }
                WavePlaybackSeekBar(song: song, onArtwork: true)
            }
        }.padding(.vertical, 2)
    }
    private func nowPlaying(_ song: PlaybackSong) -> some View {
        HStack(spacing: 8) {
            WaveArtwork(size: 32, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(song.track.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(song.track.artist).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                if let error = player.error { Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func transport(_ song: PlaybackSong) -> some View {
        HStack(spacing: 4) {
            Button { wake(); player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
            Button { wake(); player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 48, height: 48).background(Color.white.opacity(0.12), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            Button { wake(); player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
            LikeButton(song: song, compact: true)
        }.font(.title3)
    }
    private func wake() {
        idle.interacted(at: .now)
        if dimmed { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { dimmed = false } }
    }
}
