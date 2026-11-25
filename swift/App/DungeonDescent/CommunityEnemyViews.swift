import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Security
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
                    .owned(by: v["ownerUid"] as? String)
            }
            loadedAt = Date()
            failed = false
        } catch {
            failed = true
        }
        refreshPool(store)
    }

    func refreshPool(_ store: GameStore) { CommunityEnemies.pool = visible(store) }

    /// ecSubmit: fire and forget, like the web version. 12.2: it remembers
    /// who made it (ownerUid, and this device's list), so they can edit it.
    func submit(_ e: CommunityEnemies.Entry) {
        let data: [String: Any] = [
            "name": e.name, "desc": e.desc, "type": e.type, "dungeon": e.dungeon, "music": e.music ?? NSNull(),
            "creator": e.creator, "icon": e.icon, "hp": e.hp, "atk": e.atk, "def": e.def, "kills": 0,
            "createdAt": (Date().timeIntervalSince1970 * 1000).rounded(), "approved": true, "ownerUid": Self.ownerId,
        ]
        let ref = col.document()
        ref.setData(data) { _ in }
        Self.remember(ref.documentID)
        loadedAt = .distantPast
    }

    // MARK: Your own enemies (12.2)

    /// Who new enemies belong to: your account, or (signed out) your
    /// creator ID, which lives in iCloud Keychain so it survives deleting
    /// the app and follows you to your other Apple devices.
    static var ownerId: String { Auth.auth().currentUser?.uid ?? CreatorKey.id }

    /// Every ID that's yours (an enemy made signed out stays yours after you sign in).
    static var myIds: Set<String> {
        var s: Set<String> = [CreatorKey.id]
        if let uid = Auth.auth().currentUser?.uid { s.insert(uid) }
        return s
    }

    static var madeHere: [String] { UserDefaults.standard.stringArray(forKey: "swift_my_enemies") ?? [] }
    static func remember(_ id: String) { UserDefaults.standard.set(madeHere + [id], forKey: "swift_my_enemies") }

    /// The developer's account can edit every enemy (older ones saved no
    /// account, only a name anyone could type, so only the developer edits those).
    static var isDeveloper: Bool { CloudAccount.shared.isDeveloper }

    /// Yours: made with your account, or on this device.
    func isMine(_ e: CommunityEnemies.Entry, username: String?) -> Bool {
        if Self.isDeveloper { return true }
        if let o = e.owner { return Self.myIds.contains(o) }
        return Self.madeHere.contains(e.id)
    }

    @Published private(set) var mine: [CommunityEnemies.Entry] = []

    /// Every live enemy that's yours (not just the 50 the dungeon loads).
    func loadMine(username: String?) async {
        var found: [String: CommunityEnemies.Entry] = [:]
        func add(_ id: String, _ v: [String: Any]) {
            guard v["approved"] as? Bool == true, let name = v["name"] as? String else { return }
            func n(_ k: String) -> Int { (v[k] as? NSNumber)?.intValue ?? 0 }
            let e = CommunityEnemies.Entry(id: id, name: name, desc: v["desc"] as? String ?? "",
                                           type: v["type"] as? String ?? "common", dungeon: v["dungeon"] as? String ?? "all",
                                           music: v["music"] as? String, creator: v["creator"] as? String ?? "Unknown",
                                           icon: v["icon"] as? String ?? "👤", hp: n("hp"), atk: n("atk"), def: n("def"), kills: n("kills"))
                .owned(by: v["ownerUid"] as? String)
            if isMine(e, username: username) { found[e.id] = e }
        }
        if Self.isDeveloper {
            // Every live enemy, for the developer.
            for d in (try? await col.whereField("approved", isEqualTo: true).getDocuments())?.documents ?? [] { add(d.documentID, d.data()) }
        } else {
            for d in (try? await col.whereField("ownerUid", in: Array(Self.myIds)).getDocuments())?.documents ?? [] { add(d.documentID, d.data()) }
        }
        for id in Self.madeHere where found[id] == nil {
            if let d = try? await col.document(id).getDocument(), let v = d.data() { add(id, v) }
        }
        mine = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Saves your changes (and claims an older enemy for your account).
    func save(_ e: CommunityEnemies.Entry, username: String?) async -> String? {
        guard isMine(e, username: username) else { return "That enemy isn't yours." }
        do {
            // The developer's edits leave the enemy with whoever made it.
            var fields: [String: Any] = [
                "name": e.name, "desc": e.desc, "type": e.type, "icon": e.icon, "hp": e.hp, "atk": e.atk, "def": e.def,
                "editedAt": (Date().timeIntervalSince1970 * 1000).rounded(),
            ]
            // An enemy keeps the owner it has; one made here before it had one gets yours.
            if !Self.isDeveloper && e.owner == nil { fields["ownerUid"] = Self.ownerId }
            try await col.document(e.id).updateData(fields)
            loadedAt = .distantPast
            if let i = mine.firstIndex(where: { $0.id == e.id }) { mine[i] = Self.isDeveloper || e.owner != nil ? e : e.owned(by: Self.ownerId) }
            return nil
        } catch {
            return "Couldn't save it. Check your connection and try again."
        }
    }

    /// Takes it out of every dungeon. Kept (not erased) so moderation can still see it.
    func delete(_ e: CommunityEnemies.Entry, username: String?) async -> String? {
        guard isMine(e, username: username) else { return "That enemy isn't yours." }
        do {
            try await col.document(e.id).updateData([
                "approved": false, (Self.isDeveloper ? "deletedByDeveloper" : "deletedByOwner"): true,
                "moderatedAt": (Date().timeIntervalSince1970 * 1000).rounded(),
            ])
            loadedAt = .distantPast
            mine.removeAll { $0.id == e.id }
            entries.removeAll { $0.id == e.id }
            return nil
        } catch {
            return "Couldn't delete it. Check your connection and try again."
        }
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

    // MARK: Moderation (Developer Tools, 12.1)
    //
    // Every version of the game, the web included, only loads enemies marked
    // approved, so switching that off removes one for everyone at once, even
    // players who never update. Nothing is deleted: Restore brings it back.

    /// One enemy, by the ID in a report.
    func moderate(_ id: String, approved: Bool) async -> String {
        let clean = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Paste an enemy ID first." }
        do {
            let doc = try await col.document(clean).getDocument()
            guard doc.exists, let name = doc.data()?["name"] as? String else { return "No enemy with that ID." }
            try await col.document(clean).updateData(["approved": approved, "moderatedAt": (Date().timeIntervalSince1970 * 1000).rounded()])
            loadedAt = .distantPast
            return approved ? "\(name) is back in everyone's dungeons." : "\(name) is removed from everyone's dungeons."
        } catch {
            return "Couldn't change it: \(error.localizedDescription)"
        }
    }

    /// Every enemy one creator made.
    func removeAll(by creator: String) async -> String {
        let name = creator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Type the creator's name first." }
        do {
            let snap = try await col.whereField("creator", isEqualTo: name).getDocuments()
            guard !snap.documents.isEmpty else { return "No enemies by \(name)." }
            for d in snap.documents {
                try await d.reference.updateData(["approved": false, "moderatedAt": (Date().timeIntervalSince1970 * 1000).rounded()])
            }
            loadedAt = .distantPast
            return "Enemies removed by \(name): \(snap.documents.count)."
        } catch {
            return "Couldn't remove them: \(error.localizedDescription)"
        }
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
        (Text(t) + Text(hint.isEmpty ? "" : " (\(hint))").foregroundColor(Color(hex: 0x909090)))
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
            Text(t).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x909090))
            Text("\(v)" as String).font(Theme.decorative(18)).foregroundStyle(Self.violet)
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
    @State private var managing = false

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
            Button("🛠 My Enemies") { managing = true }
                .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xaa88ff))
                .frame(maxWidth: .infinity).padding(10)
                .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x554488)))
                .accessibilityLabel("My enemies. Rename, make stronger or delete the enemies you made")
            if pool.loading && pool.entries.isEmpty {
                note("Loading community enemies...")
            } else if pool.failed && pool.entries.isEmpty {
                note("Failed to load community enemies. Check your connection.")
            } else if pool.entries.isEmpty {
                note("No community enemies yet. Be the first to create one!")
            } else if list.isEmpty {
                note("No community enemies to show.")
            }
            EagerGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(list) { e in card(e) }
            }
        }
        .fullScreenCover(isPresented: $managing) { MyEnemiesView { managing = false } }
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
        Text(t).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x909090)).frame(maxWidth: .infinity).padding(20)
    }

    private func card(_ e: CommunityEnemies.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.icon).font(.system(size: 28)).accessibilityHidden(true)
                Text(e.name).font(Theme.cinzel(13)).foregroundStyle(Theme.textPrimary)
                Text("Created by \(e.creator)" as String).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0xaa88ff))
                if !e.desc.isEmpty { Text(e.desc).font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textSecondary) }
                Text("\(e.dungeon == "all" ? "All Dungeons" : e.dungeon) · \(e.type) · HP \(e.hp) · ATK \(e.atk) · ⚔ \(e.kills) kills" as String)
                    .font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x909090))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(e.name), created by \(e.creator), \(e.kills) kills. \(e.desc)" as String)
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

/// 12.2: the creator ID for players who aren't signed in, kept in iCloud
/// Keychain (synchronizable), so deleting the app or moving to another
/// iPhone, iPad, Mac or Apple Vision Pro on the same Apple ID keeps it.
@MainActor
enum CreatorKey {
    private static let service = "com.dungeon.descent.creator"
    private static let account = "creator-id"
    private static var cached: String?

    static var id: String {
        if let c = cached { return c }
        if let k = read() { cached = k; return k }
        // An ID from an earlier build on this device, or a new one.
        let new = UserDefaults.standard.string(forKey: "swift_owner_device_id") ?? "device-" + UUID().uuidString
        save(new)
        UserDefaults.standard.set(new, forKey: "swift_owner_device_id")
        cached = new
        return new
    }

    private static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func save(_ value: String) {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8),
        ]
        _ = SecItemAdd(item as CFDictionary, nil)
    }
}

