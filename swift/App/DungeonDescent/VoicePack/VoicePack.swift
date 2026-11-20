import Foundation
import AVFoundation
import CryptoKit
import SwiftUI
#if canImport(OnnxRuntimeC) && canImport(MisakiSwift) && os(iOS) && !targetEnvironment(macCatalyst)
import MisakiSwift
import MLX
#endif

/// 12.0 THE LEWIS VOICE PACK: Kokoro running on the iPhone itself, so Lewis
/// can say anything (numbers, names, every announcement), not only the
/// Hunting Grounds' recorded lines. The model (Kokoro-82M, Apache 2.0, 327 MB)
/// is downloaded once from Hugging Face when the player asks for it, checked
/// against its SHA-256, and kept in Application Support. Lewis's voice
/// (bm_lewis.voice, 510 × 256 floats) ships with the app. English only:
/// in Portuguese the game keeps VoiceOver (and Alex's recordings in the hunt).
/// iPhone only (iOS 18): the engine (ONNX Runtime, MisakiSwift) isn't built for the
/// Mac or Apple Vision Pro versions.
@MainActor
final class VoicePack: NSObject, ObservableObject {
    static let shared = VoicePack()

    /// Pinned to one revision of the model repository, so the file never changes under us.
    /// Kokoro v1.0 as ONNX (the model that recorded the Hunting Grounds lines),
    /// from kokoro-onnx's model release, checked against its SHA-256.
    nonisolated static let modelURL = URL(string: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx")!
    nonisolated static let modelSHA256 = "7d5df8ecf7d4b1878015a32686053fd0eebe2bc377234608764cc0ef3636a6c5"
    nonisolated static let modelBytes: Int64 = 325_532_387
    static let narrateKey = "swift_voice_narrate"

    enum State: Equatable {
        case unsupported, notDownloaded, downloading(Double), checking, ready, failed(String)
    }

    @Published private(set) var state: State = .notDownloaded
    /// Why Lewis was turned off on his own, for Settings.
    @Published var notice: String?
    /// What happened the last time Lewis tried to speak (shown under Hear Lewis).
    @Published var report: String?
    /// Lewis reads the game's announcements in place of VoiceOver's voice.
    @Published var narrate = UserDefaults.standard.bool(forKey: VoicePack.narrateKey) {
        didSet {
            UserDefaults.standard.set(narrate, forKey: Self.narrateKey)
            if !narrate { LiveVoice.shared.stop(); LiveVoice.shared.unload() }
            else if state == .ready { LiveVoice.shared.preload() }
        }
    }

    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var lastAnnounced = 0

    nonisolated static var supported: Bool {
        #if canImport(OnnxRuntimeC) && canImport(MisakiSwift) && os(iOS) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// Everyone on iPhone and iPad (it was TestFlight-only while it was tested).
    nonisolated static var available: Bool { supported }

    nonisolated static var modelFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoicePack", isDirectory: true)
        return dir.appendingPathComponent("kokoro-v1.0.onnx")
    }

    /// Set while Lewis is making speech; still set at launch means the game
    /// died doing it last time, so Lewis is turned off rather than crash again.
    nonisolated static let busyKey = "swift_voice_busy"

    override init() {
        super.init()
        // A build without the engine: a model downloaded by an earlier test
        // build would only take up 327 MB, so it goes.
        if !Self.supported, FileManager.default.fileExists(atPath: Self.modelFile.path) {
            try? FileManager.default.removeItem(at: Self.modelFile)
            narrate = false
        }
        // The MLX model of the earlier test builds (327 MB) isn't used any more.
        let old = Self.modelFile.deletingLastPathComponent().appendingPathComponent("kokoro-v1_0.safetensors")
        if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.removeItem(at: old) }
        refresh()
        // The test builds' crash guard: it also tripped when the game was
        // simply closed while Lewis was talking, and turned him off.
        UserDefaults.standard.removeObject(forKey: Self.busyKey)
        // Lewis on: load him in the background once the game is up.
        if narrate && state == .ready {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { LiveVoice.shared.preload() }
        }
    }

    func refresh() {
        if !Self.available { state = .unsupported; return }
        let size = (try? FileManager.default.attributesOfItem(atPath: Self.modelFile.path)[.size] as? Int64) ?? nil
        state = size == Self.modelBytes ? .ready : .notDownloaded
    }

    /// Whether Lewis speaks right now: the pack is in, the switch is on, and the game is in English.
    var speaking: Bool { state == .ready && narrate && !Language.code.hasPrefix("pt") }

    // MARK: Download

    func download() {
        guard Self.available, task == nil else { return }
        state = .downloading(0)
        lastAnnounced = 0
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        let t = s.downloadTask(with: Self.modelURL)
        task = t
        t.resume()
        Feedback.announce("Downloading the Lewis Voice Pack, 326 megabytes. You can keep playing.")
    }

    func cancel() {
        task?.cancel()
        task = nil
        refresh()
        Feedback.announce("Download cancelled.")
    }

    func delete() {
        LiveVoice.shared.unload()
        try? FileManager.default.removeItem(at: Self.modelFile)
        narrate = false
        refresh()
        Feedback.announce("Lewis Voice Pack deleted. 326 megabytes freed.")
    }

    /// Moves the download into place once its checksum matches.
    fileprivate func finished(_ tmp: URL) {
        state = .checking
        let dest = Self.modelFile
        Task.detached(priority: .userInitiated) {
            let ok = Self.sha256(of: tmp) == Self.modelSHA256
            if ok {
                var dir = dest.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: tmp, to: dest)
                var rv = URLResourceValues(); rv.isExcludedFromBackup = true
                try? dir.setResourceValues(rv)
            } else {
                try? FileManager.default.removeItem(at: tmp)
            }
            await MainActor.run {
                self.task = nil
                if ok {
                    self.refresh()
                    self.narrate = true
                    Feedback.announce("The Lewis Voice Pack is ready. Lewis will now read the game to you.")
                    LiveVoice.shared.speak("Hello. I'm Lewis. I'll be your narrator from now on.")
                } else {
                    self.state = .failed("The download was damaged. Please try again.")
                    Feedback.announce("The download was damaged. Please try again.")
                }
            }
        }
    }

    nonisolated static func sha256(of url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func progress(_ p: Double) {
        state = .downloading(p)
        let pct = Int(p * 100)
        if pct >= lastAnnounced + 25 && pct < 100 {
            lastAnnounced = pct - pct % 25
            Feedback.announce("Voice Pack \(lastAnnounced) percent.")
        }
    }

    fileprivate func failed(_ message: String) {
        task = nil
        state = .failed(message)
        Feedback.announce("The Voice Pack download stopped: \(message)")
    }
}

extension VoicePack: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears when this returns: keep it first.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("voicepack-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: keep)
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        Task { @MainActor in
            if status == 200 { self.finished(keep) } else { try? FileManager.default.removeItem(at: keep); self.failed("the server answered \(status).") }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : VoicePack.modelBytes
        let p = Double(totalBytesWritten) / Double(total)
        Task { @MainActor in self.progress(p) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor in self.failed(error.localizedDescription) }
    }
}

/// Lewis, live: turns text into speech on the iPhone, a sentence at a time,
/// and plays each sentence as soon as it's ready.
@MainActor
final class LiveVoice {
    static let shared = LiveVoice()

    /// Every bit of the model runs on this one thread: MLX keeps its streams per
    /// thread, and the model needs far more stack than a dispatch queue's 512 KB
    /// (the first Voice Pack build crashed as Lewis started to speak).
    private let worker = VoiceWorker()
    /// Lewis plays through AVAudioPlayer, like the recorded narrator (an
    /// AVAudioEngine of his own made speech no one heard), one clip at a time.
    private var queue: [(Data, Float)] = []
    private var player: AVAudioPlayer?
    private var playing = false
    /// Bumped to drop sentences still waiting (a newer line replaces them).
    private var generation = 0
    private var pending = 0
    private var started = false

    #if canImport(OnnxRuntimeC) && canImport(MisakiSwift) && os(iOS) && !targetEnvironment(macCatalyst)
    nonisolated(unsafe) private var session: OrtRunner?
    nonisolated(unsafe) private var g2p: EnglishG2P?
    /// Lewis's voice: 510 rows of 256, one per phoneme count.
    nonisolated(unsafe) private var voice: [Float] = []
    nonisolated(unsafe) private var vocab: [String: Int64] = [:]
    #endif

    private init() {}

    /// Loads the model in the background (when Lewis is turned on), so his
    /// first line doesn't wait for it.
    func preload() {
        worker.run { [weak self] in _ = self?.loadIfNeeded() }
    }

    /// Says `text`. `latest`: drop what hasn't been said yet and say this now.
    /// Lewis waits until the game has been open a few seconds: the crash
    /// report showed him starting 1.6 seconds after launch, while the first
    /// screen was still being drawn.
    private let openedAt = Date()

    func speak(_ text: String, latest: Bool = false, test: Bool = false) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard test || (Date().timeIntervalSince(openedAt) > 5 && UIApplication.shared.applicationState == .active) else {
            Announcer.shared.say(Language.t(clean), latest: latest)
            return
        }
        if latest { stop() }
        let gen = generation
        let parts = Self.sentences(clean)
        pending += parts.count
        let vol = Float(min(1, AppSettings.effectsVolume * 1.2))
        worker.run { [weak self] in
            for p in parts {
                guard let self else { return }
                let (samples, report) = self.render(p)
                DispatchQueue.main.async {
                    self.pending -= 1
                    // Shown in Settings only when something went wrong.
                    VoicePack.shared.report = samples == nil ? "Lewis couldn't speak: " + report + "." : nil
                    guard gen == self.generation else { return }
                    guard let samples, !samples.isEmpty else {
                        Announcer.shared.say(test ? "Lewis couldn't speak: \(report)." : p, latest: false)
                        return
                    }
                    self.play(samples, volume: vol)
                }
            }
        }
    }

    func stop() {
        generation += 1
        queue = []
        player?.stop()
        player = nil
        playing = false
    }

    /// Frees the model's memory (about 330 MB) when Lewis is turned off.
    func unload() {
        worker.run {
            #if canImport(OnnxRuntimeC) && canImport(MisakiSwift) && os(iOS) && !targetEnvironment(macCatalyst)
            self.session = nil
            self.g2p = nil
            MLX.GPU.clearCache()
            #endif
        }
    }

    private func play(_ samples: [Float], volume: Float) {
        queue.append((Self.wav(samples), volume))
        if !playing { next() }
    }

    private func next() {
        guard !queue.isEmpty else { playing = false; return }
        playing = true
        let (data, vol) = queue.removeFirst()
        guard let p = try? AVAudioPlayer(data: data) else { next(); return }
        p.volume = vol
        player = p
        p.play()
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + p.duration + 0.12) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.next()
        }
    }

    /// 16-bit mono WAV at 24 kHz.
    static func wav(_ samples: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(24000); u32(48000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices { pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }

    #if canImport(OnnxRuntimeC) && canImport(MisakiSwift) && os(iOS) && !targetEnvironment(macCatalyst)
    /// The model, Lewis's voice, the phoneme alphabet and the pronunciation
    /// engine, loaded once (on the voice thread); nil, or why not.
    nonisolated private func loadIfNeeded() -> String? {
        if session == nil {
            let file = VoicePack.modelFile
            guard FileManager.default.fileExists(atPath: file.path) else { return "the Voice Pack file is missing; download it again" }
            guard let vurl = Bundle.main.url(forResource: "bm_lewis", withExtension: "voice"),
                  let data = try? Data(contentsOf: vurl) else { return "Lewis's voice file is missing from the app" }
            let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard floats.count == 510 * 256 else { return "Lewis's voice file is the wrong size, \(floats.count) numbers" }
            guard let aurl = Bundle.main.url(forResource: "kokoro-vocab", withExtension: "json"),
                  let adata = try? Data(contentsOf: aurl),
                  let table = try? JSONDecoder().decode([String: Int64].self, from: adata) else { return "the phoneme alphabet is missing from the app" }
            // MisakiSwift's fallback for unknown words runs on MLX: the CPU
            // only (the iPhone's GPU rejected MLX's work and crashed the app).
            Device.setDefault(device: .cpu)
            MLX.GPU.set(cacheLimit: 0)
            do {
                session = try OrtRunner(modelPath: file.path,
                                        threads: Int32(max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))))
            } catch {
                return "the voice model didn't open: \(String(describing: error).prefix(160))"
            }
            voice = floats
            vocab = table
            g2p = Device.withDefaultDevice(.cpu) { EnglishG2P(british: true) }
        }
        return nil
    }
    #else
    nonisolated private func loadIfNeeded() -> String? { "the Voice Pack only runs on iPhone and iPad" }
    #endif

    /// One sentence of speech (24 kHz), made on the voice thread, and a report
    /// of what happened (for Hear Lewis): the speech, or nil and why not.
    nonisolated private func render(_ text: String) -> ([Float]?, String) {
        #if canImport(OnnxRuntimeC) && canImport(MisakiSwift) && os(iOS) && !targetEnvironment(macCatalyst)
        let loadStart = Date()
        if let problem = loadIfNeeded() { return (nil, problem) }
        let loaded = Date().timeIntervalSince(loadStart)
        let began = Date()
        guard let session, let g2p else { return (nil, "the voice engine didn't start") }
        // Text to phonemes (MisakiSwift), phonemes to Kokoro's numbers, one
        // symbol at a time (a combining accent is its own symbol).
        let phonemes = Device.withDefaultDevice(.cpu) { g2p.phonemize(text: text).0 }
        var tokens: [Int64] = phonemes.unicodeScalars.compactMap { vocab[String($0)] }
        if tokens.count > 510 { tokens = Array(tokens.prefix(510)) }
        guard !tokens.isEmpty else { return (nil, "no sounds to say for this line (phonemes: \(phonemes.prefix(40)))") }
        // Lewis's style for this many phonemes: row n - 1.
        let row = min(tokens.count, 510) - 1
        let style = Array(voice[(row * 256)..<(row * 256 + 256)])
        let raw: [Float]
        do {
            raw = try session.speak(ids: [0] + tokens + [0], style: style, speed: 1.0)
        } catch {
            MLX.GPU.clearCache()
            return (nil, "the engine stopped with an error: \(String(describing: error).prefix(160))")
        }
        MLX.GPU.clearCache()
        let took = Date().timeIntervalSince(began)
        guard !raw.isEmpty else { return (nil, "the engine made no sound at all") }
        let bad = raw.filter { !$0.isFinite }.count
        guard bad * 10 < raw.count else { return (nil, "the engine made broken sound, \(bad) of \(raw.count) samples invalid") }
        var samples = raw.map { $0.isFinite ? $0 : 0 }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0.0001 else { return (nil, "the engine made only silence") }
        // Speech louder than full scale: bring it down to normal speech level
        // instead of playing it distorted (the first build's "weird audio").
        if peak > 1 { let k = 0.9 / peak; samples = samples.map { $0 * k } }
        let secs = Double(samples.count) / 24000
        return (samples, String(format: "%.1f seconds of speech in %.1f seconds%@, peak %.2f%@", secs, took,
                                loaded > 0.5 ? String(format: " (plus %.1f seconds loading the voice)", loaded) : "",
                                peak, peak > 1 ? ", turned down to normal level" : ""))
        #else
        return (nil, "the Voice Pack only runs on iPhone and iPad")
        #endif
    }

    /// Sentences, with emoji and symbols the voice can't say taken out.
    nonisolated static func sentences(_ s: String) -> [String] {
        let spoken = String(s.unicodeScalars.filter { !$0.properties.isEmojiPresentation && !($0.properties.isEmoji && $0.value > 0x2000) })
        var out: [String] = []
        var cur = ""
        for w in spoken.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            cur += (cur.isEmpty ? "" : " ") + w
            if let c = w.last, ".!?".contains(c), cur.count > 12 { out.append(cur); cur = "" }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        // Very long sentences are split again: the model has a token limit.
        return out.flatMap { $0.count > 220 ? $0.split(separator: ",").map(String.init) : [$0] }
    }
}

/// One long-lived thread with a large stack that runs jobs in order.
final class VoiceWorker: Thread, @unchecked Sendable {
    private let cond = NSCondition()
    private var jobs: [() -> Void] = []

    override init() {
        super.init()
        name = "dd.livevoice"
        stackSize = 32 * 1024 * 1024
        qualityOfService = .userInitiated
        start()
    }

    func run(_ job: @escaping () -> Void) {
        cond.lock()
        jobs.append(job)
        cond.signal()
        cond.unlock()
    }

    override func main() {
        while true {
            cond.lock()
            while jobs.isEmpty { cond.wait() }
            let job = jobs.removeFirst()
            cond.unlock()
            autoreleasepool { job() }
        }
    }
}
