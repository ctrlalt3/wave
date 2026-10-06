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

// Expand with a brief override, then restore the native downward-scroll
// behavior. Leaving the override active prevents the next collapse.
struct WaveNativeTabScrollBehavior: ViewModifier {
    @EnvironmentObject private var chrome: WaveNavigationChrome
    @State private var forceExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(forceExpanded ? .never : .onScrollDown)
                .task(id: chrome.compact) {
                    if chrome.compact {
                        setExpanded(false)
                        return
                    }
                    setExpanded(true)
                    do { try await Task.sleep(nanoseconds: 240_000_000) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    setExpanded(false)
                }
        } else { content }
        #else
        content
        #endif
    }
    private func setExpanded(_ value: Bool) {
        guard forceExpanded != value else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { forceExpanded = value }
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
