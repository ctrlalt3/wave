import SwiftUI
import WidgetKit

struct WaveWidgetBrowserView: View {
    let page: WaveWidgetBrowserPage
    let playback: WaveWidgetSnapshot
    var rowLimit: Int? = nil
    @Environment(\.widgetFamily) private var family
    private var rows: Int { rowLimit ?? (family == .systemSmall || family == .systemMedium || family == .accessoryRectangular ? 1 : 4) }
    @ViewBuilder var body: some View {
        if family == .accessoryInline {
            Label(page.title + " · Wave", systemImage: page.state.source == .local ? "music.note" : "server.rack")
                .widgetURL(WaveWidgetDestination.playlists.url)
        } else if family == .accessoryRectangular { accessoryBrowser }
        else {
            VStack(spacing: 0) {
                header
                if page.items.isEmpty {
                    Text(page.message ?? "Esta carpeta está vacía.").font(.caption).lineLimit(family == .systemSmall ? 2 : 3)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    ForEach(Array(page.items.prefix(rows))) { item in itemButton(item) }
                }
                if family != .systemSmall && family != .systemMedium, let message = page.message { Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                if family != .systemSmall { Spacer(minLength: 0) }
                pagination
            }.padding(family == .systemSmall ? 6 : 10)
        }
    }
    private var header: some View {
        HStack(spacing: 4) {
            Button(intent: browse(.toggleSource)) {
                Label(page.state.source == .local ? "Local" : "Servidor", systemImage: page.state.source == .local ? "iphone" : "server.rack")
                    .font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityLabel("Cambiar biblioteca. Actual: " + (page.state.source == .local ? "Local" : "Servidor"))
            if family != .systemSmall {
                Text(page.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !page.state.folder.isEmpty { navigationButton(.up, symbol: "arrow.turn.up.left", label: "Carpeta superior") }
            }
            navigationButton(family == .systemSmall && !page.state.folder.isEmpty ? .up : .refresh,
                             symbol: family == .systemSmall && !page.state.folder.isEmpty ? "arrow.turn.up.left" : "arrow.clockwise",
                             label: family == .systemSmall && !page.state.folder.isEmpty ? "Carpeta superior" : "Actualizar biblioteca")
        }
    }
    private var pagination: some View {
        HStack(spacing: 0) {
            navigationButton(.previousPage, symbol: "chevron.left", label: "Página anterior").disabled(!page.canGoBack)
            Spacer(minLength: 0)
            Text(page.total == 0 ? "0" : "\(page.state.offset + 1)–\(min(page.state.offset + rows, page.total)) / \(page.total)")
                .font(.caption2.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7).accessibilityLabel("Posición en la biblioteca")
            Spacer(minLength: 0)
            navigationButton(.nextPage, symbol: "chevron.right", label: "Página siguiente").disabled(!page.canGoForward(rows: rows))
        }
    }
    @ViewBuilder private func itemButton(_ item: WaveWidgetBrowserItem) -> some View {
        if item.kind == .folder {
            Button(intent: browse(.folder, item: item.id)) { rowLabel(item) }.buttonStyle(.plain).accessibilityLabel("Abrir carpeta " + item.title)
        } else {
            Button(intent: WaveChooseSongIntent(source: page.state.source, songID: item.id, serverID: page.serverID)) { rowLabel(item) }
                .buttonStyle(.plain).accessibilityLabel("Reproducir " + item.title + " · " + item.subtitle)
        }
    }
    private func rowLabel(_ item: WaveWidgetBrowserItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind == .folder ? "folder" : item.playbackID == playback.songID && playback.isPlaying ? "waveform" : "play.fill")
                .font(.caption).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(family == .systemMedium ? (page.message ?? item.subtitle) : item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 44).background(item.playbackID != nil && item.playbackID == playback.songID ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
    private func browse(_ command: WaveWidgetBrowseCommand, item: String = "") -> WaveBrowseLibraryIntent {
        WaveBrowseLibraryIntent(command, item: item, revision: page.state.revision, rows: rows)
    }
    private func navigationButton(_ command: WaveWidgetBrowseCommand, symbol: String, label: String, size: CGFloat = 44) -> some View {
        Button(intent: browse(command)) { Image(systemName: symbol).font(.caption.weight(.semibold)).frame(width: size, height: size) }
            .buttonStyle(.plain).accessibilityLabel(label)
    }
    private var accessoryBrowser: some View {
        HStack(spacing: 4) {
            VStack(spacing: 0) {
                navigationButton(.toggleSource, symbol: page.state.source == .local ? "iphone" : "server.rack", label: "Cambiar biblioteca", size: 28)
                navigationButton(page.state.folder.isEmpty ? .refresh : .up, symbol: page.state.folder.isEmpty ? "arrow.clockwise" : "arrow.turn.up.left", label: page.state.folder.isEmpty ? "Actualizar" : "Carpeta superior", size: 28)
            }
            if let item = page.items.first { itemButton(item) }
            else { Text(page.message ?? "Sin canciones").font(.caption2).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading) }
            VStack(spacing: 0) {
                navigationButton(.previousPage, symbol: "chevron.up", label: "Anterior", size: 28).disabled(!page.canGoBack)
                navigationButton(.nextPage, symbol: "chevron.down", label: "Siguiente", size: 28).disabled(!page.canGoForward(rows: 1))
            }
        }
    }
}

struct WaveMusicConsoleView: View {
    let entry: WaveWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if family == .systemExtraLarge {
                HStack(spacing: 20) {
                    WaveWidgetBrowserView(page: entry.browser, playback: entry.state, rowLimit: 4)
                    Divider()
                    playerPane.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    WaveWidgetBrowserView(page: entry.browser, playback: entry.state, rowLimit: 2)
                    Divider().padding(.horizontal, 10)
                    playerPane.padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
    }
    private var playerPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.state.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if let message = entry.state.message { Text(message).font(.caption2).lineLimit(2) }
            HStack(spacing: 4) {
                Button(intent: WavePlaybackIntent(command: .previous)) { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Anterior")
                Button(intent: WavePlaybackIntent(command: .toggle)) { Image(systemName: entry.state.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(entry.state.isPlaying ? "Pausar" : "Reproducir")
                Button(intent: WavePlaybackIntent(command: .next)) { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente")
                Spacer(minLength: 0)
            }.buttonStyle(.plain).disabled(entry.state.songID == nil)
        }
    }
}
