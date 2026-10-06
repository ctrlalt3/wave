import SwiftUI
import Combine

@MainActor
final class WaveNavigationChrome: ObservableObject {
    @Published var compact = false
    private var travel: CGFloat = 0
    func scroll(delta: CGFloat) {
        if (delta > 0 && travel < 0) || (delta < 0 && travel > 0) { travel = 0 }
        travel += delta
        if travel > 16 { compact = true; travel = 0 }
        else if travel < -16 { compact = false; travel = 0 }
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
            content.onScrollPhaseChange { _, phase in interacting = phase == .interacting }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
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
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28)) }
        else { material(content) }
        #else
        material(content)
        #endif
    }
    private func material(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).stroke(WaveTheme.border.opacity(0.4), lineWidth: 0.5) }
    }
}

struct WaveBottomNavigation: View {
    @Binding var section: WaveSection
    @Binding var expanded: Bool
    @EnvironmentObject private var chrome: WaveNavigationChrome
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 8) {
            if chrome.compact {
                HStack(spacing: 8) {
                    Button { chrome.expand() } label: {
                        Image(systemName: section.icon).font(.title3).frame(width: 52, height: 52)
                    }.modifier(WaveGlassPanel()).accessibilityLabel("Mostrar navegación")
                    if let song = player.current { mini(song).modifier(WaveGlassPanel()) }
                    else { Spacer(minLength: 0) }
                }
            } else {
                if let song = player.current { mini(song).modifier(WaveGlassPanel()) }
                HStack(spacing: 0) {
                    ForEach(WaveSection.allCases) { item in
                        Button {
                            section = item; chrome.expand()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon).font(.system(size: 19, weight: section == item ? .semibold : .regular))
                                Text(item.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(section == item ? WaveTheme.accent : WaveTheme.secondary)
                        }.accessibilityAddTraits(section == item ? .isSelected : [])
                    }
                }.padding(.horizontal, 8).modifier(WaveGlassPanel())
            }
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chrome.compact)
    }
    private func mini(_ song: PlaybackSong) -> some View {
        HStack(spacing: 8) {
            Button { expanded = true } label: {
                HStack(spacing: 10) {
                    WaveArtwork(size: 34, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.track.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !chrome.compact { Text(song.track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.accessibilityLabel("Abrir reproductor: \(song.track.name)")
            if !chrome.compact { LikeButton(song: song) }
            Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
            if !chrome.compact { Button { player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente") }
        }.padding(.horizontal, 12).frame(minHeight: 52)
    }
}
