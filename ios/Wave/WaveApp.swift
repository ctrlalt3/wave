import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct WaveApp: App {
    @StateObject private var player = WavePlayer()
    @StateObject private var local = LocalLibrary()
    @StateObject private var device = DeviceMusicLibrary()
    var body: some Scene {
        WindowGroup {
            WaveHome().environmentObject(player).environmentObject(local).environmentObject(device)
                .tint(WaveTheme.accent).foregroundStyle(WaveTheme.ink).preferredColorScheme(.light)
        }
    }
}

enum WaveSection: String, CaseIterable, Identifiable {
    case server, local, spotify, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .server: return "Servidor"; case .local: return UIDevice.current.userInterfaceIdiom == .pad ? "Mi iPad" : "Mi iPhone"; case .spotify: return "Spotify"; case .settings: return "Ajustes" }
    }
    var icon: String {
        switch self { case .server: return "externaldrive"; case .local: return "music.note"; case .spotify: return "magnifyingglass"; case .settings: return "gearshape" }
    }
}

struct WaveHome: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: WaveSection = .server
    @State private var expanded = false
    @EnvironmentObject private var local: LocalLibrary
    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label { Text("WAVE").tracking(3) } icon: { Image(systemName: "waveform") }.font(.title2.weight(.semibold)).padding(18)
                        Text("BIBLIOTECAS").font(.caption2.monospaced()).tracking(2).foregroundStyle(WaveTheme.secondary).padding(.horizontal, 18)
                        ForEach(WaveSection.allCases) { item in
                            Button { section = item } label: {
                                Label(item.title, systemImage: item.icon).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                    .background(section == item ? WaveTheme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).padding(.horizontal, 12)
                        }
                        Spacer()
                        Text("WAVE PARA IOS · 0.3").font(.caption2.monospaced()).foregroundStyle(WaveTheme.secondary).padding(24)
                    }.background(WaveTheme.sidebar)
                } detail: { content(section).id(section) }
            } else {
                TabView(selection: $section) {
                    ForEach(WaveSection.allCases) { item in
                        content(item).tabItem { Label(item.title, systemImage: item.icon) }.tag(item)
                    }
                }
            }
        }.safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(WaveTheme.accent)
                Text("WAVE").font(.headline).tracking(3)
                Spacer()
                Text("0.3").font(.caption.monospacedDigit()).foregroundStyle(WaveTheme.secondary).accessibilityIdentifier("wave.build-version")
            }.padding(.horizontal, 22).padding(.vertical, 12).background(WaveTheme.sidebar)
        }.safeAreaInset(edge: .bottom, spacing: 0) { PlayerBar(expanded: $expanded) }
            .sheet(isPresented: $expanded) { ExpandedPlayer() }.task { await local.load() }
    }
    @ViewBuilder private func content(_ item: WaveSection) -> some View {
        NavigationStack {
            switch item {
            case .server: ServerLibraryView()
            case .local: LocalLibraryView()
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
        }.background(WaveTheme.background).navigationTitle("Servidor Wave")
            .searchable(text: $search, prompt: "Buscar carpetas").refreshable { await load() }.task(id: server) { await load() }
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
    @State private var tracks: [WaveTrack] = []
    @State private var loading = false
    @State private var error: String?
    @State private var search = ""
    @State private var sort: TrackSort = .manual
    @State private var advanced = false
    @State private var hidden = Set<String>()
    @State private var saving = false
    @EnvironmentObject private var player: WavePlayer
    private var visible: [WaveTrack] { sort.sorted(tracks.filter { (advanced || !hidden.contains($0.id)) && (search.isEmpty || ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search)) }) }
    var body: some View {
        List {
            TrackTools(sort: $sort, advanced: $advanced).listRowBackground(Color.clear)
            if loading { ProgressView("Cargando canciones…").listRowBackground(Color.clear) }
            if let error { Text(error).foregroundStyle(.red).listRowBackground(Color.clear) }
            if !loading && error == nil && visible.isEmpty { WaveMessage(title: "No hay canciones visibles.", detail: "Prueba otra búsqueda o carpeta.").listRowBackground(Color.clear) }
            Section("\(visible.count) canciones") {
                ForEach(visible) { track in
                    Button { player.play(track, queue: visible.filter { !hidden.contains($0.id) || $0.id == track.id }, api: api) } label: {
                        TrackRow(track: track, active: player.current?.id == api.base.absoluteString + track.id, advanced: advanced, remoteCover: api.artworkURL(track.coverUrl))
                            .opacity(hidden.contains(track.id) ? 0.5 : 1)
                    }.listRowBackground(player.current?.id == api.base.absoluteString + track.id ? WaveTheme.selected : WaveTheme.surface)
                        .swipeActions {
                            Button(hidden.contains(track.id) ? "Mostrar" : "Ocultar") { Task { await setHidden(track) } }.tint(WaveTheme.accent).disabled(saving)
                        }.moveDisabled(sort != .manual || !search.isEmpty || saving)
                }
                .onMove { offsets, destination in
                    var reordered = visible
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    let visibleIDs = Set(reordered.map(\.id))
                    let paths = reordered.map(\.id) + tracks.filter { !visibleIDs.contains($0.id) }.map(\.id)
                    Task { await saveOrder(paths) }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(WaveTheme.background).navigationTitle(folder.name).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Canción o artista").task { await load() }.refreshable { await load() }
            .toolbar { EditButton().disabled(sort != .manual || !search.isEmpty || saving) }
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
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var device: DeviceMusicLibrary
    @State private var importer = false
    @State private var importingFolder = false
    @State private var search = ""
    private var folders: [String] { Array(Set(local.songs.map(\.folder))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var body: some View {
        List {
            Section("Música de tu dispositivo") {
                NavigationLink { DeviceMusicLibraryView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note.list").font(.title2).foregroundStyle(WaveTheme.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Biblioteca de Música").font(.headline)
                            Text(device.authorization == .authorized ? "\(device.songs.count) canciones · álbumes · playlists" : "Ver las canciones de la app Música").font(.caption).foregroundStyle(WaveTheme.secondary)
                        }
                    }.padding(.vertical, 10)
                }.listRowBackground(WaveTheme.selected)
            }
            Section("Archivos importados en Wave") {
            Text("Tus archivos, guardados para escucharlos sin conexión.").font(.subheadline).foregroundStyle(WaveTheme.secondary).listRowBackground(Color.clear)
            if local.importing { ProgressView("Importando música…").listRowBackground(Color.clear) }
            if let notice = local.notice { Text(notice).font(.caption).foregroundStyle(WaveTheme.secondary).textSelection(.enabled).listRowBackground(Color.clear) }
            if local.songs.isEmpty && !local.importing {
                WaveMessage(title: "Tu colección, en su sitio.", detail: "Importa canciones o una carpeta desde Archivos, iCloud Drive o un almacenamiento conectado.").listRowBackground(Color.clear)
            }
            Button { importingFolder = false; importer = true } label: { Label("Importar canciones", systemImage: "plus") }.disabled(local.importing).listRowBackground(WaveTheme.selected)
            Button { importingFolder = true; importer = true } label: { Label("Importar carpeta", systemImage: "folder.badge.plus") }.disabled(local.importing).listRowBackground(WaveTheme.surface)
            }
            Section("Biblioteca") {
                NavigationLink { LocalTracksView() } label: { FolderRow(name: "Todas las canciones", count: local.songs.filter { !$0.hidden }.count) }.listRowBackground(WaveTheme.surface)
                ForEach(folders.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { folder in
                    NavigationLink { LocalTracksView(folder: folder) } label: { FolderRow(name: folder, count: local.songs.filter { $0.folder == folder && !$0.hidden }.count) }.listRowBackground(WaveTheme.surface)
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(WaveTheme.background).navigationTitle(WaveSection.local.title).searchable(text: $search, prompt: "Buscar carpetas")
            .task { device.reload() }
            .fileImporter(isPresented: $importer, allowedContentTypes: importingFolder ? [.folder] : [.audio], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await local.importFiles(urls) }
                case .failure(let error): local.notice = error.localizedDescription
                }
            }
    }
}

struct LocalTracksView: View {
    var folder: String?
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var player: WavePlayer
    @State private var search = ""
    @State private var sort: TrackSort = .manual
    @State private var advanced = false
    private var visible: [LocalSong] {
        let songs = local.songs.filter { (folder == nil || $0.folder == folder) && (advanced || !$0.hidden) && (search.isEmpty || ($0.name + " " + $0.artist).localizedCaseInsensitiveContains(search)) }
        switch sort {
        case .manual: return songs
        case .name: return songs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .duration: return songs.sorted { $0.duration < $1.duration }
        }
    }
    var body: some View {
        List {
            TrackTools(sort: $sort, advanced: $advanced).listRowBackground(Color.clear)
            if visible.isEmpty { WaveMessage(title: "No hay canciones visibles.", detail: "Importa música o usa la vista Avanzada para ver canciones ocultas.").listRowBackground(Color.clear) }
            Section("\(visible.count) canciones") {
                ForEach(visible) { song in
                    Button {
                        player.play(local.playable(song), queue: visible.filter { !$0.hidden || $0.id == song.id }.map { local.playable($0) })
                    } label: { TrackRow(track: song.track, active: player.current?.id == "local:" + song.id, advanced: advanced).opacity(song.hidden ? 0.5 : 1) }
                        .listRowBackground(player.current?.id == "local:" + song.id ? WaveTheme.selected : WaveTheme.surface)
                        .swipeActions { Button(song.hidden ? "Mostrar" : "Ocultar") { Task { await local.setHidden(song.id, hidden: !song.hidden) } }.tint(WaveTheme.accent).disabled(local.importing) }
                        .moveDisabled(sort != .manual || !search.isEmpty || local.importing)
                }
                .onMove { offsets, destination in
                    var reordered = visible
                    reordered.move(fromOffsets: offsets, toOffset: destination)
                    Task { await local.reorder(reordered.map(\.id)) }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(WaveTheme.background).navigationTitle(folder ?? "Todas las canciones").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Canción o artista")
            .toolbar { EditButton().disabled(sort != .manual || !search.isEmpty || local.importing) }
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
            Section("Wave para iOS · 0.3") {
                Text("Servidor, archivos locales y biblioteca de Música del dispositivo.")
                Text("Versión instalada: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").font(.caption.monospacedDigit())
            }.font(.caption).listRowBackground(WaveTheme.surface)
        }.scrollContentBackground(.hidden).background(WaveTheme.background).navigationTitle("Ajustes").onAppear { draft = server }
    }
}
