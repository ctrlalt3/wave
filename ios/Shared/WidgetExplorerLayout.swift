import Foundation

struct WaveWidgetExplorerLayout: Equatable {
    let columns: Int
    let rowsPerColumn: Int
    var capacity: Int { columns * rowsPerColumn }
    init(width: Double, height: Double) {
        columns = width.isFinite && width >= 560 ? 2 : 1
        let available = max(44, (height.isFinite ? height : 320) - 124)
        rowsPerColumn = max(1, min(12, Int((available / 44).rounded(.down))))
    }
}
