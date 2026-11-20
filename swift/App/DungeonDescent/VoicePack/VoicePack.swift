import Foundation
import AVFoundation
import CryptoKit
import SwiftUI
#if canImport(KokoroSwift) && os(iOS) && !targetEnvironment(macCatalyst)
import KokoroSwift
import MLX
#endif

/// 12.0 THE LEWIS VOICE PACK: Kokoro running on the iPhone itself, so Lewis
/// can say anything (numbers, names, every announcement), not only the
/// Hunting Grounds' recorded lines. The model (Kokoro-82M, Apache 2.0, 327 MB)
/// is downloaded once from Hugging Face when the player asks for it, checked
/// against its SHA-256, and kept in Application Support. Lewis's voice
/// (bm_lewis.voice, 510 × 256 floats) ships with the app. English only:
/// in Portuguese the game keeps VoiceOver (and Alex's recordings in the hunt).
/// iPhone only (iOS 18): the engine (KokoroSwift, MLX) isn't built for the
/// Mac or Apple Vision Pro versions.
@MainActor
final class VoicePack: NSObject, ObservableObject {
    static let shared = VoicePack()

    /// Pinned to one revision of the model repository, so the file never changes under us.
    nonisolated static let modelURL = URL(string: "https://huggingface.co/prince-canuma/Kokoro-82M/resolve/e02c9eada7ce7416798af36b190a8a2dd2ecd566/kokoro-v1_0.safetensors")!
    nonisolated static let modelSHA256 = "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"
    nonisolated static let modelBytes: Int64 = 327_115_152
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
        }
    }

    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var lastAnnounced = 0

    nonisolated static var supported: Bool {
        #if canImport(KokoroSwift) && os(iOS) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// 12.0: the Voice Pack is still being tested, so it only shows in
    /// TestFlight builds (their receipt is the sandbox one); App Store players
    /// don't see it until it's proven (12.1).
    nonisolated static var available: Bool {
        supported && Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    nonisolated static var modelFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("VoicePack", isDirectory: true)
        return dir.appendingPathComponent("kokoro-v1_0.safetensors")
    }

    /// Set while Lewis is making speech; still set at launch means the game
    /// died doing it last time, so Lewis is turned off rather than crash again.
    nonisolated static let busyKey = "swift_voice_busy"

    override init() {
        super.init()
        refresh()
        if UserDefaults.standard.bool(forKey: Self.busyKey) {
            UserDefaults.standard.set(false, forKey: Self.busyKey)
            narrate = false
            notice = "Lewis stopped the game last time, so he's turned off. Turn him on again to retry, or delete the Voice Pack."

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
        Feedback.announce("Downloading the Lewis Voice Pack, 327 megabytes. You can keep playing.")
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
        Feedback.announce("Lewis Voice Pack deleted. 327 megabytes freed.")
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
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    /// Bumped to drop sentences still waiting (a newer line replaces them).
    private var generation = 0
    private var pending = 0
    private var started = false

    #if canImport(KokoroSwift) && os(iOS) && !targetEnvironment(macCatalyst)
    nonisolated(unsafe) private var tts: KokoroTTS?
    nonisolated(unsafe) private var voice: MLXArray?
    #endif

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func start() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }

    /// Says `text`. `latest`: drop what hasn't been said yet and say this now.
    func speak(_ text: String, latest: Bool = false, test: Bool = false) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
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
                    VoicePack.shared.report = (samples == nil ? "Lewis couldn't speak: " : "Lewis made ") + report + "."
                    guard gen == self.generation else { return }
                    guard let samples, !samples.isEmpty else {
                        Announcer.shared.say(test ? "Lewis couldn't speak: \(report)." : p, latest: false)
                        return
                    }
                    self.play(samples, volume: vol)
                    if test {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(samples.count) / 24000 + 0.5) {
                            Announcer.shared.say("Lewis made \(report).", latest: false)
                        }
                    }
                }
            }
        }
    }

    func stop() {
        generation += 1
        player.stop()
    }

    /// Frees the model's memory (about 330 MB) when Lewis is turned off.
    func unload() {
        worker.run {
            #if canImport(KokoroSwift) && os(iOS) && !targetEnvironment(macCatalyst)
            self.tts = nil
            self.voice = nil
            MLX.Memory.clearCache()
            #endif
        }
    }

    private func play(_ samples: [Float], volume: Float) {
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let ch = buf.floatChannelData else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ch[0].update(from: $0.baseAddress!, count: samples.count) }
        start()
        player.volume = volume
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// One sentence of speech (24 kHz), made on the voice thread, and a report
    /// of what happened (for Hear Lewis): the speech, or nil and why not.
    nonisolated private func render(_ text: String) -> ([Float]?, String) {
        #if canImport(KokoroSwift) && os(iOS) && !targetEnvironment(macCatalyst)
        let began = Date()
        if tts == nil {
            UserDefaults.standard.set(true, forKey: VoicePack.busyKey)
            UserDefaults.standard.synchronize()
            defer { UserDefaults.standard.set(false, forKey: VoicePack.busyKey) }
            let file = VoicePack.modelFile
            guard FileManager.default.fileExists(atPath: file.path) else { return (nil, "the Voice Pack file is missing; download it again") }
            guard let vurl = Bundle.main.url(forResource: "bm_lewis", withExtension: "voice"),
                  let data = try? Data(contentsOf: vurl) else { return (nil, "Lewis's voice file is missing from the app") }
            let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard floats.count == 510 * 256 else { return (nil, "Lewis's voice file is the wrong size, \(floats.count) numbers") }
            // Keep MLX's spare GPU memory small: the phone's memory is shared with the game.
            MLX.Memory.cacheLimit = 64 * 1024 * 1024
            voice = MLXArray(floats, [510, 1, 256])
            tts = KokoroTTS(modelPath: file, g2p: .misaki)
        }
        guard let tts, let voice else { return (nil, "the voice engine didn't start") }
        UserDefaults.standard.set(true, forKey: VoicePack.busyKey)
        UserDefaults.standard.synchronize()
        defer { UserDefaults.standard.set(false, forKey: VoicePack.busyKey) }
        let raw: [Float]
        do {
            raw = try tts.generateAudio(voice: voice, language: .enGB, text: text, speed: 1.0).0
        } catch {
            MLX.Memory.clearCache()
            return (nil, "the engine stopped with an error: \(String(describing: error).prefix(160))")
        }
        MLX.Memory.clearCache()
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
        return (samples, String(format: "%.1f seconds of speech in %.1f seconds, peak %.2f%@", secs, took, peak, peak > 1 ? ", turned down to normal level" : ""))
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
