import SwiftUI

struct WaveDockView: View {
    let onClose: () -> Void
    @EnvironmentObject private var player: WavePlayer
    @EnvironmentObject private var progress: WavePlaybackProgress
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            let side = max(88, min(geometry.size.height - 112, geometry.size.width * 0.23, 280))
            ZStack(alignment: .topTrailing) {
                Color(white: 0.035).ignoresSafeArea()
                ScrollView {
                    HStack(alignment: .center, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            TimelineView(.periodic(from: Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60), by: 60)) { timeline in
                                Text(timeline.date, format: .dateTime.hour().minute())
                                    .font(.system(size: min(geometry.size.width * 0.12, 116), weight: .light, design: .rounded))
                                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                Text(timeline.date, format: .dateTime.weekday(.wide).day().month(.wide))
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                            }
                            Label("WAVE", systemImage: "waveform").font(.caption.weight(.semibold)).tracking(3).padding(.top, 12).foregroundStyle(.white.opacity(0.5))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if let song = player.current {
                            if !typeSize.isAccessibilitySize {
                                WaveArtwork(size: side, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                                    .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                Text(song.track.name).font(.title3.weight(.semibold)).lineLimit(3)
                                Text(song.track.artist).font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                                ProgressView(value: min(progress.elapsed, max(progress.duration, 1)), total: max(progress.duration, 1)).tint(.white)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 12) { playbackButtons; LikeButton(song: song, compact: true) }
                                    VStack(alignment: .leading, spacing: 6) { playbackButtons; LikeButton(song: song, compact: true) }
                                }
                                if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: "music.note").font(.largeTitle)
                                Text("Tu música, en reposo.").font(.title3.weight(.medium))
                                Button("Elegir música", action: onClose).frame(minHeight: 44)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.horizontal, 28).padding(.top, 60).padding(.bottom, 20)
                        .frame(minHeight: geometry.size.height)
                }
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle()) }
                    .padding(12).accessibilityLabel("Cerrar En reposo y volver a Wave")
            }.foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
        }.accessibilityIdentifier("wave.dock")
    }
    private var playbackButtons: some View {
        HStack(spacing: 12) {
            Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
            Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 56, height: 56).background(.white.opacity(0.15), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
        }.font(.title2)
    }
}
