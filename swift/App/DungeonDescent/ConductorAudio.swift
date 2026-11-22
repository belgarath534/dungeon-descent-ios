import AVFoundation
import DungeonCore

/// 12.1: The Conductor's lullaby. It isn't the normal music player, because
/// the song has to stop on any note, drag and go out of tune (slower and
/// lower, like a music box winding down), and pick up again where it stopped.
/// Far away it's Goodbye Lullaby; for the last steps, Witch's Dancing Doll.
@MainActor
final class ConductorAudio {
    static let shared = ConductorAudio()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let speed = AVAudioUnitVarispeed()
    private var file: AVAudioFile?
    private var song: String?
    /// Bumped each time a new song is scheduled, so an old song's end doesn't loop the new one.
    private var generation = 0
    private var tempo: Float = 1
    private var dragTimer: Timer?

    private init() {
        engine.attach(player)
        engine.attach(speed)
        engine.connect(player, to: speed, format: nil)
        engine.connect(speed, to: engine.mainMixerNode, format: nil)
    }

    /// Louder than nothing even with the music turned off in Settings: you
    /// can't play this room without hearing it.
    private var volume: Float {
        Float(AppSettings.musicOn ? max(0.35, AppSettings.musicVolume) : max(0.35, AppSettings.effectsVolume))
    }

    /// Start (or switch to) the far or near song. The same song picks up
    /// where it stopped.
    func play(near: Bool, tempo: Double) {
        self.tempo = Float(tempo)
        let name = near ? "conductor-near.mp3" : "conductor-far.mp3"
        if name != song {
            guard let u = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "audio"),
                  let f = try? AVAudioFile(forReading: u) else { return }
            player.stop()
            file = f
            song = name
            generation += 1
            schedule(generation)
        }
        if !engine.isRunning { try? engine.start() }
        player.volume = volume
        speed.rate = self.tempo
        player.play()
    }

    private func schedule(_ gen: Int) {
        guard let file else { return }
        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, gen == self.generation, self.song != nil else { return }
                self.schedule(gen)
            }
        }
    }

    /// The music box winds down: slower and flatter over `seconds`.
    func drag(seconds: Double) {
        dragTimer?.invalidate()
        let start = Date()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let p = min(1, Date().timeIntervalSince(start) / seconds)
                self.speed.rate = self.tempo * Float(1 - 0.45 * p)
                if p >= 1 { self.dragTimer?.invalidate() }
            }
        }
    }

    /// The fake-out: it catches itself and plays on.
    func recover() {
        dragTimer?.invalidate()
        speed.rate = tempo
    }

    /// Silence, right on the note it reached.
    func pause() {
        dragTimer?.invalidate()
        player.pause()
    }

    func stop() {
        dragTimer?.invalidate()
        generation += 1
        song = nil
        file = nil
        player.stop()
        engine.stop()
    }
}
