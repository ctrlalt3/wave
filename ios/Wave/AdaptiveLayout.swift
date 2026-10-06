import Combine
import SwiftUI
import UIKit

struct WaveAdaptiveLayout: Equatable {
    let size: CGSize
    var isLandscape: Bool { size.width > size.height && size.width >= 540 }
    var usesSidebar: Bool { isLandscape || size.width >= 760 }
    var compactSidebar: Bool { size.height < 500 || size.width < 900 }
    var sidebarWidth: CGFloat { usesSidebar ? (compactSidebar ? 76 : 216) : 0 }
    var compactHeader: Bool { isLandscape && size.height < 500 }
    static let portrait = WaveAdaptiveLayout(size: CGSize(width: 390, height: 844))
}
private struct WaveLayoutKey: EnvironmentKey {
    static let defaultValue = WaveAdaptiveLayout.portrait
}
extension EnvironmentValues {
    var waveLayout: WaveAdaptiveLayout {
        get { self[WaveLayoutKey.self] }
        set { self[WaveLayoutKey.self] = newValue }
    }
}

@MainActor
final class WaveChargingMonitor: ObservableObject {
    @Published private(set) var isCharging = false
    @Published private(set) var isDeviceLandscape = false
    private var observation: AnyCancellable?
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        refresh()
        observation = Publishers.Merge3(
            NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification),
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification),
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        )
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
    }
    private func refresh() {
        isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        isDeviceLandscape = scene?.interfaceOrientation.isLandscape ?? UIDevice.current.orientation.isLandscape
    }
}

struct WaveSidebar: View {
    @Binding var section: WaveSection
    @Binding var expanded: Bool
    let layout: WaveAdaptiveLayout
    let openDock: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    if !layout.compactHeader {
                        Label("WAVE", systemImage: "waveform")
                            .labelStyle(SidebarLabelStyle(compact: layout.compactSidebar))
                            .font(.headline).tracking(2).padding(.bottom, 12).accessibilityLabel("Wave")
                    }
                    VStack(spacing: 6) {
                        ForEach(WaveSection.allCases.filter { $0 != .settings }) { item in navigationButton(item) }
                    }
                    Divider().padding(.horizontal, 4)
                    VStack(spacing: 6) {
                        navigationButton(.settings)
                        Button(action: openDock) {
                            Label("En reposo", systemImage: "rectangle.split.2x1")
                                .labelStyle(SidebarLabelStyle(compact: layout.compactSidebar))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Abrir biblioteca En reposo")
                    }
                    if !layout.compactSidebar {
                        Text("WAVE · 0.11.3").font(.caption2.monospaced()).foregroundStyle(WaveTheme.secondary).padding(.top, 12)
                    }
                }.frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 32), alignment: .center)
                    .padding(.horizontal, 12).padding(.vertical, 16)
            }.scrollIndicators(.hidden)
        }.frame(maxHeight: .infinity).background(WaveTheme.sidebar)
            .overlay(alignment: .trailing) { Divider() }
    }
    private func navigationButton(_ item: WaveSection) -> some View {
        Button { expanded = false; section = item } label: {
            Label(item.title, systemImage: item.icon)
                .labelStyle(SidebarLabelStyle(compact: layout.compactSidebar))
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: layout.compactSidebar ? .center : .leading)
                .padding(.horizontal, layout.compactSidebar ? 0 : 12)
                .background(section == item ? WaveTheme.selected : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(item.title)
            .accessibilityAddTraits(section == item ? [.isSelected] : [])
    }

}
private struct SidebarLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.frame(width: 24)
            if !compact { configuration.title.lineLimit(1) }
        }
    }
}
