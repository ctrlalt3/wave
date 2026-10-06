import AppIntents
import Foundation
import WidgetKit

enum WaveWidgetPlaybackCommand: String, AppEnum {
    case toggle, previous, next
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reproducción"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .toggle: "Reproducir o pausar", .previous: "Canción anterior", .next: "Canción siguiente"
    ]
}
struct WavePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Controlar la música de Wave"
    static var description = IntentDescription("Controla la reproducción de Wave desde sus widgets.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    @Parameter(title: "Acción") var command: WaveWidgetPlaybackCommand
    init() { command = .toggle }
    init(command: WaveWidgetPlaybackCommand) { self.command = command }
    @MainActor func perform() async throws -> some IntentResult {
        #if WAVE_APP
        await WavePlayer.shared.performWidgetCommand(command)
        #endif
        return .result()
    }
}

// Browsing runs inside the widget extension; it never opens the app or changes audio.
struct WaveBrowseLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Navegar por la biblioteca de Wave"
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    @Parameter(title: "Acción") var action: String
    @Parameter(title: "Carpeta") var item: String
    @Parameter(title: "Revisión") var revision: String
    @Parameter(title: "Canciones por página") var rows: Int
    init() { action = "refresh"; item = ""; revision = ""; rows = 1 }
    init(_ command: WaveWidgetBrowseCommand, item: String = "", revision: String, rows: Int = 1) {
        action = command.rawValue; self.item = item; self.revision = revision; self.rows = rows
    }
    func perform() async throws -> some IntentResult {
        if let command = WaveWidgetBrowseCommand(rawValue: action) {
            _ = await WaveWidgetBrowserService.shared.navigate(command, item: item, revision: revision, stride: rows)
            WidgetCenter.shared.reloadAllTimelines()
        }
        return .result()
    }
}
struct WaveChooseSongIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Reproducir una canción de Wave"
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    @Parameter(title: "Biblioteca") var source: String
    @Parameter(title: "Canción") var songID: String
    @Parameter(title: "Servidor") var serverID: String
    init() { source = "local"; songID = ""; serverID = "" }
    init(source: WaveWidgetLibrarySource, songID: String, serverID: String) {
        self.source = source.rawValue; self.songID = songID; self.serverID = serverID
    }
    @MainActor func perform() async throws -> some IntentResult {
        #if WAVE_APP
        if let source = WaveWidgetLibrarySource(rawValue: source) {
            await WavePlayer.shared.chooseWidgetSong(source: source, id: songID, serverID: serverID)
        }
        #endif
        return .result()
    }
}

struct WaveFavoriteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Me gusta en Wave"
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    @Parameter(title: "Canción") var songID: String
    @Parameter(title: "Marcar Me gusta") var liked: Bool
    init() { songID = ""; liked = true }
    init(songID: String, liked: Bool) { self.songID = songID; self.liked = liked }
    @MainActor func perform() async throws -> some IntentResult {
        #if WAVE_APP
        await WavePlayer.shared.favoriteWidgetSong(id: songID, liked: liked)
        #endif
        return .result()
    }
}
