import SwiftUI
import AVFoundation
import DungeonCore

/// The Chronicles' text from the web version (lore sections, STORIES,
/// VOID_CHRONICLES, MUSIC_CATALOGUE), pulled by extract-game-data.js.
struct ChroniclesData: Decodable {
    struct Lore: Decodable { let label, title: String; let paragraphs: [String] }
    struct Story: Decodable {
        let id: String?
        let title, author, version, dungeon, excerpt: String
        let body: [String]
        let hidden: Bool?
        let spireFloor: Int?
        let audio: String?
    }
    struct Track: Decodable { let key, label, dungeon: String }
    let lore: [Lore]
    let stories: [Story]
    let voidChronicles: [Story]
    let music: [Track]

    static let shared: ChroniclesData = {
        guard let url = Bundle.main.url(forResource: "chronicles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(ChroniclesData.self, from: data) else {
            return ChroniclesData(lore: [], stories: [], voidChronicles: [], music: [])
        }
        return c
    }()
}

/// The web version's #screen-chronicles: Lore, Library, Journal and Music.
@MainActor
struct ChroniclesView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "lore"
    @State private var reading: (story: ChroniclesData.Story, isVoid: Bool)?
    @State private var journalChar = 0
    @State private var narration: AVPlayer?

    private let data = ChroniclesData.shared
    private static let audioBase = "https://pub-a22a05b8dcb64f86b6bbb814578b93e4.r2.dev/"

    var body: some View {
        ZStack {
            WebScreen {
                ScreenHeader(title: "The Chronicles")
                HStack(spacing: 0) {
                    tabButton("lore", "📖 Lore", "Lore tab")
                    tabButton("library", "📚 Library", "Library tab")
                    tabButton("journal", "📜 Journal", "Journal tab")
                    tabButton("music", "🎵 Music", "Music Player tab")
                }
                .overlay(Rectangle().stroke(Theme.borderDim))
                .padding(.bottom, 8)
                switch tab {
                case "library": library
                case "journal": journal
                case "music": MusicPlayerPanel()
                default: lore
                }
            }
            if let r = reading { reader(r.story, isVoid: r.isVoid) }
        }
        .onAppear {
            Sound.track("chronicles")
            Feedback.announce("The Chronicles.")
        }
        .onDisappear {
            narration?.pause()
            Sound.track("menu")
        }
    }

    private func tabButton(_ id: String, _ text: String, _ label: String) -> some View {
        let on = tab == id
        return Button {
            Sound.sfx("sfx-select")
            tab = id
            let names = ["lore": "Lore", "library": "Library — stories from the world and from players",
                         "journal": "Character journal", "music": "Music player."]
            if id == "library" {
                Feedback.announce("Library. \(data.stories.count) stories available. Swipe through to find one and double tap to read.")
            } else if id == "music" {
                Feedback.announce("Music Player. \(data.music.count) tracks available. Select a track then press Play.")
            } else {
                Feedback.announce(names[id] ?? id)
            }
        } label: {
            Text(text.uppercased()).font(Theme.cinzel(11.5)).tracking(1.5)
                .foregroundStyle(on ? Theme.gold : Theme.textDim)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity).padding(10)
                .background(on ? Color(hex: 0x1e1a10) : Color(hex: 0x12100d))
                .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel)
            .overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
    }

    // MARK: Lore

    private var lore: some View {
        VStack(spacing: 14) {
            ForEach(data.lore, id: \.title) { l in
                panel {
                    Text(l.title).font(Theme.cinzel(14)).tracking(1.4).foregroundStyle(Theme.gold)
                        .padding(.bottom, 10).accessibilityAddTraits(.isHeader)
                    ForEach(l.paragraphs, id: \.self) { p in
                        Text(p).font(Theme.crimson(14.4, italic: true)).foregroundStyle(Theme.textSecondary)
                            .lineSpacing(8).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 22).padding(.horizontal, 26)
                .background(Theme.bgPanel)
                .overlay(Rectangle().stroke(Theme.borderDim))
                .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
            }
        }
    }

    // MARK: Library

    private var spireBest: Int {
        guard let s = game.store.getItem("dd_spire"), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String: JSONValue].self, from: d),
              case .number(let n)? = v["bestFloor"] else { return 1 }
        return Int(n)
    }

    private var library: some View {
        let fragments = min(jsParseInt(game.store.getItem("dd_void_fragments")) ?? 0, data.voidChronicles.count)
        let best = spireBest
        let visible = data.stories.filter { s in
            guard s.hidden == true else { return true }
            if s.id == "julio-story" && game.store.getItem("dd_julio_story") == nil { return false }
            if let f = s.spireFloor, best < f { return false }
            return true
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Stories from the world of Dungeon Descent. Written by the creators and submitted by players.")
                .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary).padding(.bottom, 4)
            ForEach(0..<fragments, id: \.self) { i in
                let s = data.voidChronicles[i]
                storyCard(s, isVoid: true, title: "👁 " + s.title,
                          meta: "\(s.dungeon) · Fragment \(i + 1) of 25",
                          label: "\(s.title). \(s.excerpt) Double tap to read.")
            }
            ForEach(visible.indices, id: \.self) { i in
                let s = visible[i]
                let isNew = s.spireFloor != nil && game.store.getItem("dd_story_\(s.id ?? "undefined")") == nil
                storyCard(s, isVoid: false, title: (isNew ? "✦ NEW — " : "") + s.title,
                          meta: "\(s.dungeon) · \(s.version) · By \(s.author)",
                          label: (isNew ? "New. " : "") + "\(s.title). \(s.dungeon). \(s.excerpt) Double tap to read.")
            }
        }
    }

    private func storyCard(_ s: ChroniclesData.Story, isVoid: Bool, title: String, meta: String, label: String) -> some View {
        Button { open(s, isVoid: isVoid) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.cinzel(14)).foregroundStyle(isVoid ? Color(hex: 0xbb88ff) : Theme.ashLight)
                    .padding(.bottom, 4)
                Text(meta).font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim).padding(.bottom, 6)
                Text(s.excerpt).font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 16).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgPanel)
            .overlay(Rectangle().stroke(isVoid ? Color(hex: 0x6644aa) : Theme.borderDim))
            .overlay(alignment: .leading) { Rectangle().fill(isVoid ? Color(hex: 0x6644aa) : Theme.goldDim).frame(width: 3) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isHeader)
    }

    /// openStory: the first read counts toward storiesRead.
    private func open(_ s: ChroniclesData.Story, isVoid: Bool) {
        Sound.sfx("sfx-select")
        reading = (s, isVoid)
        Feedback.announce("Reading: \(s.title). \(s.body.first ?? "") Double tap Back to Library when done.")
        let key = "dd_story_\(s.id ?? "undefined")"
        if game.store.getItem(key) == nil {
            game.store.setItem(key, "1")
            game.achievements.increment("storiesRead")
            game.achievements.setMax("storyRead_\(s.id ?? "undefined")", 1)
            game.achievements.check()
        }
    }

    private func reader(_ s: ChroniclesData.Story, isVoid: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.title).font(Theme.decorative(19.2)).foregroundStyle(Theme.gold).padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(s.dungeon) · \(s.version) · By \(s.author)".uppercased())
                        .font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.textDim)
                        .padding(.bottom, 14)
                    Rectangle().fill(Theme.borderDim).frame(height: 1).padding(.bottom, 24)
                    if let audio = s.audio {
                        HStack(spacing: 10) {
                            Text("🎙️ NARRATED").font(Theme.cinzel(10.4)).tracking(1).foregroundStyle(Theme.gold)
                            if narration == nil {
                                Button("▶ Listen") { playNarration(audio) }
                                    .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xffd700))
                                    .padding(.vertical, 6).padding(.horizontal, 14)
                                    .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Theme.gold))
                                    .accessibilityLabel("Listen to narrated version")
                            } else {
                                Button("■ Stop") { stopNarration() }
                                    .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                                    .padding(.vertical, 6).padding(.horizontal, 14)
                                    .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Color(hex: 0x555555)))
                                    .accessibilityLabel("Stop narration")
                            }
                        }
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x0a0800))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x887700)))
                        .padding(.bottom, 18)
                    }
                    ForEach(s.body.indices, id: \.self) { i in
                        Text(s.body[i]).font(Theme.crimson(15.2, italic: true)).foregroundStyle(Theme.textSecondary)
                            .lineSpacing(12).fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 16)
                    }
                    Button("← Back to Library") {
                        stopNarration()
                        reading = nil
                        Feedback.announce("Story closed. Back to library.")
                    }
                    .buttonStyle(BackButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Close story and return to library")
                }
                .padding(36)
                .frame(maxWidth: 680, alignment: .leading)
                .background(Color(hex: 0x0e0b08))
                .overlay(Rectangle().stroke(Theme.goldDim))
                .overlay(alignment: .top) { Rectangle().fill(Theme.gold).frame(height: 2) }
                .padding(.horizontal, 12).padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
            .accessibilityAddTraits(.isModal)
        }
    }

    private func playNarration(_ file: String) {
        let name = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
        guard let url = URL(string: Self.audioBase + name) else { return }
        stopNarration()
        let p = AVPlayer(url: url)
        p.volume = Float(AppSettings.effectsVolume)
        p.play()
        narration = p
        Feedback.announce("Playing narration.")
    }

    private func stopNarration() {
        narration?.pause()
        narration = nil
    }

    // MARK: Journal

    private var journal: some View {
        let chars = game.characters
        return VStack(alignment: .leading, spacing: 6) {
            Text("An auto-written record of each character's descent. Updates after every run.")
                .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary).padding(.bottom, 8)
            if chars.isEmpty {
                Text("No characters yet. Create a character and begin your descent.")
                    .font(Theme.crimson(13.6, italic: true)).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(20)
            } else {
                let idx = min(journalChar, chars.count - 1)
                Text("SELECT CHARACTER").font(Theme.cinzel(10.4)).tracking(2.6).foregroundStyle(Theme.goldDim)
                    .padding(.bottom, 2)
                FlowRow(spacing: 8) {
                    ForEach(chars.indices, id: \.self) { i in
                        Button(chars[i].name) {
                            Sound.sfx("sfx-select")
                            journalChar = i
                            let n = entries(chars[i]).count
                            Feedback.announce(n == 0 ? "Journal for \(chars[i].name). No entries yet." : "\(chars[i].name) journal. \(n) entries.")
                        }
                        .font(Theme.cinzel(10.4))
                        .foregroundStyle(i == idx ? Theme.gold : Theme.textSecondary)
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .overlay(Rectangle().stroke(i == idx ? Theme.gold : Theme.borderDim))
                        .accessibilityLabel("\(chars[i].name) journal")
                        .accessibilityAddTraits(i == idx ? [.isSelected] : [])
                    }
                }
                .padding(.bottom, 8)
                let list = entries(chars[idx])
                if list.isEmpty {
                    Text("\(chars[idx].name) has not yet descended. Enter the dungeon to begin the journal.")
                        .font(Theme.crimson(13.6, italic: true)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(20)
                } else {
                    ForEach(list.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list[i].time.uppercased()).font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                            Text(list[i].text).font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.bgPanel)
                        .overlay(Rectangle().stroke(Theme.borderDim))
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(list[i].time). \(list[i].text)")
                    }
                }
            }
        }
    }

    private func entries(_ ch: PlayerCharacter) -> [JournalEntry] {
        switch ch.extra["journal"] {
        case .array(let a)?:
            return a.compactMap { v in
                guard case .object(let o) = v else { return nil }
                var time = "", text = ""
                if case .string(let t)? = o["time"] { time = t }
                if case .string(let t)? = o["text"] { text = t }
                return text.isEmpty ? nil : JournalEntry(time: time, text: text)
            }
        case .string(let t)?: return t.isEmpty ? [] : [JournalEntry(time: "", text: t)]
        default: return []
        }
    }

}

/// The music player (MUSIC_CATALOGUE, mpPlay, mpStop): every track in the game,
/// by dungeon. In the Chronicles, and from the Music Player item in a run.
struct MusicPlayerPanel: View {
    @State private var mpKey: String?
    @State private var mpPlaying = false
    @State private var mpShuffle = false
    @AppStorage("swift_music_volume") private var musicVolume = 0.7
    private let data = ChroniclesData.shared

    var body: some View {
        let groups = data.music.reduce(into: [(String, [ChroniclesData.Track])]()) { acc, t in
            if let i = acc.firstIndex(where: { $0.0 == t.dungeon }) { acc[i].1.append(t) } else { acc.append((t.dungeon, [t])) }
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text("Browse and play any track from Dungeon Descent. Select a track then press Play.")
                .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("NOW PLAYING").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                    .padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                Text(nowPlaying).font(Theme.decorative(14.4)).foregroundStyle(Theme.gold).padding(.bottom, 10)
                FlowRow(spacing: 8) {
                    mpButton("⏮", "Previous track") { step(-1) }
                    mpButton("▶ Play", "Play selected track") { play() }
                    mpButton("■ Stop", "Stop music") { stop() }
                    mpButton("⏭", "Next track") { step(1) }
                    mpButton("🔀 \(mpShuffle ? "On" : "Off")", "Shuffle, currently \(mpShuffle ? "on" : "off")", active: mpShuffle) {
                        mpShuffle.toggle()
                        Feedback.announce("Shuffle \(mpShuffle ? "on" : "off").")
                    }
                }
                .padding(.bottom, 12)
                HStack(spacing: 8) {
                    Text("🔈").font(Theme.cinzel(10.4)).accessibilityHidden(true)
                    VolumeSlider(label: "Music volume", value: $musicVolume)
                        .onChange(of: musicVolume) { _ in Sound.settingsChanged() }
                    Text("🔊").font(Theme.cinzel(10.4)).accessibilityHidden(true)
                }
            }
            .padding(16)
            .background(Theme.bgPanel)
            .overlay(Rectangle().stroke(Theme.borderDim))
            .overlay(alignment: .top) { Rectangle().fill(Theme.goldDim).frame(height: 3) }
            ForEach(groups.indices, id: \.self) { g in
                VStack(alignment: .leading, spacing: 0) {
                    Text(groups[g].0.uppercased()).font(Theme.cinzel(9.9)).tracking(2.5).foregroundStyle(Theme.goldDim)
                        .padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                    Rectangle().fill(Theme.borderDim).frame(height: 1).padding(.bottom, 8)
                    ForEach(groups[g].1, id: \.key) { t in trackRow(t) }
                }
            }
            MyTracksSection()
        }
    }

    private var nowPlaying: String {
        guard let k = mpKey else { return "Select a track below" }
        guard mpPlaying else { return "Nothing playing" }
        return data.music.first { $0.key == k }?.label ?? k
    }

    private func mpButton(_ text: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(text, action: action)
            .font(Theme.cinzel(11.2))
            .foregroundStyle(active ? Theme.gold : Theme.textSecondary)
            .padding(.vertical, 7).padding(.horizontal, 14)
            .background(active ? Theme.gold.opacity(0.08) : .clear)
            .overlay(Rectangle().stroke(active ? Theme.gold : Theme.borderDim))
            .accessibilityLabel(label)
    }

    private func trackRow(_ t: ChroniclesData.Track) -> some View {
        let on = mpPlaying && mpKey == t.key
        return Button {
            mpKey = t.key
            play()
        } label: {
            Text(t.label).font(Theme.crimson(12.5)).foregroundStyle(on ? Theme.gold : Theme.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(on ? Theme.gold.opacity(0.06) : .clear)
                .overlay(alignment: .leading) { if on { Rectangle().fill(Theme.gold).frame(width: 2) } }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderDim).frame(height: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// mpPlay: game tracks the app doesn't carry say so, like the web version.
    private func play() {
        guard let k = mpKey else { Feedback.announce("Select a track first."); return }
        let label = data.music.first { $0.key == k }?.label ?? k
        guard Soundtrack.file(forTrack: k) != nil else {
            Feedback.announce("Track not uploaded yet. Add the audio file to play this track.")
            return
        }
        // Stop everything first, custom track included (mpPlay).
        if AudioEngine.shared.customLabel != nil { AudioEngine.shared.stopCustom() }
        Sound.track(k)
        mpPlaying = true
        Feedback.announce("Now playing: \(label)")
    }

    private func stop() {
        Sound.stopMusic()
        mpPlaying = false
        Feedback.announce("Music stopped.")
    }

    private func step(_ d: Int) {
        let keys = data.music.map(\.key)
        guard !keys.isEmpty else { return }
        if mpShuffle {
            mpKey = keys.randomElement()
        } else {
            let i = mpKey.flatMap { keys.firstIndex(of: $0) } ?? (d > 0 ? -1 : 0)
            mpKey = keys[(i + d + keys.count) % keys.count]
        }
        play()
    }
}
