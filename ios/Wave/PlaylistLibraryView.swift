import SwiftUI

struct PlaylistLibraryView: View {
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var device: DeviceMusicLibrary
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
    private var visiblePlaylists: [FolderPlaylist] { preferences.state.visiblePlaylists }
    var body: some View {
        List {
            Section("Me gusta") {
                NavigationLink { LocalTracksView(favoritesOnly: true) } label: { Label("Archivos que te gustan", systemImage: "heart.fill").labelStyle(WaveHeartLabelStyle()) }.listRowBackground(WaveTheme.surface)
                if device.authorization == .authorized {
                    NavigationLink { DeviceSongsView(title: "Me gusta · Música", songs: device.songs, favoritesOnly: true) } label: { Label("Música del dispositivo", systemImage: "music.note") }.listRowBackground(WaveTheme.surface)
                } else {
                    NavigationLink { DeviceMusicLibraryView() } label: { Label("Permitir acceso a Música", systemImage: "music.note") }.listRowBackground(WaveTheme.surface)
                }
                if let api = try? WaveAPI(server: server) {
                    NavigationLink { ServerFolderView(folder: WaveFolder(name: "Me gusta · Servidor", count: 0), api: api, allTracks: true, favoritesOnly: true) } label: { Label("Servidor Wave", systemImage: "icloud") }.listRowBackground(WaveTheme.surface)
                }
            }
            Section("Carpetas como playlists") {
                if visiblePlaylists.isEmpty {
                    WaveMessage(title: "Tus carpetas, tus playlists.", detail: "En Mi iPhone añade una carpeta como playlist. En el servidor, abre una carpeta y pulsa el botón de añadir playlist.").listRowBackground(Color.clear)
                }
                ForEach(visiblePlaylists) { playlist in
                    destination(playlist).listRowBackground(WaveTheme.surface)
                        .swipeActions { Button("Quitar playlist", role: .destructive) { Task { await preferences.remove(playlist) } }.disabled(preferences.saving) }
                }
            }
        }.waveLibraryStyle().navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: "Playlists") }.task { device.reload() }
    }
    @ViewBuilder private func destination(_ playlist: FolderPlaylist) -> some View {
        if playlist.source == .local {
            NavigationLink { LocalTracksView(folder: playlist.folder, playlistTitle: playlist.title) } label: {
                LocalPlaylistRow(folder: playlist.folder)
            }
        } else if let server = playlist.server, let api = try? WaveAPI(server: server) {
            NavigationLink { ServerFolderView(folder: WaveFolder(name: playlist.folder, count: 0), api: api) } label: {
                PlaylistRow(name: playlist.title, subtitle: playlist.folder)
            }
        }
    }
}
