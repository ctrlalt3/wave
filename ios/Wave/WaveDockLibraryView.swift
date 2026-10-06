import SwiftUI
import WidgetKit

struct WaveDockLibraryView: View {
    var safeLeadingInset: CGFloat = 0
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var player: WavePlayer
    @State private var page = WaveWidgetBrowserPage.empty
    @State private var busy = false
    @State private var folders: [WaveWidgetFolderRecord] = []
    @State private var localArtwork: [String: URL] = [:]
    @State private var artworkManifestDate = Date.distantPast
    private let pageSize = 24
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { backButton; sourceMenu; folderMenu; refreshButton; closeButton }
                VStack(spacing: 4) {
                    HStack { sourceMenu; refreshButton; closeButton }
                    HStack { backButton; folderMenu }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if busy { ProgressView("Cargando biblioteca…").tint(.white).padding(.vertical, 12) }
                    ForEach(page.items) { item in
                        Button { Task { await select(item) } } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if item.kind == .folder { Image(systemName: "folder").font(.title2).frame(width: 44, height: 44) }
                                    else { WaveArtwork(size: 44, remoteURL: serverArtwork(item), audioURL: page.state.source == .local ? localArtwork[item.id] : nil).clipShape(RoundedRectangle(cornerRadius: 8)) }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.body.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1).multilineTextAlignment(.leading)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if item.kind == .folder { Image(systemName: "chevron.right").font(.caption) }
                            }.padding(.leading, 14 + safeLeadingInset).padding(.trailing, 14).padding(.vertical, 10).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .background(item.playbackID != nil && item.playbackID == player.current?.id ? Color.white.opacity(0.15) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).disabled(busy).accessibilityLabel((item.kind == .folder ? "Abrir carpeta " : "Reproducir ") + item.title)
                    }
                    if page.items.isEmpty && !busy { Text(page.message ?? "Esta carpeta está vacía.").font(.subheadline).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading) }
                    else if let message = page.message { Text(message).font(.caption).foregroundStyle(.orange).padding(.vertical, 8) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button { Task { await navigate(.previousPage) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(busy || !page.canGoBack).accessibilityLabel("Página anterior")
                Spacer(minLength: 0)
                Text(page.total == 0 ? "0 canciones" : "\(page.state.offset + 1)–\(min(page.state.offset + pageSize, page.total)) / \(page.total)").font(.caption.monospacedDigit())
                Spacer(minLength: 0)
                Button { Task { await navigate(.nextPage) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(busy || !page.canGoForward(rows: pageSize)).accessibilityLabel("Página siguiente")
            }
        }.buttonStyle(.plain).task {
            while !Task.isCancelled {
                if !busy { page = await WaveWidgetBrowserService.shared.snapshot(rows: pageSize); folders = await WaveWidgetBrowserService.shared.folderOptions(); await loadLocalArtwork() }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private func serverArtwork(_ item: WaveWidgetBrowserItem) -> URL? {
        guard item.kind == .song, page.state.source == .server,
              let base = WaveWidgetBrowserStorage.serverURL(), let api = try? WaveAPI(server: base.absoluteString),
              WaveAPI.safePath(item.id) else { return nil }
        let track = WaveTrack(name: item.title, artist: item.subtitle, duration: 0, relPath: item.id, filename: (item.id as NSString).lastPathComponent)
        return api.artworkURL(for: track)
    }
    @MainActor private func loadLocalArtwork() async {
        guard page.state.source == .local else { return }
        let manifest = WavePlaybackStorage.root.appendingPathComponent("library.json")
        let date = (try? FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date) ?? .distantPast
        guard localArtwork.isEmpty || date != artworkManifestDate else { return }
        let songs = (try? await LocalLibraryStorage(root: WavePlaybackStorage.root).read()) ?? []
        localArtwork = Dictionary(songs.filter { !$0.hidden && $0.file == ($0.file as NSString).lastPathComponent }.map { ($0.id, WavePlaybackStorage.root.appendingPathComponent($0.file)) }, uniquingKeysWith: { first, _ in first })
        artworkManifestDate = date
    }
    private var sourceMenu: some View {
        Menu {
            Button("Local") { Task { await navigate(.local) } }
            Button("Servidor") { Task { await navigate(.server) } }
        } label: {
            HStack(spacing: 6) {
                Text(page.state.source == .local ? "Local" : "Servidor").font(.headline)
                Image(systemName: "chevron.down").font(.caption)
            }.frame(minWidth: 70, minHeight: 44, alignment: .leading)
        }.disabled(busy).accessibilityLabel("Elegir biblioteca Local o Servidor")
    }
    private var folderMenu: some View {
        Menu {
            Button("Inicio de biblioteca") { Task { await navigate(.location, item: "") } }
            if !page.state.folder.isEmpty {
                let parts = page.state.folder.split(separator: "/")
                ForEach(parts.indices, id: \.self) { index in
                    let path = parts.prefix(index + 1).joined(separator: "/")
                    Button(String(parts[index])) { Task { await navigate(.location, item: path) } }
                }
            }
            if !folders.isEmpty {
                Section("Carpetas") {
                    ForEach(folders, id: \.path) { folder in
                        Button(folder.path) { Task { await navigate(.location, item: folder.path) } }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(page.state.folder.isEmpty ? "Carpetas" : page.title).lineLimit(1).multilineTextAlignment(.leading)
                Image(systemName: "chevron.down").font(.caption)
            }.font(.subheadline).frame(minWidth: 60, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.disabled(busy).accessibilityLabel("Navegar entre carpetas de la biblioteca actual")
    }
    @ViewBuilder private var closeButton: some View {
        if let onClose { Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Cerrar En reposo") }
    }
    private var backButton: some View {
        Button { Task { await navigate(.up) } } label: { Image(systemName: "arrow.turn.up.left").frame(width: 44, height: 44) }
            .disabled(page.state.folder.isEmpty || busy).accessibilityLabel("Carpeta superior")
    }
    private var refreshButton: some View {
        Button { Task { await navigate(.refresh) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
            .disabled(busy).accessibilityLabel("Actualizar biblioteca")
    }
    @MainActor private func navigate(_ command: WaveWidgetBrowseCommand, item: String = "") async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        page = await WaveWidgetBrowserService.shared.navigate(command, item: item, revision: page.state.revision, stride: pageSize)
        folders = await WaveWidgetBrowserService.shared.folderOptions()
        await loadLocalArtwork()
        WidgetCenter.shared.reloadAllTimelines()
    }
    @MainActor private func select(_ item: WaveWidgetBrowserItem) async {
        if item.kind == .folder { await navigate(.folder, item: item.id) }
        else {
            guard !busy else { return }
            busy = true; defer { busy = false }
            await player.chooseWidgetSong(source: page.state.source, id: item.id, serverID: page.serverID)
        }
    }
}
