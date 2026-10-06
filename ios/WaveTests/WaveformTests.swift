import Foundation
import XCTest
@testable import Wave

final class WaveformTests: XCTestCase {
    func testWaveformReadsActualAudioWithQuietAndLoudRegions() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: file) }
        var pcm = Data()
        for index in 0..<44100 {
            let amplitude = index < 22050 ? 0.0 : 16000.0
            let phase = Double(index) * 2.0 * Double.pi * 440.0 / 44100.0
            var sample = Int16(amplitude * sin(phase)).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(44100)); append(UInt32(88200)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        try data.write(to: file)
        let result = await WaveformAnalyzer.read(file)
        let samples = try XCTUnwrap(result)
        XCTAssertEqual(samples.count, 160)
        XCTAssertLessThan(samples.prefix(60).max() ?? 1, 0.1)
        XCTAssertGreaterThan(samples.suffix(60).max() ?? 0, 0.8)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }
    func testInvalidAudioDoesNotGenerateAFakeWaveform() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("invalid audio".utf8).write(to: file)
        let samples = await WaveformAnalyzer.read(file)
        XCTAssertNil(samples)
    }
}
