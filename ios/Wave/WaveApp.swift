import SwiftUI
import WidgetKit
import UniformTypeIdentifiers
import UIKit

@main
@MainActor
struct WaveApp: App {
    @AppStorage("wave.appearance") private var appearance = WaveAppearance.system.rawValue
    @AppStorage("wave.accent") private var accent = WaveAccent.system.rawValue
    @StateObject private var player = WavePlayer.shared
    @StateObject private var local = LocalLibrary()
    @StateObject private var device = DeviceMusicLibrary()
    @StateObject private var preferences = LibraryPreferences()
    init() {
        WaveServerSettings.prepareDefaults()
        Task { await WaveWidgetBootstrap.refresh() }
    }
    var body: some Scene {
        WindowGroup {
            WaveHome().environmentObject(player).environmentObject(player.progress).environmentObject(local).environmentObject(device).environmentObject(preferences)
                .tint((WaveAccent(rawValue: accent) ?? .system).color)
                .accentColor((WaveAccent(rawValue: accent) ?? .system).color)
                .preferredColorScheme((WaveAppearance(rawValue: appearance) ?? .system).scheme)
                .foregroundStyle(WaveTheme.ink)
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
    @AppStorage("wave.server") private var synchronizationServer = WaveServerSettings.defaultAddress
    @Environment(\.scenePhase) private var phase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: WaveSection = .server
    @State private var expanded = false
    @StateObject private var charging = WaveChargingMonitor()
    @AppStorage("wave.dock.automatic") private var automaticDock = true
    @State private var dockDismissed = false
    @State private var manualDock = false
    @State private var widgetCatalogTask: Task<Void, Never>?
    @State private var layout = WaveAdaptiveLayout.portrait
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var player: WavePlayer
    private var automaticDockActive: Bool { automaticDock && charging.isCharging && charging.isDeviceLandscape && layout.isLandscape }
    private var showsDock: Bool { manualDock || (automaticDockActive && !dockDismissed) }
    var body: some View {
        GeometryReader { geometry in
            let measured = WaveAdaptiveLayout(size: geometry.size)
            HStack(spacing: 0) {
                WaveSidebar(section: $section, expanded: $expanded, layout: measured) { manualDock = true }
                    .frame(width: measured.sidebarWidth).clipped()
                    .accessibilityHidden(!measured.usesSidebar)
                compactTabs.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WaveTheme.background)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(WaveTheme.background)
            .accessibilityHidden(showsDock)
            .environment(\.waveLayout, measured)
            .fullScreenCover(isPresented: Binding(get: { showsDock }, set: { presented in
                if !presented { manualDock = false; dockDismissed = true }
            })) {
                WaveDockView(protectedInsets: geometry.safeAreaInsets) { manualDock = false; dockDismissed = true }
                    .ignoresSafeArea(.container)
                    .statusBarHidden(true)
                    .environment(\.waveLayout, measured)
            }
            .onChange(of: measured, initial: true) { _, value in layout = value }
        }
        .background(WaveTheme.background.ignoresSafeArea())
        .task {
            player.connectFavorites(preferences)
            await preferences.load()
            await local.load()
            if local.ready { await preferences.prepareLocalPlaylists(local.songs, replacements: local.duplicateReplacements) }
            if WavePlaybackStorage.read() != nil { await player.restoreWidgetQueue() }
            player.publishWidgetLibrary(localCount: local.songs.count, favoritesCount: preferences.state.favorites.count, playlistsCount: preferences.state.visiblePlaylists.count)
            publishWidgetCatalog()
        }
        .task(id: synchronizationServer) {
            while !Task.isCancelled {
                await synchronizeFavorites()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await synchronizeFavorites() }; player.publishWidgetSnapshot(force: true) }
        }
        .onChange(of: automaticDockActive) { _, active in if !active { dockDismissed = false } }
        .onChange(of: layout.isLandscape) { _, landscape in if !landscape { manualDock = false } }
        .onReceive(local.$songs) { songs in player.publishWidgetLibrary(localCount: songs.count, favoritesCount: preferences.state.favorites.count, playlistsCount: preferences.state.visiblePlaylists.count); publishWidgetCatalog() }
        .onReceive(preferences.$state) { state in player.publishWidgetLibrary(localCount: local.songs.count, favoritesCount: state.favorites.count, playlistsCount: state.visiblePlaylists.count) }
        .onChange(of: synchronizationServer) { _, _ in publishWidgetCatalog() }
        .onChange(of: local.ready) { _, _ in publishWidgetCatalog() }
        .onOpenURL { url in handleWidgetURL(url) }
        .alert("No se pudo guardar el cambio", isPresented: Binding(get: { preferences.error != nil }, set: { if !$0 { preferences.error = nil } })) {
            Button("Aceptar") { preferences.error = nil }
        } message: { Text(preferences.error ?? "") }
    }
    private func publishWidgetCatalog() {
        guard local.ready else { return }
        let songs = local.songs.filter { !$0.hidden }.map { song in
            WaveWidgetBrowserItem(id: song.id, title: song.name, subtitle: song.artist, kind: .song, playbackID: local.playable(song).id, folderPath: song.folder)
        }
        let folders = LocalSong.playlistFolders(for: local.songs)
        let server = synchronizationServer
        widgetCatalogTask?.cancel()
        widgetCatalogTask = Task {
            do {
                try await WaveWidgetBrowserService.shared.configureServer(server)
                try await WaveWidgetBrowserService.shared.publishLocal(songs, folders: folders)
                WidgetCenter.shared.reloadAllTimelines()
            } catch is CancellationError { }
            catch { local.notice = "No se pudo actualizar la biblioteca del widget: " + error.localizedDescription }
        }
    }
    private func handleWidgetURL(_ url: URL) {
        guard let destination = WaveWidgetDestination(url: url) else { return }
        switch destination {
        case .player: Task { await player.restoreWidgetQueue(); expanded = true }
        case .playlists: select(.playlists)
        case .local: select(.local)
        case .server: select(.server)
        case .dock: manualDock = true
        }
    }
    @ViewBuilder private var compactTabs: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabs(nativeAccessory: true)
                .tabBarMinimizeBehavior(.onScrollDown)
                .modifier(LiquidAccessoryModifier(expanded: $expanded, enabled: !layout.usesSidebar))
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
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(WaveTheme.background)
            .background(WaveTabReselectionObserver { expanded = false })
    }

    private func synchronizeFavorites() async {
        guard let api = try? WaveAPI(server: synchronizationServer), preferences.ready else { return }
        await preferences.synchronizeServer(api)
    }

    private func select(_ item: WaveSection) {
        expanded = false
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
            if !expanded && (!nativeAccessory || layout.usesSidebar) { PlayerBar(expanded: $expanded) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(WaveTheme.background)
        .toolbar(layout.usesSidebar ? .hidden : .visible, for: .tabBar)
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
    @EnvironmentObject private var preferences: LibraryPreferences
    @AppStorage("wave.server") private var server = WaveServerSettings.defaultAddress
    @State private var folders: [WaveFolder] = []
    @State private var api: WaveAPI?
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    var body: some View {
        List {
            if loading { ProgressView("Conectando con Wave…").listRowBackground(Color.clear) }
            if let error {
                Text(error).foregroundStyle(.red).listRowBackground(Color.clear)
                Button("Volver a conectar") { Task { await load() } }
            }
            if !loading && error == nil && folders.isEmpty {
                WaveMessage(title: "Tu colección, en su sitio.", detail: "Las carpetas del servidor aparecerán aquí.").listRowBackground(Color.clear)
            }
            if let api {
                DiscoverSection(api: api, serverFolders: folders).listRowBackground(Color.clear)
                NavigationLink {
                    ServerFolderView(folder: WaveFolder(name: "Todas las canciones", count: total), api: api, allTracks: true)
                } label: { FolderRow(name: "Todas las canciones", count: total) }.listRowBackground(WaveTheme.selected)
                Section {
                    ForEach(folders.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { folder in
                        NavigationLink { ServerFolderView(folder: folder, api: api) } label: {
                            PlaylistRow(name: folder.name, count: folder.count, remoteCover: api.artworkURL(folder.coverUrl))
                        }.listRowBackground(WaveTheme.surface)
                            .swipeActions {
                                if let playlist = preferences.state.playlists.first(where: { $0.source == .server && $0.folder == folder.name && $0.server == api.base.absoluteString }) {
                                    Button("Quitar playlist", role: .destructive) { Task { await preferences.remove(playlist) } }.disabled(preferences.saving)
                                }
                            }
                    }
                } header: { WaveSectionHeader(title: "Playlists · \(folders.count)") }
            }
        }.waveLibraryStyle()
            .wavePage(title: "Servidor Wave", search: $search, prompt: "Buscar carpetas")
            .refreshable { await load() }.task(id: server) { await load() }
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
        let visible = self.visible
        return List {
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
                    }.modifier(WaveServerSongMenu(track: track, tracks: visible, api: api))
                        .listRowInsets(EdgeInsets()).listRowBackground(player.current?.id == api.base.absoluteString + track.id ? WaveTheme.selected : WaveTheme.surface)
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
        }.waveLibraryStyle()
            .wavePage(title: folder.name, search: $search, prompt: "Canción o artista")
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
        LocalSong.childFolders(in: nil, songs: local.songs)
    }
    private var visibleFolders: [String] {
        folders.filter { folder in
            (search.isEmpty || folder.localizedCaseInsensitiveContains(search)) &&
            (!likedOnly || local.songs(in: folder, recursive: true).contains { local.liked($0, in: preferences) })
        }.sorted { descending ? $0.localizedStandardCompare($1) == .orderedDescending : $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var body: some View {
        List {
            DisclosureGroup(isExpanded: $addExpanded) {
                Text("Tus archivos, guardados para escucharlos sin conexión.").font(.subheadline).foregroundStyle(WaveTheme.secondary)
                Button { importingFolder = false; importer = true } label: { Label("Importar canciones", systemImage: "plus") }.disabled(local.importing || !local.ready)
                Button { importingFolder = true; importer = true } label: { Label("Añadir carpeta", systemImage: "folder.badge.plus") }.disabled(local.importing || !local.ready || !preferences.ready || preferences.saving)
                Text("Las carpetas de dentro se añaden como playlists.").font(.caption).foregroundStyle(WaveTheme.secondary)
            } label: { Text("Añadir").font(.headline) }.listRowBackground(WaveTheme.surface)
            if local.importing { ProgressView("Importando música…").listRowBackground(Color.clear) }
            if let notice = local.notice { Text(notice).font(.caption).foregroundStyle(WaveTheme.secondary).textSelection(.enabled).listRowBackground(Color.clear) }
            CloudLibrarySection()
            DiscoverSection().listRowBackground(Color.clear)
            NavigationLink { LocalTracksView() } label: { FolderRow(name: "Todas las canciones", count: local.songs.filter { !$0.hidden }.count) }.listRowBackground(WaveTheme.selected)
            Section {
                HStack {
                    Menu {
                        Picker("Ordenar por", selection: $descending) { Text("Nombre A–Z").tag(false); Text("Nombre Z–A").tag(true) }
                    } label: { Label("Ordenar por", systemImage: "arrow.up.arrow.down") }
                    Spacer()
                    Toggle("Con favoritos", isOn: $likedOnly).toggleStyle(.button)
                }.font(.subheadline).listRowBackground(Color.clear)
                if local.songs.isEmpty && !local.importing {
                    WaveMessage(title: "Tu colección, en su sitio.", detail: "Importa canciones o una carpeta desde Archivos.").listRowBackground(Color.clear)
                }
                ForEach(visibleFolders, id: \.self) { folder in
                    NavigationLink { LocalTracksView(folder: folder, playlistTitle: folder.split(separator: "/").last.map(String.init) ?? folder) } label: { LocalPlaylistRow(folder: folder) }
                        .listRowBackground(WaveTheme.surface)
                        .swipeActions {
                            if let playlist = preferences.state.playlists.first(where: { $0.source == .local && $0.folder == folder }) {
                                Button("Quitar playlist", role: .destructive) { Task { await preferences.remove(playlist) } }.disabled(preferences.saving)
                            }
                        }
                }
            } header: { WaveSectionHeader(title: "Carpetas · \(visibleFolders.count)") }
            Section("Música de tu dispositivo") {
                NavigationLink { DeviceMusicLibraryView() } label: { PlaylistRow(name: "Biblioteca de Música", count: device.authorization == .authorized ? device.songs.count : nil, subtitle: "Canciones, álbumes y playlists") }.listRowBackground(WaveTheme.surface)
            }
        }.waveLibraryStyle()
            .wavePage(title: WaveSection.local.title, search: $search, prompt: "Buscar playlists")
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
    // true whenever we must look past this exact folder into its subfolders —
    // shared with Descubre's own folder scan so a heart saved there always
    // surfaces here too.
    private var recursive: Bool { includeSubfolders || favoritesOnly || likedOnly }
    private var children: [String] {
        guard let folder else { return [] }
        let candidates = local.songs(in: nil, recursive: true, advanced: advanced).filter { !(favoritesOnly || likedOnly) || local.liked($0, in: preferences) }
        let folders = LocalSong.childFolders(in: folder, songs: (favoritesOnly || likedOnly) ? candidates : local.songs).filter { child in
            search.isEmpty || child.localizedCaseInsensitiveContains(search) || candidates.contains {
                ($0.folder == child || $0.folder.hasPrefix(child + "/")) && ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search)
            }
        }
        return sort == .nameDescending ? Array(folders.reversed()) : folders
    }
    private var visible: [LocalSong] {
        let songs = local.songs(in: folder, recursive: recursive, advanced: advanced).filter { song in
            (!(favoritesOnly || likedOnly) || local.liked(song, in: preferences)) && (search.isEmpty || (song.name + " " + song.artist).localizedCaseInsensitiveContains(search))
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
        let visible = self.visible
        let children = self.children
        return List {
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
                Section {
                    ForEach(children, id: \.self) { child in
                        NavigationLink {
                            LocalTracksView(folder: child, playlistTitle: child.split(separator: "/").last.map(String.init) ?? child)
                        } label: { LocalPlaylistRow(folder: child) }
                            .listRowBackground(WaveTheme.surface)
                    }
                } header: { WaveSectionHeader(title: "Carpetas") }
            }
            if visible.isEmpty && children.isEmpty { WaveMessage(title: "No hay canciones visibles.", detail: "Importa música o usa la vista Avanzada para ver canciones ocultas.").listRowBackground(Color.clear) }
            Section("\(visible.count) canciones") {
                ForEach(visible) { song in
                    HStack(spacing: 0) {
                        Button {
                            player.play(local.playable(song), queue: visible.filter { !$0.hidden || $0.id == song.id }.map { local.playable($0) })
                        } label: { TrackRow(track: song.track, active: player.current?.id == local.playable(song).id, advanced: advanced, audioURL: local.playable(song).url, folder: song.folder).opacity(song.hidden ? 0.5 : 1) }
                            .buttonStyle(.plain)
                        LikeButton(song: local.playable(song))
                    }.modifier(WaveSongMenu(song: local.playable(song), playQueue: { visible.map { local.playable($0) } }))
                        .listRowInsets(EdgeInsets()).listRowBackground(player.current?.id == local.playable(song).id ? WaveTheme.selected : WaveTheme.surface)
                        .swipeActions { Button(song.hidden ? "Mostrar" : "Ocultar") { Task { await local.setHidden(song.id, hidden: !song.hidden) } }.tint(WaveTheme.accent).disabled(local.importing) }
                        .moveDisabled(sort != .manual || !search.isEmpty || local.importing || favoritesOnly || likedOnly)
                }
                .onMove { offsets, destination in
                    var reordered = visible
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    Task { await local.reorder(reordered.map(\.id)) }
                }
            }
        }.waveLibraryStyle()
            .wavePage(title: favoritesOnly ? "Me gusta" : playlistTitle ?? folder ?? "Todas las canciones", search: $search, prompt: "Carpeta, canción o artista")
            .toolbar {
                if let folder {
                    if !preferences.state.playlists.contains(where: { $0.source == .local && $0.folder == folder }) {
                        Button { Task { await preferences.addFolder(folder, source: .local) } } label: { Image(systemName: "text.badge.plus") }
                            .accessibilityLabel("Añadir carpeta como playlist").disabled(!preferences.ready || preferences.saving)
                    }
                }
                EditButton().disabled(sort != .manual || !search.isEmpty || local.importing || favoritesOnly || likedOnly)
            }
    }
}

struct WaveSettingsView: View {
    @AppStorage("wave.dock.dimWhenIdle") private var dimWhenIdle = true
    @AppStorage("wave.dock.automatic") private var automaticDock = true
    @AppStorage("wave.appearance") private var appearance = WaveAppearance.system.rawValue
    @AppStorage("wave.accent") private var accent = WaveAccent.system.rawValue
    @AppStorage("wave.liquidGlass") private var liquidGlass = true
    @AppStorage("wave.server") private var server = WaveServerSettings.defaultAddress
    @State private var draft = ""
    @State private var notice: String?
    var body: some View {
        Form {
            Section("Apariencia") {
                Toggle("Liquid Glass y animación del reproductor", isOn: $liquidGlass)
                Picker("Modo", selection: $appearance) { ForEach(WaveAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                Picker("Color", selection: $accent) { ForEach(WaveAccent.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                Text("Sistema sigue el modo claro u oscuro del iPhone y usa los colores nativos de iOS.").font(.caption).foregroundStyle(WaveTheme.secondary)
            }.listRowBackground(WaveTheme.surface)
            Section("Servidor Wave") {
                TextField("URL HTTPS del servidor", text: $draft).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Guardar conexión") {
                    do { let api = try WaveAPI(server: draft); server = api.base.absoluteString; notice = "Conexión guardada." }
                    catch { notice = error.localizedDescription }
                }
                if let notice { Text(notice).font(.caption) }
            }.listRowBackground(WaveTheme.surface)
            Section("Horizontal y En reposo") {
                Toggle("En reposo al cargar en horizontal", isOn: $automaticDock)
                Toggle("Atenuar tras 20 segundos sin tocar", isOn: $dimWhenIdle)
                Text("El menú aparece a la izquierda al girar el dispositivo. La vista En reposo de Wave muestra reloj y música mientras la app está abierta.").font(.caption).foregroundStyle(WaveTheme.secondary)
                if !WaveWidgetStore.available { Text("Los widgets no están conectados. Revisa las instrucciones de instalación de esta versión.").font(.caption).foregroundStyle(WaveTheme.secondary) }
                Text("Los widgets Elegir canción y Reproduciendo permiten seleccionar música y controlarla desde Inicio o En reposo de iOS. El widget grande Biblioteca y reproductor reúne ambos.").font(.caption).foregroundStyle(WaveTheme.secondary)
            }.listRowBackground(WaveTheme.surface)
            Section("Música local") {
                Text("En Mi iPhone o Mi iPad puedes abrir tu biblioteca de Música o importar archivos desde Archivos.")
                Text("Los originales permanecen en su ubicación. Las copias importadas ocupan espacio en este dispositivo.")
            }.font(.subheadline).foregroundStyle(WaveTheme.secondary).listRowBackground(WaveTheme.surface)
            Section("Wave para iOS · 0.11.7") {
                Text("Servidor, archivos locales y biblioteca de Música del dispositivo.")
                Text("Versión instalada: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.caption.monospacedDigit())
            }.font(.caption).listRowBackground(WaveTheme.surface)
        }.waveLibraryStyle()
            .wavePage(title: "Ajustes").onAppear { draft = server }
    }
}
