import Combine
import SwiftUI
import UIKit

struct WaveAdaptiveLayout: Equatable {
    let size: CGSize
    var isLandscape: Bool { size.width > size.height && size.width >= 540 }
    var usesSidebar: Bool { isLandscape || size.width >= 760 }
    var compactSidebar: Bool { size.height < 500 || size.width < 900 }
    var sidebarWidth: CGFloat { usesSidebar ? (compactSidebar ? 72 : 208) : 0 }
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
        VStack(spacing: 8) {
            Label("WAVE", systemImage: "waveform")
                .labelStyle(SidebarLabelStyle(compact: layout.compactSidebar))
                .font(.headline).tracking(2).padding(.top, 12).padding(.bottom, 4)
                .accessibilityLabel("Wave")
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(WaveSection.allCases) { item in
                        Button { expanded = false; section = item } label: {
                            Label(item.title, systemImage: item.icon)
                                .labelStyle(SidebarLabelStyle(compact: layout.compactSidebar))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: layout.compactSidebar ? .center : .leading)
                                .padding(.horizontal, layout.compactSidebar ? 0 : 12)
                                .background(section == item ? WaveTheme.selected : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel(item.title)
                            .accessibilityAddTraits(section == item ? [.isSelected] : [])
                    }
                }.padding(.horizontal, 8)
            }.scrollIndicators(.hidden)
            Button(action: openDock) {
                Label("En reposo", systemImage: "moon.stars")
                    .labelStyle(SidebarLabelStyle(compact: layout.compactSidebar))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("Abrir vista En reposo")
            if !layout.compactSidebar {
                Text("WAVE · 0.9.0").font(.caption2.monospaced()).foregroundStyle(WaveTheme.secondary).padding(.bottom, 12)
            }
        }.background(WaveTheme.sidebar)
            .overlay(alignment: .trailing) { Divider() }
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
