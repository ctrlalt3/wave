import SwiftUI

struct WaveDockView: View {
    var protectedInsets = EdgeInsets()
    let onClose: () -> Void
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            let horizontal = geometry.size.width > geometry.size.height
            let safeWidth = max(0, geometry.size.width - protectedInsets.leading - protectedInsets.trailing)
            let recoveredWidth = max(0, geometry.size.width - safeWidth)
            let playerWidth = max(212 + protectedInsets.trailing, max(176, min(280, safeWidth * 0.31)) + 36 + recoveredWidth * 0.5)
            VStack(spacing: 4) {
                HStack {
                    Label("Biblioteca", systemImage: "music.note.list").font(.headline)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Cerrar En reposo y volver a Wave")
                }
                if horizontal || geometry.size.width >= 760 {
                    HStack(spacing: 8) {
                        WaveDockLibraryView(safeLeadingInset: protectedInsets.leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().overlay(Color.white.opacity(0.15))
                        playerPane
                            .padding(.trailing, protectedInsets.trailing)
                            .frame(width: playerWidth, height: max(0, geometry.size.height - protectedInsets.top - protectedInsets.bottom - 56), alignment: .center)
                    }
                } else {
                    VStack(spacing: 8) {
                        WaveDockLibraryView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        playerPane
                    }.padding(.horizontal, max(protectedInsets.leading, protectedInsets.trailing))
                }
            }.padding(.horizontal, 6).padding(.top, protectedInsets.top).padding(.bottom, max(6, protectedInsets.bottom))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.035).ignoresSafeArea())
            .foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
            .accessibilityIdentifier("wave.dock")
    }
    @ViewBuilder private var playerPane: some View {
        if let song = player.current {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    if !typeSize.isAccessibilitySize {
                        WaveArtwork(size: 64, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.track.name).font(.headline).lineLimit(2)
                        Text(song.track.artist).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                WavePlaybackSeekBar(song: song, onArtwork: true)
                HStack(spacing: 8) {
                    Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
                    Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 56, height: 56).background(Color.white.opacity(0.15), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                    LikeButton(song: song, compact: true)
                }.font(.title3).frame(maxWidth: .infinity, alignment: .center)
                if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            }.padding(.vertical, 4).frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "music.note").font(.largeTitle)
                Text("Elige una canción").font(.headline)
                Text("Navega por Local o Servidor sin cerrar esta pantalla.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }
}
