import SwiftUI
import UIKit

struct WaveDockView: View {
    var protectedInsets = EdgeInsets()
    let onClose: () -> Void
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("wave.dock.dimWhenIdle") private var dimWhenIdle = true
    @State private var idle = WaveDockIdlePolicy()
    @State private var dimmed = false
    var body: some View {
        GeometryReader { geometry in
            let horizontal = geometry.size.width > geometry.size.height
            let safeWidth = max(0, geometry.size.width - protectedInsets.leading - protectedInsets.trailing)
            let recoveredWidth = max(0, geometry.size.width - safeWidth)
            let defaultPlayerWidth = max(212 + protectedInsets.trailing, max(176, min(280, safeWidth * 0.31)) + 54 + recoveredWidth * 0.5)
            let libraryIslandInset = protectedInsets.leading > protectedInsets.trailing ? protectedInsets.leading : 0
            let playerWidth = max(176 + protectedInsets.trailing, defaultPlayerWidth - libraryIslandInset)
            let height = max(0, geometry.size.height - protectedInsets.top - protectedInsets.bottom - 8)
            Group {
                if horizontal || geometry.size.width >= 760 {
                    HStack(spacing: 14) {
                        WaveDockLibraryView(safeLeadingInset: libraryIslandInset, onClose: onClose)
                            .padding(.leading, 10).padding(.top, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().overlay(Color.white.opacity(0.15))
                        playerPane(height: height, width: playerWidth - protectedInsets.trailing)
                            .padding(.trailing, protectedInsets.trailing)
                            .frame(width: playerWidth, height: height, alignment: .top)
                    }
                } else {
                    VStack(spacing: 12) {
                        WaveDockLibraryView(onClose: onClose).padding(.leading, 10).padding(.top, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        playerPane(height: min(height * 0.42, 300), width: geometry.size.width - 24)
                    }.padding(.horizontal, max(protectedInsets.leading, protectedInsets.trailing))
                }
            }.padding(.horizontal, 6).padding(.top, protectedInsets.top).padding(.bottom, max(6, protectedInsets.bottom))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.035).ignoresSafeArea())
            .foregroundStyle(.white).buttonStyle(.plain).environment(\.colorScheme, .dark)
            .background(WaveDockActivityObserver { wake() })
            .overlay {
                if dimmed {
                    Color.black.opacity(0.78).ignoresSafeArea().contentShape(Rectangle())
                        .onTapGesture { wake() }.accessibilityLabel("Pantalla atenuada. Toca para iluminar")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .task(id: dimWhenIdle && phase == .active) {
                guard dimWhenIdle && phase == .active else { dimmed = false; return }
                while !Task.isCancelled {
                    if idle.shouldDim(at: .now) && !dimmed && !UIAccessibility.isVoiceOverRunning {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { dimmed = true }
                    }
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .onChange(of: phase) { _, _ in wake() }
            .onChange(of: dimWhenIdle) { _, _ in wake() }
            .onAppear { wake() }
            .accessibilityIdentifier("wave.dock")
    }
    @ViewBuilder private func playerPane(height: CGFloat, width: CGFloat) -> some View {
        if let song = player.current {
            let artworkSize = max(64, min(240, width, height - 210))
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.track.name).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(song.track.artist).font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    WaveArtwork(size: artworkSize, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
                        .clipShape(RoundedRectangle(cornerRadius: 14)).frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
                WavePlaybackSeekBar(song: song, onArtwork: true)
                HStack(spacing: 8) {
                    Button { wake(); player.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
                    Button { wake(); player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 56, height: 56).background(Color.white.opacity(0.15), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                    Button { wake(); player.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                    LikeButton(song: song, compact: true)
                }.font(.title3).frame(maxWidth: .infinity, alignment: .center)
                if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(1) }
            }.padding(.vertical, 4).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "music.note").font(.largeTitle)
                Text("Elige una canción").font(.headline)
                Text("Navega por Local o Servidor sin cerrar esta pantalla.").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
    private func wake() {
        idle.interacted(at: .now)
        if dimmed { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { dimmed = false } }
    }
}
