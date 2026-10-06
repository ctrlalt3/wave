import CryptoKit
import Foundation
import SwiftUI

struct CloudTrack: Decodable { let path: String; let hash: String; let size: Int64 }
struct CloudManifest: Decodable { let revision: String; let tracks: [CloudTrack]; let folders: [String] }
struct CloudOperation: Decodable, Identifiable { let id: String; let expires: Double; let changed: Int }
extension WaveAPI {
    func cloudUpload(path: String, file: URL, operation: String) async throws {
        guard Self.safePath(path) else { throw Failure(message: "Ruta no válida.") }
        var components = URLComponents(url: url(["api", "cloud", "upload", operation]), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"; request.timeoutInterval = 300
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, fromFile: file)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw cloudFailure(data) }
    }
    func cloudRequest<T: Decodable>(_ components: [String], body: [String: Any] = [:]) async throws -> T {
        var request = URLRequest(url: url(components))
        request.httpMethod = "POST"; request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw cloudFailure(data) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func cloudFailure(_ data: Data) -> Failure {
        struct Message: Decodable { let error: String }
        return Failure(message: (try? JSONDecoder().decode(Message.self, from: data).error) ?? "No se pudo completar la actualización. Vuelve a intentarlo.")
    }
    func cloudDownload(_ track: CloudTrack) async throws -> URL {
        guard Self.safePath(track.path), track.hash.count == 64, track.hash.allSatisfy({ $0.isHexDigit }) else { throw Failure(message: "Manifiesto no válido.") }
        var request = URLRequest(url: url(["api", "cloud", "blob", track.hash])); request.timeoutInterval = 300
        let (file, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw Failure(message: "No se pudo descargar \(track.path).") }
        return file
    }
}
struct CloudLibrarySection: View {
    @AppStorage("wave.server") private var server = WaveServerSettings.defaultAddress
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var preferences: LibraryPreferences
    @State private var busy = false
    @State private var operations: [CloudOperation] = []
    @State private var notice: String?
    @State private var folder = ""
    @State private var folders: [String] = []
    var body: some View {
        Section("Nube · iOS y Mac") {
            Text(server.isEmpty ? "Guarda la dirección de tu servidor en Ajustes para conectar la nube." : "Servidor de destino: \(server)").font(.caption).textSelection(.enabled)
            Picker("Carpeta para descargar", selection: $folder) {
                Text("Toda la nube").tag("")
                ForEach(folders, id: \.self) { Text($0).tag($0) }
            }
            Button("Subir / actualizar mis carpetas") { Task { await run { try await local.publishCloud(try WaveAPI(server: server), preferences: preferences) } } }
            Button("Descargar / actualizar este dispositivo") { Task { await run {
                let api = try WaveAPI(server: server)
                try await local.downloadCloud(api, folder: folder.isEmpty ? nil : folder)
                for folder in LocalSong.automaticPlaylists(for: local.songs) { await preferences.addFolder(folder, source: .local) }
                await preferences.synchronizeServer(api)
            } } }
            Button("Deshacer descarga (30 minutos)") { Task { await run { try await local.undoCloudDownload() } } }
            Button("Historial de actualizaciones") { Task { await history() } }
            ForEach(operations) { operation in
                HStack {
                    Text("\(operation.changed) cambios · hasta \(Date(timeIntervalSince1970: operation.expires).formatted(date: .omitted, time: .shortened))").font(.caption)
                    Spacer()
                    Button("Deshacer") { Task { await run {
                        struct Result: Decodable { let ok: Bool }
                        let _: Result = try await WaveAPI(server: server).cloudRequest(["api", "cloud", "undo", operation.id])
                        await history()
                    } } }
                }
            }
            if busy { ProgressView("Actualizando música…") }
            if let notice { Text(notice).font(.caption).textSelection(.enabled) }
            Text("Descarga para escuchar sin conexión. Cada actualización se puede deshacer durante 30 minutos.").font(.caption).foregroundStyle(WaveTheme.secondary)
        }.disabled(busy || local.importing || server.isEmpty)
            .task(id: server) {
                do { folders = try await WaveAPI(server: server).folders().map(\.name) }
                catch { notice = error.localizedDescription }
            }
    }
    @MainActor private func run(_ action: () async throws -> Void) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await action(); notice = "Actualización completada." } catch { notice = error.localizedDescription }
    }
    @MainActor private func history() async {
        do { operations = try await WaveAPI(server: server).get(["api", "cloud", "history"]) } catch { notice = error.localizedDescription }
    }
}
