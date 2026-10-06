import SwiftUI
import UIKit
import WidgetKit

@main
struct WaveWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WaveNowPlayingWidget()
        WaveLibraryWidget()
    }
}
struct WaveWidgetEntry: TimelineEntry {
    let date: Date
    let state: WaveWidgetSnapshot
    let artwork: UIImage?
}
struct WaveWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaveWidgetEntry { WaveWidgetEntry(date: .now, state: .preview, artwork: nil) }
    func getSnapshot(in context: Context, completion: @escaping (WaveWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WaveWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
    private func entry() -> WaveWidgetEntry {
        let state = WaveWidgetStore.read()
        let image = WaveWidgetStore.artworkURL(filename: state.artworkFilename).flatMap { UIImage(contentsOfFile: $0.path) }
        return WaveWidgetEntry(date: .now, state: state, artwork: image)
    }
}
struct WaveNowPlayingWidget: Widget {
    let kind = "WaveNowPlaying"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaveWidgetProvider()) { entry in
            WaveNowPlayingWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
                .widgetURL(WaveWidgetDestination.player.url)
        }
        .containerBackgroundRemovable(true)
        .configurationDisplayName("Wave · Reproduciendo")
        .description("Tu canción y controles de música, también en la pantalla bloqueada y En reposo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
struct WaveNowPlayingWidgetView: View {
    let entry: WaveWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var rendering
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @ViewBuilder var body: some View {
        switch family {
        case .accessoryInline:
            Label(entry.state.songID == nil ? "Wave · Tu música" : entry.state.title, systemImage: entry.state.isPlaying ? "waveform" : "music.note")
        case .accessoryCircular:
            if entry.state.songID != nil {
                Button(intent: WavePlaybackIntent(command: .toggle)) {
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: entry.state.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                }.buttonStyle(.plain).accessibilityLabel(entry.state.isPlaying ? "Pausar Wave" : "Reproducir Wave")
            } else { ZStack { AccessoryWidgetBackground(); Image(systemName: "waveform") } }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.state.title).font(.headline).lineLimit(1)
                    Text(entry.state.artist).font(.caption).lineLimit(1)
                    ProgressView(value: entry.state.fraction).tint(.primary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if entry.state.songID != nil { playbackButton(.toggle, symbol: entry.state.isPlaying ? "pause.fill" : "play.fill", label: entry.state.isPlaying ? "Pausar" : "Reproducir", size: 36) }
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    artwork(size: 32)
                    Spacer(minLength: 4)
                    Image(systemName: "waveform").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                Text(entry.state.title).font(showsBackground ? .subheadline.weight(.semibold) : .headline).lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if entry.state.songID != nil {
                    HStack {
                        playbackButton(.toggle, symbol: entry.state.isPlaying ? "pause.fill" : "play.fill", label: entry.state.isPlaying ? "Pausar" : "Reproducir")
                        Spacer(minLength: 4)
                        playbackButton(.next, symbol: "forward.end.fill", label: "Siguiente")
                    }
                } else { Label("Abrir Wave", systemImage: "arrow.up.right").font(.caption) }
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    artwork(size: family == .systemMedium ? 64 : 90)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.state.title).font(.headline).lineLimit(2)
                        Text(entry.state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if let message = entry.state.message { Text(message).font(.caption2).lineLimit(2) }
                        else if family != .systemMedium { Label(entry.state.songID == nil ? "Tu música, a mano" : entry.state.isPlaying ? "Reproduciendo" : "En pausa", systemImage: entry.state.isPlaying ? "waveform" : "music.note").font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if entry.state.songID != nil {
                    HStack(spacing: 12) {
                        playbackButton(.previous, symbol: "backward.end.fill", label: "Anterior")
                        playbackButton(.toggle, symbol: entry.state.isPlaying ? "pause.fill" : "play.fill", label: entry.state.isPlaying ? "Pausar" : "Reproducir")
                        playbackButton(.next, symbol: "forward.end.fill", label: "Siguiente")
                        Spacer(minLength: 4)
                        if entry.state.isLiked { Image(systemName: "heart.fill").foregroundStyle(.red).accessibilityLabel("En Me gusta") }
                        if family != .systemMedium { Text("WAVE").font(.caption2).tracking(2).foregroundStyle(.secondary) }
                    }
                }
                if family != .systemMedium {
                    ProgressView(value: entry.state.fraction)
                    Text("A continuación").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(entry.state.queue.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).lineLimit(1)
                            Text(item.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if entry.state.queue.isEmpty { Text("Abre Wave para elegir tu próxima canción.").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
            }
        }
    }
    private func artwork(size: CGFloat) -> some View {
        Group {
            if rendering == .fullColor, let artwork = entry.artwork { Image(uiImage: artwork).resizable().scaledToFill() }
            else { ZStack { Color.primary.opacity(0.08); Image(systemName: "waveform").font(.title2).foregroundStyle(.primary) } }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
    }
    private func playbackButton(_ command: WaveWidgetPlaybackCommand, symbol: String, label: String, size: CGFloat = 44) -> some View {
        Button(intent: WavePlaybackIntent(command: command)) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: size, height: size)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

struct WaveLibraryWidget: Widget {
    let kind = "WaveLibrary"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WaveWidgetProvider()) { entry in
            WaveLibraryWidgetView(state: entry.state)
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
                .widgetURL(WaveWidgetDestination.playlists.url)
        }
        .containerBackgroundRemovable(true)
        .configurationDisplayName("Wave · Tu biblioteca")
        .description("Accede a tus playlists, Me gusta y música descargada.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
struct WaveLibraryWidgetView: View {
    let state: WaveWidgetSnapshot
    @Environment(\.widgetFamily) private var family
    @ViewBuilder var body: some View {
        if family == .accessoryInline {
            Label("\(state.favoritesCount) Me gusta · Wave", systemImage: "heart.fill")
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tu biblioteca · Wave").font(.headline)
                Text("\(state.playlistsCount) playlists · \(state.favoritesCount) Me gusta").font(.caption).lineLimit(1)
                Text("\(state.localCount) canciones en el dispositivo").font(.caption2).lineLimit(1)
            }
        } else if family == .systemMedium {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("WAVE", systemImage: "waveform").font(.caption.weight(.semibold)).tracking(2)
                    Text("Tu biblioteca").font(.headline)
                    Text("\(state.localCount) canciones descargadas").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Link(destination: WaveWidgetDestination.playlists.url) { Label("\(state.favoritesCount) Me gusta", systemImage: "heart.fill").frame(minHeight: 44) }
                    Link(destination: WaveWidgetDestination.local.url) { Label("Mi música", systemImage: "music.note.list").frame(minHeight: 44) }
                }.font(.subheadline)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("WAVE", systemImage: "waveform").font(.caption.weight(.semibold)).tracking(2)
                Text("\(state.favoritesCount)").font(.largeTitle.weight(.semibold)).monospacedDigit()
                Text("Me gusta").font(.headline)
                Spacer(minLength: 0)
                Text("\(state.playlistsCount) playlists").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
