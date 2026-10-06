import SwiftUI
import Combine

@MainActor
final class WaveNavigationChrome: ObservableObject {
    @Published var compact = false
    private var travel: CGFloat = 0
    func scroll(delta: CGFloat) {
        if (delta > 0 && travel < 0) || (delta < 0 && travel > 0) { travel = 0 }
        travel += delta
        if travel > 16 { if !compact { compact = true }; travel = 0 }
        else if travel < -16 { if compact { compact = false }; travel = 0 }
    }
    func expand() { compact = false; travel = 0 }
}

