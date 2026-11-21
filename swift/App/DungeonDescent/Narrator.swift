import AVFoundation
import DungeonCore

/// 12.0: the Hunting Grounds narrator, recorded with Kokoro (Lewis in English,
/// Alex in Portuguese) and shipped in the game (audio/hunt/<en|pt>/<id>.mp3,
/// made by swift/tools/hunt-voice.py from hunt-lines.json). No account and no
/// connection needed. One line at a time; a line with no recording (or with
/// sound effects off) is read by VoiceOver instead. Replaces Brian, who
/// needed the narration server and a signed-in account.
@MainActor
final class Narrator: NSObject, AVAudioPlayerDelegate {
    static let shared = Narrator()

    /// Each line's id, by its English words, for text the old hunt builds.
    private static let ids: [String: String] = {
        var m: [String: String] = [:]
        for (id, l) in HuntLines.all { if let en = l["en"] { m[en] = id } }
        return m
    }()

    private var queue: [String] = []
    private var playing = false
    private var player: AVAudioPlayer?

    static var pt: Bool { Language.code.hasPrefix("pt") }

    /// The words of a line, in the game's language.
    static func text(_ id: String) -> String { HuntLines.text(id, pt: pt) }

    /// Speaks lines by id, in order.
    func say(ids: [String]) {
        queue += ids
        if !playing { next() }
    }

    /// Speaks English text: each sentence with a recording is spoken, the rest
    /// goes to VoiceOver ("text:" entries in the queue).
    func say(_ text: String) {
        if let id = Self.ids[text] { say(ids: [id]); return }
        var parts: [String] = []
        var cur = ""
        for w in text.split(separator: " ") {
            cur += (cur.isEmpty ? "" : " ") + w
            if let c = w.last, ".!?".contains(c) { parts.append(cur); cur = "" }
        }
        if !cur.isEmpty { parts.append(cur) }
        say(ids: parts.map { Self.ids[$0] ?? "text:" + $0 })
    }

    func stop() {
        queue = []
        player?.stop()
        player = nil
        playing = false
    }

    private func url(_ id: String) -> URL? {
        Bundle.main.url(forResource: id, withExtension: "mp3", subdirectory: "audio/hunt/\(Self.pt ? "pt" : "en")")
    }

    private func next() {
        guard !queue.isEmpty else { playing = false; return }
        playing = true
        let item = queue.removeFirst()
        if !item.hasPrefix("text:"), AppSettings.effectsOn, let u = url(item), let p = try? AVAudioPlayer(contentsOf: u) {
            p.delegate = self
            p.volume = Float(min(1, AppSettings.effectsVolume * 1.2))
            player = p
            if p.play() { return }
        }
        // No recording, or sound off: VoiceOver reads it.
        let words = item.hasPrefix("text:") ? Language.t(String(item.dropFirst(5))) : Self.text(item)
        Feedback.announce(words)
        DispatchQueue.main.asyncAfter(deadline: .now() + min(4, 0.9 + Double(words.count) * 0.055)) { [weak self] in self?.next() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.next()
        }
    }
}
