import AVFoundation
import DungeonCore

/// What the game asks for: music by track name, ambience by key, sound effects
/// by id. The audio files are the web version's own (www/audio), bundled as
/// the "audio" folder.
@MainActor
enum Sound {
    static func track(_ name: String) { AudioEngine.shared.playTrack(name) }
    static func ambient(_ key: String?) { AudioEngine.shared.playAmbient(key) }
    static func sfx(_ id: String) { AudioEngine.shared.playEffect(id) }
    static func settingsChanged() { AudioEngine.shared.applySettings() }
}

@MainActor
final class AudioEngine {
    static let shared = AudioEngine()

    private var music: AVAudioPlayer?
    private var musicName: String?
    private var ambient: AVAudioPlayer?
    private var ambientKey: String?
    private var effects: [String: AVAudioPlayer] = [:]

    private init() {
        // Same session as the web version's AudioSessionPlugin: keeps playing with
        // the silent switch on (the game needs sound), and mixes with other audio
        // so VoiceOver's speech isn't fighting it.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func url(_ file: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "audio")
    }

    func playTrack(_ name: String) {
        guard AppSettings.musicOn else { musicName = name; return }
        if name == musicName, music?.isPlaying == true { return }
        musicName = name
        guard let file = Soundtrack.file(forTrack: name), let u = url(file),
              let next = try? AVAudioPlayer(contentsOf: u) else { return }
        fadeOut(music)
        next.numberOfLoops = -1
        next.volume = 0
        next.play()
        next.setVolume(Float(AppSettings.musicVolume), fadeDuration: 0.8)
        music = next
    }

    func playAmbient(_ key: String?) {
        guard let key, AppSettings.ambientOn else {
            fadeOut(ambient)
            ambient = nil
            ambientKey = key
            return
        }
        if key == ambientKey, ambient?.isPlaying == true { return }
        ambientKey = key
        guard let file = Soundtrack.file(forAmbient: key), let u = url(file),
              let next = try? AVAudioPlayer(contentsOf: u) else { return }
        fadeOut(ambient)
        next.numberOfLoops = -1
        next.volume = 0
        next.play()
        next.setVolume(Float(AppSettings.ambientVolume), fadeDuration: 1.2)
        ambient = next
    }

    func playEffect(_ id: String) {
        guard AppSettings.effectsOn else { return }
        let player: AVAudioPlayer
        if let p = effects[id] {
            player = p
        } else {
            guard let u = url("\(id).mp3") ?? url("\(id).wav"),
                  let p = try? AVAudioPlayer(contentsOf: u) else { return }
            p.prepareToPlay()
            effects[id] = p
            player = p
        }
        player.volume = Float(AppSettings.effectsVolume)
        player.currentTime = 0
        player.play()
    }

    /// Called when audio settings change: starts or stops music and ambience, and sets volumes.
    func applySettings() {
        if AppSettings.musicOn {
            music?.volume = Float(AppSettings.musicVolume)
            if music?.isPlaying != true, let name = musicName {
                musicName = nil
                playTrack(name)
            }
        } else {
            fadeOut(music)
            music = nil
        }
        if AppSettings.ambientOn {
            ambient?.volume = Float(AppSettings.ambientVolume)
            if ambient?.isPlaying != true, let key = ambientKey {
                ambientKey = nil
                playAmbient(key)
            }
        } else {
            fadeOut(ambient)
            ambient = nil
        }
    }

    private func fadeOut(_ player: AVAudioPlayer?) {
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { player.stop() }
    }
}
