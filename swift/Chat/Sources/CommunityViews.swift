import SwiftUI
import DungeonCore

// MARK: - Activity

/// Everything aimed at you in one list: @mentions, replies to your messages
/// and reactions to them. Each one opens the conversation at that message.
struct ActivityView: View {
    @EnvironmentObject var chat: ChatService
    @State private var target: OpenTarget?
    @State private var profileUID: ProfileTarget?
    @State private var confirmClear = false
    /// What counted as new when you opened the tab (so the "new" marks stay while you read).
    @State private var seenAtOpen = Date()

    private var shown: [ActivityItem] { chat.activity.filter { chat.blocked[$0.fromUID] == nil } }

    var body: some View {
        NavigationStack {
            List {
                if shown.isEmpty {
                    Text("Nothing yet. When someone mentions you with @\(chat.member?.username ?? "your name"), replies to you or reacts to your message, it shows up here.")
                }
                let new = shown.filter { $0.date > seenAtOpen }
                let earlier = shown.filter { $0.date <= seenAtOpen }
                if !new.isEmpty { Section("New") { ForEach(new) { row($0, isNew: true) } } }
                if !earlier.isEmpty { Section(new.isEmpty ? "" : "Earlier") { ForEach(earlier) { row($0, isNew: false) } } }
            }
            .navigationTitle("Activity")
            .toolbar { if !shown.isEmpty { Button("Clear all") { confirmClear = true } } }
            .navigationDestination(item: $target) { ConversationView(room: $0.room, focus: $0.focus) }
            .sheet(item: $profileUID) { ProfileView(uid: $0.id) }
            .confirmationDialog("Clear all activity?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear all", role: .destructive) { Task { await chat.clearActivity(); Speech.say("Activity cleared.") } }
            }
            .onAppear { seenAtOpen = chat.activitySeen; chat.markActivitySeen() }
            .onDisappear { chat.markActivitySeen() }
            .onChange(of: chat.activity.first?.id) { _, _ in chat.markActivitySeen() }
        }
    }

    private func row(_ a: ActivityItem, isNew: Bool) -> some View {
        Button { open(a) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(a.headline).font(.subheadline.weight(isNew ? .bold : .semibold))
                if !a.text.isEmpty { Text("“\(a.text)”").lineLimit(3).foregroundStyle(.secondary) }
                Text(a.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((isNew ? "New. " : "") + a.spokenHeadline + (a.text.isEmpty ? "" : ": " + a.text))
        .accessibilityValue(a.date.formatted(.relative(presentation: .named)))
        .accessibilityHint("Opens the conversation at that message.")
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            Button("View \(a.from)'s profile") { profileUID = ProfileTarget(id: a.fromUID) }
            Button("Remove") { Task { await chat.removeActivity(a) } }
        }
        .contextMenu {
            Button("View \(a.from)'s profile") { profileUID = ProfileTarget(id: a.fromUID) }
            Button("Remove", role: .destructive) { Task { await chat.removeActivity(a) } }
        }
        .swipeActions { Button("Remove", role: .destructive) { Task { await chat.removeActivity(a) } } }
    }

    private func open(_ a: ActivityItem) {
        guard let room = chat.room(kind: a.roomKind, id: a.room) else {
            Speech.say("That conversation isn't available anymore.")
            return
        }
        target = OpenTarget(room: room, focus: a.messageID)
    }
}

// MARK: - Community

/// What's going on in the game: events, the weekly challenges, leaderboards,
/// the latest Hall of Legends posts and who's online.
struct CommunityView: View {
    @EnvironmentObject var chat: ChatService
    @State private var worldBossTotal: Int?
    @State private var legends: [ChatMessage] = []
    @State private var nextEvent: (title: String, days: Int)?
    @State private var legendsRoom: Room?

    var body: some View {
        let now = Date()
        let banner = Events.bannerLines(on: now)
        let weekly = Challenges.weekly(now)
        let season = Tournament.season(now)
        let boss = WorldBoss.day(now)
        NavigationStack {
            List {
                Section("Happening now") {
                    if banner.isEmpty {
                        Text("No event is running today.")
                    } else {
                        ForEach(banner, id: \.self) { line in
                            Text(line.replacingOccurrences(of: " · ACTIVE · ", with: ": "))
                        }
                    }
                    if let n = nextEvent, n.days > 0 {
                        Text("Next: \(n.title), in \(n.days) \(n.days == 1 ? "day" : "days")").foregroundStyle(.secondary)
                    }
                    NavigationLink("All events") { EventsListView() }
                }
                Section("Challenges") {
                    NavigationLink {
                        LeaderboardView(title: "Weekly Ladder, \(weekly.name)", unit: "points",
                                        intro: "\(weekly.dungeon), with \(weekly.mods.map(\.name).joined(separator: " and ")). One life. It starts over every Monday.") {
                            await chat.board(weekly.season)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Weekly Ladder, \(weekly.name)").font(.headline)
                            Text("\(weekly.dungeon): \(weekly.mods.map(\.name).joined(separator: ", "))").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    NavigationLink {
                        LeaderboardView(title: "World Boss today", unit: "damage", intro: WorldBoss.status(boss, totalDamage: worldBossTotal)) {
                            await chat.board(boss.season)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text("World Boss: \(boss.boss.name)").font(.headline)
                            Text(WorldBoss.status(boss, totalDamage: worldBossTotal)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    NavigationLink {
                        LeaderboardView(title: "Tournament, \(season.name)", unit: "points",
                                        intro: season.active ? "\(season.boss.name). \(season.hoursLeft) hours left." : "The last Tournament's final scores. The next one starts in \(season.daysUntil) days.") {
                            await chat.board(season.key)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(season.active ? "Tournament: \(season.boss.icon) \(season.boss.name)" : "Tournament").font(.headline)
                            Text(season.active ? "\(season.name), \(season.hoursLeft) hours left" : "Next one in \(season.daysUntil) days. See \(season.name)'s results.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section("Leaderboards") {
                    NavigationLink("High Score") {
                        LeaderboardView(title: "High Score", unit: "points", intro: "Everyone's best High Score total, as uploaded from the game.") {
                            await chat.highScores()
                        }
                    }
                    NavigationLink("Endless Descent") {
                        LeaderboardView(title: "Endless Descent", unit: "floor", intro: "The deepest floors reached in Endless Descent.") {
                            await chat.board(AFKRivals.season)
                        }
                    }
                }
                Section("Hall of Legends") {
                    if legends.isEmpty { Text("No legends yet. Conquer a dungeon in the game to be the first.") }
                    ForEach(legends.prefix(5)) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.text)
                            Text(m.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if let room = chat.room(kind: "channel", id: "hall-of-legends") {
                        Button("Open #\(room.title)") { legendsRoom = room }
                    }
                }
                Section("Players") {
                    NavigationLink("\(chat.online.count) \(chat.online.count == 1 ? "player" : "players") online") { OnlineList() }
                }
            }
            .navigationTitle("Community")
            .navigationDestination(item: $legendsRoom) { ConversationView(room: $0) }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func refresh() async {
        async let total = chat.worldBossTotal(WorldBoss.day().season)
        async let posts = chat.legends()
        async let next = Task.detached { () -> (String, Int)? in
            let now = Date()
            let running = Events.active(on: now)
            return Events.list.filter { $0.id != running }
                .map { ($0.title, Events.daysUntil($0.id, from: now)) }
                .filter { $0.1 > 0 }
                .min { $0.1 < $1.1 }
        }.value
        worldBossTotal = await total
        legends = await posts
        nextEvent = await next.map { (title: $0.0, days: $0.1) }
        await chat.refreshOnline()
    }
}

/// Who's online (inside the Community tab).
struct OnlineList: View {
    @EnvironmentObject var chat: ChatService

    var body: some View {
        List {
            if chat.online.isEmpty { Text("Nobody else is online right now.") }
            ForEach(chat.online, id: \.self) { Text($0) }
        }
        .navigationTitle("\(chat.online.count) online")
        .refreshable { await chat.refreshOnline() }
        .task { await chat.refreshOnline() }
    }
}

/// Every event in the game, soonest first, with what it brings.
struct EventsListView: View {
    struct Row: Identifiable {
        let id, title, desc, bonuses, dates: String
        let running: Bool
        let days: Int
    }
    @State private var rows: [Row] = []

    var body: some View {
        List {
            if rows.isEmpty { ProgressView() }
            ForEach(rows) { r in
                DisclosureGroup {
                    Text(r.desc)
                    Text(r.bonuses).font(.subheadline)
                    Text(r.dates).font(.caption).foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading) {
                        Text(r.title).font(.headline)
                        Text(r.running ? "Running now" : r.days == 1 ? "Starts tomorrow" : "Starts in \(r.days) days")
                            .font(.subheadline).foregroundStyle(r.running ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Events")
        .task {
            rows = await Task.detached {
                let now = Date()
                let running = Events.active(on: now)
                return Events.list.map { e in
                    Row(id: e.id, title: e.title, desc: e.desc, bonuses: e.bonuses, dates: e.dates,
                        running: e.id == running, days: e.id == running ? 0 : Events.daysUntil(e.id, from: now))
                }
                .sorted { ($0.running ? -1 : $0.days == 0 ? 9999 : $0.days) < ($1.running ? -1 : $1.days == 0 ? 9999 : $1.days) }
            }.value
        }
    }
}

/// One of the game's leaderboards. Names that belong to chat members open their profile.
struct LeaderboardView: View {
    @EnvironmentObject var chat: ChatService
    let title: String
    let unit: String
    let intro: String
    let load: () async -> [BoardEntry]
    @State private var entries: [BoardEntry] = []
    @State private var loaded = false
    @State private var profileUID: ProfileTarget?

    init(title: String, unit: String, intro: String, load: @escaping () async -> [BoardEntry]) {
        self.title = title
        self.unit = unit
        self.intro = intro
        self.load = load
    }

    var body: some View {
        List {
            if !intro.isEmpty { Section { Text(intro) } }
            Section {
                if loaded && entries.isEmpty { Text("No scores yet. Be the first!") }
                if !loaded { ProgressView() }
                ForEach(entries) { e in
                    Button { Task { await openProfile(e) } } label: {
                        HStack {
                            Text("\(e.rank).").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 28, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(e.name + (e.id == chat.member?.uid ? " (you)" : "")).fontWeight(e.id == chat.member?.uid ? .bold : .regular)
                                if !e.detail.isEmpty { Text(e.detail).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(score(e)).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Number \(e.rank), \(e.name)\(e.id == chat.member?.uid ? ", you" : ""), \(score(e))" + (e.detail.isEmpty ? "" : ", \(e.detail)"))
                    .accessibilityHint("Opens their chat profile, if they're in chat.")
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .navigationTitle(title)
        .sheet(item: $profileUID) { ProfileView(uid: $0.id) }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func score(_ e: BoardEntry) -> String {
        unit == "floor" ? "Floor \(e.score.formatted())" : "\(e.score.formatted()) \(unit)"
    }

    private func reload() async {
        entries = await load()
        loaded = true
    }

    private func openProfile(_ e: BoardEntry) async {
        if await chat.isChatMember(e.id) { profileUID = ProfileTarget(id: e.id) }
        else { Speech.say("\(e.name) isn't in Dungeon Descent Chat yet.") }
    }
}

// MARK: - Profile (you)

/// Your own profile: what others see, your "about me" and favorite class,
/// your game stats, and Settings.
struct MeView: View {
    @EnvironmentObject var chat: ChatService
    @State private var bio = ""
    @State private var favClass = ""
    @State private var stats: Profile?
    @State private var problem = ""
    @State private var showPublic = false
    private var edited: Bool { bio != (chat.member?.bio ?? "") || favClass != (chat.member?.favClass ?? "") }

    var body: some View {
        NavigationStack {
            Form {
                if let me = chat.member {
                    Section {
                        LabeledContent("Username", value: me.username)
                        LabeledContent("Role", value: chat.isDeveloper ? "Developer" : me.mod ? "Moderator" : me.tester ? "Tester" : "Member")
                        LabeledContent("Joined chat", value: me.createdAt.formatted(date: .abbreviated, time: .omitted))
                        Button("See my profile as others do") { showPublic = true }
                    }
                    Section {
                        TextField("A line or two about you", text: $bio, axis: .vertical)
                            .lineLimit(2...5)
                        Picker("Favorite class", selection: $favClass) {
                            Text("None").tag("")
                            ForEach(ChatService.classes, id: \.self) { Text(ChatService.className($0)).tag($0) }
                        }
                        if !problem.isEmpty { Text(problem).foregroundStyle(.orange) }
                        Button("Save profile") {
                            Task {
                                if let p = await chat.saveProfile(bio: bio, favClass: favClass) { problem = p; Speech.say(p) }
                                else { problem = ""; Speech.say("Profile saved.") }
                            }
                        }
                        .disabled(!edited)
                    } header: { Text("About me") } footer: { Text("\(bio.count) of 160 characters. Everyone in chat can see this.") }
                    Section("In the game") {
                        if let s = stats {
                            LabeledContent("High Score", value: s.highScore?.formatted() ?? "Not uploaded yet")
                            LabeledContent("Endless Descent best", value: s.endlessFloor.map { "Floor \($0.formatted())" } ?? "None yet")
                            LabeledContent("Weekly Ladder this week", value: s.weeklyScore?.formatted() ?? "Not played yet")
                        } else {
                            ProgressView()
                        }
                        Text("These come from the game when you're signed in with the same account.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section {
                        NavigationLink("Settings") { SettingsView() }
                    }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPublic) { if let uid = chat.member?.uid { ProfileView(uid: uid) } }
            .task {
                bio = chat.member?.bio ?? ""
                favClass = chat.member?.favClass ?? ""
                if let uid = chat.member?.uid { stats = await chat.profile(uid: uid) }
            }
        }
    }
}
