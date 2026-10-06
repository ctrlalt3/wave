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
