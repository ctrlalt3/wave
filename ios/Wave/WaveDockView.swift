import SwiftUI

struct WaveDockView: View {
    let onClose: () -> Void
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            let isHorizontal = geometry.size.width > geometry.size.height
            VStack(spacing: 4) {
                HStack {
                    Label("Biblioteca", systemImage: "music.note.list").font(.headline)
                    Spacer(minLength: 0)
                    Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Cerrar En reposo y volver a Wave")
                }
                if geometry.size.width > geometry.size.height || geometry.size.width >= 760 {
                    HStack(spacing: isHorizontal ? 8 : 16) {
                        WaveDockLibraryView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().overlay(Color.white.opacity(0.15))
                        ScrollView { playerPane }
                            .frame(width: max(176, min(280, geometry.size.width * 0.31)) + (isHorizontal ? 36 : 0))
                    }
                } else {
                    VStack(spacing: 12) {
                        WaveDockLibraryView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        playerPane
                    }
                }
            }.padding(.horizontal, isHorizontal ? 6 : 16).padding(.bottom, 8)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.background(Color(white: 0.035).ignoresSafeArea())
            .foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
            .accessibilityIdentifier("wave.dock")
    }
    @ViewBuilder private var playerPane: some View {
        if let song = player.current {
            VStack(spacing: 10) {
                if !typeSize.isAccessibilitySize {
                    WaveArtwork(size: 88, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                        .clipShape(RoundedRectangle(cornerRadius: 14)).frame(maxWidth: .infinity)
                }
                Text(song.track.name).font(.headline).lineLimit(3).multilineTextAlignment(.center)
                Text(song.track.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(2).multilineTextAlignment(.center)
                WavePlaybackSeekBar(song: song, onArtwork: true)
                HStack(spacing: 8) {
                    Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
                    Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 56, height: 56).background(Color.white.opacity(0.15), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                }.font(.title2).frame(maxWidth: .infinity, alignment: .center)
                LikeButton(song: song, compact: true).frame(maxWidth: .infinity, alignment: .center)
                if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.padding(.vertical, 8).frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "music.note").font(.largeTitle)
                Text("Elige una canción").font(.headline)
                Text("Navega por Local o Servidor sin cerrar esta pantalla.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }.multilineTextAlignment(.center).padding(.vertical, 24).frame(maxWidth: .infinity)
        }
    }
}
