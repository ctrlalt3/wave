import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct WaveApp: App {
    @AppStorage("wave.appearance") private var appearance = WaveAppearance.system.rawValue
    @AppStorage("wave.accent") private var accent = WaveAccent.system.rawValue
    @StateObject private var player = WavePlayer()
    @StateObject private var local = LocalLibrary()
    @StateObject private var device = DeviceMusicLibrary()
    @StateObject private var preferences = LibraryPreferences()
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: WaveSection = .server
    @State private var expanded = false
    @State private var sectionOffset: CGFloat = 0
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.18))) private var sectionDrag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columns: NavigationSplitViewVisibility = .all
    @StateObject private var chrome = WaveNavigationChrome()
    @Namespace private var playerNamespace
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
                        Text("WAVE PARA IOS · 0.7.2").font(.caption2.monospaced())
                            .foregroundStyle(WaveTheme.secondary).padding(24)
                    }.background(WaveTheme.sidebar)
                } detail: {
                    playerPage(section).id(section)
                }
            } else {
                compactTabs
            }
        }.offset(x: reduceMotion ? 0 : sectionOffset + sectionDrag).safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(WaveTheme.accent)
                Text("WAVE").font(.headline).tracking(3)
                Spacer()
                Text("0.7.2").font(.caption.monospacedDigit()).foregroundStyle(WaveTheme.secondary).accessibilityIdentifier("wave.build-version")
            }.padding(.horizontal, 22).padding(.vertical, 12).background(WaveTheme.background)
                .contentShape(Rectangle()).gesture(sectionGesture)
                .accessibilityHint("Desliza a izquierda o derecha para cambiar de sección")
        }.transaction { if reduceMotion { $0.animation = nil } }.environmentObject(chrome)
            .onChange(of: expanded) { _, value in chrome.trackingEnabled = !value }
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
                .modifier(WaveNativeTabScrollBehavior())
                .modifier(LiquidAccessoryModifier(expanded: $expanded, transitionNamespace: playerNamespace))
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

    private var sectionGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($sectionDrag) { value, drag, transaction in
                if reduceMotion { transaction.animation = nil }
                guard !expanded, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                drag = max(-40, min(40, value.translation.width * 0.25))
            }
            .onEnded { value in
                guard !expanded else { sectionOffset = 0; return }
                if let next = WaveGestureNavigation.section(after: section, horizontal: value.translation.width, vertical: value.translation.height) {
                    select(next)
                    sectionOffset = reduceMotion ? 0 : (value.translation.width < 0 ? 24 : -24)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { sectionOffset = 0 }
            }
    }

    private func select(_ item: WaveSection) {
        if section != item { expanded = false }
        section = item
        chrome.expand()
    }

    // Preserve each library navigation stack while presenting the full player.
    // The native accessory owns the source transition; library stacks stay intact.
    private func playerPage(_ item: WaveSection, nativeAccessory: Bool = false) -> some View {
        content(item)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !nativeAccessory { PlayerBar(expanded: $expanded, transitionNamespace: playerNamespace) }
            }
            .fullScreenCover(isPresented: Binding(get: { expanded && section == item }, set: { expanded = $0 }), onDismiss: { chrome.expand() }) {
                ExpandedPlayer(onClose: { expanded = false })
                    .modifier(WavePlayerTransition(namespace: playerNamespace))
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
    @EnvironmentObject private var preferences: LibraryPreferences
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
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
        }.waveLibraryStyle().navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: "Servidor Wave", search: $search, prompt: "Buscar carpetas") }
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
        }.waveLibraryStyle().navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
        preferences.state.visiblePlaylists.filter { $0.source == .local }.map(\.folder)
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
            } header: { WaveSectionHeader(title: "Mis playlist · \(visibleFolders.count)") }
            Section("Música de tu dispositivo") {
                NavigationLink { DeviceMusicLibraryView() } label: { PlaylistRow(name: "Biblioteca de Música", count: device.authorization == .authorized ? device.songs.count : nil, subtitle: "Canciones, álbumes y playlists") }.listRowBackground(WaveTheme.surface)
            }
        }.waveLibraryStyle().navigationTitle("").navigationBarTitleDisplayMode(.inline)
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
    // true whenever we must look past this exact folder into its subfolders —
    // shared with Descubre's own folder scan so a heart saved there always
    // surfaces here too.
    private var recursive: Bool { includeSubfolders || favoritesOnly || likedOnly }
    private var children: [String] {
        guard let folder else { return [] }
        let candidates = local.songs(in: nil, recursive: true, advanced: advanced).filter { !(favoritesOnly || likedOnly) || local.liked($0, in: preferences) }
        let folders = LocalSong.childFolders(in: folder, songs: candidates).filter { child in
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
                        } label: { TrackRow(track: song.track, active: player.current?.id == "local:" + song.id, advanced: advanced, audioURL: local.playable(song).url).opacity(song.hidden ? 0.5 : 1) }
                            .buttonStyle(.plain)
                        LikeButton(song: local.playable(song))
                    }.modifier(WaveSongMenu(song: local.playable(song), playQueue: { visible.map { local.playable($0) } }))
                        .listRowInsets(EdgeInsets()).listRowBackground(player.current?.id == "local:" + song.id ? WaveTheme.selected : WaveTheme.surface)
                        .swipeActions { Button(song.hidden ? "Mostrar" : "Ocultar") { Task { await local.setHidden(song.id, hidden: !song.hidden) } }.tint(WaveTheme.accent).disabled(local.importing) }
                        .moveDisabled(sort != .manual || !search.isEmpty || local.importing || favoritesOnly || likedOnly)
                }
                .onMove { offsets, destination in
                    var reordered = visible
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    Task { await local.reorder(reordered.map(\.id)) }
                }
            }
        }.waveLibraryStyle().navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: favoritesOnly ? "Me gusta" : playlistTitle ?? folder ?? "Todas las canciones", search: $search, prompt: "Carpeta, canción o artista") }
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
    @AppStorage("wave.appearance") private var appearance = WaveAppearance.system.rawValue
    @AppStorage("wave.accent") private var accent = WaveAccent.system.rawValue
    @AppStorage("wave.liquidGlass") private var liquidGlass = true
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
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
                    do { _ = try WaveAPI(server: draft); server = draft; notice = "Conexión guardada." }
                    catch { notice = error.localizedDescription }
                }
                if let notice { Text(notice).font(.caption) }
            }.listRowBackground(WaveTheme.surface)
            Section("Música local") {
                Text("En Mi iPhone o Mi iPad puedes abrir tu biblioteca de Música o importar archivos desde Archivos.")
                Text("Los originales permanecen en su ubicación. Las copias importadas ocupan espacio en este dispositivo.")
            }.font(.subheadline).foregroundStyle(WaveTheme.secondary).listRowBackground(WaveTheme.surface)
            Section("Wave para iOS · 0.7.2") {
                Text("Servidor, archivos locales y biblioteca de Música del dispositivo.")
                Text("Versión instalada: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.caption.monospacedDigit())
            }.font(.caption).listRowBackground(WaveTheme.surface)
        }.waveLibraryStyle().navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { WavePageHeader(title: "Ajustes") }.onAppear { draft = server }
    }
}
