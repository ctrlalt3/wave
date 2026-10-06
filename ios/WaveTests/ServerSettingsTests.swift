import Foundation
import XCTest
@testable import Wave

final class ServerSettingsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "WaveServerTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    func testMissingOrEmptyServerGetsEstablishedDefault() throws {
        let settings = try defaults()
        XCTAssertEqual(WaveServerSettings.resolvedAddress(defaults: settings), WaveServerSettings.defaultAddress)
        settings.set(" \n ", forKey: "wave.server")
        WaveServerSettings.prepareDefaults(defaults: settings)
        XCTAssertEqual(settings.string(forKey: "wave.server"), WaveServerSettings.defaultAddress)
    }
    func testCustomServerIsPreserved() throws {
        let settings = try defaults()
        settings.set("https://example.com/music/", forKey: "wave.server")
        WaveServerSettings.prepareDefaults(defaults: settings)
        XCTAssertEqual(WaveServerSettings.resolvedAddress(defaults: settings), "https://example.com/music/")
    }
}
