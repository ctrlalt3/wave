import SwiftUI
import UIKit

enum DiscoverSwipe: Equatable {
    case save, next, previous, none
    static func action(horizontal: CGFloat, vertical: CGFloat) -> DiscoverSwipe {
        if abs(horizontal) > abs(vertical) {
            if horizontal > 80 { return .save }
            if horizontal < -80 { return .next }
        } else {
            if vertical < -60 { return .next }
            if vertical > 60 { return .previous }
        }
        return .none
    }
}

struct DiscoverSession: Identifiable {
    let id = UUID()
    let folder: String
    let songs: [PlaybackSong]
}

struct DiscoverSection: View {
    var api: WaveAPI? = nil
    var serverFolders: [WaveFolder] = []
    @EnvironmentObject private var local: LocalLibrary
    @EnvironmentObject private var preferences: LibraryPreferences
    @State private var expanded = false
    @State private var selected = ""
    @State private var loading = false
    @State private var error: String?
    @State private var session: DiscoverSession?
    private var folders: [String] {
        if api != nil { return serverFolders.map(\.name) }
        return LocalSong.playlistFolders(for: local.songs.filter { !$0.hidden })
    }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Una canción cada vez. Izquierda para pasar, derecha para guardar en Me gusta.")
                    .font(.subheadline).foregroundStyle(WaveTheme.secondary)
                if folders.isEmpty {
                    Text("Añade una carpeta con música para empezar.").font(.caption).foregroundStyle(WaveTheme.secondary)
                } else {
                    Picker("Elige una carpeta", selection: $selected) {
                        ForEach(folders, id: \.self) { folder in
                            Text(folder).tag(folder)
                        }
                    }.pickerStyle(.wheel).frame(height: 140).clipped()
                        .sensoryFeedback(.selection, trigger: selected)
                        .accessibilityLabel("Carpeta para descubrir")
                    Button { Task { await open() } } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(loading ? "Preparando canciones…" : "Empezar a descubrir")
                            Spacer()
                            if loading { ProgressView() } else { Image(systemName: "arrow.right") }
                        }.font(.subheadline.weight(.semibold)).padding(16)
                            .background(WaveTheme.selected, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(loading || selected.isEmpty || !preferences.ready)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(.top, 16).padding(.bottom, 8)
        } label: {
            Label("Descubre", systemImage: "sparkles").font(.headline)
        }
        .task(id: folders) { if !folders.contains(selected) { selected = folders.first ?? "" } }
        .fullScreenCover(item: $session) { value in
            DiscoverFeed(session: value)
        }
    }
    @MainActor private func open() async {
        guard !loading, !selected.isEmpty else { return }
        loading = true; error = nil
        defer { loading = false }
        let folder = selected
        do {
            let songs: [PlaybackSong]
            if let api {
                let tracks = try await api.tracks(folder: folder)
                await preferences.synchronizeServer(api)
                songs = try tracks.map { try PlaybackSong.server($0, api: api) }
            } else {
                songs = local.songs.filter {
                    !$0.hidden && ($0.folder == folder || $0.folder.hasPrefix(folder + "/"))
                }.map { local.playable($0) }
            }
            guard !songs.isEmpty else { throw WaveAPI.Failure(message: "Esta carpeta no tiene canciones visibles.") }
            session = DiscoverSession(folder: folder, songs: songs.shuffled())
        } catch { self.error = error.localizedDescription }
    }
}

struct DiscoverFeed: View {
    let session: DiscoverSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var player: WavePlayer
    @EnvironmentObject private var preferences: LibraryPreferences
    @State private var index = 0
    @State private var drag = CGSize.zero
    @State private var saving = false
    @State private var error: String?
    @State private var saved = Set<String>()
    private var song: PlaybackSong? { session.songs.indices.contains(index) ? session.songs[index] : nil }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Descubre").font(.largeTitle.weight(.bold))
                            Text(session.folder).font(.subheadline).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }
                            .accessibilityLabel("Cerrar Descubre")
                    }.padding(.top, 20)
                    if let song {
                        ViewThatFits(in: .vertical) {
                            card(song, size: max(80, min(geometry.size.width - 80, geometry.size.height * 0.34)))
                            compactCard(song)
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(WaveTheme.surface, in: RoundedRectangle(cornerRadius: 28))
                            .overlay { RoundedRectangle(cornerRadius: 28).stroke(WaveTheme.border, lineWidth: 1) }
                            .offset(x: drag.width, y: drag.height * 0.18)
                            .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width / 35)))
                            .gesture(swipe)
                            .accessibilityAction(named: "Descartar") { advance() }
                            .accessibilityAction(named: "Guardar en Me gusta") { Task { await save(song) } }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        HStack(spacing: 16) {
                            Button { advance() } label: {
                                Label("Descartar", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 52)
                            }.background(.thinMaterial, in: Capsule())
                            Button { Task { await save(song) } } label: {
                                Label(saving ? "Guardando…" : "Guardar", systemImage: "heart.fill").frame(maxWidth: .infinity, minHeight: 52)
                            }.foregroundStyle(.white).background(WaveTheme.accent, in: Capsule())
                        }.buttonStyle(.plain).disabled(saving)
                        HStack {
                            Text("\(index + 1) / \(session.songs.count)").monospacedDigit()
                            Spacer()
                            Text("Desliza hacia arriba para seguir")
                        }.font(.caption).foregroundStyle(WaveTheme.secondary)
                    } else {
                        Spacer()
                        WaveMessage(title: "Has recorrido esta playlist.", detail: "\(saved.count) canciones guardadas en Me gusta.")
                        Button("Volver a descubrir") { index = 0 }.buttonStyle(.borderedProminent)
                        Button("Volver a la biblioteca") { dismiss() }
                        Spacer()
                    }
                }.padding(.horizontal, 22).padding(.bottom, 24)
            }.background(WaveTheme.background).toolbar(.hidden, for: .navigationBar)
                .task { playCurrent() }
                .onChange(of: index) { _, _ in playCurrent() }
        }
    }
    private func card(_ song: PlaybackSong, size: CGFloat) -> some View {
        VStack(spacing: 18) {
            HStack {
                Label(drag.width > 0 ? "Guardar" : "Descartar", systemImage: drag.width > 0 ? "heart.fill" : "xmark")
                    .font(.headline).foregroundStyle(drag.width > 0 ? WaveTheme.accent : WaveTheme.secondary)
                    .opacity(min(1, abs(drag.width) / 65))
                Spacer()
                if preferences.liked(song.id) { Image(systemName: "heart.fill").foregroundStyle(WaveTheme.accent).accessibilityLabel("Ya está en Me gusta") }
            }
            WaveArtwork(size: size, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
            VStack(spacing: 8) {
                Text(song.track.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
                Text(song.track.artist).font(.subheadline).foregroundStyle(WaveTheme.secondary).lineLimit(2)
            }
            ProgressView(value: min(player.elapsed, max(player.duration, 1)), total: max(player.duration, 1)).tint(WaveTheme.accent)
            HStack {
                Text(WaveTheme.time(player.elapsed)).font(.caption.monospacedDigit())
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 52, height: 52)
                        .background(WaveTheme.selected, in: Circle())
                }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                Spacer()
                Text(WaveTheme.time(song.track.duration)).font(.caption.monospacedDigit())
            }.foregroundStyle(WaveTheme.secondary)
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
        }.padding(22)
    }
    private func compactCard(_ song: PlaybackSong) -> some View {
        HStack(spacing: 16) {
            WaveArtwork(size: 72, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil)
            VStack(alignment: .leading, spacing: 6) {
                Text(song.track.name).font(.headline).lineLimit(2)
                Text(song.track.artist).font(.caption).foregroundStyle(WaveTheme.secondary).lineLimit(1)
                if preferences.liked(song.id) { Label("En Me gusta", systemImage: "heart.fill").font(.caption).foregroundStyle(WaveTheme.accent) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
            }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
        }.padding(16)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !saving else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !saving else { return }
                let action = DiscoverSwipe.action(horizontal: value.translation.width, vertical: value.translation.height)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { drag = .zero }
                switch action {
                case .save:
                    if let song { Task { await save(song) } }
                case .next: advance()
                case .previous: if index > 0 { index -= 1 }
                case .none: break
                }
            }
    }
    private func advance() {
        guard !saving else { return }
        error = nil
        if index < session.songs.count { index += 1 }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    @MainActor private func save(_ song: PlaybackSong) async {
        guard !saving else { return }
        saving = true; error = nil
        let success = await preferences.saveLike(song)
        saving = false
        if success {
            saved.insert(song.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advance()
        } else { error = preferences.error ?? "No se pudo guardar. Vuelve a intentarlo." }
    }
    private func playCurrent() {
        if let song { player.play(song, queue: [song]) }
        else { player.pause() }
    }
}
