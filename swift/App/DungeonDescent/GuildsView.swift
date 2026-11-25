import SwiftUI
import DungeonCore

/// 12.2 Guilds: find or start a guild of up to 20 players, talk in its own
/// chat, and fight the weekly Guild Boss together. Each part is its own page,
/// with a Back button at the top.
struct GuildsView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @ObservedObject private var guilds = GuildStore.shared
    @ObservedObject private var account = CloudAccount.shared

    enum Page: Hashable { case home, create, browse, chat, boss, members, rankings, manage }
    @State private var page = Page.home
    @State private var loadingList = false
    @State private var listFailed = false
    @State private var message = ""
    @State private var busy = false
    // Create and manage.
    @State private var nameDraft = ""
    @State private var descDraft = ""
    // Chat.
    @State private var draft = ""
    @State private var askingTerms = false
    @State private var reportingMessage: GuildStore.Message?
    @State private var reportingGuild: GuildStore.Guild?
    @State private var reportReason = ""
    @State private var blocking: GuildStore.Message?
    // Leader and member actions.
    @State private var confirmingLeave = false
    @State private var confirmingDisband = false
    @State private var removing: (uid: String, name: String)?
    @State private var promoting: (uid: String, name: String)?
    @State private var devRemoving: GuildStore.Guild?
    // The boss.
    @State private var week = Guilds.week()
    @State private var charIndex = 0
    @State private var log: [String] = []
    @State private var dice = SystemDice()

    private let teal = Color(hex: 0x66ddcc)

    var body: some View {
        WebScreen { content }
            .id(page)
            .task { await guilds.loadMine(); announceHome() }
            .onChange(of: account.user?.uid) { _ in Task { await guilds.loadMine() } }
            .onDisappear { guilds.closeChat() }
            .alert("Before you post", isPresented: $askingTerms) {
                Button("I agree") { GlobalChat(store: game.store).agree(); sendDraft() }
                Button("Cancel", role: .cancel) { Feedback.announce("You need to agree to the Terms of Service to post.") }
            } message: {
                Text("Guild chat is seen by every member of your guild. By continuing you agree to the Dungeon Descent Terms of Service at dungen-descent.org/terms. There is no tolerance for objectionable content or abusive players. You can report or block anyone. Do you agree?")
            }
            .alert("Report", isPresented: Binding(get: { reportingMessage != nil || reportingGuild != nil },
                                                   set: { if !$0 { reportingMessage = nil; reportingGuild = nil } })) {
                TextField("Reason (optional)", text: $reportReason)
                Button("Send report") {
                    let reporter = GlobalChat(store: game.store).username
                    if let m = reportingMessage { Task { await guilds.report(m, reason: reportReason, reporter: reporter) } }
                    if let g = reportingGuild { Task { await guilds.report(guild: g, reason: reportReason, reporter: reporter) } }
                    reportingMessage = nil; reportingGuild = nil
                }
                Button("Cancel", role: .cancel) { reportingMessage = nil; reportingGuild = nil; Feedback.announce("Report cancelled.") }
            } message: {
                Text("What is wrong with it? For example: offensive, harassment, spam. You can also leave this empty.")
            }
            .alert("Block \(blocking?.username ?? "")?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } })) {
                Button("Block", role: .destructive) {
                    if let m = blocking { GlobalChat(store: game.store).block(m.username); guilds.closeChat(); guilds.openChat(store: game.store) }
                    blocking = nil
                }
                Button("Cancel", role: .cancel) { blocking = nil }
            } message: {
                Text("You will no longer see their messages. You can unblock everyone later in Settings, Chat.")
            }
            .alert("Leave \(guilds.mine?.name ?? "the guild")?", isPresented: $confirmingLeave) {
                Button("Leave", role: .destructive) { act { await guilds.leave() } done: { go(.home, "You left the guild.") } }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Disband \(guilds.mine?.name ?? "the guild")?", isPresented: $confirmingDisband) {
                Button("Disband", role: .destructive) { act { await guilds.disband() } done: { go(.home, "The guild has been disbanded.") } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The guild ends for every member. This can't be undone.")
            }
            .alert("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Remove", role: .destructive) {
                    if let r = removing { act { await guilds.remove(r.uid) } done: { Feedback.announce("\(r.name) was removed from the guild.") } }
                    removing = nil
                }
                Button("Cancel", role: .cancel) { removing = nil }
            }
            .alert("Make \(promoting?.name ?? "") the leader?", isPresented: Binding(get: { promoting != nil }, set: { if !$0 { promoting = nil } })) {
                Button("Make Leader") {
                    if let r = promoting { act { await guilds.makeLeader(r.uid) } done: { Feedback.announce("\(r.name) now leads the guild.") } }
                    promoting = nil
                }
                Button("Cancel", role: .cancel) { promoting = nil }
            } message: {
                Text("You stay in the guild as a member.")
            }
            .alert("Remove \(devRemoving?.name ?? "")?", isPresented: Binding(get: { devRemoving != nil }, set: { if !$0 { devRemoving = nil } })) {
                Button("Remove Guild", role: .destructive) {
                    if let g = devRemoving { act { await guilds.disband(g) } done: { Feedback.announce("\(g.name) was removed.") } }
                    devRemoving = nil
                }
                Button("Cancel", role: .cancel) { devRemoving = nil }
            } message: {
                Text("Developer: this disbands the guild for every member.")
            }
    }

    // MARK: Pages

    @ViewBuilder private var content: some View {
        switch page {
        case .home: home
        case .create: createPage
        case .browse: browsePage
        case .chat: chatPage
        case .boss: bossPage
        case .members: membersPage
        case .rankings: rankingsPage
        case .manage: managePage
        }
    }

    private func back(_ label: String = "← Back to Your Guild") -> some View {
        Button(guilds.mine == nil && label == "← Back to Your Guild" ? "← Back to Guilds" : label) { go(.home) }
            .buttonStyle(BackButtonStyle())
    }

    private func heading(_ title: String, _ sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.decorative(20)).foregroundStyle(teal).accessibilityAddTraits(.isHeader)
            if let sub { Text(sub).font(Theme.crimson(13.5, italic: true)).foregroundStyle(Theme.textSecondary) }
        }
    }

    private var status: some View {
        Group {
            if !message.isEmpty {
                Text(message).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xa0d4a0))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder private var home: some View {
        Button("← Menu") { Sound.track("menu"); router.goTo(.menu) }
            .buttonStyle(BackButtonStyle()).accessibilityLabel("Back to main menu")
        if let g = guilds.mine {
            heading("🛡 \(g.name)", g.desc.isEmpty ? nil : g.desc)
            Text("\(g.members.count) of \(Guilds.maxMembers) members · Leader: \(g.leaderName)" as String)
                .font(Theme.cinzel(11)).foregroundStyle(Theme.gold)
            Text("This week: \(week.boss.name) · \(g.thisWeek.formatted()) damage" as String)
                .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x999999))
            pageButton("💬 Guild Chat", "Guild chat, talk to your guild", .chat, kind: .gold)
            pageButton("🐉 Guild Boss", "Guild Boss, this week's boss: \(week.boss.name)", .boss, kind: .red)
            pageButton("👥 Members (\(g.members.count))", "Members, \(g.members.count) of \(Guilds.maxMembers)", .members)
            pageButton("🏆 Guild Rankings", "Guild rankings, the strongest guilds this week", .rankings)
            if guilds.isLeader {
                pageButton("⚙ Manage Guild", "Manage guild: description, or disband it", .manage)
            }
            Button("🚪 Leave Guild") {
                if guilds.isLeader && g.members.count > 1 {
                    Feedback.announce("You lead \(g.name). Make another member the leader first (Members), or disband the guild (Manage Guild).")
                } else { confirmingLeave = true }
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity).padding(.top, 14)
        } else {
            heading("🛡 Guilds", "Up to \(Guilds.maxMembers) players under one banner, with their own chat and a Guild Boss every week.")
            if !guilds.signedIn {
                Text("Guilds need an account, so everyone knows who's who. Sign in under Settings, Account, then come back.")
                    .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
                Button("⚙ Go to Settings") { router.goTo(.settings) }.buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
            } else if !guilds.checked {
                Text("Looking for your guild...").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
            } else {
                pageButton("🔍 Find a Guild", "Find a guild to join", .browse, kind: .gold)
                pageButton("➕ Create a Guild", "Create a guild and lead it", .create)
                pageButton("🏆 Guild Rankings", "Guild rankings, the strongest guilds this week", .rankings)
            }
        }
        status
    }

    private func pageButton(_ title: String, _ label: String, _ p: Page, kind: WebButtonStyle.Kind = .ghost) -> some View {
        Button(title) { go(p) }
            .buttonStyle(WebButtonStyle(kind: kind)).frame(maxWidth: .infinity)
            .accessibilityLabel(label)
    }

    @ViewBuilder private var createPage: some View {
        back("← Back to Guilds")
        heading("➕ Create a Guild", "You'll be its leader. 3 to 24 letters, numbers, spaces, apostrophes or hyphens.")
        Text("GUILD NAME").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.goldDim).accessibilityHidden(true)
        TextField("Guild name", text: $nameDraft)
            .textFieldStyle(.roundedBorder).accessibilityLabel("Guild name, 3 to 24 characters")
            .onChange(of: nameDraft) { v in if v.count > 24 { nameDraft = String(v.prefix(24)) } }
        Text("DESCRIPTION").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.goldDim).accessibilityHidden(true)
        TextField("What is your guild about? (optional)", text: $descDraft, axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(2...4).accessibilityLabel("Guild description, optional, up to 120 characters")
            .onChange(of: descDraft) { v in if v.count > 120 { descDraft = String(v.prefix(120)) } }
        Button(busy ? "Creating..." : "🛡 Create Guild") {
            let name = nameDraft
            act { await guilds.create(name: name, desc: descDraft, store: game.store) } done: {
                Sound.sfx("sfx-victory")
                nameDraft = ""; descDraft = ""
                go(.home, "\(name) is founded. You are its leader. Share the name so friends can find it.")
            }
        }
        .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity).disabled(busy)
        status
    }

    @ViewBuilder private var browsePage: some View {
        back("← Back to Guilds")
        heading("🔍 Find a Guild", "Choose one to join. The strongest this week are first.")
        if loadingList {
            Text("Loading guilds...").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
        } else if listFailed {
            Text("Couldn't load the guilds. Check your connection.").font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
        } else if guilds.all.isEmpty {
            Text("No guilds yet. Create the first one!").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
        }
        ForEach(guilds.all) { g in
            let full = g.members.count >= Guilds.maxMembers
            VStack(alignment: .leading, spacing: 6) {
                Text("🛡 \(g.name)" as String).font(Theme.cinzel(13)).foregroundStyle(Theme.textPrimary)
                if !g.desc.isEmpty { Text(g.desc).font(Theme.crimson(13)).foregroundStyle(Theme.textSecondary) }
                Text("\(g.members.count) of \(Guilds.maxMembers) members · Leader: \(g.leaderName) · \(g.thisWeek.formatted()) damage this week" as String)
                    .font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x909090))
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Button(full ? "Full" : "Join") {
                    act { await guilds.join(g, store: game.store) } done: {
                        Sound.sfx("sfx-confirm")
                        go(.home, "You joined \(g.name)! Say hello in Guild Chat.")
                    }
                }
                .buttonStyle(WebButtonStyle(kind: full ? .ghost : .gold)).disabled(full || busy)
                .accessibilityLabel(full ? "\(g.name) is full" : "Join \(g.name)")
                Button("Report") { reportReason = ""; reportingGuild = g }
                    .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Report \(g.name)")
                if CloudAccount.shared.isDeveloper {
                    Button("Remove") { devRemoving = g }
                        .buttonStyle(WebButtonStyle(kind: .red)).accessibilityLabel("Developer: remove \(g.name)")
                }
            }
            Rectangle().fill(Color(hex: 0x1a1a1a)).frame(height: 1).accessibilityHidden(true)
        }
        status
    }

    @ViewBuilder private var chatPage: some View {
        back()
        heading("💬 Guild Chat", "Only members of \(guilds.mine?.name ?? "your guild") see these messages. Every message has Report and Block.")
        VStack(alignment: .leading, spacing: 0) {
            if guilds.chat.isEmpty {
                Text("No messages yet. Say hello!").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x909090)).padding(20)
            }
            ForEach(guilds.chat) { m in
                let mine = m.uid == guilds.uid
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.username).font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: mine ? 0xc8a832 : 0x88aacc))
                        Text(m.timestamp > 0 ? GlobalChat.ago(m.timestamp) : "").font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0x909090))
                    }
                    Text(m.message).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xaaaaaa)).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.username) said \(m.message). \(m.timestamp > 0 ? GlobalChat.ago(m.timestamp) : "")" as String)
                HStack(spacing: 6) {
                    if !mine {
                        Button("Report") { reportReason = ""; reportingMessage = m }.accessibilityLabel("Report message by \(m.username)")
                        Button("Block") { blocking = m }.accessibilityLabel("Block \(m.username)")
                    }
                    if guilds.canDelete(m) {
                        Button("Delete") { Task { await guilds.delete(m) }; Feedback.announce("Message deleted.") }
                            .accessibilityLabel("Delete message by \(m.username)")
                    }
                }
                .font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0xc8a832)).padding(.top, 4)
                Rectangle().fill(Color(hex: 0x111111)).frame(height: 1).padding(.vertical, 6).accessibilityHidden(true)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x060600)).overlay(Rectangle().stroke(Color(hex: 0x113322)))
        HStack(spacing: 8) {
            TextField("Type a message...", text: $draft)
                .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xcccccc))
                .padding(10).background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x224433)))
                .accessibilityLabel("Guild message, maximum 200 characters")
                .submitLabel(.send).onSubmit(trySend)
                .onChange(of: draft) { v in if v.count > 200 { draft = String(v.prefix(200)) } }
            Button("Send", action: trySend)
                .font(Theme.cinzel(11.2)).foregroundStyle(Theme.gold)
                .padding(.vertical, 10).padding(.horizontal, 16)
                .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Theme.gold))
                .accessibilityLabel("Send message")
        }
    }

    @ViewBuilder private var bossPage: some View {
        let members = guilds.mine?.members.count ?? 1
        let total = guilds.bossTotal
        let hp = Guilds.remaining(totalDamage: total ?? 0, members: members)
        let left = Guilds.strikesLeft(store: game.store)
        back()
        heading("🐉 \(week.boss.name)", week.boss.intro)
        VStack(alignment: .leading, spacing: 4) {
            Text("GUILD BOSS — THIS WEEK").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x909090))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: 0x111111))
                    Rectangle().fill(Color(hex: 0xcc4422)).frame(width: g.size.width * Double(hp) / Double(Guilds.hp(members: members)))
                }
            }
            .frame(height: 12)
            Text(total == nil ? "Loading..." : "\(hp.formatted()) / \(Guilds.hp(members: members).formatted()) HP")
                .font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xff8866))
            Text("Your damage this week: \(Guilds.myDamage(week, store: game.store).formatted()) · \(left) of \(Guilds.strikesPerDay) strikes left today · \(Guilds.daysLeft()) days until the next boss" as String)
                .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x888888))
            Text("Kill reward: \(Guilds.goldReward.formatted()) gold + \(Guilds.fragmentReward) Soul Fragments for every member who struck. Its HP grows with the guild." as String)
                .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x44cc88))
        }
        .padding(12).overlay(Rectangle().stroke(Color(hex: 0x4a1a1a)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Guilds.status(week, totalDamage: total, members: members)
                            + " Your damage this week: \(Guilds.myDamage(week, store: game.store)). \(left) strikes left today.")
        if let total, Guilds.remaining(totalDamage: total, members: members) == 0 {
            Text("It has fallen. Every member who struck it collects the reward. A new boss comes on Monday (UTC).")
                .font(Theme.crimson(14)).foregroundStyle(Color(hex: 0x44cc88))
        } else if left > 0 {
            Text("Choose your champion").font(Theme.cinzel(12)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                Button("\(ch.name) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))" as String) {
                    charIndex = i
                    Feedback.announce("\(ch.name) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == charIndex ? .gold : .ghost))
                .accessibilityAddTraits(i == charIndex ? .isSelected : [])
            }
            Button("⚔ Strike (\(left) left today)" as String) { strike() }
                .buttonStyle(WebButtonStyle(kind: .red)).disabled(game.characters.isEmpty || total == nil)
                .accessibilityLabel("Strike \(week.boss.name). \(left) strikes left today." as String)
        } else {
            Text("You've used all \(Guilds.strikesPerDay) strikes today. Come back tomorrow." as String)
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
        }
        if !log.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(log.prefix(10).enumerated()), id: \.offset) { _, l in
                    Text(l).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x999999))
                }
            }
            .accessibilityElement(children: .combine).accessibilityLabel("Strike log")
        }
        if !guilds.hits.isEmpty {
            Text("⚔ THIS WEEK'S DAMAGE").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader).padding(.top, 8)
            ForEach(Array(guilds.hits.enumerated()), id: \.element.id) { i, h in
                Text("\(i + 1). \(h.name) — \(h.damage.formatted())" as String)
                    .font(Theme.cinzel(11)).foregroundStyle(i == 0 ? Theme.gold : Color(hex: 0xaaaaaa))
            }
        }
    }

    @ViewBuilder private var membersPage: some View {
        let g = guilds.mine
        back()
        heading("👥 Members", "\(g?.members.count ?? 0) of \(Guilds.maxMembers)." + (guilds.isLeader ? " As leader you can remove a member or make them the leader." : ""))
        ForEach(g?.roster ?? [], id: \.uid) { m in
            let leader = m.uid == g?.leader
            let me = m.uid == guilds.uid
            Text("\(leader ? "👑 " : "")\(m.name)\(me ? " (you)" : "")" as String)
                .font(Theme.cinzel(12)).foregroundStyle(leader ? Theme.gold : Theme.textPrimary)
                .accessibilityLabel("\(m.name)\(leader ? ", leader" : "")\(me ? ", you" : "")" as String)
            if guilds.isLeader && !me {
                HStack(spacing: 8) {
                    Button("Make Leader") { promoting = (m.uid, m.name) }
                        .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Make \(m.name) the leader")
                    Button("Remove") { removing = (m.uid, m.name) }
                        .buttonStyle(WebButtonStyle(kind: .red)).accessibilityLabel("Remove \(m.name) from the guild")
                }
            }
        }
        status
    }

    @ViewBuilder private var rankingsPage: some View {
        back(guilds.mine == nil ? "← Back to Guilds" : "← Back to Your Guild")
        heading("🏆 Guild Rankings", "Guild Boss damage this week (\(week.key)), every member's strikes added up.")
        if loadingList {
            Text("Loading guilds...").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
        } else if listFailed {
            Text("Couldn't load the rankings. Check your connection.").font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
        }
        let ranked = guilds.all.filter { $0.thisWeek > 0 }
        if !loadingList && !listFailed && ranked.isEmpty {
            Text("No guild has struck this week's boss yet.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
        }
        ForEach(Array(ranked.prefix(50).enumerated()), id: \.element.id) { i, g in
            Text("\(i + 1). \(g.name) — \(g.thisWeek.formatted()) damage · \(g.members.count) members" as String)
                .font(Theme.cinzel(11.5)).foregroundStyle(g.id == guilds.mine?.id ? Theme.gold : Color(hex: 0xaaaaaa))
        }
    }

    @ViewBuilder private var managePage: some View {
        back()
        heading("⚙ Manage Guild", guilds.mine?.name)
        Text("DESCRIPTION").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.goldDim).accessibilityHidden(true)
        TextField("What is your guild about?", text: $descDraft, axis: .vertical)
            .textFieldStyle(.roundedBorder).lineLimit(2...4).accessibilityLabel("Guild description, up to 120 characters")
            .onChange(of: descDraft) { v in if v.count > 120 { descDraft = String(v.prefix(120)) } }
        Button("💾 Save Description") {
            act { await guilds.setDesc(descDraft) } done: { Sound.sfx("sfx-confirm"); message = "Description saved."; Feedback.announce(message) }
        }
        .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity).disabled(busy)
        Text("To hand the guild to someone else, open Members and choose Make Leader.")
            .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary).padding(.top, 8)
        Button("🗑 Disband Guild") { confirmingDisband = true }
            .buttonStyle(WebButtonStyle(kind: .red)).frame(maxWidth: .infinity).padding(.top, 20)
            .accessibilityLabel("Disband \(guilds.mine?.name ?? "the guild") for every member")
        status
    }

    // MARK: Actions

    private func go(_ p: Page, _ say: String? = nil) {
        message = ""
        page = p
        Sound.sfx("sfx-select")
        switch p {
        case .home:
            guilds.closeChat()
            if let say { message = say; Feedback.announce(say, after: 0.3) } else { announceHome() }
        case .browse, .rankings:
            Feedback.announce(p == .browse ? "Find a Guild. Loading guilds." : "Guild Rankings. Loading.", after: 0.3)
            Task { await loadList(announce: p) }
        case .create:
            Feedback.announce("Create a Guild. Type a name, then Create Guild.", after: 0.3)
        case .chat:
            guilds.openChat(store: game.store)
            Feedback.announce("Guild Chat. New messages are read out as they arrive.", after: 0.3)
        case .boss:
            week = Guilds.week()
            Sound.track("boss")
            Task { await loadBoss(announce: true) }
        case .members:
            let n = guilds.mine?.members.count ?? 0
            Feedback.announce("Members. \(n) of \(Guilds.maxMembers).", after: 0.3)
        case .manage:
            descDraft = guilds.mine?.desc ?? ""
            Feedback.announce("Manage Guild.", after: 0.3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { UIAccessibility.post(notification: .screenChanged, argument: nil) }
    }

    private func announceHome() {
        guard guilds.checked else { return }
        if let g = guilds.mine {
            Feedback.announce("\(g.name). \(g.members.count) of \(Guilds.maxMembers) members. This week's Guild Boss: \(week.boss.name).", after: 0.3)
        } else if !guilds.signedIn {
            Feedback.announce("Guilds. Sign in under Settings, Account, to join or create a guild.", after: 0.3)
        } else {
            Feedback.announce("Guilds. You're not in a guild yet. Find one to join, or create your own.", after: 0.3)
        }
    }

    private func loadList(announce p: Page) async {
        loadingList = true
        listFailed = !(await guilds.loadAll())
        loadingList = false
        if listFailed { Feedback.announce("Couldn't load the guilds. Check your connection."); return }
        if p == .browse {
            Feedback.announce(guilds.all.isEmpty ? "No guilds yet. Create the first one!" : "\(guilds.all.count) guilds.")
        } else {
            let n = guilds.all.filter { $0.thisWeek > 0 }.count
            Feedback.announce(n == 0 ? "No guild has struck this week's boss yet." : "\(n) guilds ranked this week.")
        }
    }

    /// Runs an online change: a problem is read out, otherwise `done`.
    private func act(_ work: @escaping () async -> String?, done: @escaping () -> Void) {
        busy = true
        Task {
            let problem = await work()
            busy = false
            if let problem { message = problem; Feedback.announce(problem) } else { done() }
        }
    }

    private func trySend() {
        guard GlobalChat(store: game.store).agreed else {
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty { askingTerms = true }
            else { Feedback.announce("Please type a message first.") }
            return
        }
        sendDraft()
    }

    private func sendDraft() {
        if let problem = guilds.send(draft, store: game.store) {
            Feedback.announce(problem)
            if problem.hasPrefix("Your message contains") { draft = "" }
        } else {
            draft = ""
        }
    }

    /// The shared HP, and any reward owed (this week's or last week's).
    private func loadBoss(announce: Bool) async {
        await guilds.loadBoss(week: week)
        let members = guilds.mine?.members.count ?? 1
        if announce {
            Feedback.announce(week.boss.intro + " " + Guilds.status(week, totalDamage: guilds.bossTotal, members: members)
                              + " You have \(Guilds.strikesLeft(store: game.store)) strikes left today.", after: 0.3)
        }
        collect(week, total: guilds.bossTotal, members: members)
        let last = Guilds.lastWeek()
        if Guilds.myDamage(last, store: game.store) > 0, let t = await guilds.total(week: last) {
            collect(last, total: t, members: members)
        }
    }

    private func collect(_ w: Guilds.Week, total: Int?, members: Int) {
        guard let total, let r = Guilds.claim(w, totalDamage: total, members: members, store: game.store, wallet: game.wallet) else { return }
        game.refresh()
        Sound.sfx("sfx-victory")
        Feedback.announce("\(w.boss.name) has fallen! Your guild did it. You earn \(r.gold) gold and \(r.fragments) Soul Fragments.", after: 1)
    }

    private func strike() {
        guard game.characters.indices.contains(charIndex) else { Feedback.announce("Please select a character."); return }
        let ch = game.characters[charIndex]
        guard let s = Guilds.strike(week, level: ch.persistLevel ?? 1, store: game.store, dice: &dice) else {
            Feedback.announce("No strikes left today.")
            return
        }
        Sound.sfx(s.crit ? "sfx-heavy-hit" : "sfx-attack")
        let line = (s.crit ? "💥 Critical! " : "⚔ ") + "\(ch.name) deals \(s.damage) damage. \(s.taunt)"
        log.insert(line, at: 0)
        let members = guilds.mine?.members.count ?? 1
        let hp = Guilds.remaining(totalDamage: (guilds.bossTotal ?? 0) + s.damage, members: members)
        Feedback.announce(line + " \(hp.formatted()) HP left. \(Guilds.strikesLeft(store: game.store)) strikes left today.", latest: true)
        Task {
            await guilds.record(s.damage, week: week, store: game.store)
            await loadBoss(announce: false)
        }
    }
}
