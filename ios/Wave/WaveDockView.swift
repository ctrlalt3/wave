import SwiftUI

struct WaveDockView: View {
    let onClose: () -> Void
    @EnvironmentObject private var player: WavePlayer
    @EnvironmentObject private var progress: WavePlaybackProgress
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsLibrary = true
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.035).ignoresSafeArea()
                VStack(spacing: 8) {
                    header
                    if showsLibrary {
                        if geometry.size.width >= 600 {
                            HStack(spacing: 20) {
                                WaveDockLibraryView().frame(width: min(360, geometry.size.width * 0.43))
                                Divider().overlay(Color.white.opacity(0.15))
                                ScrollView { playerPane(size: geometry.size) }.frame(maxWidth: .infinity)
                            }
                        } else {
                            VStack(spacing: 12) {
                                WaveDockLibraryView().frame(maxHeight: max(220, geometry.size.height * 0.5))
                                ScrollView { playerPane(size: geometry.size) }
                            }
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 24) {
                                clock.font(.system(size: min(geometry.size.width * 0.12, 116), weight: .light, design: .rounded))
                                playerPane(size: geometry.size)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }.foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
        }.accessibilityIdentifier("wave.dock")
    }
    private var header: some View {
        HStack(spacing: 12) {
            clock.font(.title3.weight(.medium))
            Spacer(minLength: 0)
            Button { showsLibrary.toggle() } label: { Label(showsLibrary ? "Solo reproductor" : "Biblioteca", systemImage: showsLibrary ? "waveform" : "music.note.list").font(.subheadline).frame(minHeight: 44) }
                .accessibilityLabel(showsLibrary ? "Ocultar biblioteca" : "Mostrar biblioteca")
            Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle()) }
                .accessibilityLabel("Cerrar En reposo y volver a Wave")
        }
    }
    private var clock: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60), by: 60)) { timeline in
            Text(timeline.date, format: .dateTime.hour().minute()).monospacedDigit()
        }
    }
    @ViewBuilder private func playerPane(size: CGSize) -> some View {
        if let song = player.current {
            VStack(alignment: .leading, spacing: 12) {
                if !typeSize.isAccessibilitySize {
                    WaveArtwork(size: max(80, min(size.height * 0.34, size.width * 0.22, 240)), artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                        .clipShape(RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity)
                }
                Text(song.track.name).font(.title3.weight(.semibold)).lineLimit(3)
                Text(song.track.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                WaveformSeekBar(song: song, onArtwork: true)
                HStack(spacing: 12) { playbackButtons; LikeButton(song: song, compact: true) }
                if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "music.note").font(.largeTitle)
                Text("Elige una canción").font(.title3.weight(.medium))
                Text("Explora Local o Servidor en el panel de biblioteca. La música empezará aquí sin cerrar En reposo.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                if !showsLibrary { Button("Mostrar biblioteca") { showsLibrary = true }.frame(minHeight: 44) }
            }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var playbackButtons: some View {
        HStack(spacing: 12) {
            Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
            Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 56, height: 56).background(.white.opacity(0.15), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
        }.font(.title2)
    }
}
