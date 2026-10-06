import SwiftUI
import Combine
import UIKit

@MainActor
final class WaveNavigationChrome: ObservableObject {
    @Published var compact = false
    var trackingEnabled = true
    private var travel: CGFloat = 0
    func scroll(delta: CGFloat) {
        guard trackingEnabled else { return }
        if (delta > 0 && travel < 0) || (delta < 0 && travel > 0) { travel = 0 }
        travel += delta
        if travel > 16 { if !compact { compact = true }; travel = 0 }
        else if travel < -16 { if compact { compact = false }; travel = 0 }
    }
    func expand() { compact = false; travel = 0 }
}


struct WaveScrollTracking: ViewModifier {
    @EnvironmentObject private var chrome: WaveNavigationChrome
    @State private var interacting = false
    @State private var previousDrag: CGFloat = 0
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                interacting = phase == .interacting || phase == .decelerating
            }.onScrollGeometryChange(for: CGFloat.self) { geometry in
                let maximum = max(0, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom)
                return min(maximum, max(0, geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { old, new in
                if interacting { chrome.scroll(delta: new - old) }
            }
        } else { legacy(content) }
        #else
        legacy(content)
        #endif
    }
    private func legacy(_ content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
            guard abs(value.translation.height) > abs(value.translation.width) else { return }
            chrome.scroll(delta: previousDrag - value.translation.height)
            previousDrag = value.translation.height
        }.onEnded { _ in previousDrag = 0 })
    }
}

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

struct WavePlayerTransitionSource: ViewModifier {
    var namespace: Namespace.ID?
    @AppStorage("wave.liquidGlass") private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *), enabled, !reduceMotion, let namespace {
            content.matchedTransitionSource(id: "expanded-player", in: namespace)
        } else { content }
        #else
        content
        #endif
    }
}

struct WavePlayerTransition: ViewModifier {
    let namespace: Namespace.ID
    @AppStorage("wave.liquidGlass") private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *), enabled, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: "expanded-player", in: namespace))
        } else { content }
        #else
        content
        #endif
    }
}

struct WaveBottomNavigation: View {
    @Binding var section: WaveSection
    @Binding var expanded: Bool
    let playerNamespace: Namespace.ID
    @EnvironmentObject private var chrome: WaveNavigationChrome
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) { panels }
            } else { panels }
            #else
            panels
            #endif
        }.buttonStyle(.plain).padding(.horizontal, 6).padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: chrome.compact)
    }
    private var panels: some View {
        VStack(spacing: 10) {
            if let song = player.current { mini(song) }
            HStack(spacing: 0) {
                ForEach(WaveSection.allCases) { item in
                    Button { section = item; chrome.expand() } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: section == item ? .semibold : .regular))
                            if !chrome.compact {
                                Text(item.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }.frame(maxWidth: .infinity, minHeight: chrome.compact ? 44 : 60)
                            .contentShape(Rectangle())
                            .foregroundStyle(section == item ? WaveTheme.accent : WaveTheme.secondary)
                            .background(section == item ? WaveTheme.selected : Color.clear, in: Capsule())
                    }.accessibilityLabel(item.title)
                        .accessibilityAddTraits(section == item ? .isSelected : [])
                }
            }.padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .modifier(WaveGlassPanel(radius: 30, capsule: true))
        }.frame(maxWidth: .infinity)
    }
    private func mini(_ song: PlaybackSong) -> some View {
        HStack(spacing: 4) {
            Button { expanded = true } label: {
                HStack(spacing: 10) {
                    WaveArtwork(size: 42, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.track.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(song.track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).contentShape(Rectangle())
            }.accessibilityLabel("Abrir reproductor: \(song.track.name)")
            LikeButton(song: song)
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 64).contentShape(Rectangle())
            }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 64).contentShape(Rectangle()) }
                .accessibilityLabel("Siguiente")
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .modifier(WaveGlassPanel(radius: 30, capsule: true))
            .modifier(WavePlayerTransitionSource(namespace: playerNamespace))
            .modifier(WaveSongMenu(song: song, queue: player.queue))
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
