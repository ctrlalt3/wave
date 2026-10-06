import SwiftUI
import WidgetKit

struct WaveDockLibraryView: View {
    var safeLeadingInset: CGFloat = 0
    var onClose: (() -> Void)? = nil
    @EnvironmentObject private var player: WavePlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = WaveWidgetBrowserPage.empty
    @State private var busy = false
    @State private var localArtwork: [String: URL] = [:]
    @State private var artworkManifestDate = Date.distantPast
    private let pageSize = 24
    private var listScope: String { page.state.source.rawValue + ":" + page.state.folder + ":" + String(page.state.offset) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                backButton
                breadcrumbs
                Spacer(minLength: 0)
                refreshButton
                sourceMenu
                closeButton
            }
            .frame(height: 44)
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Color.clear.frame(height: 0).id("dock-list-top")
                    ForEach(page.items) { item in
                        dockRow(item)
                    }
                    if page.items.isEmpty && !busy { Text(page.message ?? "Esta carpeta está vacía.").font(.subheadline).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading) }
                    else if let message = page.message { Text(message).font(.caption).foregroundStyle(.orange).padding(.vertical, 8) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(busy ? 0.72 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: busy)
                .onChange(of: listScope) { _, _ in
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo("dock-list-top", anchor: .top) }
                }
            }
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
                if !busy {
                    let revision = page.state.revision
                    let next = await WaveWidgetBrowserService.shared.snapshot(rows: pageSize)
                    if !busy && page.state.revision == revision { apply(next); await loadLocalArtwork() }
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private func dockRow(_ item: WaveWidgetBrowserItem) -> some View {
        let isFolder = item.kind == .folder
        let isPlaying = item.playbackID.map { $0 == player.current?.id } ?? false
        return Button { Task { await select(item) } } label: {
            WaveDockLibraryRow(
                item: item,
                isFolder: isFolder,
                isPlaying: isPlaying,
                safeLeadingInset: safeLeadingInset,
                audioURL: page.state.source == .local ? localArtwork[item.id] : nil,
                remoteURL: serverArtwork(item)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(busy)
        .accessibilityLabel((isFolder ? "Abrir carpeta " : "Reproducir ") + item.title)
        .simultaneousGesture(DragGesture(minimumDistance: 28).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.25 else { return }
            if value.translation.width < -42, isFolder {
                Task { await select(item) }
            } else if value.translation.width > 42 {
                Task { await navigate(.up) }
            }
        })
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
    private var breadcrumbs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                Button { Task { await navigate(.location, item: "") } } label: { Image(systemName: "house").frame(width: 44, height: 44) }
                    .accessibilityLabel("Inicio de biblioteca")
                let parts = page.state.folder.split(separator: "/")
                ForEach(parts.indices, id: \.self) { index in
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.5))
                    let path = parts.prefix(index + 1).joined(separator: "/")
                    Button(String(parts[index])) { Task { await navigate(.location, item: path) } }
                        .font(.subheadline).frame(minHeight: 44).disabled(index == parts.count - 1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.hidden).disabled(busy).frame(height: 44)
    }
    private func apply(_ next: WaveWidgetBrowserPage) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { page = next }
    }
    @ViewBuilder private var closeButton: some View {
        if let onClose { Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Cerrar En reposo") }
    }
    private var backButton: some View {
        Button { Task { await navigate(.up) } } label: { Image(systemName: "arrow.turn.up.left").frame(width: 44, height: 44) }
            .disabled(page.state.folder.isEmpty || busy).accessibilityLabel("Carpeta superior")
    }
    private var refreshButton: some View {
        Button { Task { await navigate(.refresh) } } label: {
            Group { if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.clockwise") } }.frame(width: 44, height: 44)
        }
            .disabled(busy).accessibilityLabel("Actualizar biblioteca")
    }
    @MainActor private func navigate(_ command: WaveWidgetBrowseCommand, item: String = "") async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        let next = await WaveWidgetBrowserService.shared.navigate(command, item: item, revision: page.state.revision, stride: pageSize)
        apply(next)
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

private struct WaveDockLibraryRow: View {
    let item: WaveWidgetBrowserItem
    let isFolder: Bool
    let isPlaying: Bool
    let safeLeadingInset: CGFloat
    let audioURL: URL?
    let remoteURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            artwork
            labels
            if isFolder {
                Image(systemName: "chevron.right").font(.caption)
            }
        }
        .padding(.leading, safeLeadingInset)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var artwork: some View {
        if isFolder {
            Image(systemName: "folder").font(.title2).frame(width: 44, height: 44)
        } else {
            WaveArtwork(size: 44, remoteURL: remoteURL, audioURL: audioURL)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(item.subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backgroundColor: Color {
        isPlaying ? Color.white.opacity(0.15) : Color.white.opacity(0.05)
    }
}
