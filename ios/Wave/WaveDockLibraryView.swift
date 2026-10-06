import SwiftUI
import WidgetKit

struct WaveDockLibraryView: View {
    var safeLeadingInset: CGFloat = 0
    @EnvironmentObject private var player: WavePlayer
    @State private var page = WaveWidgetBrowserPage.empty
    @State private var busy = false
    private let pageSize = 24
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { backButton; folderTitle; sourcePicker.frame(width: 160); refreshButton }
                VStack(spacing: 4) {
                    HStack { sourcePicker; refreshButton }
                    HStack { backButton; folderTitle }
                }
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    if busy { ProgressView("Cargando biblioteca…").tint(.white).padding(.vertical, 12) }
                    ForEach(page.items) { item in
                        Button { Task { await select(item) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.kind == .folder ? "folder" : item.playbackID == player.current?.id ? "speaker.wave.2.fill" : "play.fill").frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.body.weight(.medium)).lineLimit(2)
                                    Text(item.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if item.kind == .folder { Image(systemName: "chevron.right").font(.caption) }
                            }.padding(.leading, 14 + safeLeadingInset).padding(.trailing, 14).padding(.vertical, 10).frame(minHeight: 56)
                                .background(item.playbackID != nil && item.playbackID == player.current?.id ? Color.white.opacity(0.15) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(busy).accessibilityLabel((item.kind == .folder ? "Abrir carpeta " : "Reproducir ") + item.title)
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
                if !busy { page = await WaveWidgetBrowserService.shared.snapshot(rows: pageSize) }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    private var sourcePicker: some View {
        Picker("Biblioteca", selection: Binding(get: { page.state.source }, set: { source in
            Task { await navigate(source == .local ? .local : .server) }
        })) { Text("Local").tag(WaveWidgetLibrarySource.local); Text("Servidor").tag(WaveWidgetLibrarySource.server) }
            .pickerStyle(.segmented).frame(minHeight: 44).disabled(busy)
    }
    private var folderTitle: some View { Text(page.title).font(.headline).lineLimit(1).frame(minWidth: 60, maxWidth: .infinity, alignment: .leading) }
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
