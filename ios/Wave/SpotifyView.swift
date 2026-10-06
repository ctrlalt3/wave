import Foundation
import SwiftUI

struct SpotifyToken: Decodable {
    let access_token: String
    let expires_in: Int
}

struct SpotifySong: Decodable, Identifiable {
    struct Artist: Decodable { let name: String }
    struct Cover: Decodable { let url: URL }
    struct Album: Decodable { let name: String; let images: [Cover] }
    struct Links: Decodable { let spotify: URL? }
    let id: String
    let name: String
    let artists: [Artist]
    let album: Album
    let duration_ms: Double
    let external_urls: Links
    var artist: String { artists.map(\.name).joined(separator: ", ") }
}

struct SpotifyPage: Decodable {
    let items: [SpotifySong?]
    let total: Int
    let next: String?
}

actor SpotifyCatalog {
    private var token: String?
    private var expires = Date.distantPast
    private var server = ""
    func search(_ query: String, api: WaveAPI, market: String, offset: Int) async throws -> SpotifyPage {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...200).contains(query.count), (0...1000).contains(offset), market.count == 2 else {
            throw WaveAPI.Failure(message: "Escribe entre 2 y 200 caracteres para buscar.")
        }
        if token == nil || expires < Date().addingTimeInterval(30) || server != api.base.absoluteString {
            let value: SpotifyToken = try await api.post(["api", "spotify", "search-token"])
            token = value.access_token
            expires = Date().addingTimeInterval(Double(value.expires_in))
            server = api.base.absoluteString
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.spotify.com"
        components.path = "/v1/search"
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "track"), URLQueryItem(name: "limit", value: "10"), URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "market", value: market)]
        guard let url = components.url, let token else { throw WaveAPI.Failure(message: "No se pudo preparar la búsqueda.") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw WaveAPI.Failure(message: "Spotify no ha respondido.") }
        if response.statusCode == 401 { self.token = nil; throw WaveAPI.Failure(message: "La sesión de Spotify ha caducado. Vuelve a buscar.") }
        if response.statusCode == 429 { throw WaveAPI.Failure(message: "Spotify ha limitado las búsquedas. Espera \(response.value(forHTTPHeaderField: "Retry-After") ?? "60") segundos.") }
        guard (200..<300).contains(response.statusCode) else { throw WaveAPI.Failure(message: "Spotify ha rechazado la búsqueda (\(response.statusCode)).") }
        struct Result: Decodable { let tracks: SpotifyPage }
        return try JSONDecoder().decode(Result.self, from: data).tracks
    }
}

struct SpotifyView: View {
    @AppStorage("wave.server") private var server = "https://tulopetas.duckdns.org/wave/"
    @Environment(\.openURL) private var openURL
    @State private var catalog = SpotifyCatalog()
    @State private var query = ""
    @State private var market = "ES"
    @State private var loading = false
    @State private var page: SpotifyPage?
    @State private var offset = 0
    @State private var searched = ""
    @State private var searchedMarket = "ES"
    @State private var error: String?
    var body: some View {
        List {
            Text("Busca canciones en el catálogo y ábrelas en Spotify para escucharlas.").font(.subheadline).foregroundStyle(WaveTheme.secondary).listRowBackground(Color.clear)
            Section {
                TextField("Canción, artista o álbum", text: $query).submitLabel(.search).onSubmit { startSearch() }
                Picker("Mercado", selection: $market) {
                    Text("España").tag("ES"); Text("México").tag("MX"); Text("Argentina").tag("AR"); Text("Estados Unidos").tag("US"); Text("Reino Unido").tag("GB")
                }
                Button("Buscar en Spotify") { startSearch() }.disabled(loading || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            }.listRowBackground(WaveTheme.surface)
            if loading { ProgressView("Buscando…").listRowBackground(Color.clear) }
            if let error { Text(error).foregroundStyle(.red).listRowBackground(Color.clear) }
            if let page {
                Section("\(page.total) resultados") {
                    ForEach(page.items.compactMap { $0 }) { song in
                        Button {
                            if let url = song.external_urls.spotify, url.scheme == "https", url.host == "open.spotify.com" { openURL(url) }
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: song.album.images.last?.url) { image in image.resizable().scaledToFill() } placeholder: { WaveArtwork(size: 44) }
                                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(song.name).font(.subheadline.weight(.medium)).foregroundStyle(WaveTheme.ink)
                                    Text(song.artist).font(.caption).foregroundStyle(WaveTheme.secondary)
                                    Text(song.album.name).font(.caption2).foregroundStyle(WaveTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption)
                            }.padding(.vertical, 5)
                        }.listRowBackground(WaveTheme.surface)
                    }
                }
                HStack {
                    Button("Anterior") { Task { await search(at: max(0, offset - 10)) } }.disabled(loading || offset == 0)
                    Spacer()
                    Text("Página \(offset / 10 + 1)").font(.caption.monospacedDigit())
                    Spacer()
                    Button("Siguiente") { Task { await search(at: offset + 10) } }.disabled(loading || page.next == nil || offset >= 1000)
                }.listRowBackground(Color.clear)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(WaveTheme.background).navigationTitle("Spotify")
    }
    private func startSearch() {
        guard !loading else { return }
        searched = query; searchedMarket = market
        Task { await search(at: 0) }
    }
    @MainActor private func search(at position: Int) async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do { page = try await catalog.search(searched, api: WaveAPI(server: server), market: searchedMarket, offset: position); offset = position }
        catch { self.error = error.localizedDescription }
    }
}
