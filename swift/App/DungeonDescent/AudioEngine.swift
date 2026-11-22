import AVFoundation
import UIKit
import DungeonCore

/// What the game asks for: music by track name, ambience by key, sound effects
/// by id. The audio files are the web version's own (www/audio), bundled as
/// the "audio" folder.
@MainActor
enum Sound {
    static func track(_ name: String) { AudioEngine.shared.playTrack(name) }
    static func stopMusic() { AudioEngine.shared.stopMusic() }
    /// A looping sound placed left or right (pan -1…1), like a StereoPannerNode.
    static func startLoop(_ file: String, volume: Double, pan: Double) { AudioEngine.shared.startLoop(file, volume: volume, pan: pan) }
    static func moveLoop(volume: Double, pan: Double) { AudioEngine.shared.moveLoop(volume: volume, pan: pan) }
    static func stopLoop() { AudioEngine.shared.stopLoop() }
    /// A one-shot sound placed left or right.
    static func placed(_ file: String, volume: Double, pan: Double) { AudioEngine.shared.placed(file, volume: volume, pan: pan) }
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

    /// iOS can start the app in the background (Background App Refresh for
    /// Endless Descent, a Live Activity, the watch) without it ever being
    /// opened. Nothing plays then: the music the game asked for starts when
    /// the app is really opened.
    private var hidden: Bool { UIApplication.shared.applicationState == .background }
    private var startWhenOpened = false

    private func url(_ file: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "audio")
    }

    func playTrack(_ requested: String) {
        // "menu" means the menu music of the day (holiday versions included).
        let name = requested == "menu" ? Soundtrack.menuTrack() : requested
        // The game choosing its own music ends the Music Player's track
        // (the player sets the flag again right after it calls this).
        musicPlayerActive = false
        // A custom track plays instead of the game's music until it's stopped.
        guard AppSettings.musicOn, customLabel == nil else { musicName = name; return }
        if name == musicName, music?.isPlaying == true { return }
        musicName = name
        if hidden {
            startWhenOpened = true
            return
        }
        // A playlist: one of its songs (not the one just heard), then the next.
        let list = Self.playlists[name]
        let file: String?
        if let list {
            file = list.filter { $0 != playlistFile }.randomElement()
            playlistFile = file
        } else {
            file = Soundtrack.file(forTrack: name)
        }
        guard let file, let u = url(file), let next = Self.player(u) else { return }
        fadeOut(music)
        next.numberOfLoops = list == nil ? -1 : 0
        next.delegate = list == nil ? nil : playlistEnd
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
        if hidden {
            startWhenOpened = true
            return
        }
        guard let file = Soundtrack.file(forAmbient: key), let u = url(file),
              let next = Self.player(u) else { return }
        fadeOut(ambient)
        next.numberOfLoops = -1
        next.volume = 0
        next.play()
        next.setVolume(Float(AppSettings.ambientVolume), fadeDuration: 1.2)
        ambient = next
    }

    func playEffect(_ id: String) {
        guard AppSettings.effectsOn, !hidden else { return }
        let player: AVAudioPlayer
        if let p = effects[id] {
            player = p
        } else {
            guard let u = url("\(id).mp3") ?? url("\(id).wav"),
                  let p = Self.player(u) else { return }
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
        custom?.volume = Float(AppSettings.musicVolume)
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

    private var loop: AVAudioPlayer?
    private var oneShots: [AVAudioPlayer] = []

    func startLoop(_ file: String, volume: Double, pan: Double) {
        stopLoop()
        guard AppSettings.effectsOn, let u = url(file), let p = Self.player(u) else { return }
        p.numberOfLoops = -1
        loop = p
        moveLoop(volume: volume, pan: pan)
        p.play()
    }

    func moveLoop(volume: Double, pan: Double) {
        loop?.volume = Float(volume * AppSettings.effectsVolume)
        loop?.pan = Float(pan)
    }

    func stopLoop() {
        loop?.stop()
        loop = nil
    }

    func placed(_ file: String, volume: Double, pan: Double) {
        guard AppSettings.effectsOn, let u = url(file), let p = Self.player(u) else { return }
        p.volume = Float(volume * AppSettings.effectsVolume)
        p.pan = Float(pan)
        oneShots.removeAll { !$0.isPlaying }
        oneShots.append(p)
        p.play()
    }

    /// Opens an audio file by what it really holds. Two of the web version's
    /// ".mp3" files are WAV (the Blacksmith's and raid-victory); browsers sniff
    /// the format, but iOS trusts the name and plays nothing.
    static func player(_ url: URL) -> AVAudioPlayer? {
        if let p = try? AVAudioPlayer(contentsOf: url) { return p }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let wav = data.prefix(4) == Data("RIFF".utf8)
        return try? AVAudioPlayer(data: data, fileTypeHint: wav ? AVFileType.wav.rawValue : nil)
    }

    // MARK: Playlists (12.1)

    /// Names that play several songs shuffled, one after another, instead of
    /// one song on repeat. The tavern songs (all CC0, from OpenGameArt.org):
    /// King's Feast, Minstrel Dance and The Bard's Tale by RandomMind, The Old
    /// Tower Inn by Airos, Crowded Pub by Bobjt.
    static let playlists: [String: [String]] = ["tavern": (1...5).map { "music-tavern\($0).mp3" }]
    private var playlistFile: String?
    private let playlistEnd = PlaylistEnd()

    private final class PlaylistEnd: NSObject, AVAudioPlayerDelegate {
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            let id = ObjectIdentifier(player)
            Task { @MainActor in AudioEngine.shared.playlistSongEnded(id) }
        }
    }

    private func playlistSongEnded(_ id: ObjectIdentifier) {
        guard let m = music, ObjectIdentifier(m) == id, let name = musicName, Self.playlists[name] != nil else { return }
        musicName = nil
        playTrack(name)
    }

    func stopMusic() {
        fadeOut(music)
        music = nil
        musicName = nil
    }

    // MARK: Leaving the app

    /// The Music Player is playing a track you chose.
    var musicPlayerActive = false
    private var pausedForBackground = false

    /// Leaving the app: the game's music and ambience stop, unless the Music
    /// Player or one of your own tracks is playing (they kept going before,
    /// because the app may play audio in the background).
    func enterBackground() {
        guard !musicPlayerActive, customLabel == nil else { return }
        if music?.isPlaying == true || ambient?.isPlaying == true {
            music?.pause()
            ambient?.pause()
            pausedForBackground = true
        }
    }

    func enterForeground() {
        if startWhenOpened {
            // Started in the background: begin what the game asked for.
            startWhenOpened = false
            pausedForBackground = false
            let track = musicName, key = ambientKey
            musicName = nil
            ambientKey = nil
            if let track, music?.isPlaying != true { playTrack(track) }
            if let key, ambient?.isPlaying != true { playAmbient(key) }
            return
        }
        guard pausedForBackground else { return }
        pausedForBackground = false
        if AppSettings.musicOn { music?.play() }
        ambient?.play()
    }

    // MARK: Custom tracks (playCustomTrack, stopCustomTrack)

    private var custom: AVPlayer?
    private var customLoop: NSObjectProtocol?
    private(set) var customLabel: String?

    /// Your own file or audio link, looping, in place of the game's music.
    func playCustom(_ url: URL, label: String) {
        stopCustomPlayer()
        fadeOut(music)
        music = nil
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.volume = Float(AppSettings.musicVolume)
        customLoop = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak p] _ in
            p?.seek(to: .zero)
            p?.play()
        }
        p.play()
        custom = p
        customLabel = label
    }

    /// Music played by something else (Apple Music, a YouTube link) in place
    /// of the game's: the game's music stops, and `stop` ends it later.
    private var externalStop: (() -> Void)?

    func playExternal(label: String, stop: @escaping () -> Void) {
        stopCustomPlayer()
        fadeOut(music)
        music = nil
        externalStop = stop
        customLabel = label
    }

    /// Back to the game's music.
    func stopCustom() {
        stopCustomPlayer()
        let name = musicName ?? "menu"
        musicName = nil
        playTrack(name)
    }

    private func stopCustomPlayer() {
        externalStop?()
        externalStop = nil
        custom?.pause()
        custom = nil
        customLabel = nil
        if let o = customLoop { NotificationCenter.default.removeObserver(o) }
        customLoop = nil
    }

    private func fadeOut(_ player: AVAudioPlayer?) {
        guard let player, player.isPlaying else { return }
        player.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { player.stop() }
    }
}
