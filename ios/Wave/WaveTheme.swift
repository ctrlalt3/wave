import SwiftUI
import MediaPlayer
import AVFoundation
import UIKit

enum WaveAppearance: String, CaseIterable {
    case system = "Sistema", light = "Claro", dark = "Oscuro"
    var scheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
enum WaveAccent: String, CaseIterable {
    case system = "Sistema", green = "Verde", pink = "Rosa", orange = "Naranja", purple = "Morado"
    var color: Color {
        switch self {
        case .system: return Color(uiColor: .systemBlue)
        case .green: return .green
        case .pink: return .pink
        case .orange: return .orange
        case .purple: return .purple
        }
    }
}

enum WaveTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let sidebar = Color(uiColor: .secondarySystemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let secondary = Color.secondary
    static let accent = Color.accentColor
    static let selected = Color.accentColor.opacity(0.12)
    static let border = Color(uiColor: .separator)

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "0:00" }
        let value = Int(seconds)
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }
}

@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()
    private let images = NSCache<NSURL, UIImage>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]
    private init() { images.totalCostLimit = 32 * 1024 * 1024 }
    func cached(_ url: URL?) -> UIImage? { url.flatMap { images.object(forKey: $0 as NSURL) } }
    func image(remote: URL?, audio: URL?) async -> UIImage? {
        guard let key = remote ?? audio else { return nil }
        if let value = cached(key) { return value }
        if let task = pending[key] { return await task.value }
        let task = Task<UIImage?, Never> {
            if let remote, let (data, response) = try? await URLSession.shared.data(from: remote),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let image = UIImage(data: data) { return image }
            if let audio, let metadata = try? await AVURLAsset(url: audio).load(.commonMetadata) {
                for item in metadata where item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue), let image = UIImage(data: data) { return image }
                }
            }
            return nil
        }
        pending[key] = task
        let value = await task.value
        pending[key] = nil
        if let value { images.setObject(value, forKey: key as NSURL, cost: Int(value.size.width * value.size.height * 4)) }
        return value
    }
}

struct WaveArtwork: View {
    var size: CGFloat = 40
    var artwork: MPMediaItemArtwork? = nil
    var remoteURL: URL? = nil
    var audioURL: URL? = nil
    var fillsSpace = false
    @State private var loadedImage: UIImage?
    @State private var loadedKey: URL?
    private var key: URL? { remoteURL ?? audioURL }
    private var image: UIImage? {
        artwork?.image(at: CGSize(width: max(size * 2, 600), height: max(size * 2, 600))) ??
        (loadedKey == key ? loadedImage : nil) ?? ArtworkCache.shared.cached(key)
    }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    WaveTheme.selected
                    Image(systemName: "music.note").font(.system(size: fillsSpace ? 80 : size * 0.4)).foregroundStyle(WaveTheme.accent)
                }
            }
        }
        .frame(width: fillsSpace ? nil : size, height: fillsSpace ? nil : size)
        .frame(maxWidth: fillsSpace ? .infinity : nil, maxHeight: fillsSpace ? .infinity : nil)
        .clipped().clipShape(RoundedRectangle(cornerRadius: fillsSpace ? 0 : size * 0.13))
        .accessibilityHidden(true)
        .task(id: key) {
            let requestedKey = key
            let value = await ArtworkCache.shared.image(remote: remoteURL, audio: audioURL)
            guard !Task.isCancelled, requestedKey == key else { return }
            loadedImage = value; loadedKey = requestedKey
        }
    }
}

struct WaveMessage: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list").font(.system(size: 32)).foregroundStyle(WaveTheme.accent)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(WaveTheme.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 48).padding(.horizontal, 20)
    }
}
