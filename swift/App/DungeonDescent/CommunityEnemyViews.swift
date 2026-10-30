import SwiftUI
import FirebaseFirestore
import DungeonCore

/// The shared "community_enemies" pool (loadCommunityEnemies, ecSubmit,
/// incrementCommunityKill), in the same Firestore database as the web version.
@MainActor
final class CommunityEnemyStore: ObservableObject {
    static let shared = CommunityEnemyStore()
    @Published private(set) var entries: [CommunityEnemies.Entry] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var loadedAt = Date.distantPast
    private var db: Firestore { Firestore.firestore(database: "dungeon-descent") }
    private var col: CollectionReference { db.collection("community_enemies") }

    /// The ones not blocked or hidden on this device.
    func visible(_ store: GameStore) -> [CommunityEnemies.Entry] {
        let chat = GlobalChat(store: store)
        let hidden = Set(Self.list(store, "dd_hidden_content"))
        return entries.filter { !chat.isBlocked($0.creator) && !hidden.contains($0.id) }
    }

    static func list(_ store: GameStore, _ key: String) -> [String] {
        guard let s = store.getItem(key), let d = s.data(using: .utf8), let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    /// Cached for five minutes, like the web version. Updates the dungeon's pool.
    func load(_ store: GameStore, force: Bool = false) async {
        if !force && Date().timeIntervalSince(loadedAt) < 300 && !entries.isEmpty { refreshPool(store); return }
        loading = true
        defer { loading = false }
        do {
            let snap = try await col.whereField("approved", isEqualTo: true).limit(to: 50).getDocuments()
            entries = snap.documents.compactMap { d in
                let v = d.data()
                guard let name = v["name"] as? String else { return nil }
                func n(_ k: String) -> Int { (v[k] as? NSNumber)?.intValue ?? 0 }
                return CommunityEnemies.Entry(id: d.documentID, name: name, desc: v["desc"] as? String ?? "",
                                              type: v["type"] as? String ?? "common", dungeon: v["dungeon"] as? String ?? "all",
                                              music: v["music"] as? String, creator: v["creator"] as? String ?? "Unknown",
                                              icon: v["icon"] as? String ?? "👤", hp: n("hp"), atk: n("atk"), def: n("def"), kills: n("kills"))
            }
            loadedAt = Date()
            failed = false
        } catch {
            failed = true
        }
        refreshPool(store)
    }

    func refreshPool(_ store: GameStore) { CommunityEnemies.pool = visible(store) }

    /// ecSubmit: fire and forget, like the web version.
    func submit(_ e: CommunityEnemies.Entry) {
        let data: [String: Any] = [
            "name": e.name, "desc": e.desc, "type": e.type, "dungeon": e.dungeon, "music": e.music ?? NSNull(),
            "creator": e.creator, "icon": e.icon, "hp": e.hp, "atk": e.atk, "def": e.def, "kills": 0,
            "createdAt": (Date().timeIntervalSince1970 * 1000).rounded(), "approved": true,
        ]
        col.addDocument(data: data) { _ in }
        loadedAt = .distantPast
    }

    /// incrementCommunityKill.
    func killed(_ id: String) {
        col.document(id).updateData(["kills": FieldValue.increment(Int64(1))]) { _ in }
    }

    func report(_ e: CommunityEnemies.Entry, reason: String, store: GameStore) async {
        let chat = GlobalChat(store: store)
        chat.hide(e.id)
        refreshPool(store)
        objectWillChange.send()
        await GlobalChat.sendReport(kind: "enemy", id: e.id, author: e.creator, content: "\(e.name): \(e.desc)",
                                    reason: reason, reporter: chat.username)
    }

    func block(_ creator: String, store: GameStore) {
        GlobalChat(store: store).block(creator)
        refreshPool(store)
        objectWillChange.send()
    }
}

/// #screen-enemy-creator
struct EnemyCreatorView: View {
    @EnvironmentObject var game: GameModel
    @ObservedObject private var pool = CommunityEnemyStore.shared
    @State private var name = ""
    @State private var desc = ""
    @State private var kind = CommunityEnemies.Kind.common
    @State private var dungeon = "all"
    @State private var music = ""
    @State private var creator = ""
    @State private var stats = (hp: 0, atk: 0, def: 0)
    @State private var error = ""
    @State private var done: String?
    @State private var askingTerms = false
    @State private var dice = SystemDice()

    private static let violet = Color(hex: 0xaa88ff), violetBorder = Color(hex: 0x554488)

    var body: some View {
        WebScreen {
            ScreenHeader(title: "Enemy Creator", subtitle: "Build an enemy. Set it loose. Let the dungeon remember your name.")
            if let done { success(done) } else { form }
        }
        .onAppear {
            if creator.isEmpty { creator = GlobalChat(store: game.store).username ?? "" }
            roll(announce: false)
            Feedback.announce("Enemy Creator. Build an enemy. Set it loose. Let the dungeon remember your name.", after: 0.4)
        }
        .alert("Before you post", isPresented: $askingTerms) {
            Button("I agree") { GlobalChat(store: game.store).agree(); submit() }
            Button("Cancel", role: .cancel) { Feedback.announce("You need to agree to the Terms of Service to post.") }
        } message: {
            Text("Chat messages and community enemies are seen by all players. By continuing you agree to the Dungeon Descent Terms of Service at dungen-descent.org/terms. There is no tolerance for objectionable content or abusive players. Content that breaks the rules is removed. You can report or block anyone. Do you agree?")
        }
    }

    private func label(_ t: String, _ hint: String = "") -> some View {
        (Text(t) + Text(hint.isEmpty ? "" : " (\(hint))").foregroundColor(Color(hex: 0x555555)))
            .font(Theme.cinzel(10.4)).foregroundStyle(Self.violet).accessibilityHidden(true)
    }

    private func field(_ placeholder: String, _ text: Binding<String>, max: Int, voice: String, axis: Axis = .horizontal) -> some View {
        TextField(placeholder, text: text, axis: axis)
            .lineLimit(axis == .vertical ? 3...5 : 1...1)
            .font(Theme.cinzel(12.5)).padding(10)
            .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
            .onChange(of: text.wrappedValue) { v in if v.count > max { text.wrappedValue = String(v.prefix(max)) } }
            .accessibilityLabel(voice)
    }

    private func picker<T: Hashable>(_ voice: String, _ sel: Binding<T>, _ options: [(T, String)]) -> some View {
        Picker(voice, selection: sel) {
            ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
        }
        .pickerStyle(.menu).tint(Self.violet)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4).background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
        .accessibilityLabel(voice)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            label("Enemy Name", "max 30 chars")
            field("e.g. The Hollow Watcher", $name, max: 30, voice: "Enemy name, maximum 30 characters")
            label("Description", "max 120 chars")
            field("What is this thing? What does it want?", $desc, max: 120, voice: "Enemy description, maximum 120 characters", axis: .vertical)
            label("Enemy Type")
            picker("Enemy type", $kind, CommunityEnemies.Kind.allCases.map { ($0, $0.label) })
                .onChange(of: kind) { _ in roll(announce: true) }
            label("Dungeon")
            picker("Which dungeon this enemy lives in", $dungeon, CommunityEnemies.dungeons.map { ($0, $0 == "all" ? "All Dungeons" : $0) })
            label("Theme Music", "plays when this enemy spawns")
            picker("Music that plays when your enemy spawns", $music,
                   [("", "— Default dungeon music —")] + ChroniclesData.shared.music.map { ($0.key, $0.label) })
            label("Your Name", "shown in dungeon announcement")
            field("Your name or username", $creator, max: 24, voice: "Your creator name, shown when your enemy appears in the dungeon")
            VStack(spacing: 8) {
                Text("Auto-rolled Stats (based on type)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
                HStack {
                    stat("HP", stats.hp)
                    stat("ATK", stats.atk)
                    stat("DEF", stats.def)
                }
                .accessibilityElement(children: .combine)
                Button("🎲 Reroll Stats") { roll(announce: true) }
                    .font(Theme.cinzel(10.4)).foregroundStyle(Self.violet)
                    .padding(.vertical, 6).padding(.horizontal, 14).overlay(Rectangle().stroke(Self.violetBorder))
                    .accessibilityLabel("Reroll enemy stats")
            }
            .frame(maxWidth: .infinity).padding(12)
            .background(Color(hex: 0x08060f)).overlay(Rectangle().stroke(Self.violetBorder))
            if !error.isEmpty {
                Text(error).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xff5555))
            }
            Button("⚔ Unleash This Enemy") { submit() }
                .font(Theme.cinzel(13)).tracking(1.5).foregroundStyle(Self.violet)
                .frame(maxWidth: .infinity).padding(14)
                .background(Color(hex: 0x0d0818)).overlay(Rectangle().stroke(Self.violetBorder, lineWidth: 2))
                .accessibilityLabel("Submit your enemy to the community pool")
            Text("Your enemy will appear in dungeons for all players after passing a content filter. By creating one you agree to the Terms of Service (dungen-descent.org/terms). Players can report or block any community enemy in the Bestiary, Community tab.")
                .font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim)
        }
    }

    private func stat(_ t: String, _ v: Int) -> some View {
        VStack(spacing: 2) {
            Text(t).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
            Text("\(v)").font(Theme.decorative(18)).foregroundStyle(Self.violet)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func success(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Text("⚔").font(.system(size: 44)).accessibilityHidden(true)
            Text("Enemy Unleashed.").font(Theme.decorative(18)).foregroundStyle(Self.violet).accessibilityAddTraits(.isHeader)
            Text(msg).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button("Create Another") {
                name = ""; desc = ""; kind = .common; dungeon = "all"; music = ""; error = ""; done = nil
                roll(announce: false)
            }
            .buttonStyle(WebButtonStyle(kind: .ghost))
            .accessibilityLabel("Create another enemy")
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private func roll(announce: Bool) {
        let s = CommunityEnemies.roll(kind, dice: &dice)
        stats = (s.hp, s.atk, s.def)
        if announce { Feedback.announce("Stats rolled. HP: \(s.hp). ATK: \(s.atk). DEF: \(s.def).") }
    }

    private func submit() {
        if let p = CommunityEnemies.problem(name: name, desc: desc, creator: creator) {
            error = p
            Feedback.announce(p)
            return
        }
        guard GlobalChat(store: game.store).agreed else { askingTerms = true; return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines), c = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        pool.submit(.init(name: n, desc: desc.trimmingCharacters(in: .whitespacesAndNewlines), type: kind.rawValue, dungeon: dungeon,
                          music: music.isEmpty ? nil : music, creator: c, icon: kind.icon, hp: stats.hp, atk: stats.atk, def: stats.def))
        game.achievements.increment("enemyCreated")
        _ = game.achievements.check()
        Sound.sfx("sfx-unlock")
        error = ""
        done = "\"\(n)\" has been added to the dungeon pool. Players will encounter your enemy in \(dungeon == "all" ? "all dungeons" : dungeon). When they do, the dungeon will announce: \"\(n), unleashed by \(c).\""
        Feedback.announce("\(n) has been unleashed into the dungeon. Players will encounter your creation soon.")
    }
}

/// #be-section-community: the pool, each with Report and Block.
struct CommunityBestiary: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @ObservedObject private var pool = CommunityEnemyStore.shared
    @State private var reporting: CommunityEnemies.Entry?
    @State private var reason = ""
    @State private var blocking: CommunityEnemies.Entry?

    var body: some View {
        let list = pool.visible(game.store)
        VStack(alignment: .leading, spacing: 10) {
            Text("Enemies created by the community. They walk among the others now.")
                .font(Theme.crimson(14.4, italic: true)).foregroundStyle(Theme.textSecondary)
            Button("⚔ Create Your Own Enemy") { router.goTo(.enemyCreator) }
                .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaa88ff))
                .frame(maxWidth: .infinity).padding(10)
                .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x554488)))
                .accessibilityLabel("Create your own community enemy")
            if pool.loading && pool.entries.isEmpty {
                note("Loading community enemies...")
            } else if pool.failed && pool.entries.isEmpty {
                note("Failed to load community enemies. Check your connection.")
            } else if pool.entries.isEmpty {
                note("No community enemies yet. Be the first to create one!")
            } else if list.isEmpty {
                note("No community enemies to show.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(list) { e in card(e) }
            }
        }
        .task {
            await pool.load(game.store)
            let n = pool.visible(game.store).count
            if n > 0 { Feedback.announce("\(n) community enemies loaded. Each one has Report and Block buttons.") }
        }
        .alert("Report this enemy", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            TextField("Reason (optional)", text: $reason)
            Button("Send report") {
                if let e = reporting { Task { await pool.report(e, reason: reason, store: game.store) } }
                reporting = nil
            }
            Button("Cancel", role: .cancel) { reporting = nil; Feedback.announce("Report cancelled.") }
        } message: {
            Text("What is wrong with it? For example: offensive, harassment, spam. You can also leave this empty.")
        }
        .alert("Block \(blocking?.creator ?? "")?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } })) {
            Button("Block", role: .destructive) {
                if let e = blocking { pool.block(e.creator, store: game.store) }
                blocking = nil
            }
            Button("Cancel", role: .cancel) { blocking = nil }
        } message: {
            Text("You will no longer see their chat messages or community enemies. You can unblock everyone later in Settings, Chat.")
        }
    }

    private func note(_ t: String) -> some View {
        Text(t).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555)).frame(maxWidth: .infinity).padding(20)
    }

    private func card(_ e: CommunityEnemies.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.icon).font(.system(size: 28)).accessibilityHidden(true)
                Text(e.name).font(Theme.cinzel(13)).foregroundStyle(Theme.textPrimary)
                Text("Created by \(e.creator)").font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0xaa88ff))
                if !e.desc.isEmpty { Text(e.desc).font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary) }
                Text("\(e.dungeon == "all" ? "All Dungeons" : e.dungeon) · \(e.type) · HP \(e.hp) · ATK \(e.atk) · ⚔ \(e.kills) kills")
                    .font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x555555))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(e.name), created by \(e.creator), \(e.kills) kills. \(e.desc)")
            HStack(spacing: 6) {
                ugc("Report", "Report enemy by \(e.creator)") { reason = ""; reporting = e }
                ugc("Block", "Block \(e.creator)") { blocking = e }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Theme.bgStone).overlay(Rectangle().stroke(Color(hex: 0x554488)))
    }

    private func ugc(_ t: String, _ voice: String, action: @escaping () -> Void) -> some View {
        Button(t, action: action)
            .font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0xc8a832))
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
            .accessibilityLabel(voice)
    }
}
