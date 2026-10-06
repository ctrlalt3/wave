import SwiftUI

struct LocalFolderBrowser: View {
    let folder: String
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var preferences: LibraryPreferences
    private var children: [String] {
        let prefix = folder + "/"
        return Array(Set(local.songs.compactMap { song -> String? in
            guard song.folder.hasPrefix(prefix), let component = song.folder.dropFirst(prefix.count).split(separator: "/").first else { return nil }
            return prefix + component
        })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var count: Int { local.songs.filter { ($0.folder == folder || $0.folder.hasPrefix(folder + "/")) && !$0.hidden }.count }
    var body: some View {
        LocalTracksView(folder: folder, playlistTitle: folder.split(separator: "/").last.map(String.init) ?? folder)
    }
}
