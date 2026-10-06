import SwiftUI
import AVFoundation
import AudioToolbox
import CoreMedia
import CryptoKit

actor WaveformCache {
    static let shared = WaveformCache()
    private var memory: [URL: [Double]] = [:]
    func samples(for url: URL) async -> [Double]? {
        if let samples = memory[url] { return samples }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Waveforms", isDirectory: true)
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(key + ".json")
        if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < 86_400,
           let data = try? Data(contentsOf: file), let values = try? JSONDecoder().decode([Double].self, from: data), !values.isEmpty {
            memory[url] = values; return values
        }
        let task = Task.detached(priority: .utility) { await WaveformAnalyzer.read(url) }
        let values = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if let values, !Task.isCancelled {
            if memory.count > 32 { memory.removeAll() }
            memory[url] = values
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(values) { try? data.write(to: file, options: .atomic) }
        }
        return values
    }
}

enum WaveformAnalyzer {
    static func read(_ source: URL) async -> [Double]? {
        var temporary: URL?
        defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
        do {
            let url: URL
            if source.isFileURL { url = source }
            else {
                let (download, response) = try await URLSession.shared.download(from: source)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    try? FileManager.default.removeItem(at: download); return nil
                }
                let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension.isEmpty ? "mp3" : source.pathExtension)
                try FileManager.default.moveItem(at: download, to: target)
                temporary = target; url = target
            }
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
            let reader = try AVAssetReader(asset: asset)
            let rate = 12_000.0
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading() else { return nil }
            var peaks = [Double](repeating: 0, count: 160)
            while let sample = output.copyNextSampleBuffer() {
                if Task.isCancelled { reader.cancelReading(); return nil }
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let length = CMBlockBufferGetDataLength(block)
                guard length > 0, length % MemoryLayout<Float>.size == 0 else { continue }
                var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
                let status = floats.withUnsafeMutableBytes { bytes -> OSStatus in
                    guard let pointer = bytes.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: pointer)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard start.isFinite else { continue }
                for i in stride(from: 0, to: floats.count, by: 3) {
                    let position = start + Double(i) / rate
                    let fraction = min(1, max(0, position / duration))
                    let bin = min(peaks.count - 1, Int(fraction * Double(peaks.count)))
                    if floats[i].isFinite { peaks[bin] = max(peaks[bin], Double(abs(floats[i]))) }
                }
            }
            guard reader.status == .completed else { return nil }
            let maximum = peaks.max() ?? 0
            return maximum > 0 ? peaks.map { pow($0 / maximum, 0.55) } : peaks
        } catch { return nil }
    }
}

struct WaveformSeekBar: View {
    let song: PlaybackSong
    var onArtwork = false
    @EnvironmentObject private var player: WavePlayer
    @State private var samples: [Double] = []
    @State private var loading = true
    @State private var dragTime: Double?
    private var duration: Double { max(0, max(player.duration, song.track.duration)) }
    private var position: Double { dragTime ?? player.elapsed }
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                Canvas { context, size in
                    let values = samples.isEmpty ? [Double](repeating: 0.02, count: 160) : samples
                    let width = size.width / CGFloat(values.count)
                    let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
                    for (index, value) in values.enumerated() {
                        let height = max(3, CGFloat(value) * size.height)
                        let rect = CGRect(x: CGFloat(index) * width, y: (size.height - height) / 2, width: max(1, width - 1.2), height: height)
                        let path = RoundedRectangle(cornerRadius: 1).path(in: rect)
                        let played = Double(index) / Double(values.count) <= fraction
                        context.fill(path, with: .color(played ? (onArtwork ? .white : WaveTheme.accent) : (onArtwork ? .white.opacity(0.35) : WaveTheme.secondary.opacity(0.25))))
                    }
                }.contentShape(Rectangle())
                    .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard duration > 0 else { return }
                        dragTime = min(1, max(0, value.location.x / max(1, geometry.size.width))) * duration
                    }.onEnded { _ in
                        if let dragTime { player.seek(dragTime) }
                        dragTime = nil
                    })
                    .accessibilityElement().accessibilityLabel("Posición de reproducción")
                    .accessibilityValue(WaveTheme.time(position) + " de " + WaveTheme.time(duration))
                    .accessibilityAdjustableAction { direction in
                        player.seek(player.elapsed + (direction == .increment ? 10 : -10))
                    }
            }.frame(height: 52)
            HStack {
                Text(WaveTheme.time(position))
                Spacer()
                if samples.isEmpty { Text(loading ? "Cargando onda…" : "Barra de progreso") }
                Spacer()
                Text(WaveTheme.time(duration))
            }.font(.caption.monospacedDigit()).foregroundStyle(onArtwork ? Color.white.opacity(0.9) : WaveTheme.secondary)
        }
        .task(id: song.id) {
            samples = []; loading = true; dragTime = nil
            guard let url = song.url else { loading = false; return }
            let result = await WaveformCache.shared.samples(for: url)
            guard !Task.isCancelled else { return }
            samples = result ?? []; loading = false
        }
    }
}
