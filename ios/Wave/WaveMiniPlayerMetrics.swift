import Foundation

// All values derive from the width iOS proposes during the native morph,
// not just from the target placement (which can change before that morph ends).
struct WaveMiniPlayerMetrics {
    let width: CGFloat
    let padding: CGFloat
    let spacing: CGFloat
    let controlWidth: CGFloat
    let openWidth: CGFloat
    let titleWidth: CGFloat
    let artworkSpacing: CGFloat
    let showsArtwork: Bool
    let showsDetails: Bool

    init(width proposedWidth: CGFloat, inline: Bool) {
        let width = proposedWidth.isFinite ? max(0, proposedWidth) : 0
        let padding = min(12, width / 10)
        let available = max(0, width - padding * 2)
        let showsDetails = !inline && width >= 280
        let count: CGFloat = showsDetails ? 3 : 1
        let controlWidth = min(44, available / count)
        let spacing = min(8, max(0, (available - controlWidth * count) / count))
        let openWidth = max(0, available - count * (controlWidth + spacing))
        let showsArtwork = openWidth >= 64
        let artworkSpacing: CGFloat = showsArtwork ? 8 : 0
        self.width = width
        self.padding = padding
        self.spacing = spacing
        self.controlWidth = controlWidth
        self.openWidth = openWidth
        self.showsArtwork = showsArtwork
        self.artworkSpacing = artworkSpacing
        self.titleWidth = max(0, openWidth - (showsArtwork ? 32 + artworkSpacing : 0))
        self.showsDetails = showsDetails
    }
}
