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
                            WaveArtwork(size: 34, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
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
            }.padding(.horizontal, 16).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                .overlay { RoundedRectangle(cornerRadius: 26).stroke(WaveTheme.border.opacity(0.4), lineWidth: 0.5) }
                .padding(.horizontal, 12).padding(.bottom, 8).padding(.top, 6)
        } else if let error = player.error { Text(error).font(.caption).foregroundStyle(.red).padding() }
    }
}

struct ExpandedPlayer: View {
    @EnvironmentObject private var player: WavePlayer
    let onClose: () -> Void
    var body: some View {
        NavigationStack {
            List {
                if let song = player.current {
                    GeometryReader { geometry in
                        WaveArtwork(size: geometry.size.width, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil, fillsSpace: true)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle()).gesture(artworkGesture)
                    }.frame(height: 340).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowSeparator(.hidden)
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(song.track.name).font(.title2.weight(.semibold))
                                Text(song.track.artist).foregroundStyle(WaveTheme.secondary)
                            }
                            Spacer()
                            LikeButton(song: song)
                        }
                        WaveformSeekBar(song: song)
                        transport
                        if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
                    }.padding(.vertical, 12).listRowBackground(WaveTheme.surface)
                    Section("Cola de reproducción · \(player.queue.count)") {
                        ForEach(player.queue) { queued in
                            HStack(spacing: 0) {
                                Button { player.play(queued, queue: player.queue) } label: {
                                    TrackRow(track: queued.track, active: player.current?.id == queued.id, artwork: queued.mediaItem?.artwork, remoteCover: queued.coverURL, audioURL: queued.source == "local" ? queued.url : nil)
                                }.buttonStyle(.plain)
                                LikeButton(song: queued)
                            }.listRowBackground(player.current?.id == queued.id ? WaveTheme.selected : WaveTheme.surface)
                        }
                    }
                }
            }.waveLibraryStyle().navigationTitle("").toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Button(action: onClose) { Label("Volver", systemImage: "chevron.down").frame(minHeight: 44) }
                        Spacer()
                        Text("Reproduciendo").font(.headline)
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Cerrar reproductor")
                    }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12).background(WaveTheme.background)
                }
        }
    }
    private var artworkGesture: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) {
                if value.translation.width < -60 { player.next() }
                else if value.translation.width > 60 { player.previous() }
            } else if value.translation.height > 80 { onClose() }
        }
    }
    private var transport: some View {
        HStack {
            Button { player.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.shuffle ? WaveTheme.accent : WaveTheme.secondary).frame(width: 44, height: 44) }.accessibilityLabel("Aleatorio")
            Spacer(minLength: 4)
            Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
            Spacer(minLength: 4)
            Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").foregroundStyle(.white).frame(width: 64, height: 64).background(WaveTheme.accent, in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            Spacer(minLength: 4)
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
            Spacer(minLength: 4)
            Button { player.repeatQueue.toggle() } label: { Image(systemName: "repeat").foregroundStyle(player.repeatQueue ? WaveTheme.accent : WaveTheme.secondary).frame(width: 44, height: 44) }.accessibilityLabel("Repetir cola")
        }.font(.title3).buttonStyle(.plain)
    }
}


#if compiler(>=6.2)
@available(iOS 26.0, *)
struct LiquidAccessoryModifier: ViewModifier {
    @Binding var expanded: Bool
    @EnvironmentObject private var player: WavePlayer
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.3)
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: player.current != nil && !expanded) {
                LiquidPlayerAccessory(expanded: $expanded)
            }
        } else {
            content.tabViewBottomAccessory {
                if !expanded { LiquidPlayerAccessory(expanded: $expanded) }
            }
        }
        #else
        content.tabViewBottomAccessory {
            if !expanded { LiquidPlayerAccessory(expanded: $expanded) }
        }
        #endif
    }
}

@available(iOS 26.0, *)
struct LiquidPlayerAccessory: View {
    @Binding var expanded: Bool
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @EnvironmentObject private var player: WavePlayer
    var body: some View {
        if let song = player.current {
            HStack(spacing: placement == .inline ? 8 : 12) {
                Button { expanded = true } label: {
                    HStack(spacing: 10) {
                        WaveArtwork(size: 32, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(song.track.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if placement != .inline { Text(song.track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.accessibilityLabel("Abrir reproductor: \(song.track.name)")
                if placement != .inline { LikeButton(song: song) }
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                if placement != .inline {
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                }
            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 4)
        }
    }
}
#endif
