import Foundation
import XCTest
@testable import Wave

final class LocalLibraryTests: XCTestCase {
    func testImportOwnsCopyAndSurvivesRestart() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("Canción #1.wav")
        try waveAudio().write(to: source)
        let root = temporary.appendingPathComponent("library")
        let storage = LocalLibraryStorage(root: root)
        let report = try await storage.importFiles([source])
        XCTAssertTrue(report.failures.isEmpty, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.songs.count, 1)
        let song = try XCTUnwrap(report.songs.first)
        XCTAssertEqual(song.name, "Canción #1")
        XCTAssertEqual(song.track.filename, "Canción #1.wav")
        XCTAssertGreaterThan(song.duration, 0)
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(song.file).path))
        let reopened = LocalLibraryStorage(root: root)
        let restored = try await reopened.read()
        XCTAssertEqual(restored.first?.id, song.id)
        var hidden = restored
        hidden[0].hidden = true
        try await reopened.save(hidden)
        let persisted = try await storage.read()
        XCTAssertEqual(persisted.first?.hidden, true)
    }

    func testFolderImportPreservesGroupsAndRejectsInvalidAudio() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let folder = temporary.appendingPathComponent("Colección/Álbum", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try waveAudio().write(to: folder.appendingPathComponent("válida.wav"))
        try Data("invalid audio".utf8).write(to: folder.appendingPathComponent("inválida.mp3"))
        let storage = LocalLibraryStorage(root: temporary.appendingPathComponent("library"))
        let report = try await storage.importFiles([temporary.appendingPathComponent("Colección")])
        XCTAssertEqual(report.songs.count, 1)
        XCTAssertEqual(report.songs.first?.folder, "Colección/Álbum")
        XCTAssertEqual(report.failures.count, 1)
        let saved = try await storage.read()
        XCTAssertEqual(saved.count, 1)
        let audioCopies = try FileManager.default.contentsOfDirectory(at: temporary.appendingPathComponent("library"), includingPropertiesForKeys: nil).filter { $0.pathExtension != "json" }
        XCTAssertEqual(audioCopies.count, 1)
    }

    func testCorruptManifestIsNotOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("library.json")
        let original = Data("broken manifest".utf8)
        try original.write(to: manifest)
        let storage = LocalLibraryStorage(root: root)
        do {
            _ = try await storage.importFiles([])
            XCTFail("A corrupt library must not be replaced during import.")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: manifest), original)
    }

    private func waveAudio() -> Data {
        let samples = Data(repeating: 0, count: 44100 * 2)
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count))
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(44100)); append(UInt32(88200)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(samples.count)); data.append(samples)
        return data
    }
}
