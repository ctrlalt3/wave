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
    func remainingSongs(favorites: Set<String>) -> [PlaybackSong] {
        songs.filter { !favorites.contains($0.id) }
    }
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
                Text("Solo canciones sin Me gusta. Izquierda para pasar, derecha para guardar en los favoritos de tu playlist.")
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
                .environmentObject(preferences)
                .environmentObject(local)
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
                songs = local.songs(in: folder, recursive: true).map { local.playable($0) }
            }
            guard songs.contains(where: { !preferences.liked($0.id) }) else { throw WaveAPI.Failure(message: "No quedan canciones por descubrir en esta carpeta: todas las visibles están en Me gusta.") }
            session = DiscoverSession(folder: folder, songs: songs.filter { !preferences.liked($0.id) }.shuffled())
        } catch { self.error = error.localizedDescription }
    }
}

struct DiscoverFeed: View {
    let session: DiscoverSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var player: WavePlayer
    @EnvironmentObject private var preferences: LibraryPreferences
    @EnvironmentObject private var local: LocalLibrary
    @State private var relocating = false
    @State private var destinations: [String] = []
    @State private var destination = ""
    @State private var relocationNotice: String?
    @State private var relocationTask: Task<Void, Never>?
    @State private var index = 0
    @State private var drag = CGSize.zero
    @State private var saving = false
    @State private var error: String?
    @State private var saved = Set<String>()
    @State private var relocatedIDs = Set<String>()
    @State private var songs: [PlaybackSong]
    init(session: DiscoverSession) {
        self.session = session
        _songs = State(initialValue: session.songs)
    }
    private var song: PlaybackSong? { songs.indices.contains(index) ? songs[index] : nil }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    if let song {
                        WaveArtwork(size: geometry.size.width, artwork: song.mediaItem?.artwork, remoteURL: song.coverURL, audioURL: song.source == "local" ? song.url : nil, fillsSpace: true)
                            .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2).ignoresSafeArea()
                            .offset(x: reduceMotion ? 0 : max(-28, min(28, drag.width * 0.15)), y: reduceMotion ? 0 : max(-28, min(28, drag.height * 0.15)))
                        LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                        (drag.width > 0 ? Color.green : Color.red).opacity(abs(drag.width) > abs(drag.height) ? min(0.35, abs(drag.width) / 500) : 0).ignoresSafeArea().allowsHitTesting(false)
                        ViewThatFits(in: .vertical) {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Descubre").font(.title2.weight(.bold))
                                    Text(session.folder).font(.caption).lineLimit(1)
                                }
                                Spacer()
                                close
                            }.padding(.top, 20)
                            Spacer(minLength: 12)
                            if abs(drag.width) > 24 && abs(drag.width) > abs(drag.height) {
                                Label {
                                    Text(drag.width > 0 ? "GUARDAR" : "DESCARTAR")
                                } icon: {
                                    Image(systemName: drag.width > 0 ? "heart.fill" : "xmark")
                                        .foregroundStyle(drag.width > 0 ? Color.red : Color.white)
                                }
                                    .font(.title.weight(.bold)).padding(20)
                                    .background(drag.width > 0 ? Color.green.opacity(0.85) : Color.red.opacity(0.85), in: Capsule())
                                    .accessibilityHidden(true)
                            }
                            Spacer(minLength: 12)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(song.track.name).font(.title.weight(.bold)).lineLimit(3)
                                Text(song.track.artist).font(.headline).foregroundStyle(.white.opacity(0.85))
                                if preferences.liked(song.id) { Label("En Me gusta", systemImage: "heart.fill").font(.caption).foregroundStyle(.red) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            WaveformSeekBar(song: song, onArtwork: true)
                            HStack(spacing: 28) {
                                Button { player.seek(max(0, player.elapsed - 10)) } label: { Image(systemName: "gobackward.10").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("Retroceder 10 segundos")
                                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title).frame(width: 60, height: 60).background(.white.opacity(0.2), in: Circle()) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                                Button { player.seek(player.elapsed + 10) } label: { Image(systemName: "goforward.10").font(.title2).frame(width: 48, height: 48) }.accessibilityLabel("Adelantar 10 segundos")
                            }
                            if let message = error ?? player.error { Text(message).font(.caption).foregroundStyle(.white).padding(8).background(.red.opacity(0.7), in: RoundedRectangle(cornerRadius: 8)) }
                            HStack(spacing: 12) {
                                Button { advance() } label: { Label("Descartar", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 48) }.background(.black.opacity(0.45), in: Capsule())
                                Button { Task { await save(song) } } label: { Label(saving ? "Guardando…" : "Guardar", systemImage: "heart.fill").foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 48) }.modifier(WaveGlassPanel(radius: 24)).tint(.red)
                            }.disabled(saving)
                            Button { Task { await openRelocation() } } label: {
                                Label("Enviar a…", systemImage: "folder.badge.arrow.forward").frame(maxWidth: .infinity, minHeight: 44)
                            }.disabled(saving)
                            HStack {
                                Text("\(index + 1) / \(songs.count)").monospacedDigit()
                                Spacer()
                                Text("↑ Siguiente · ↓ Anterior")
                            }.font(.caption).foregroundStyle(.white.opacity(0.8))
                        }.padding(.horizontal, 22).padding(.bottom, 24).foregroundStyle(.white).buttonStyle(.plain)
                            compactControls(song)
                        }
                    } else {
                        VStack(spacing: 20) {
                            HStack { Text("Descubre").font(.title2.weight(.bold)); Spacer(); close }
                            Spacer()
                            WaveMessage(title: "Has recorrido esta playlist.", detail: "\(saved.count) canciones guardadas en Me gusta.")
                            if !songs.isEmpty {
                                Button("Volver a descubrir") { index = 0 }.buttonStyle(.borderedProminent)
                            }
                            Button("Volver a la biblioteca") { dismiss() }
                            Spacer()
                        }.padding(22)
                    }
                }.contentShape(Rectangle()).gesture(swipe)
                    .accessibilityAction(named: "Descartar") { advance() }
                    .accessibilityAction(named: "Guardar en Me gusta") { if let song { Task { await save(song) } } }
            }.overlay(alignment: .top) {
                if let relocationNotice {
                    HStack {
                        Text(relocationNotice).font(.caption)
                        Button { self.relocationNotice = nil; relocationTask?.cancel() } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Ocultar aviso")
                    }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding()
                }
            }.sheet(isPresented: $relocating) {
                NavigationStack {
                    Form {
                        Picker("Dónde enviar la canción", selection: $destination) {
                            ForEach(destinations, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.wheel)
                        Button("Enviar canción") { Task { await relocateCurrent() } }.disabled(saving || destination.isEmpty)
                        if let error { Text(error).foregroundStyle(.red) }
                    }.navigationTitle("Enviar a…")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { relocating = false } } }
                }.presentationDetents([.medium, .large])
            }.background(WaveTheme.background).toolbar(.hidden, for: .navigationBar)
                .task(id: song?.id) { playCurrent() }
                .onChange(of: preferences.state.favorites) { _, favorites in
                    updateSongs(favorites: favorites)
                }
        }
    }
    @MainActor private func openRelocation() async {
        guard !saving, let song else { return }
        error = nil
        do {
            if let base = song.serverBase {
                let manifest: CloudManifest = try await WaveAPI(server: base.absoluteString).get(["api", "cloud", "manifest"])
                var folders = Set<String>()
                for track in manifest.tracks {
                    let parts = track.path.split(separator: "/").dropLast()
                    for length in 1...max(1, parts.count) where length <= parts.count { folders.insert(parts.prefix(length).joined(separator: "/")) }
                }
                destinations = folders.sorted()
            } else { destinations = LocalSong.playlistFolders(for: local.songs) }
            destination = destinations.first ?? ""; relocating = true
        } catch { self.error = error.localizedDescription }
    }
    @MainActor private func relocateCurrent() async {
        guard !saving, let song, !destination.isEmpty else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            if let base = song.serverBase {
                struct Result: Decodable { let path: String }
                let api = try WaveAPI(server: base.absoluteString)
                let result: Result = try await api.cloudRequest(["api", "cloud", "relocate"], body: ["track": song.track.relPath, "folder": destination])
                if song.source == "local" { try await local.relocate(song, folder: destination, cloudPath: result.path) }
                await preferences.synchronizeServer(api)
            } else { try await local.relocate(song, folder: destination) }
            relocating = false
            relocationNotice = "Canción enviada a " + destination
            relocationTask?.cancel()
            relocationTask = Task { try? await Task.sleep(for: .seconds(15)); if !Task.isCancelled { relocationNotice = nil } }
            relocatedIDs.insert(song.id)
            songs.removeAll { $0.id == song.id }; index = min(index, songs.count)
            playCurrent()
        } catch { self.error = error.localizedDescription }
    }
    private func updateSongs(favorites: Set<String>) {
        let currentID = song?.id
        let remaining = session.remainingSongs(favorites: favorites).filter { !relocatedIDs.contains($0.id) }
        if let currentID, let position = remaining.firstIndex(where: { $0.id == currentID }) {
            index = position
        } else { index = min(index, remaining.count) }
        songs = remaining
    }
    private func compactControls(_ song: PlaybackSong) -> some View {
        VStack(spacing: 8) {
            Button { Task { await openRelocation() } } label: { Label("Enviar a…", systemImage: "folder.badge.arrow.forward").frame(minHeight: 44) }.disabled(saving)
            HStack {
                Text(abs(drag.width) > 40 && abs(drag.width) > abs(drag.height) ? (drag.width > 0 ? "GUARDAR" : "DESCARTAR") : "Descubre").font(.headline)
                Spacer()
                Text("\(index + 1) / \(songs.count)").font(.caption.monospacedDigit())
                close
            }
            HStack { Text(song.track.name).font(.headline).lineLimit(1); Spacer(); Text(song.track.artist).font(.caption).lineLimit(1) }
            WaveformSeekBar(song: song, onArtwork: true)
            HStack {
                Button { player.seek(max(0, player.elapsed - 10)) } label: { Image(systemName: "gobackward.10").frame(width: 44, height: 44) }.accessibilityLabel("Retroceder 10 segundos")
                Spacer()
                Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44) }.accessibilityLabel(player.playing ? "Pausar" : "Reproducir")
                Spacer()
                Button { player.seek(player.elapsed + 10) } label: { Image(systemName: "goforward.10").frame(width: 44, height: 44) }.accessibilityLabel("Adelantar 10 segundos")
                Spacer()
                Button { advance() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.disabled(saving).accessibilityLabel("Descartar")
                Spacer()
                Button { Task { await save(song) } } label: { Image(systemName: "heart.fill").foregroundStyle(.red).frame(width: 48, height: 56).contentShape(Rectangle()) }.disabled(saving).accessibilityLabel("Guardar en Me gusta")
            }.font(.title2)
            if let message = error ?? player.error { Text(message).font(.caption).lineLimit(2) }
        }.padding(.horizontal, 22).padding(.vertical, 12).foregroundStyle(.white).buttonStyle(.plain)
    }

    private var close: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").frame(width: 44, height: 44)
                .foregroundStyle(song == nil ? WaveTheme.ink : Color.white)
                .background(song == nil ? WaveTheme.selected : Color.black.opacity(0.4), in: Circle())
        }.accessibilityLabel("Cerrar Descubre")
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
        if index < songs.count { index += 1 }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    @MainActor private func save(_ song: PlaybackSong) async {
        guard !saving else { return }
        saving = true; error = nil
        let success = await preferences.saveLike(song)
        saving = false
        if success {
            saved.insert(song.id)
            updateSongs(favorites: preferences.state.favorites)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // The shared favorites update removes this song from the feed.
            // Keep the index so the next unsaved song is not skipped.
        } else { error = preferences.error ?? "No se pudo guardar. Vuelve a intentarlo." }
    }
    private func playCurrent() {
        if let song { player.play(song, queue: [song]) }
        else { player.pause() }
    }
}
