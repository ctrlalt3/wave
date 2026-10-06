import SwiftUI

struct PlayerBar: View {
    @Environment(\.waveLayout) private var layout
    @Binding var expanded: Bool
    @EnvironmentObject private var player: WavePlayer
    var body: some View {
        if let song = player.current {
            VStack(spacing: layout.compactHeader ? 4 : 8) {
                if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack(spacing: 14) {
                    Button { expanded = true } label: {
                        HStack(spacing: 10) {
                            WaveArtwork(size: 34, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.track.name).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.tail).foregroundStyle(WaveTheme.ink)
                                Text(song.track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                            }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
                        }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
                    }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped().accessibilityLabel("Abrir reproductor: \(song.track.name)")
                    LikeButton(song: song, compact: layout.compactHeader)
                    Button { player.toggle() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44).background(WaveTheme.selected, in: Circle())
                    }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                }.buttonStyle(.plain)
                PlayerProgressBar()
            }.padding(.horizontal, 16).padding(.vertical, layout.compactHeader ? 6 : 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
                .overlay { RoundedRectangle(cornerRadius: 26).stroke(WaveTheme.border.opacity(0.4), lineWidth: 0.5) }
                .modifier(WaveSongMenu(song: song, queue: player.queue))
                .padding(.horizontal, 12).padding(.bottom, layout.compactHeader ? 4 : 8).padding(.top, layout.compactHeader ? 2 : 6)
        } else if let error = player.error { Text(error).font(.caption).foregroundStyle(.red).padding() }
    }
}

private struct PlayerProgressBar: View {
    @EnvironmentObject private var progress: WavePlaybackProgress
    var body: some View {
        ProgressView(value: min(progress.elapsed, max(progress.duration, 1)), total: max(progress.duration, 1))
            .tint(WaveTheme.accent)
    }
}

struct ExpandedPlayer: View {
    @EnvironmentObject private var player: WavePlayer
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.waveLayout) private var layout
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.18))) private var artworkDrag = CGSize.zero
    @State private var songDirection: CGFloat = 1
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.18))) private var backDrag: CGFloat = 0
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.18))) private var headerDrag: CGFloat = 0
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if let song = player.current, geometry.size.width > geometry.size.height, geometry.size.width >= 440 {
                    landscapePlayer(song, size: geometry.size)
                } else { portraitPlayer }
            }.navigationTitle("").toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Button(action: onClose) { Label("Volver", systemImage: "chevron.down").frame(minHeight: 44) }
                        Spacer()
                        Text("Reproduciendo").font(.headline)
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Cerrar reproductor")
                    }.padding(.horizontal, 16).padding(.top, layout.compactHeader ? 0 : 20).padding(.bottom, layout.compactHeader ? 0 : 12).background(WaveTheme.background).buttonStyle(.plain)
                        .contentShape(Rectangle()).simultaneousGesture(headerDismissGesture)
                }
        }
            .overlay(alignment: .leading) {
                // Reserve only the edge; artwork swipes and waveform seeking keep their gestures.
                Color.clear.frame(width: 24).contentShape(Rectangle())
                    .gesture(backGesture).accessibilityHidden(true)
            }
            .offset(x: reduceMotion ? 0 : backDrag, y: reduceMotion ? 0 : max(artworkDrag.height, headerDrag))
            .transaction { if reduceMotion { $0.animation = nil } }
    }
    private var portraitPlayer: some View {
        List {
                if let song = player.current {
                    GeometryReader { geometry in
                        WaveArtwork(size: geometry.size.width, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil, fillsSpace: true)
                            .frame(maxWidth: .infinity)
                            .id(song.id)
                            .transition(.asymmetric(insertion: .offset(x: songDirection * 24).combined(with: .opacity), removal: .offset(x: -songDirection * 24).combined(with: .opacity)))
                            .offset(x: reduceMotion ? 0 : artworkDrag.width)
                            .contentShape(Rectangle()).gesture(artworkGesture)
                    }.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: player.current?.id)
                        .frame(height: 340).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)).listRowSeparator(.hidden)
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(song.track.name).font(.title2.weight(.semibold))
                                Text(song.track.artist).foregroundStyle(WaveTheme.secondary)
                            }
                            Spacer()
                            LikeButton(song: song)
                        }
                        WavePlaybackSeekBar(song: song)
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
                            }.modifier(WaveSongMenu(song: queued, queue: player.queue))
                                .listRowInsets(EdgeInsets()).listRowBackground(player.current?.id == queued.id ? WaveTheme.selected : WaveTheme.surface)
                        }
                    }
                }
            }.waveLibraryStyle()
    }
    private func landscapePlayer(_ song: PlaybackSong, size: CGSize) -> some View {
        let artworkSize = max(100, min(size.width * 0.26, size.height - 24, 220))
        return HStack(spacing: 20) {
            VStack {
                Spacer(minLength: 0)
                WaveArtwork(size: artworkSize, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .offset(x: reduceMotion ? 0 : artworkDrag.width)
                    .contentShape(Rectangle()).gesture(artworkGesture)
                    .modifier(WaveSongMenu(song: song, queue: player.queue))
                Spacer(minLength: 0)
            }.frame(width: artworkSize)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.track.name).font(.title3.weight(.semibold)).lineLimit(3)
                            Text(song.track.artist).font(.subheadline).foregroundStyle(WaveTheme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        LikeButton(song: song, compact: true)
                    }
                    WavePlaybackSeekBar(song: song)
                    transport
                    if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("Cola de reproducción · \(player.queue.count)").font(.subheadline.weight(.semibold)).padding(.top, 8)
                    LazyVStack(spacing: 2) {
                        ForEach(player.queue) { queued in
                            HStack(spacing: 0) {
                                Button { player.play(queued, queue: player.queue) } label: {
                                    TrackRow(track: queued.track, active: player.current?.id == queued.id, artwork: queued.mediaItem?.artwork, remoteCover: queued.coverURL, audioURL: queued.source == "local" ? queued.url : nil)
                                }.buttonStyle(.plain)
                                LikeButton(song: queued, compact: true)
                            }.modifier(WaveSongMenu(song: queued, queue: player.queue))
                                .background(player.current?.id == queued.id ? WaveTheme.selected : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.padding(.vertical, 12)
            }.frame(maxWidth: .infinity)
        }.padding(.horizontal, 16).background(WaveTheme.background)
    }
    private var backGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($backDrag) { value, drag, transaction in
                if reduceMotion { transaction.animation = nil }
                guard value.translation.width > abs(value.translation.height) * 1.3 else { return }
                drag = min(80, max(0, value.translation.width * 0.4))
            }
            .onEnded { value in
                if value.translation.width >= 70,
                   value.translation.width > abs(value.translation.height) * 1.3 { onClose() }
            }
    }

    private var headerDismissGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($headerDrag) { value, drag, transaction in
                if reduceMotion { transaction.animation = nil }
                guard value.translation.height > abs(value.translation.width) * 1.3 else { return }
                drag = min(220, max(0, value.translation.height))
            }
            .onEnded { value in
                if value.translation.height > 100,
                   value.translation.height > abs(value.translation.width) * 1.3 { onClose() }
            }
    }

    private var artworkGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($artworkDrag) { value, drag, transaction in
                if reduceMotion { transaction.animation = nil }
                if abs(value.translation.width) > abs(value.translation.height) * 1.3 {
                    drag = CGSize(width: max(-60, min(60, value.translation.width * 0.4)), height: 0)
                } else if value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) * 1.3 {
                    drag = CGSize(width: 0, height: min(220, value.translation.height))
                }
            }
            .onEnded { value in
                if abs(value.translation.width) >= 60, abs(value.translation.width) > abs(value.translation.height) * 1.3 {
                    songDirection = value.translation.width < 0 ? 1 : -1
                    if value.translation.width < 0 { player.next() } else { player.previous() }
                } else if value.translation.height > 100, value.translation.height > abs(value.translation.width) * 1.3 {
                    onClose()
                }
            }
    }
    private var transport: some View {
        ViewThatFits(in: .horizontal) {
            transportRow(spacing: 16, playSize: 64)
            transportRow(spacing: 8, playSize: 56)
            VStack(spacing: 8) {
                HStack(spacing: 12) { previousButton; playButton(size: 56); nextButton }
                HStack(spacing: 16) { shuffleButton; repeatButton }
            }
        }.frame(maxWidth: .infinity, alignment: .center).font(.title3).buttonStyle(.plain)
    }
    private func transportRow(spacing: CGFloat, playSize: CGFloat) -> some View {
        HStack(spacing: spacing) { shuffleButton; previousButton; playButton(size: playSize); nextButton; repeatButton }
    }
    private var shuffleButton: some View {
        Button { player.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(player.shuffle ? WaveTheme.accent : WaveTheme.secondary).frame(width: 44, height: 44) }.accessibilityLabel("Aleatorio")
    }
    private var previousButton: some View {
        Button { player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
    }
    private func playButton(size: CGFloat) -> some View {
        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").foregroundStyle(.white).frame(width: size, height: size).background(WaveTheme.accent, in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
    }
    private var nextButton: some View {
        Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
    }
    private var repeatButton: some View {
        Button { player.repeatQueue.toggle() } label: { Image(systemName: "repeat").foregroundStyle(player.repeatQueue ? WaveTheme.accent : WaveTheme.secondary).frame(width: 44, height: 44) }.accessibilityLabel("Repetir cola")
    }

}


#if compiler(>=6.2)
@available(iOS 26.0, *)
struct LiquidAccessoryModifier: ViewModifier {
    @Binding var expanded: Bool
    var enabled = true
    @EnvironmentObject private var player: WavePlayer
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.3)
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: enabled && player.current != nil && !expanded) {
                LiquidPlayerAccessory(expanded: $expanded)
            }
        } else {
            content.tabViewBottomAccessory {
                if enabled && !expanded { LiquidPlayerAccessory(expanded: $expanded) }
            }
        }
        #else
        content.tabViewBottomAccessory {
            if enabled && !expanded { LiquidPlayerAccessory(expanded: $expanded) }
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
