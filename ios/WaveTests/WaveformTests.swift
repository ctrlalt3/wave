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

private actor WaveformLoadCounter {
    var loads = 0
    func load(_ url: URL) async -> [Double]? {
        loads += 1
        try? await Task.sleep(nanoseconds: 50_000_000)
        return [0.1, 0.8]
    }
    func count() -> Int { loads }
}

final class WaveformCacheTests: XCTestCase {
    func testConcurrentViewsShareOneAnalysisAndLaterReuseMemory() async {
        let counter = WaveformLoadCounter()
        let cache = WaveformCache(loader: { await counter.load($0) })
        let url = URL(fileURLWithPath: "/fixture/\(UUID().uuidString).wav")
        async let first = cache.samples(for: url)
        async let second = cache.samples(for: url)
        let results = await (first, second)
        XCTAssertEqual(results.0, [0.1, 0.8])
        XCTAssertEqual(results.1, results.0)
        let again = await cache.samples(for: url)
        XCTAssertEqual(again, results.0)
        let loads = await counter.count()
        XCTAssertEqual(loads, 1)
    }
}
