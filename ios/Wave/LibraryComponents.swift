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
        }.padding(.vertical, 5)
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
            Picker("Ordenar por", selection: $sort) { ForEach(TrackSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.caption) }
    }
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
        .background(WaveTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
        .background(WaveTheme.background)
    }
}

struct LocalPlaylistRow: View {
    let folder: String
    @EnvironmentObject private var local: LocalLibrary
    private var songs: [LocalSong] {
        local.songs.filter { !$0.hidden && ($0.folder == folder || $0.folder.hasPrefix(folder + "/")) }
    }
    private var first: LocalSong? {
        // Prefer this folder, then the first nested folder; use its saved song order.
        let firstFolder = songs.map(\.folder).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first
        return songs.first { $0.folder == firstFolder }
    }
    var body: some View {
        HStack(spacing: 14) {
            WaveArtwork(size: 52, audioURL: first.flatMap { local.playable($0).url })
            VStack(alignment: .leading, spacing: 6) {
                Text(folder.split(separator: "/").last.map(String.init) ?? folder).font(.headline)
                Text("\(songs.count) canciones").font(.caption).foregroundStyle(WaveTheme.secondary)
                if folder.contains("/") {
                    Text(folder).font(.caption2).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                }
            }
        }.padding(.vertical, 8)
    }
}

struct DeletePlaylistButton: View {
    let playlist: FolderPlaylist
    @EnvironmentObject private var preferences: LibraryPreferences
    var body: some View {
        Button(role: .destructive) { Task { await preferences.remove(playlist) } } label: {
            Label("Eliminar playlist", systemImage: "trash").font(.caption)
                .frame(minHeight: 44)
        }.buttonStyle(.borderless).disabled(!preferences.ready || preferences.saving)
            .accessibilityLabel("Eliminar playlist \(playlist.title)")
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
