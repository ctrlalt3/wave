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
        List {
            Text(folder).font(.caption.monospaced()).foregroundStyle(WaveTheme.secondary).listRowBackground(Color.clear)
            NavigationLink { LocalTracksView(folder: folder, includeSubfolders: true, playlistTitle: folder) } label: {
                FolderRow(name: "Toda la carpeta", count: count)
            }.listRowBackground(WaveTheme.selected)
            Button { Task { await preferences.addFolder(folder, source: .local) } } label: {
                Label("Usar carpeta como playlist", systemImage: "text.badge.plus")
            }.disabled(!preferences.ready || preferences.saving).listRowBackground(WaveTheme.surface)
            if !children.isEmpty {
                Section("Subcarpetas") {
                    ForEach(children, id: \.self) { child in
                        NavigationLink { LocalFolderBrowser(folder: child) } label: {
                            FolderRow(name: child.split(separator: "/").last.map(String.init) ?? child, count: local.songs.filter { ($0.folder == child || $0.folder.hasPrefix(child + "/")) && !$0.hidden }.count)
                        }.listRowBackground(WaveTheme.surface)
                    }
                }
            }
            if local.songs.contains(where: { $0.folder == folder }) {
                Section("Canciones") {
                    NavigationLink { LocalTracksView(folder: folder) } label: {
                        FolderRow(name: "Canciones de esta carpeta", count: local.songs.filter { $0.folder == folder && !$0.hidden }.count)
                    }.listRowBackground(WaveTheme.surface)
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(WaveTheme.background)
            .navigationTitle(folder.split(separator: "/").last.map(String.init) ?? folder).navigationBarTitleDisplayMode(.inline)
    }
}
