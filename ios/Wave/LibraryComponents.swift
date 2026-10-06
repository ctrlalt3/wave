import SwiftUI
import MediaPlayer

struct FolderRow: View {
    let name: String
    let count: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder").font(.title2).foregroundStyle(WaveTheme.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.subheadline.weight(.medium))
                Text("\(count) canciones").font(.caption).foregroundStyle(WaveTheme.secondary)
            }
        }.padding(.vertical, 6)
    }
}

struct TrackRow: View {
    let track: WaveTrack
    let active: Bool
    var advanced = false
    var artwork: MPMediaItemArtwork? = nil
    var remoteCover: URL? = nil
    var body: some View {
        HStack(spacing: 12) {
            WaveArtwork(artwork: artwork, remoteURL: remoteCover)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.name).font(.subheadline.weight(.medium)).foregroundStyle(WaveTheme.ink).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                if advanced { Text(track.filename).font(.caption2.monospaced()).foregroundStyle(WaveTheme.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if active { Image(systemName: "speaker.wave.2").foregroundStyle(WaveTheme.accent) }
            Text(WaveTheme.time(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(WaveTheme.secondary)
        }.padding(.vertical, 5)
    }
}

enum TrackSort: String, CaseIterable {
    case manual = "Personalizado", name = "Nombre A–Z", duration = "Duración"
    func sorted(_ tracks: [WaveTrack]) -> [WaveTrack] {
        switch self {
        case .manual: return tracks
        case .name: return tracks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .duration: return tracks.sorted { $0.duration < $1.duration }
        }
    }
}

struct TrackTools: View {
    @Binding var sort: TrackSort
    @Binding var advanced: Bool
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { order; Spacer(); mode }
            VStack(alignment: .leading, spacing: 10) { order; mode }
        }.padding(.vertical, 4)
    }
    private var order: some View {
        Menu {
            Picker("Orden", selection: $sort) { ForEach(TrackSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption) }
    }
    private var mode: some View {
        Picker("Vista", selection: $advanced) { Text("Normal").tag(false); Text("Avanzada").tag(true) }
            .pickerStyle(.segmented).frame(width: 180)
    }
}
