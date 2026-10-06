import SwiftUI
import MediaPlayer

struct PlaylistRow: View {
    let name: String
    var count: Int? = nil
    var subtitle: String? = nil
    var artwork: MPMediaItemArtwork? = nil
    var remoteCover: URL? = nil
    var audioURL: URL? = nil
    var body: some View {
        HStack(spacing: 14) {
            WaveArtwork(size: 52, artwork: artwork, remoteURL: remoteCover, audioURL: audioURL)
            VStack(alignment: .leading, spacing: 6) {
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(WaveTheme.ink).lineLimit(2)
                if let count { Text("\(count) canciones").font(.caption).foregroundStyle(WaveTheme.secondary) }
                if let subtitle { Text(subtitle).font(.caption2).foregroundStyle(WaveTheme.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8)
    }
}
struct FolderRow: View {
    let name: String
    let count: Int
    var body: some View { PlaylistRow(name: name, count: count) }
}

struct TrackRow: View {
    let track: WaveTrack
    let active: Bool
    var advanced = false
    var artwork: MPMediaItemArtwork? = nil
    var remoteCover: URL? = nil
    var audioURL: URL? = nil
    var body: some View {
        HStack(spacing: 12) {
            WaveArtwork(artwork: artwork, remoteURL: remoteCover, audioURL: audioURL)
            VStack(alignment: .leading, spacing: 5) {
                Text(track.name).font(.subheadline.weight(.medium)).foregroundStyle(WaveTheme.ink).lineLimit(2)
                Text(track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                if advanced { Text(track.filename).font(.caption2.monospaced()).foregroundStyle(WaveTheme.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if active { Image(systemName: "speaker.wave.2").foregroundStyle(WaveTheme.accent) }
            Text(WaveTheme.time(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(WaveTheme.secondary)
        }.padding(.vertical, 5).padding(.leading, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
    }
}

enum TrackSort: String, CaseIterable {
    case manual = "Personalizado", name = "Nombre A–Z", nameDescending = "Nombre Z–A", artist = "Artista", duration = "Duración"
    func sorted(_ tracks: [WaveTrack]) -> [WaveTrack] {
        switch self {
        case .manual: return tracks
        case .name: return tracks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending: return tracks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .artist: return tracks.sorted { ($0.artist + " " + $0.name).localizedStandardCompare($1.artist + " " + $1.name) == .orderedAscending }
        case .duration: return tracks.sorted { $0.duration < $1.duration }
        }
    }
}

struct TrackSortMenu: View {
    @Binding var sort: TrackSort
    var body: some View {
        Menu {
            Picker("Ordenar por", selection: $sort) { ForEach(TrackSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption).padding(.horizontal, 12).padding(.vertical, 10).modifier(WaveGlassPanel(radius: 18)) }
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
    private var order: some View { TrackSortMenu(sort: $sort) }
    private var mode: some View {
        Picker("Vista", selection: $advanced) { Text("Normal").tag(false); Text("Avanzada").tag(true) }
            .pickerStyle(.segmented).frame(width: 180)
    }
}

// Kept outside the scrolling list so search remains available at every position.
struct LibrarySearchBar: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(WaveTheme.secondary)
            TextField(prompt, text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(WaveTheme.secondary).accessibilityLabel("Borrar búsqueda")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .modifier(WaveGlassPanel(radius: 16))
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
        .background(WaveTheme.background)
    }
}

struct LocalPlaylistRow: View {
    let folder: String
    @EnvironmentObject private var local: LocalLibrary
    private var summary: LocalFolderSummary? { local.folderSummaries[folder] }
    var body: some View {
        PlaylistRow(name: folder.split(separator: "/").last.map(String.init) ?? folder, count: summary?.count ?? 0,
                    subtitle: folder.contains("/") ? folder : nil, audioURL: summary.flatMap { local.playable($0.first).url })
    }
}

struct WavePageHeader: View {
    let title: String
    var search: Binding<String>? = nil
    var prompt = "Buscar"
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(WaveTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, search == nil ? 20 : 4)
                .accessibilityAddTraits(.isHeader)
            if let search { LibrarySearchBar(text: search, prompt: prompt) }
        }.background(WaveTheme.background)
    }
}

extension View {
    func waveLibraryStyle() -> some View {
        self.listStyle(.plain).listSectionSpacing(20).scrollContentBackground(.hidden)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 32, for: .scrollContent).background(WaveTheme.background)
            .modifier(WaveScrollTracking())
    }
}

struct WaveHeartLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon.foregroundStyle(.red)
            configuration.title
        }
    }
}

struct WaveSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(WaveTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).background(WaveTheme.background)
            .accessibilityAddTraits(.isHeader).textCase(nil)
    }
}
