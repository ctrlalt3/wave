import SwiftUI

struct PlaylistLibraryView: View {
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var device: DeviceMusicLibrary
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
    var body: some View {
        List {
            Section("Me gusta") {
                NavigationLink { LocalTracksView(favoritesOnly: true) } label: { Label("Archivos que te gustan", systemImage: "heart.fill") }.listRowBackground(WaveTheme.surface)
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
                if preferences.state.playlists.isEmpty {
                    WaveMessage(title: "Tus carpetas, tus playlists.", detail: "En Mi iPhone añade una carpeta como playlist. En el servidor, abre una carpeta y pulsa el botón de añadir playlist.").listRowBackground(Color.clear)
                }
                ForEach(preferences.state.playlists) { playlist in
                    destination(playlist).listRowBackground(WaveTheme.surface)
                        .swipeActions { Button("Quitar playlist", role: .destructive) { Task { await preferences.remove(playlist) } }.disabled(preferences.saving) }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(WaveTheme.background).navigationTitle("Playlists").task { device.reload() }
    }
    @ViewBuilder private func destination(_ playlist: FolderPlaylist) -> some View {
        if playlist.source == .local {
            NavigationLink { LocalTracksView(folder: playlist.folder, includeSubfolders: true, playlistTitle: playlist.title) } label: {
                FolderRow(name: playlist.title, count: local.songs.filter { ($0.folder == playlist.folder || $0.folder.hasPrefix(playlist.folder + "/")) && !$0.hidden }.count)
            }
        } else if let server = playlist.server, let api = try? WaveAPI(server: server) {
            NavigationLink { ServerFolderView(folder: WaveFolder(name: playlist.folder, count: 0), api: api) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Label(playlist.title, systemImage: "music.note.list")
                    Text("Servidor · \(playlist.folder)").font(.caption).foregroundStyle(WaveTheme.secondary)
                }.padding(.vertical, 8)
            }
        }
    }
}
