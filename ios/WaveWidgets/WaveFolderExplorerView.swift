import SwiftUI
import WidgetKit

struct WaveFolderExplorerView: View {
    let page: WaveWidgetBrowserPage
    let playback: WaveWidgetSnapshot
    var body: some View {
        GeometryReader { geometry in
            let metrics = WaveWidgetExplorerLayout(width: Double(geometry.size.width), height: Double(geometry.size.height))
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Button(intent: action(.toggleSource, rows: metrics.capacity)) {
                        Label(page.state.source == .local ? "Local" : "Servidor", systemImage: page.state.source == .local ? "iphone" : "server.rack")
                            .font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityLabel("Cambiar entre Local y Servidor")
                    navigation(.home, symbol: "house", label: "Inicio de biblioteca", rows: metrics.capacity).disabled(page.state.folder.isEmpty && page.state.offset == 0)
                    navigation(.up, symbol: "arrow.turn.up.left", label: "Carpeta superior", rows: metrics.capacity).disabled(page.state.folder.isEmpty)
                    navigation(.refresh, symbol: "arrow.clockwise", label: "Actualizar biblioteca", rows: metrics.capacity)
                }
                Text(page.state.folder.isEmpty ? "Biblioteca · " + page.title : page.state.folder)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Ruta actual: " + page.title)
                if page.items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "folder").font(.largeTitle)
                        Text(page.message ?? "Esta carpeta está vacía.").font(.subheadline)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 2) {
                        ForEach(0..<metrics.rowsPerColumn, id: \.self) { row in
                            HStack(spacing: 8) {
                                ForEach(0..<metrics.columns, id: \.self) { column in
                                    let index = row * metrics.columns + column
                                    if page.items.indices.contains(index) {
                                        itemButton(page.items[index], rows: metrics.capacity).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else { Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityHidden(true) }
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 4) {
                    navigation(.previousPage, symbol: "chevron.left", label: "Página anterior", rows: metrics.capacity).disabled(!page.canGoBack)
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text(page.total == 0 ? "0 elementos" : "\(page.state.offset + 1)–\(min(page.state.offset + metrics.capacity, page.total)) / \(page.total)").font(.caption.monospacedDigit())
                        if let message = page.message, !page.items.isEmpty { Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    navigation(.nextPage, symbol: "chevron.right", label: "Página siguiente", rows: metrics.capacity).disabled(!page.canGoForward(rows: metrics.capacity))
                }
            }.padding(6).frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    @ViewBuilder private func itemButton(_ item: WaveWidgetBrowserItem, rows: Int) -> some View {
        if item.kind == .folder {
            Button(intent: action(.folder, item: item.id, rows: rows)) { itemLabel(item) }.buttonStyle(.plain).accessibilityLabel("Abrir carpeta " + item.title)
        } else {
            Button(intent: WaveChooseSongIntent(source: page.state.source, songID: item.id, serverID: page.serverID)) { itemLabel(item) }
                .buttonStyle(.plain).accessibilityLabel("Reproducir " + item.title)
        }
    }
    private func itemLabel(_ item: WaveWidgetBrowserItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .folder ? "folder.fill" : item.playbackID == playback.songID && playback.isPlaying ? "speaker.wave.2.fill" : "play.fill").frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if item.kind == .folder { Image(systemName: "chevron.right").font(.caption2) }
        }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(item.playbackID != nil && item.playbackID == playback.songID ? Color.primary.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private func action(_ command: WaveWidgetBrowseCommand, item: String = "", rows: Int) -> WaveBrowseLibraryIntent {
        WaveBrowseLibraryIntent(command, item: item, revision: page.state.revision, rows: rows)
    }
    private func navigation(_ command: WaveWidgetBrowseCommand, symbol: String, label: String, rows: Int) -> some View {
        Button(intent: action(command, rows: rows)) { Image(systemName: symbol).font(.body).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
