import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct WaveApp: App {
    @StateObject private var player = WavePlayer()
    @StateObject private var local = LocalLibrary()
    @StateObject private var device = DeviceMusicLibrary()
    @StateObject private var preferences = LibraryPreferences()
    var body: some Scene {
        WindowGroup {
            WaveHome().environmentObject(player).environmentObject(local).environmentObject(device).environmentObject(preferences)
                .tint(WaveTheme.accent).foregroundStyle(WaveTheme.ink).preferredColorScheme(.light)
        }
    }
}

enum WaveSection: String, CaseIterable, Identifiable {
    case server, local, playlists, spotify, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .server: return "Servidor"; case .local: return UIDevice.current.userInterfaceIdiom == .pad ? "Mi iPad" : "Mi iPhone"; case .playlists: return "Playlists"; case .spotify: return "Spotify"; case .settings: return "Ajustes" }
    }
    var icon: String {
        switch self { case .server: return "icloud"; case .local: return "music.note"; case .playlists: return "music.note.list"; case .spotify: return "magnifyingglass"; case .settings: return "gearshape" }
    }
}

struct WaveHome: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: WaveSection = .server
    @State private var expanded = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var player: WavePlayer
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView(columnVisibility: $columns) {
                    VStack(alignment: .leading, spacing: 24) {
                        Label { Text("WAVE").tracking(3) } icon: { Image(systemName: "waveform") }
                            .font(.title2.weight(.semibold)).padding(18)
                        Text("BIBLIOTECAS").font(.caption2.monospaced()).tracking(2)
                            .foregroundStyle(WaveTheme.secondary).padding(.horizontal, 18)
                        ForEach(WaveSection.allCases) { item in
                            Button { select(item) } label: {
                                Label(item.title, systemImage: item.icon)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(section == item ? WaveTheme.selected : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).padding(.horizontal, 12)
                        }
                        Spacer()
                        Text("WAVE PARA IOS · 0.5").font(.caption2.monospaced())
                            .foregroundStyle(WaveTheme.secondary).padding(24)
                    }.background(WaveTheme.sidebar)
                } detail: {
                    playerPage(section).id(section)
                }
            } else {
                compactTabs
            }
        }.safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(WaveTheme.accent)
                Text("WAVE").font(.headline).tracking(3)
                Spacer()
                Text("0.5").font(.caption.monospacedDigit()).foregroundStyle(WaveTheme.secondary).accessibilityIdentifier("wave.build-version")
            }.padding(.horizontal, 22).padding(.vertical, 12).background(WaveTheme.sidebar)
        }
            .task {
                await preferences.load()
                await local.load()
                if local.ready { await preferences.prepareLocalPlaylists(local.songs, replacements: local.duplicateReplacements) }
            }
            .alert("No se pudo guardar el cambio", isPresented: Binding(get: { preferences.error != nil }, set: { if !$0 { preferences.error = nil } })) {
                Button("Aceptar") { preferences.error = nil }
            } message: { Text(preferences.error ?? "") }
    }
    @ViewBuilder private var compactTabs: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabs(nativeAccessory: true)
                .tabBarMinimizeBehavior(.onScrollDown)
                .modifier(LiquidAccessoryModifier(expanded: $expanded))
        } else { tabs(nativeAccessory: false) }
        #else
        tabs(nativeAccessory: false)
        #endif
    }
    private func tabs(nativeAccessory: Bool) -> some View {
        TabView(selection: Binding(get: { section }, set: { select($0) })) {
            ForEach(WaveSection.allCases) { item in
                playerPage(item, nativeAccessory: nativeAccessory)
                    .tabItem { Label(item.title, systemImage: item.icon) }
                    .tag(item)
            }
        }
    }

    private func select(_ item: WaveSection) {
        if section != item { expanded = false }
        section = item
    }

    // The player belongs to the tab's content area, so the native tab bar
    // keeps its own safe area and remains outside both player presentations.
    private func playerPage(_ item: WaveSection, nativeAccessory: Bool = false) -> some View {
        ZStack {
            content(item)
                .allowsHitTesting(!(expanded && section == item))
                .accessibilityHidden(expanded && section == item)
            if expanded && section == item {
                ExpandedPlayer(onClose: { expanded = false })
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !expanded && !nativeAccessory { PlayerBar(expanded: $expanded) }
        }
        .toolbar(.visible, for: .tabBar)
    }

    @ViewBuilder private func content(_ item: WaveSection) -> some View {
        NavigationStack {
            switch item {
            case .server: ServerLibraryView()
            case .local: LocalLibraryView()
            case .playlists: PlaylistLibraryView()
            case .spotify: SpotifyView()
            case .settings: WaveSettingsView()
            }
        }
    }
}

struct ServerLibraryView: View {
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
    @State private var folders: [WaveFolder] = []
    @State private var api: WaveAPI?
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("BIBLIOTECA DEL SERVIDOR").font(.caption2.monospaced()).tracking(2).foregroundStyle(WaveTheme.secondary)
                Text("Tu música, desde el servidor Wave.").font(.subheadline).foregroundStyle(WaveTheme.secondary)
                if loading { ProgressView("Conectando con Wave…").frame(maxWidth: .infinity).padding(.vertical, 24) }
                if let error {
                    Text(error).foregroundStyle(.red)
                    Button("Volver a conectar") { Task { await load() } }
                }
                if !loading && error == nil && folders.isEmpty {
                    WaveMessage(title: "Tu colección, en su sitio.", detail: "Las carpetas del servidor aparecerán aquí.")
                }
                if let api {
                    DiscoverSection(api: api, serverFolders: folders)
                    NavigationLink {
                        ServerFolderView(folder: WaveFolder(name: "Todas las canciones", count: total), api: api, allTracks: true)
                    } label: {
                        HStack {
                            Label("Todas las canciones", systemImage: "music.note.list").font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(total)").font(.caption.monospacedDigit())
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(16).background(WaveTheme.selected, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                    HStack {
                        Text("Carpetas").font(.headline)
                        Spacer()
                        Text("\(folders.count) carpetas").font(.caption).foregroundStyle(WaveTheme.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(folders.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { folder in
                            NavigationLink { ServerFolderView(folder: folder, api: api) } label: {
                                HStack(spacing: 14) {
                                    if let cover = api.artworkURL(folder.coverUrl) { WaveArtwork(size: 46, remoteURL: cover) }
                                    else { Image(systemName: "folder").font(.title).foregroundStyle(WaveTheme.accent).frame(width: 46, height: 46) }
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(folder.name).font(.subheadline.weight(.medium)).foregroundStyle(WaveTheme.ink).lineLimit(2)
                                        Text("\(folder.count) canciones").font(.caption).foregroundStyle(WaveTheme.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }.frame(maxWidth: .infinity, minHeight: 70, alignment: .leading).padding(16)
                                    .background(WaveTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(WaveTheme.border, lineWidth: 1) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.padding(22).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
        }.contentMargins(.bottom, 32, for: .scrollContent).background(WaveTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: "Servidor Wave", search: $search, prompt: "Buscar carpetas") }.refreshable { await load() }.task(id: server) { await load() }
            .toolbar { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading).accessibilityLabel("Actualizar biblioteca") }
    }
    private var total: Int { folders.reduce(0) { $0 + $1.count } }
    @MainActor private func load() async {
        let requestedServer = server
        loading = true; error = nil; folders = []; api = nil
        defer { if requestedServer == server { loading = false } }
        do {
            let connection = try WaveAPI(server: requestedServer)
            let result = try await connection.folders()
            try Task.checkCancellation()
            guard requestedServer == server else { return }
            api = connection; folders = result
        } catch is CancellationError { }
        catch { if requestedServer == server { self.error = error.localizedDescription } }
    }
}

struct ServerFolderView: View {
    let folder: WaveFolder
    let api: WaveAPI
    var allTracks = false
    var favoritesOnly = false
    @EnvironmentObject private var preferences: LibraryPreferences
    @State private var tracks: [WaveTrack] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var sort: TrackSort = .manual
    @State private var advanced = false
    @State private var hidden = Set<String>()
    @State private var saving = false
    @EnvironmentObject private var player: WavePlayer
    private var visible: [WaveTrack] { sort.sorted(tracks.filter { (advanced || !hidden.contains($0.id)) && (!favoritesOnly || preferences.liked(api.base.absoluteString + $0.id)) && (search.isEmpty || ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search)) }) }
    var body: some View {
        List {
            TrackTools(sort: $sort, advanced: $advanced).listRowBackground(Color.clear)
            if let first = visible.first(where: { !hidden.contains($0.id) }) {
                Button { player.play(first, queue: visible.filter { !hidden.contains($0.id) }, api: api) } label: {
                    Label("Reproducir playlist", systemImage: "play.fill")
                }.listRowBackground(WaveTheme.selected)
            }
            if loading { ProgressView("Cargando canciones…").listRowBackground(Color.clear) }
            if let error { Text(error).foregroundStyle(.red).listRowBackground(Color.clear) }
            if !loading && error == nil && visible.isEmpty { WaveMessage(title: "No hay canciones visibles.", detail: "Prueba otra búsqueda o carpeta.").listRowBackground(Color.clear) }
            Section("\(visible.count) canciones") {
                ForEach(visible) { track in
                    HStack(spacing: 0) {
                        Button { player.play(track, queue: visible.filter { !hidden.contains($0.id) || $0.id == track.id }, api: api) } label: {
                            TrackRow(track: track, active: player.current?.id == api.base.absoluteString + track.id, advanced: advanced, remoteCover: api.artworkURL(for: track))
                                .opacity(hidden.contains(track.id) ? 0.5 : 1)
                        }.buttonStyle(.plain)
                        if let song = try? PlaybackSong.server(track, api: api) { LikeButton(song: song) }
                    }.listRowBackground(player.current?.id == api.base.absoluteString + track.id ? WaveTheme.selected : WaveTheme.surface)
                        .swipeActions {
                            Button(hidden.contains(track.id) ? "Mostrar" : "Ocultar") { Task { await setHidden(track) } }.tint(WaveTheme.accent).disabled(saving)
                        }.moveDisabled(sort != .manual || !search.isEmpty || saving || favoritesOnly)
                }
                .onMove { offsets, destination in
                    var reordered = visible
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    let visibleIDs = Set(reordered.map(\.id))
                    let paths = reordered.map(\.id) + tracks.filter { !visibleIDs.contains($0.id) }.map(\.id)
                    Task { await saveOrder(paths) }
                }
            }
        }.listStyle(.plain).listSectionSpacing(20).scrollContentBackground(.hidden).contentMargins(.bottom, 32, for: .scrollContent).background(WaveTheme.background).navigationTitle(folder.name).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: folder.name, search: $search, prompt: "Canción o artista") }
            .task { await load(); await preferences.load(); await preferences.synchronizeServer(api) }
            .refreshable { await load(); await preferences.synchronizeServer(api) }
            .toolbar {
                if !allTracks {
                    Button { Task { await preferences.addFolder(folder.name, source: .server, server: api.base.absoluteString) } } label: { Image(systemName: "text.badge.plus") }
                        .accessibilityLabel("Añadir carpeta como playlist").disabled(!preferences.ready || preferences.saving)
                }
                EditButton().disabled(sort != .manual || !search.isEmpty || saving || favoritesOnly)
            }
    }
    @MainActor private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let contents: ServerContents
            if allTracks { contents = try await api.allContents() }
            else { contents = try await api.contents(folder: folder.name) }
            tracks = contents.tracks
            hidden = Set(contents.state.hidden)
        }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func setHidden(_ track: WaveTrack) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do { hidden = Set(try await api.setHidden(track.id, hidden: !hidden.contains(track.id)).hidden) }
        catch { self.error = error.localizedDescription }
    }
    @MainActor private func saveOrder(_ paths: [String]) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await api.saveOrder(scope: allTracks ? "*" : folder.name, paths: paths)
            let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            tracks = paths.compactMap { byID[$0] }
        } catch { self.error = error.localizedDescription }
    }
}

struct LocalLibraryView: View {
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var device: DeviceMusicLibrary
    @State private var importer = false
    @State private var importingFolder = false
    @AppStorage("wave.local.addExpanded") private var addExpanded = true
    @State private var search = ""
    @State private var descending = false
    @State private var likedOnly = false
    private var folders: [String] {
        preferences.state.playlists.filter { $0.source == .local }.map(\.folder)
    }
    private var visibleFolders: [String] {
        folders.filter { folder in
            (search.isEmpty || folder.localizedCaseInsensitiveContains(search)) &&
            (!likedOnly || local.songs.contains {
                ($0.folder == folder || $0.folder.hasPrefix(folder + "/")) && !$0.hidden && preferences.liked("local:" + $0.id)
            })
        }.sorted { descending ? $0.localizedStandardCompare($1) == .orderedDescending : $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DisclosureGroup(isExpanded: $addExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tus archivos, guardados para escucharlos sin conexión.").font(.subheadline).foregroundStyle(WaveTheme.secondary)
                        Button { importingFolder = false; importer = true } label: { Label("Importar canciones", systemImage: "plus") }
                            .disabled(local.importing || !local.ready)
                        Button { importingFolder = true; importer = true } label: { Label("Añadir carpeta", systemImage: "folder.badge.plus") }
                            .disabled(local.importing || !local.ready || !preferences.ready || preferences.saving)
                        Text("Las carpetas de dentro se añaden como playlists. Si la carpeta solo contiene canciones, se añade ella misma.").font(.caption).foregroundStyle(WaveTheme.secondary)
                    }.padding(.top, 16).padding(.bottom, 8)
                } label: { Text("Añadir").font(.headline) }
                if local.importing { ProgressView("Importando música…") }
                if let notice = local.notice { Text(notice).font(.caption).foregroundStyle(WaveTheme.secondary).textSelection(.enabled) }
                if local.songs.isEmpty && !local.importing {
                    WaveMessage(title: "Tu colección, en su sitio.", detail: "Importa canciones o una carpeta desde Archivos, iCloud Drive o un almacenamiento conectado.")
                }
                DiscoverSection()
                NavigationLink { LocalTracksView() } label: {
                    HStack {
                        Label("Todas las canciones", systemImage: "music.note.list").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(local.songs.filter { !$0.hidden }.count)").font(.caption.monospacedDigit())
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(16).background(WaveTheme.selected, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
                HStack {
                    Text("Mis playlist").font(.headline)
                    Spacer()
                    Text("\(visibleFolders.count) carpetas").font(.caption).foregroundStyle(WaveTheme.secondary)
                }
                HStack {
                    Menu {
                        Picker("Ordenar por", selection: $descending) {
                            Text("Nombre A–Z").tag(false)
                            Text("Nombre Z–A").tag(true)
                        }
                    } label: { Label("Ordenar por", systemImage: "arrow.up.arrow.down") }
                    Spacer()
                    Toggle("Con favoritos", isOn: $likedOnly).toggleStyle(.button)
                }.font(.subheadline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(visibleFolders, id: \.self) { folder in
                        VStack(alignment: .leading, spacing: 8) {
                            NavigationLink { LocalTracksView(folder: folder, playlistTitle: folder.split(separator: "/").last.map(String.init) ?? folder) } label: {
                                LocalPlaylistRow(folder: folder).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                            }.buttonStyle(.plain)
                            if let playlist = preferences.state.playlists.first(where: { $0.source == .local && $0.folder == folder }) {
                                DeletePlaylistButton(playlist: playlist)
                            }
                        }.padding(16)
                            .background(WaveTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).stroke(WaveTheme.border, lineWidth: 1) }
                    }
                }
                Text("Música de tu dispositivo").font(.headline).padding(.top, 8)
                NavigationLink { DeviceMusicLibraryView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note.list").font(.title2).foregroundStyle(WaveTheme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Biblioteca de Música").font(.headline)
                            Text(device.authorization == .authorized ? "\(device.songs.count) canciones · álbumes · playlists" : "Ver las canciones de la app Música").font(.caption).foregroundStyle(WaveTheme.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(16).background(WaveTheme.selected, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain)
            }.padding(22).frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
        }.contentMargins(.bottom, 32, for: .scrollContent).background(WaveTheme.background)
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: WaveSection.local.title, search: $search, prompt: "Buscar playlists") }
            .task { device.reload() }
            .fileImporter(isPresented: $importer, allowedContentTypes: importingFolder ? [.folder] : [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    let addPlaylists = importingFolder
                    Task {
                        let folders = await local.importFiles(urls)
                        if addPlaylists { for folder in folders { await preferences.addFolder(folder, source: .local) } }
                    }
                case .failure(let error): local.notice = error.localizedDescription
                }
            }
    }
}

struct LocalTracksView: View {
    var folder: String?
    var includeSubfolders = false
    var playlistTitle: String? = nil
    var favoritesOnly = false
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var player: WavePlayer
    @State private var search = ""
    @State private var sort: TrackSort = .manual
    @State private var advanced = false
    @State private var likedOnly = false
    private var children: [String] {
        guard let folder else { return [] }
        let candidates = local.songs.filter { (advanced || !$0.hidden) && (!(favoritesOnly || likedOnly) || preferences.liked("local:" + $0.id)) }
        let folders = LocalSong.childFolders(in: folder, songs: candidates).filter { child in
            search.isEmpty || child.localizedCaseInsensitiveContains(search) || candidates.contains {
                ($0.folder == child || $0.folder.hasPrefix(child + "/")) && ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search)
            }
        }
        return sort == .nameDescending ? Array(folders.reversed()) : folders
    }
    private var visible: [LocalSong] {
        let songs = local.songs.filter { song in
            let matchesFolder = folder.map { song.folder == $0 || (includeSubfolders && song.folder.hasPrefix($0 + "/")) } ?? true
            return matchesFolder && (advanced || !song.hidden) && (!(favoritesOnly || likedOnly) || preferences.liked("local:" + song.id)) && (search.isEmpty || (song.name + " " + song.artist).localizedCaseInsensitiveContains(search))
        }
        switch sort {
        case .manual: return songs
        case .name: return songs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .nameDescending: return songs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
        case .artist: return songs.sorted { ($0.artist + " " + $0.name).localizedStandardCompare($1.artist + " " + $1.name) == .orderedAscending }
        case .duration: return songs.sorted { $0.duration < $1.duration }
        }
    }
    var body: some View {
        List {
            TrackTools(sort: $sort, advanced: $advanced).listRowBackground(Color.clear)
            if !favoritesOnly {
                Toggle("Solo favoritas", isOn: $likedOnly).listRowBackground(Color.clear)
            }
            if let first = visible.first(where: { !$0.hidden }) {
                Button { player.play(local.playable(first), queue: visible.filter { !$0.hidden }.map { local.playable($0) }) } label: {
                    Label("Reproducir playlist", systemImage: "play.fill")
                }.listRowBackground(WaveTheme.selected)
            }
            if !children.isEmpty {
                Section("Carpetas") {
                    ForEach(children, id: \.self) { child in
                        NavigationLink {
                            LocalTracksView(folder: child, playlistTitle: child.split(separator: "/").last.map(String.init) ?? child)
                        } label: { LocalPlaylistRow(folder: child) }
                            .listRowBackground(WaveTheme.surface)
                    }
                }
            }
            if visible.isEmpty && children.isEmpty { WaveMessage(title: "No hay canciones visibles.", detail: "Importa música o usa la vista Avanzada para ver canciones ocultas.").listRowBackground(Color.clear) }
            Section("\(visible.count) canciones") {
                ForEach(visible) { song in
                    HStack(spacing: 0) {
                        Button {
                            player.play(local.playable(song), queue: visible.filter { !$0.hidden || $0.id == song.id }.map { local.playable($0) })
                        } label: { TrackRow(track: song.track, active: player.current?.id == "local:" + song.id, advanced: advanced, audioURL: local.playable(song).url).opacity(song.hidden ? 0.5 : 1) }
                            .buttonStyle(.plain)
                        LikeButton(song: local.playable(song))
                    }.listRowBackground(player.current?.id == "local:" + song.id ? WaveTheme.selected : WaveTheme.surface)
                        .swipeActions { Button(song.hidden ? "Mostrar" : "Ocultar") { Task { await local.setHidden(song.id, hidden: !song.hidden) } }.tint(WaveTheme.accent).disabled(local.importing) }
                        .moveDisabled(sort != .manual || !search.isEmpty || local.importing || favoritesOnly || likedOnly)
                }
                .onMove { offsets, destination in
                    var reordered = visible
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    Task { await local.reorder(reordered.map(\.id)) }
                }
            }
        }.listStyle(.plain).listSectionSpacing(20).scrollContentBackground(.hidden).contentMargins(.bottom, 32, for: .scrollContent).background(WaveTheme.background).navigationTitle(favoritesOnly ? "Me gusta" : playlistTitle ?? folder ?? "Todas las canciones").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: favoritesOnly ? "Me gusta" : playlistTitle ?? folder ?? "Todas las canciones", search: $search, prompt: "Carpeta, canción o artista") }
            .toolbar {
                if let folder {
                    if let playlist = preferences.state.playlists.first(where: { $0.source == .local && $0.folder == folder }) {
                        DeletePlaylistButton(playlist: playlist)
                    } else {
                        Button { Task { await preferences.addFolder(folder, source: .local) } } label: { Image(systemName: "text.badge.plus") }
                            .accessibilityLabel("Añadir carpeta como playlist").disabled(!preferences.ready || preferences.saving)
                    }
                }
                EditButton().disabled(sort != .manual || !search.isEmpty || local.importing || favoritesOnly || likedOnly)
            }
    }
}

struct WaveSettingsView: View {
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
    @State private var draft = ""
    @State private var notice: String?
    var body: some View {
        Form {
            Section("Servidor Wave") {
                TextField("URL HTTPS del servidor", text: $draft).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Guardar conexión") {
                    do { _ = try WaveAPI(server: draft); server = draft; notice = "Conexión guardada." }
                    catch { notice = error.localizedDescription }
                }
                if let notice { Text(notice).font(.caption) }
            }.listRowBackground(WaveTheme.surface)
            Section("Música local") {
                Text("En Mi iPhone o Mi iPad puedes abrir tu biblioteca de Música o importar archivos desde Archivos.")
                Text("Los originales permanecen en su ubicación. Las copias importadas ocupan espacio en este dispositivo.")
            }.font(.subheadline).foregroundStyle(WaveTheme.secondary).listRowBackground(WaveTheme.surface)
            Section("Wave para iOS · 0.4") {
                Text("Servidor, archivos locales y biblioteca de Música del dispositivo.")
                Text("Versión instalada: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.caption.monospacedDigit())
            }.font(.caption).listRowBackground(WaveTheme.surface)
        }.scrollContentBackground(.hidden).contentMargins(.bottom, 32, for: .scrollContent).background(WaveTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: "Ajustes") }.onAppear { draft = server }
    }
}
