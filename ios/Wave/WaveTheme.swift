import SwiftUI
import MediaPlayer
import AVFoundation

enum WaveTheme {
    static let background = Color(red: 247 / 255, green: 246 / 255, blue: 243 / 255)
    static let sidebar = Color(red: 241 / 255, green: 240 / 255, blue: 236 / 255)
    static let surface = Color(red: 251 / 255, green: 251 / 255, blue: 250 / 255)
    static let ink = Color(red: 47 / 255, green: 52 / 255, blue: 55 / 255)
    static let secondary = Color(red: 120 / 255, green: 119 / 255, blue: 116 / 255)
    static let accent = Color(red: 69 / 255, green: 101 / 255, blue: 74 / 255)
    static let selected = Color(red: 228 / 255, green: 232 / 255, blue: 225 / 255)
    static let border = Color(red: 230 / 255, green: 229 / 255, blue: 225 / 255)

    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "0:00" }
        let value = Int(seconds)
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }
}

struct WaveArtwork: View {
    var size: CGFloat = 40
    var artwork: MPMediaItemArtwork? = nil
    var remoteURL: URL? = nil
    var audioURL: URL? = nil
    @State private var embeddedImage: UIImage?
    var body: some View {
        Group {
        if let image = artwork?.image(at: CGSize(width: size * 2, height: size * 2)) ?? embeddedImage {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.13))
        } else if let remoteURL {
            AsyncImage(url: remoteURL) { image in
                image.resizable().scaledToFill()
            } placeholder: { symbol }
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.13))
        } else { symbol }
        }.accessibilityHidden(true)
            .task(id: audioURL) {
                embeddedImage = nil
                guard let audioURL else { return }
                let asset = AVURLAsset(url: audioURL)
                guard let metadata = try? await asset.load(.commonMetadata) else { return }
                for item in metadata where item.commonKey == .commonKeyArtwork {
                    if let data = try? await item.load(.dataValue), let image = UIImage(data: data) {
                        guard !Task.isCancelled else { return }
                        embeddedImage = image
                        return
                    }
                }
            }
    }
    private var symbol: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.4, weight: .regular))
            .foregroundStyle(WaveTheme.accent.opacity(0.75))
            .frame(width: size, height: size)
            .background(WaveTheme.selected, in: RoundedRectangle(cornerRadius: size * 0.13))
            .accessibilityHidden(true)
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
