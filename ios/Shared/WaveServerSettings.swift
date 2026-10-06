import Foundation

enum WaveServerSettings {
    static let defaultAddress = "https://tulopetas.duckdns.org/wave/"
    static func resolvedAddress(defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: "wave.server")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultAddress : saved
    }
    static func prepareDefaults(defaults: UserDefaults = .standard) {
        let address = resolvedAddress(defaults: defaults)
        if defaults.string(forKey: "wave.server") != address {
            defaults.set(address, forKey: "wave.server")
        }
    }
}
