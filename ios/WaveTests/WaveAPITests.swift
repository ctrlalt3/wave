import XCTest
@testable import Wave

final class WaveAPITests: XCTestCase {
    func testKeepsReverseProxyPrefixAndEncodesNames() throws {
        let api = try WaveAPI(server: "https://example.com/wave")
        XCTAssertEqual(api.url(["api", "folder", "Música #1", "tracks"]).absoluteString,
                       "https://example.com/wave/api/folder/M%C3%BAsica%20%231/tracks")
        let track = WaveTrack(name: "Song", artist: "Artist", duration: 10,
                              relPath: "Música #1/song?.mp3", filename: "song?.mp3")
        XCTAssertEqual(try api.audioURL(track).absoluteString,
                       "https://example.com/wave/music/M%C3%BAsica%20%231/song%3F.mp3")
    }

    func testRejectsTraversalAndUntrustedConfiguration() {
        for path in ["../song.mp3", "/song.mp3", "folder/../song.mp3", "folder\\song.mp3", "folder//song.mp3"] {
            XCTAssertFalse(WaveAPI.safePath(path))
        }
        for server in ["http://example.com", "https://user:password@example.com", "https://example.com/?redirect=1"] {
            XCTAssertThrowsError(try WaveAPI(server: server))
        }
    }

    func testDecodesExistingServerContract() throws {
        let data = Data(#"[{"name":"Song","artist":"Artist","duration":2.5,"relPath":"folder/song.mp3","filename":"song.mp3","url":"/music/folder/song.mp3","play_count":3}]"#.utf8)
        let tracks = try JSONDecoder().decode([WaveTrack].self, from: data)
        XCTAssertEqual(tracks.first?.id, "folder/song.mp3")
    }

    func testArtworkKeepsServerPrefixAndRejectsForeignURLs() throws {
        let api = try WaveAPI(server: "https://example.com/wave/")
        XCTAssertEqual(api.artworkURL("/api/artwork/M%C3%BAsica/song%23.mp3")?.absoluteString,
                       "https://example.com/wave/api/artwork/M%C3%BAsica/song%23.mp3")
        for path in ["https://other.example/cover.png", "/api/artwork/../secret", "/api/artwork/%2e%2e/secret", "/api/artwork/song?redirect=1"] {
            XCTAssertNil(api.artworkURL(path))
        }
    }

    func testArtworkFallsBackToTrackPathWhenCoverIsMissing() throws {
        let api = try WaveAPI(server: "https://example.com/wave/")
        let track = WaveTrack(name: "Song", artist: "Artist", duration: 10,
                              relPath: "Música #1/song?.mp3", filename: "song?.mp3")
        XCTAssertEqual(api.artworkURL(for: track)?.absoluteString,
                       "https://example.com/wave/api/artwork/M%C3%BAsica%20%231/song%3F.mp3")
        var invalid = track
        invalid.coverUrl = "https://other.example/cover.png"
        XCTAssertNil(api.artworkURL(for: invalid))
        let traversal = WaveTrack(name: "Song", artist: "Artist", duration: 10,
                                  relPath: "../secret.mp3", filename: "secret.mp3")
        XCTAssertNil(api.artworkURL(for: traversal))
    }

    func testServerContentsIncludesHiddenForAdvancedAndAppliesOrder() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WaveFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = try WaveAPI(server: "https://example.com/wave/", session: session)
        let contents = try await api.contents(folder: "folder")
        XCTAssertEqual(contents.tracks.map(\.id), ["folder/b.mp3", "folder/a.mp3"])
        XCTAssertEqual(contents.state.hidden, ["folder/b.mp3"])
        let normal = try await api.tracks(folder: "folder")
        XCTAssertEqual(normal.map(\.id), ["folder/a.mp3"])
    }

    func testOrganizationPostsCorrectOperation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WaveFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = try WaveAPI(server: "https://example.com/wave/", session: session)
        let hidden = try await api.setHidden("folder/a.mp3", hidden: true)
        XCTAssertTrue(hidden.hidden.contains("folder/a.mp3"))
        let order = try await api.saveOrder(scope: "folder", paths: ["folder/a.mp3", "folder/b.mp3"])
        XCTAssertEqual(order.orders["folder"], ["folder/a.mp3", "folder/b.mp3"])
    }
}

private final class WaveFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let state: [String: Any] = ["hidden": ["folder/b.mp3"], "orders": ["folder": ["folder/b.mp3", "folder/a.mp3"]]]
        var responseValue: Any = state
        if request.httpMethod == "POST" {
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                var data = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                body = data
            }
            let operation = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any]
            if operation?["action"] as? String == "hidden", operation?["hidden"] as? Bool == true {
                responseValue = ["hidden": operation?["paths"] as? [String] ?? [], "orders": [:]] as [String: Any]
            } else if operation?["action"] as? String == "order", let scope = operation?["scope"] as? String {
                responseValue = ["hidden": [], "orders": [scope: operation?["paths"] as? [String] ?? []]] as [String: Any]
            } else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        } else if url.path == "/wave/api/folder/folder/tracks" {
            responseValue = [
                ["name": "A", "artist": "Artist", "duration": 1, "relPath": "folder/a.mp3", "filename": "a.mp3"],
                ["name": "B", "artist": "Artist", "duration": 2, "relPath": "folder/b.mp3", "filename": "b.mp3"]
            ] as [[String: Any]]
        } else if url.path != "/wave/api/desktop/state" {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]),
              let data = try? JSONSerialization.data(withJSONObject: responseValue) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
