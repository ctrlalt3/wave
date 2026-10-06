import Foundation
import XCTest
@testable import Wave

final class WidgetBrowserTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func songs(count: Int, folder: String = "Music/Album") -> [WaveWidgetBrowserItem] {
        (0..<count).map { WaveWidgetBrowserItem(id: "song-\($0)", title: String(format: "Song %02d", $0), subtitle: "Artist", kind: .song, playbackID: "local:song-\($0)", folderPath: folder) }
    }
    func testLocalHierarchyAndPagingAcrossStoredChunks() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.publishLocal(songs(count: 20), folders: ["Music/Album"])
        let top = await service.snapshot()
        XCTAssertEqual(top.items.map(\.id), ["Music"])
        let music = await service.navigate(.folder, item: "Music", revision: top.state.revision)
        XCTAssertEqual(music.items.map(\.id), ["Music/Album"])
        let album = await service.navigate(.folder, item: "Music/Album", revision: music.state.revision)
        XCTAssertEqual(album.total, 20)
        XCTAssertEqual(album.items.map(\.id), (0..<6).map { "song-\($0)" })
        let second = await service.navigate(.nextPage, revision: album.state.revision, stride: 6)
        XCTAssertEqual(second.items.map(\.id), (6..<12).map { "song-\($0)" })
        let back = await service.navigate(.previousPage, revision: second.state.revision, stride: 6)
        XCTAssertEqual(back.state.offset, 0)
        let upper = await service.navigate(.up, revision: back.state.revision)
        XCTAssertEqual(upper.state.folder, "Music")
    }
    func testDockReadsLargerPagesAndCanOpenFoldersBeyondFirstSix() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.publishLocal(songs(count: 40), folders: ["Music/Album"])
        var page = await service.snapshot()
        page = await service.navigate(.folder, item: "Music", revision: page.state.revision, stride: 24)
        page = await service.navigate(.folder, item: "Music/Album", revision: page.state.revision, stride: 24)
        XCTAssertEqual(page.items.count, 24)
        XCTAssertEqual(page.items.last?.id, "song-23")
        page = await service.navigate(.nextPage, revision: page.state.revision, stride: 24)
        XCTAssertEqual(page.state.offset, 24)
        XCTAssertEqual(page.items.count, 16)
        page = await service.navigate(.previousPage, revision: page.state.revision, stride: 24)
        XCTAssertEqual(page.state.offset, 0)
        let manyFolders = (0..<12).map { WaveWidgetBrowserItem(id: "file-\($0)", title: "Song", subtitle: "Artist", kind: .song, folderPath: "Genre/Playlist\($0)") }
        try await service.publishLocal(manyFolders, folders: manyFolders.compactMap(\.folderPath))
        page = await service.snapshot(rows: 24)
        page = await service.navigate(.folder, item: "Genre", revision: page.state.revision, stride: 24)
        XCTAssertEqual(page.items.count, 12)
        let folder = try XCTUnwrap(page.items.last?.id)
        page = await service.navigate(.folder, item: folder, revision: page.state.revision, stride: 24)
        XCTAssertEqual(page.state.folder, folder)
        XCTAssertEqual(page.items.count, 1)
    }
    func testHomeReturnsToRootWithoutChangingSource() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.publishLocal(songs(count: 20), folders: ["Music/Album"])
        var page = await service.snapshot()
        page = await service.navigate(.folder, item: "Music", revision: page.state.revision)
        page = await service.navigate(.folder, item: "Music/Album", revision: page.state.revision)
        page = await service.navigate(.nextPage, revision: page.state.revision, stride: 6)
        page = await service.navigate(.home, revision: page.state.revision)
        XCTAssertEqual(page.state.source, .local)
        XCTAssertEqual(page.state.folder, "")
        XCTAssertEqual(page.state.offset, 0)
        XCTAssertEqual(page.items.map(\.id), ["Music"])
    }
    func testTwoBrowsersShareStateAndStaleButtonsCannotJumpTwice() async throws {
        let root = try temporaryRoot(), first = WaveWidgetBrowserService(root: root), second = WaveWidgetBrowserService(root: root)
        try await first.publishLocal(songs(count: 3), folders: ["Music/Album"])
        let old = await first.snapshot()
        let opened = await first.navigate(.folder, item: "Music", revision: old.state.revision)
        let stale = await second.navigate(.folder, item: "Music", revision: old.state.revision)
        XCTAssertEqual(stale.state, opened.state)
        let observed = await second.snapshot()
        XCTAssertEqual(observed.state.folder, "Music")
        XCTAssertEqual(observed.items.map(\.id), ["Music/Album"])
    }
    func testRemovedFolderReturnsBrowserToRootAndShrinkClampsPaging() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.publishLocal(songs(count: 20), folders: ["Music/Album"])
        var page = await service.snapshot()
        page = await service.navigate(.folder, item: "Music", revision: page.state.revision)
        page = await service.navigate(.folder, item: "Music/Album", revision: page.state.revision)
        for _ in 0..<3 { page = await service.navigate(.nextPage, revision: page.state.revision, stride: 6) }
        try await service.publishLocal(songs(count: 2), folders: ["Music/Album"])
        page = await service.snapshot()
        XCTAssertEqual(page.state.offset, 1)
        page = await service.navigate(.previousPage, revision: page.state.revision)
        XCTAssertEqual(page.state.offset, 0)
        try await service.publishLocal([], folders: [])
        page = await service.snapshot()
        XCTAssertEqual(page.state.folder, "")
        XCTAssertEqual(page.total, 0)
    }
    func testFolderNavigationRejectsTraversalAndUnknownChildren() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.publishLocal(songs(count: 2), folders: ["Music/Album"])
        let original = await service.snapshot()
        for item in ["../secret", "/secret", "Music/../Album", "Music/Album", "Unknown"] {
            let page = await service.navigate(.folder, item: item, revision: original.state.revision)
            XCTAssertEqual(page.state.folder, "")
        }
    }
    func testServerBrowsingUsesSavedHTTPSSubpathAndHidesHiddenTracks() async throws {
        let root = try temporaryRoot()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [WidgetBrowserFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = WaveWidgetBrowserService(root: root, session: session)
        try await service.configureServer("https://widget.example/wave/")
        var page = await service.navigate(.server)
        XCTAssertEqual(page.items.map(\.id), ["Remote"])
        page = await service.navigate(.folder, item: "Remote", revision: page.state.revision)
        XCTAssertEqual(page.items.map(\.id), ["Remote/song.mp3"])
        XCTAssertEqual(page.items.first?.playbackID, "https://widget.example/wave/Remote/song.mp3")
        XCTAssertEqual(page.serverID, WaveWidgetBrowserStorage.key("https://widget.example/wave/"))
    }
    func testOfflineServerPreservesCachedFolderAndCanRetryInWidget() async throws {
        let root = try temporaryRoot()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [WidgetBrowserFixture.self]
        let session = URLSession(configuration: config)
        let service = WaveWidgetBrowserService(root: root, session: session)
        try await service.configureServer("https://widget.example/wave/")
        try await service.publishLocal(songs(count: 2), folders: ["Music/Album"])
        var page = await service.navigate(.server)
        page = await service.navigate(.folder, item: "Remote", revision: page.state.revision)
        let offlineConfig = URLSessionConfiguration.ephemeral
        offlineConfig.protocolClasses = [WidgetBrowserFixture.self]
        offlineConfig.httpAdditionalHeaders = ["X-Wave-Offline": "true"]
        let offlineSession = URLSession(configuration: offlineConfig)
        defer { session.invalidateAndCancel(); offlineSession.invalidateAndCancel() }
        let offline = WaveWidgetBrowserService(root: root, session: offlineSession)
        page = await offline.navigate(.refresh, revision: page.state.revision)
        XCTAssertNotNil(page.message)
        XCTAssertEqual(page.items.map(\.id), ["Remote/song.mp3"])
        let local = await offline.navigate(.local, revision: page.state.revision)
        XCTAssertEqual(local.state.source, .local)
        XCTAssertEqual(local.items.map(\.id), ["Music"])
    }
    func testRejectsInsecureServerConfigurationWithoutNetwork() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.configureServer("http://insecure.example/")
        let page = await service.navigate(.server)
        XCTAssertNotNil(page.message)
        XCTAssertTrue(page.items.isEmpty)
    }
    func testSharedCatalogContainsMetadataAndNoPrivateAudioURLs() async throws {
        let root = try temporaryRoot(), service = WaveWidgetBrowserService(root: root)
        try await service.publishLocal(songs(count: 2), folders: ["Music/Album"])
        let data = try Data(contentsOf: root.appendingPathComponent("local-folders.json"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("file://"))
        XCTAssertFalse(text.contains("WaveMusic/"))
        XCTAssertFalse(text.contains("remoteURL"))
    }
}
private final class WidgetBrowserFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "widget.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if request.value(forHTTPHeaderField: "X-Wave-Offline") == "true" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let body: Any
        switch url.path {
        case "/wave/api/folders": body = [["name": "Remote", "count": 2]]
        case "/wave/api/folder/Remote/tracks": body = [
            ["relPath": "Remote/song.mp3", "name": "Song", "artist": "Artist"],
            ["relPath": "Remote/hidden.mp3", "name": "Hidden", "artist": "Artist"]
        ]
        case "/wave/api/desktop/state": body = ["hidden": ["Remote/hidden.mp3"]]
        default: body = ["error": "unexpected path"]
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
