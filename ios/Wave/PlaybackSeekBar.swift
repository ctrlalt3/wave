import SwiftUI

enum WaveSeekPosition {
    static func duration(_ actual: Double, fallback: Double) -> Double {
        max(actual.isFinite ? max(0, actual) : 0, fallback.isFinite ? max(0, fallback) : 0)
    }
    static func clamp(_ position: Double, duration: Double) -> Double {
        guard position.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, position), duration)
    }
}
struct WavePlaybackSeekBar: View {
    let song: PlaybackSong
    var onArtwork = false
    @EnvironmentObject private var player: WavePlayer
    @EnvironmentObject private var progress: WavePlaybackProgress
    @State private var seeking = false
    @State private var draft = 0.0
    private var duration: Double { WaveSeekPosition.duration(progress.duration, fallback: song.track.duration) }
    private var position: Double { WaveSeekPosition.clamp(seeking ? draft : progress.elapsed, duration: duration) }
    var body: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { position }, set: { draft = $0 }), in: 0...max(1, duration), onEditingChanged: { editing in
                if editing { draft = WaveSeekPosition.clamp(progress.elapsed, duration: duration); seeking = true }
                else {
                    if player.current?.id == song.id { player.seek(WaveSeekPosition.clamp(draft, duration: duration)) }
                    seeking = false
                }
            }).tint(onArtwork ? Color.white : WaveTheme.accent).frame(minHeight: 44).disabled(duration <= 0)
                .accessibilityLabel("Posición de reproducción")
                .accessibilityValue(WaveTheme.time(position) + " de " + WaveTheme.time(duration))
                .accessibilityAdjustableAction { direction in
                    guard player.current?.id == song.id else { return }
                    draft = WaveSeekPosition.clamp(progress.elapsed + (direction == .increment ? 10 : -10), duration: duration)
                    player.seek(draft)
                }
            HStack { Text(WaveTheme.time(position)); Spacer(); Text(WaveTheme.time(duration)) }
                .font(.caption.monospacedDigit()).foregroundStyle(onArtwork ? Color.white.opacity(0.7) : WaveTheme.secondary)
        }.onChange(of: song.id) { _, _ in seeking = false; draft = 0 }
    }
}
