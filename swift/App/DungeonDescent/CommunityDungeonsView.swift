import SwiftUI
import DungeonCore

/// 12.1 Community Dungeons: Browse (play, like, report) and Create, with
/// their own tab bar. Every choice in Create is a list of buttons, one
/// choice at a time, so it's quick with VoiceOver.
struct CommunityDungeonsView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @ObservedObject private var store = CommunityDungeonStore.shared
    @ObservedObject private var enemies = CommunityEnemyStore.shared
    @State private var tab = "browse"
    @State private var open: CommunityDungeons.Dungeon?
    @State private var charIndex = 0
    @State private var confirmReport = false
    // Create
    @State private var name = ""
    @State private var desc = ""
    @State private var creator = ""
    @State private var base = "Crypt of Malachar"
    @State private var picked: [String] = []
    @State private var boss: String?
    @State private var rule: String?
    @State private var music: String?
    @State private var error = ""
    @State private var askingTerms = false

    private let stone = Color(hex: 0xd0a060)

    /// Music a creator can pick (only names the game can play are shown).
    static let musicChoices: [(String, String)] = [
        ("spire", "The Spire"), ("graveyard", "The Graveyard"), ("chronicles", "The Chronicles"), ("bestiary", "The Bestiary"),
        ("hunter-theme", "The Hunter"), ("shadow-stalker", "The Darkness Swallower"), ("boss", "Boss Battle"),
        ("raid", "The Raid"), ("mine-explore", "The Mine"), ("tavern", "Tavern Songs"), ("help", "The Guide"),
    ]
    private var musicChoices: [(String, String)] {
        Self.musicChoices.filter { AudioEngine.playlists[$0.0] != nil || Soundtrack.file(forTrack: $0.0) != nil }
    }

    private var bases: [String] { GameData.dungeons.filter { $0 != "The Shadow World" } }

    var body: some View {
        ScreenTabs(items: [.init(id: "browse", title: "Browse", icon: "map.fill"),
                           .init(id: "create", title: "Create", icon: "hammer.fill")],
                   selection: $tab, onBack: { router.goTo(.menu) }, onSelect: { id in
                       open = nil
                       Feedback.announce(id == "create" ? "Create a dungeon." : "Browse community dungeons.")
                   }) {
            WebScreen {
                VStack(alignment: .leading, spacing: 12) {
                    Button("← Menu") { router.goTo(.menu) }
                        .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
                    if tab == "create" { create } else if let d = open { page(d) } else { browse }
                }
            }
        }
        .onAppear {
            store.load()
            Task { await enemies.load(game.store) }
            if creator.isEmpty { creator = GlobalChat(store: game.store).username ?? "" }
            Feedback.announce("Community Dungeons. Dungeons built by players. Play one, or build your own in the Create tab.")
        }
        .alert("Before you post", isPresented: $askingTerms) {
            Button("I agree") { GlobalChat(store: game.store).agree(); publish() }
            Button("Cancel", role: .cancel) { Feedback.announce("You need to agree to the Terms of Service to post.") }
        } message: {
            Text("Community dungeons are seen by all players. By continuing you agree to the Dungeon Descent Terms of Service at dungen-descent.org/terms. There is no tolerance for objectionable content. Content that breaks the rules is removed. Do you agree?")
        }
    }

    private func header(_ s: String) -> some View {
        Text(s).font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.goldDim).accessibilityAddTraits(.isHeader).padding(.top, 6)
    }

    private func note(_ s: String) -> some View {
        Text(s).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
    }

    private func enemyName(_ id: String) -> String {
        enemies.entries.first { $0.id == id }.map { "\($0.icon) \($0.name)" } ?? "an enemy that was removed"
    }

    // MARK: Browse

    @ViewBuilder private var browse: some View {
        Text("🏰 Community Dungeons").font(Theme.decorative(22)).foregroundStyle(stone).accessibilityAddTraits(.isHeader)
        let list = store.visible(game.store)
        if store.loading && list.isEmpty {
            note("Loading dungeons…")
        } else if store.failed && list.isEmpty {
            note("Couldn't load the dungeons. Check your connection.")
        } else if list.isEmpty {
            note("No community dungeons yet. Be the first: build one in the Create tab.")
        } else {
            note("Most played and liked first. Playing one never changes your character's own dungeon progress.")
            ForEach(list) { d in
                Button("\(d.name) — by \(d.creator)" as String) {
                    open = d
                    Feedback.announce(d.summary + " " + d.desc)
                }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel(d.summary)
                .accessibilityAddTraits(.isHeader)
            }
            Button("🔄 Refresh") { store.load(); Feedback.announce("Refreshed.") }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
        }
    }

    // MARK: A dungeon's page

    @ViewBuilder private func page(_ d: CommunityDungeons.Dungeon) -> some View {
        Button("← All Dungeons") { open = nil }
            .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to all dungeons")
        Text(d.name).font(Theme.decorative(22)).foregroundStyle(stone).accessibilityAddTraits(.isHeader)
        note("By \(d.creator). \(d.plays) plays, \(d.clears) clears, \(d.likes) likes." as String)
        if !d.desc.isEmpty { Text(d.desc).font(Theme.crimson(16)).foregroundStyle(Theme.textPrimary) }
        header("THE DUNGEON")
        Text("Built on \(d.base): its rooms, its loot and its strength." as String).font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        Text("Enemies: " + d.enemies.map(enemyName).joined(separator: ", ")).font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        Text("Boss: " + (d.boss.map(enemyName) ?? "\(d.base)'s own boss")).font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        if let m = RunModifiers.modifier(d.rule) {
            Text("Rule: \(m.icon) \(m.name). \(m.desc)" as String).font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        }
        if let m = d.music, let label = Self.musicChoices.first(where: { $0.0 == m })?.1 {
            Text("Music: \(label)" as String).font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        }
        header("WHO GOES IN")
        if game.characters.isEmpty {
            note("Create a character first.")
        } else {
            ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                Button("\(Prestige.label(ch)) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))" as String) {
                    charIndex = i
                    Feedback.announce("\(ch.name) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == charIndex ? .gold : .ghost))
                .accessibilityAddTraits(i == charIndex ? .isSelected : [])
            }
            Button("⚔ Enter \(d.name)" as String) { play(d) }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityHint("A run in progress for this character is replaced.")
        }
        header("WHAT DID YOU THINK")
        Button(store.isLiked(d.id) ? "👍 Liked" : "👍 Like") { store.like(d) }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
        if !store.isMine(d.id) {
            Button("🚫 Block \(d.creator)" as String) {
                GlobalChat(store: game.store).block(d.creator)
                open = nil
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityHint("Hides everything they made.")
            Button("⚠️ Report") { confirmReport = true }
                .buttonStyle(WebButtonStyle(kind: .red)).frame(maxWidth: .infinity)
                .alert("Report \(d.name)?" as String, isPresented: $confirmReport) {
                    Button("Report", role: .destructive) {
                        Task { await store.report(d) }
                        open = nil
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It's hidden for you now, and the developer reviews reports within 24 hours.")
                }
        } else {
            note("You built this one. Its ID, if you need it: \(d.id)" as String)
        }
    }

    private func play(_ d: CommunityDungeons.Dungeon) {
        guard game.characters.indices.contains(charIndex) else { return }
        let ch = game.characters[charIndex]
        game.clearRun(for: charIndex)
        RunModel.pendingChallenge = .community(d)
        Sound.sfx("sfx-select")
        router.goTo(.dungeon(ch.created, resume: false))
        Feedback.announce("\(ch.name) enters \(d.name), built by \(d.creator).", after: 1.5)
    }

    // MARK: Create

    @ViewBuilder private var create: some View {
        Text("🏗 Build a Dungeon").font(Theme.decorative(22)).foregroundStyle(stone).accessibilityAddTraits(.isHeader)
        note("Pick a dungeon to build on, the community enemies that roam it, a boss, a rule and music. Enemies fight at the dungeon's own strength.")
        header("NAME")
        TextField("Dungeon name", text: $name)
            .font(Theme.cinzel(14)).padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityLabel("Dungeon name, up to \(CommunityDungeons.nameLimit) letters" as String)
        TextField("A short description", text: $desc, axis: .vertical)
            .font(Theme.crimson(15)).padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityLabel("Description, up to \(CommunityDungeons.descLimit) letters" as String)
        TextField("Your name as the creator", text: $creator)
            .font(Theme.crimson(15)).padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
            .accessibilityLabel("Your name as the creator")

        header("BUILT ON")
        ForEach(bases, id: \.self) { b in
            choice(b, selected: base == b) { base = b }
        }

        header("ENEMIES (UP TO \(CommunityDungeons.maxEnemies))")
        let pool = enemies.visible(game.store)
        if pool.isEmpty {
            note(enemies.loading ? "Loading community enemies…" : "No community enemies to choose from yet.")
        }
        ForEach(pool) { e in
            let on = picked.contains(e.id)
            choice("\(e.icon) \(e.name) — by \(e.creator)", selected: on) {
                if on {
                    picked.removeAll { $0 == e.id }
                    if boss == e.id { boss = nil }
                } else if picked.count < CommunityDungeons.maxEnemies {
                    picked.append(e.id)
                } else {
                    Feedback.announce("You can choose up to \(CommunityDungeons.maxEnemies). Unselect one first.")
                }
            }
        }
        Button("⚔ Make Your Own Enemy") { router.goTo(.enemyCreator) }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)

        header("THE BOSS")
        choice("\(base)'s own boss", selected: boss == nil) { boss = nil }
        ForEach(picked, id: \.self) { id in
            choice(enemyName(id) + " as the boss", selected: boss == id) { boss = id }
        }

        header("SPECIAL RULE")
        choice("No special rule", selected: rule == nil) { rule = nil }
        ForEach(RunModifiers.all, id: \.id) { m in
            choice("\(m.icon) \(m.name)", selected: rule == m.id, hint: m.desc) { rule = m.id }
        }

        header("MUSIC")
        choice("\(base)'s own music", selected: music == nil) { music = nil; Sound.track("menu") }
        ForEach(musicChoices, id: \.0) { m in
            choice(m.1, selected: music == m.0, hint: "Plays a preview.") { music = m.0; Sound.track(m.0) }
        }

        if !error.isEmpty { Text(error).font(Theme.crimson(15)).foregroundStyle(Color(hex: 0xff8888)) }
        Button("🏰 Publish Dungeon") { publish() }
            .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
    }

    private func choice(_ label: String, selected: Bool, hint: String = "", action: @escaping () -> Void) -> some View {
        Button(label) {
            action()
            Feedback.announce("\(label) selected.")
        }
        .buttonStyle(WebButtonStyle(kind: selected ? .gold : .ghost)).frame(maxWidth: .infinity)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(hint)
    }

    private func publish() {
        let d = CommunityDungeons.Dungeon(id: "", name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                          desc: desc.trimmingCharacters(in: .whitespacesAndNewlines),
                                          creator: creator.trimmingCharacters(in: .whitespacesAndNewlines),
                                          base: base, enemies: picked, boss: boss, rule: rule, music: music)
        if let p = CommunityDungeons.problem(d, known: picked) {
            error = p
            Feedback.announce(p)
            return
        }
        guard GlobalChat(store: game.store).agreed else { askingTerms = true; return }
        error = ""
        store.submit(d) { problem in
            if let problem {
                error = problem
                Feedback.announce(problem)
                return
            }
            Sound.sfx("sfx-unlock")
            Feedback.announce("\(d.name) is published! Other players can find it in Browse now.")
            name = ""; desc = ""; picked = []; boss = nil; rule = nil; music = nil
            tab = "browse"
        }
    }
}
