import Combine
import MediaPlayer
import SwiftUI
import UIKit

struct DeviceSong: Identifiable {
    let item: MPMediaItem
    var id: String { String(item.persistentID) }
    var name: String { item.title ?? "Sin título" }
    var artist: String { item.artist ?? "Artista desconocido" }
    var album: String { item.albumTitle ?? "Sin álbum" }
    var track: WaveTrack {
        WaveTrack(name: name, artist: artist, duration: item.playbackDuration, relPath: id, filename: album)
    }
    var playable: PlaybackSong {
        PlaybackSong(track: track, url: item.assetURL, source: "device", identity: "device:" + id, mediaItem: item)
    }
}

struct DeviceCollection: Identifiable {
    let id: String
    let title: String
    let songs: [DeviceSong]
}

@MainActor
final class DeviceMusicLibrary: ObservableObject {
    @Published private(set) var authorization = MPMediaLibrary.authorizationStatus()
    @Published private(set) var songs: [DeviceSong] = []
    @Published private(set) var playlists: [DeviceCollection] = []
    @Published private(set) var loading = false
    @Published var notice: String?

    var albums: [DeviceCollection] {
        Dictionary(grouping: songs, by: { String($0.item.albumPersistentID) }).map { key, songs in
            DeviceCollection(id: key, title: songs.first?.album ?? "Sin álbum", songs: songs.sorted { $0.item.albumTrackNumber < $1.item.albumTrackNumber })
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var artists: [DeviceCollection] {
        Dictionary(grouping: songs, by: \.artist).map { key, songs in
            DeviceCollection(id: key, title: key, songs: songs)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func requestAccess() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        authorization = await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
        reload()
    }

    func reload() {
        authorization = MPMediaLibrary.authorizationStatus()
        guard authorization == .authorized else { songs = []; playlists = []; return }
        #if targetEnvironment(simulator)
        notice = "Prueba la biblioteca de Música en un iPhone o iPad real. El simulador no contiene la música de tu dispositivo."
        #else
        notice = nil
        songs = (MPMediaQuery.songs().items ?? []).map(DeviceSong.init).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        playlists = (MPMediaQuery.playlists().collections ?? []).compactMap { collection in
            guard let playlist = collection as? MPMediaPlaylist else { return nil }
            return DeviceCollection(id: String(playlist.persistentID), title: playlist.name ?? "Playlist", songs: playlist.items.map(DeviceSong.init))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        #endif
    }
}

struct DeviceMusicLibraryView: View {
    @EnvironmentObject private var library: DeviceMusicLibrary
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            if library.authorization == .authorized {
                Text("La biblioteca de la app Música de este dispositivo.").font(.subheadline).foregroundStyle(WaveTheme.secondary).listRowBackground(Color.clear)
                if let notice = library.notice { Text(notice).font(.caption).listRowBackground(Color.clear) }
                if library.songs.isEmpty {
                    WaveMessage(title: "Tu biblioteca de Música está vacía.", detail: "Las canciones sincronizadas desde tu Mac o añadidas a Música aparecerán aquí. Para archivos sueltos, usa Importar canciones en Mi iPhone.").listRowBackground(Color.clear)
                }
                NavigationLink { DeviceSongsView(title: "Todas las canciones", songs: library.songs) } label: {
                    FolderRow(name: "Todas las canciones", count: library.songs.count)
                }.listRowBackground(WaveTheme.surface)
                collections("Álbumes", library.albums)
                collections("Artistas", library.artists)
                collections("Playlists", library.playlists)
            } else {
                WaveMessage(title: "Tu música del iPhone, en Wave.", detail: "Permite el acceso para ver tus canciones, álbumes, artistas y playlists de la app Música.").listRowBackground(Color.clear)
                if library.authorization == .notDetermined {
                    Button("Permitir acceso a Música") { Task { await library.requestAccess() } }.disabled(library.loading).listRowBackground(WaveTheme.selected)
                } else if library.authorization == .denied {
                    Text("El acceso está desactivado. Puedes permitirlo en los ajustes de Wave.").font(.subheadline).listRowBackground(Color.clear)
                    Button("Abrir ajustes de Wave") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.listRowBackground(WaveTheme.selected)
                } else {
                    Text("Este dispositivo restringe el acceso a la biblioteca de Música.").listRowBackground(Color.clear)
                }
            }
        }.waveLibraryStyle()
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: "Música del dispositivo") }
            .task { library.reload() }.refreshable { library.reload() }
            .onChange(of: scenePhase) { _, value in if value == .active { library.reload() } }
    }
    private func collections(_ title: String, _ values: [DeviceCollection]) -> some View {
        Section {
            ForEach(values) { collection in
                NavigationLink { DeviceSongsView(title: collection.title, songs: collection.songs) } label: {
                    PlaylistRow(name: collection.title, count: collection.songs.count, artwork: collection.songs.first?.item.artwork)
                }.listRowBackground(WaveTheme.surface)
            }
        } header: { WaveSectionHeader(title: title) }
    }
}

struct DeviceSongsView: View {
    @EnvironmentObject private var preferences: LibraryPreferences
    let title: String
    let songs: [DeviceSong]
    var favoritesOnly = false
    @EnvironmentObject private var player: WavePlayer
    @State private var search = ""
    @State private var downloadedOnly = true
    @State private var sort: TrackSort = .manual
    @State private var likedOnly = false
    private var visible: [DeviceSong] {
        let filtered = songs.filter { (!downloadedOnly || !$0.item.isCloudItem) && (!(favoritesOnly || likedOnly) || preferences.liked($0.playable.id)) && (search.isEmpty || ($0.name + " " + $0.artist + " " + $0.album).localizedCaseInsensitiveContains(search)) }
        switch sort {
        case .manual: return filtered
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .artist: return filtered.sorted { ($0.artist + " " + $0.name).localizedStandardCompare($1.artist + " " + $1.name) == .orderedAscending }
        case .duration: return filtered.sorted { $0.track.duration < $1.track.duration }
        }
    }
    var body: some View {
        let visible = self.visible
        return List {
            TrackSortMenu(sort: $sort).listRowBackground(Color.clear)
            Toggle("Solo en el dispositivo", isOn: $downloadedOnly).font(.subheadline).listRowBackground(Color.clear)
            if !favoritesOnly {
                Toggle("Solo favoritas", isOn: $likedOnly).listRowBackground(Color.clear)
            }
            if let first = visible.first {
                Button { player.play(first.playable, queue: visible.map(\.playable)) } label: { Label("Reproducir playlist", systemImage: "play.fill") }.listRowBackground(WaveTheme.selected)
            }
            if visible.isEmpty { WaveMessage(title: "No hay canciones en esta vista.", detail: "Desactiva el filtro para ver también las canciones de iCloud o prueba otra búsqueda.").listRowBackground(Color.clear) }
            Section("\(visible.count) canciones") {
                ForEach(visible) { song in
                    HStack(spacing: 0) {
                    Button { player.play(song.playable, queue: visible.map(\.playable)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            TrackRow(track: song.track, active: player.current?.id == song.playable.id, artwork: song.item.artwork)
                            if song.item.isCloudItem { Label("En iCloud", systemImage: "icloud").font(.caption2).foregroundStyle(WaveTheme.secondary).padding(.leading, 52) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).buttonStyle(.plain)
                    LikeButton(song: song.playable)
                    }.modifier(WaveSongMenu(song: song.playable, playQueue: { visible.map(\.playable) }))
                        .listRowInsets(EdgeInsets()).listRowBackground(player.current?.id == song.playable.id ? WaveTheme.selected : WaveTheme.surface)
                }
            }
        }.waveLibraryStyle()
            .navigationTitle("").navigationBarTitleDisplayMode(.inline).safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: title, search: $search, prompt: "Canción, artista o álbum") }
    }
}
