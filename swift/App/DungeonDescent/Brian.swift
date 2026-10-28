import AVFoundation
import FirebaseAuth

/// brianSay: the Hunting Grounds narrator. Lines go through the game's own
/// narration service (Amazon Polly's Brian voice, the narrateHuntLine Cloud
/// Function), which needs a signed-in account. Without one, or if the
/// service fails, the line is spoken by VoiceOver instead. One line at a time.
@MainActor
final class Brian: NSObject, AVAudioPlayerDelegate {
    static let shared = Brian()
    private static let proxy = URL(string: "https://leonardo1212-109323203666.us-central1.run.app")!

    private var queue: [String] = []
    private var playing = false
    private var player: AVAudioPlayer?

    func say(_ text: String) {
        queue.append(text)
        if !playing { next() }
    }

    func stop() {
        queue = []
        player?.stop()
        player = nil
        playing = false
    }

    private func next() {
        guard !queue.isEmpty else { playing = false; return }
        playing = true
        let text = queue.removeFirst()
        Task {
            if let data = await fetch(text), AppSettings.effectsOn, let p = try? AVAudioPlayer(data: data) {
                p.delegate = self
                p.volume = Float(AppSettings.effectsVolume)
                player = p
                if p.play() { return }
            }
            // No account, no connection or no sound: VoiceOver reads it.
            Feedback.announce(text)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            next()
        }
    }

    private func fetch(_ text: String) async -> Data? {
        guard let user = Auth.auth().currentUser, let token = try? await user.getIDToken() else { return nil }
        var req = URLRequest(url: Self.proxy)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.next() }
    }
}
