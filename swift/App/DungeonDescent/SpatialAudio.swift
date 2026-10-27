import AVFoundation
import DungeonCore

/// 3D Mode's sound: real 3D audio (HRTF, best with headphones) instead of the
/// web version's left-right panning. You always face north, like the
/// compass buttons: north is in front of you, south behind, east to your
/// right, west to your left. Everything here is mono sources placed around
/// the listener in an AVAudioEnvironmentNode, with a little room reverb.
@MainActor
final class SpatialAudio {
    static let shared = SpatialAudio()

    private let engine = AVAudioEngine()
    private let env = AVAudioEnvironmentNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var loop: AVAudioPlayerNode?
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    /// Door cues: pitched up ahead, down behind, so front and back are easy
    /// to tell apart even where HRTF alone is subtle (ROOM3D_DOOR_AUDIO).
    static func pitch(_ d: Compass) -> Double { d == .north ? 1.18 : d == .south ? 0.82 : 1 }

    private init() {
        engine.attach(env)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
        env.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        env.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        env.distanceAttenuationParameters.referenceDistance = 1
        env.distanceAttenuationParameters.maximumDistance = 40
        env.distanceAttenuationParameters.rolloffFactor = 1
        env.reverbParameters.enable = true
        env.reverbParameters.loadFactoryReverbPreset(.mediumChamber)
        env.reverbParameters.level = -8
        for _ in 0..<16 { voices.append(makeVoice()) }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.restart() }
        }
    }

    private func makeVoice() -> AVAudioPlayerNode {
        let p = AVAudioPlayerNode()
        engine.attach(p)
        engine.connect(p, to: env, format: format)
        p.renderingAlgorithm = .HRTFHQ
        p.reverbBlend = 0.3
        return p
    }

    private func restart() {
        if !engine.isRunning { try? engine.start() }
    }

    private func ready() -> Bool {
        guard AppSettings.effectsOn else { return false }
        env.outputVolume = Float(AppSettings.effectsVolume)
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return false }
        }
        return true
    }

    /// The room's reverb follows the dungeon: big echoing crypts, tight
    /// flooded archives.
    func setRoom(dungeon: String) {
        let preset: AVAudioUnitReverbPreset
        switch dungeon {
        case "Crypt of Malachar", "The Hollow": preset = .cathedral
        case "Frosthold Abyss", "The Infernal Descent": preset = .largeHall
        case "The Sunken Archives", "The Abyssal Deep": preset = .plate
        case "The Shadow World": preset = .largeHall2
        case "The Whispering Forest": preset = .mediumRoom
        default: preset = .mediumChamber
        }
        env.reverbParameters.loadFactoryReverbPreset(preset)
    }

    // MARK: Positions

    /// Where a direction is, `meters` away. -Z is in front of the listener.
    static func point(_ d: Compass, _ meters: Float) -> AVAudio3DPoint {
        AVAudio3DPoint(x: Float(d.dx) * meters, y: 0, z: Float(d.dy) * meters)
    }

    // MARK: Buffers

    /// A sound file as mono at 44.1 kHz, resampled for pitch.
    private func buffer(_ file: String, pitch: Double = 1) -> AVAudioPCMBuffer? {
        let key = "\(file)@\(pitch)"
        if let b = buffers[key] { return b }
        guard let url = Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "audio"),
              let f = try? AVAudioFile(forReading: url),
              let src = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: src)) != nil, let ch = src.floatChannelData else { return nil }
        let n = Int(src.frameLength)
        let channels = Int(src.format.channelCount)
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            for i in 0..<n { mono[i] += ch[c][i] / Float(channels) }
        }
        let step = src.format.sampleRate / format.sampleRate * pitch
        let out = resample(mono, step: step)
        let b = pcm(out)
        buffers[key] = b
        return b
    }

    private func resample(_ s: [Float], step: Double) -> [Float] {
        guard step != 1, !s.isEmpty else { return s }
        let count = Int(Double(s.count) / step)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Double(i) * step
            let a = Int(pos)
            let t = Float(pos - Double(a))
            let x0 = s[min(a, s.count - 1)], x1 = s[min(a + 1, s.count - 1)]
            out[i] = x0 + (x1 - x0) * t
        }
        return out
    }

    private func pcm(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))),
              let ch = b.floatChannelData else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { ch[0][i] = samples[i] }
        return b
    }

    enum Wave { case sine, square, sawtooth }

    /// _echoOsc: a short synth tone with a quick attack and an exponential fade.
    private func tone(_ wave: Wave, _ freq: Double, seconds: Double, peak: Float) -> AVAudioPCMBuffer? {
        let key = "tone-\(wave)-\(freq)-\(seconds)-\(peak)"
        if let b = buffers[key] { return b }
        let rate = format.sampleRate
        let n = Int(rate * (seconds + 0.05))
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let phase = (t * freq).truncatingRemainder(dividingBy: 1)
            let v: Double
            switch wave {
            case .sine: v = sin(2 * .pi * phase)
            case .square: v = phase < 0.5 ? 1 : -1
            case .sawtooth: v = 2 * phase - 1
            }
            let amp = t < 0.015 ? t / 0.015 : max(0, pow(0.0001, (t - 0.015) / max(0.01, seconds - 0.015)))
            s[i] = Float(v * amp) * peak
        }
        let b = pcm(s)
        buffers[key] = b
        return b
    }

    // MARK: Playing

    private func play(_ b: AVAudioPCMBuffer?, at p: AVAudio3DPoint, volume: Float = 1, delay: Double = 0) {
        guard let b, ready() else { return }
        let v = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        v.stop()
        v.position = p
        v.volume = volume
        v.scheduleBuffer(b, at: nil, options: [], completionHandler: nil)
        if delay > 0 {
            v.play(at: AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: delay)))
        } else {
            v.play()
        }
    }

    /// A sound file placed in the room.
    func sound(_ file: String, at p: AVAudio3DPoint, volume: Float = 1, pitch: Double = 1, delay: Double = 0) {
        play(buffer(file, pitch: pitch), at: p, volume: volume, delay: delay)
    }

    /// A game sound effect by id ("sfx-heavy-miss"), placed in the room.
    func effect(_ id: String, at p: AVAudio3DPoint, volume: Float = 1, delay: Double = 0) {
        let file = Bundle.main.url(forResource: "\(id).mp3", withExtension: nil, subdirectory: "audio") != nil ? "\(id).mp3" : "\(id).wav"
        sound(file, at: p, volume: volume, delay: delay)
    }

    // MARK: 3D Mode cues

    /// play3DExitCues: one blip from each open door, in turn. It waits for
    /// VoiceOver to finish the room announcement, which would bury it.
    func exitCues(_ cell: RoomGraph.Cell, after wait: Double = 1.8) {
        var i = 0.0
        for d in Compass.allCases where cell.has(d) {
            sound("sfx-hover.mp3", at: Self.point(d, 2), volume: 0.9, pitch: Self.pitch(d), delay: wait + i * 0.16)
            i += 1
        }
    }

    /// Bumping a wall: the thud comes from that wall.
    func wallBump(_ d: Compass) {
        effect("sfx-heavy-miss", at: Self.point(d, 1))
    }

    /// Walking through a door: footsteps going that way.
    func footsteps(_ d: Compass) {
        for i in 0..<3 {
            effect("sfx-footstep", at: Self.point(d, 0.6 + Float(i) * 0.7), volume: 0.8, delay: Double(i) * 0.28)
        }
    }

    /// An enemy's cry from the doorway you walked through: it's ahead of you
    /// in the room you just entered.
    func enemy(_ id: String, from d: Compass?) {
        effect(id, at: Self.point(d ?? .north, 3))
    }

    /// echoLocate: a ping, then each direction answers: a long fading tone
    /// down open corridors (longer the further they run), a sharp click off
    /// walls, and a hint of what waits in the next new room.
    func echo(_ e: RoomGraph.Echo) {
        let c = Self.point(.north, 0.01)
        play(tone(.sine, 300, seconds: 0.16, peak: 0.55), at: c)
        play(tone(.sine, 900, seconds: 0.12, peak: 0.35), at: c, delay: 0.05)
        for (i, d) in Compass.allCases.enumerated() {
            let delay = 0.22 + Double(i) * 0.11
            let pitch = Self.pitch(d)
            if let o = e.open.first(where: { $0.dir == d }) {
                let dur = 0.32 + Double(o.depth) * 0.14
                // The tone sits further out down a longer corridor.
                let p = Self.point(d, 2 + Float(o.depth) * 1.5)
                play(tone(.sine, 420 * pitch, seconds: dur, peak: 0.3), at: p, delay: delay)
                if o.depth >= 2 { play(tone(.sine, 420 * pitch, seconds: dur * 0.7, peak: 0.16), at: Self.point(d, 6), delay: delay + dur * 0.55) }
                if let a = o.ahead { ahead(a, at: Self.point(d, 4), delay: delay + 0.36) }
            } else {
                play(tone(.square, 950 * pitch, seconds: 0.07, peak: 0.22), at: Self.point(d, 1), delay: delay)
            }
        }
    }

    /// _echoAheadCue
    private func ahead(_ a: RoomGraph.Ahead, at p: AVAudio3DPoint, delay: Double) {
        switch a {
        case .danger:
            play(tone(.sawtooth, 85, seconds: 0.55, peak: 0.34), at: p, delay: delay)
            play(tone(.sawtooth, 110, seconds: 0.45, peak: 0.26), at: p, delay: delay + 0.08)
        case .good:
            play(tone(.sine, 1300, seconds: 0.18, peak: 0.24), at: p, delay: delay)
            play(tone(.sine, 1700, seconds: 0.2, peak: 0.24), at: p, delay: delay + 0.09)
        case .mystery:
            play(tone(.sine, 700, seconds: 0.3, peak: 0.22), at: p, delay: delay)
            play(tone(.sine, 735, seconds: 0.3, peak: 0.22), at: p, delay: delay)
        }
    }

    /// playDescentCue: a falling sweep as you go deeper.
    func descent() {
        let rate = format.sampleRate
        let n = Int(rate * 0.8)
        var s = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            let f = 520 * pow(110.0 / 520.0, min(1, t / 0.7))
            phase += f / rate
            let amp = t < 0.05 ? t / 0.05 : pow(0.0001, (t - 0.05) / 0.7)
            s[i] = Float(sin(2 * .pi * phase) * amp * 0.3)
        }
        play(pcm(s), at: Self.point(.south, 0.01))
    }

    // MARK: The Darkness Swallower

    /// Each square of the Stalker room is 1.5 meters: far off it's a faint
    /// growl across the room, right next to you it's in your ear.
    static func stalkerPoint(_ s: StalkerFloor) -> AVAudio3DPoint {
        AVAudio3DPoint(x: Float(s.ex - s.px) * 1.5, y: 0, z: Float(s.ey - s.py) * 1.5)
    }

    func stalkerStart(_ s: StalkerFloor) {
        stopStalker()
        guard let b = buffer("monster-growl.mp3"), ready() else { return }
        let p = makeVoice()
        p.position = Self.stalkerPoint(s)
        p.reverbBlend = 0.45
        p.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
        p.play()
        loop = p
    }

    /// It moved: the growl follows it, and its footstep lands where it is.
    func stalkerStep(_ s: StalkerFloor) {
        let p = Self.stalkerPoint(s)
        loop?.position = p
        sound("monster-footstep.mp3", at: p)
    }

    func stopStalker() {
        guard let l = loop else { return }
        l.stop()
        engine.detach(l)
        loop = nil
    }

    func caught() {
        stopStalker()
        sound("jump-scare-v3.mp3", at: Self.point(.north, 0.3))
    }
}
