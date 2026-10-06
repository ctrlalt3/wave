import SwiftUI

struct PlayerBar: View {
    @Binding var expanded: Bool
    @EnvironmentObject private var player: WavePlayer
    var body: some View {
        if let song = player.current {
            VStack(spacing: 8) {
                if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 14) {
                    Button { expanded = true } label: {
                        HStack(spacing: 10) {
                            WaveArtwork(size: 34, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.track.name).font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(WaveTheme.ink)
                                Text(song.track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityLabel("Abrir reproductor: \(song.track.name)")
                    LikeButton(song: song)
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44).background(WaveTheme.selected, in: Circle())
                    }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                }.buttonStyle(.plain)
                ProgressView(value: min(player.elapsed, max(player.duration, 1)), total: max(player.duration, 1)).tint(WaveTheme.accent)
            }.padding(.horizontal, 18).padding(.vertical, 10).background(WaveTheme.surface)
                .overlay(alignment: .top) { Rectangle().fill(WaveTheme.border).frame(height: 1) }
        } else if let error = player.error { Text(error).font(.caption).foregroundStyle(.red).padding() }
    }
}

struct ExpandedPlayer: View {
    @EnvironmentObject private var player: WavePlayer
    let onClose: () -> Void
    @State private var position = 0.0
    @State private var seeking = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let song = player.current {
                        WaveArtwork(size: 156, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL).padding(.top, 24)
                        VStack(spacing: 8) {
                            Text(song.track.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                            Text(song.track.artist).foregroundStyle(WaveTheme.secondary)
                            Text(song.source == "device" ? "Música del dispositivo" : song.source == "local" ? "Archivos de Wave" : "Servidor Wave").font(.caption).foregroundStyle(WaveTheme.secondary)
                            LikeButton(song: song)
                        }
                        if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
                        VStack(spacing: 6) {
                            Slider(value: $position, in: 0...max(player.duration, 1), onEditingChanged: { editing in
                                seeking = editing
                                if !editing { player.seek(position) }
                            }).disabled(player.duration <= 0).accessibilityLabel("Posición de reproducción")
                            HStack { Text(WaveTheme.time(position)); Spacer(); Text(WaveTheme.time(player.duration)) }
                                .font(.caption.monospacedDigit()).foregroundStyle(WaveTheme.secondary)
                        }
                        transport
                        HStack { Text("Cola de reproducción").font(.headline); Spacer(); Text("\(player.queue.count)").font(.caption.monospacedDigit()) }.padding(.top, 16)
                        LazyVStack(spacing: 0) {
                            ForEach(player.queue) { queued in
                                HStack(spacing: 0) {
                                Button { player.play(queued, queue: player.queue) } label: {
                                    TrackRow(track: queued.track, active: player.current?.id == queued.id).padding(.vertical, 4)
                                }.buttonStyle(.plain)
                                LikeButton(song: queued)
                                }
                                Divider()
                            }
                        }
                    }
                }.padding(.horizontal, 24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.background(WaveTheme.background).navigationTitle("Reproduciendo").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Minimizar") { onClose() } }
                .onAppear { position = player.elapsed }
                .onChange(of: player.elapsed) { _, value in if !seeking { position = min(value, max(player.duration, 1)) } }
        }
    }
    private var transport: some View {
        HStack(spacing: 8) {
            Button { player.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.shuffle ? WaveTheme.accent : WaveTheme.secondary) }.accessibilityLabel("Aleatorio").accessibilityValue(player.shuffle ? "Activado" : "Desactivado")
            Button { player.previous() } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Anterior")
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill").foregroundStyle(.white).frame(width: 60, height: 60).background(WaveTheme.accent, in: Circle())
            }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            Button { player.next() } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Siguiente")
            Button { player.repeatQueue.toggle() } label: { Image(systemName: "repeat").foregroundStyle(player.repeatQueue ? WaveTheme.accent : WaveTheme.secondary) }.accessibilityLabel("Repetir cola").accessibilityValue(player.repeatQueue ? "Activado" : "Desactivado")
        }.font(.title3).buttonStyle(.plain).frame(minHeight: 60)
            .controlSize(.large)
    }
}
