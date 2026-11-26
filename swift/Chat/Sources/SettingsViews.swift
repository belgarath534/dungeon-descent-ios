import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var account: Account
    @EnvironmentObject var push: Push
    @State private var confirmChatDelete = false
    @State private var confirmAccountDelete = false

    var body: some View {
            Form {
                Section {
                    Text("Signed in as \(chat.member?.username ?? "")"
                         + (chat.isDeveloper ? ", developer" : chat.isMod ? ", moderator" : chat.isTester ? ", tester" : ""))
                    if let uid = chat.member?.uid {
                        Text("User ID: \(uid)").font(.footnote).textSelection(.enabled)
                            .accessibilityHint("You can copy it. Support may ask for it.")
                    }
                }
                Section("Notifications") {
                    NavigationLink("Channels, private messages and sounds") { NotificationSetupView() }
                }
                Section("Privacy") {
                    Toggle("Accept private messages", isOn: Binding(get: { chat.member?.dmOff != true },
                                                                     set: { on in Task { await chat.setDMsOff(!on) } }))
                    Toggle("Show me as online", isOn: $chat.showOnline)
                    Toggle("Read new messages aloud", isOn: $chat.readAloud)
                        .accessibilityHint("While you're in a conversation. Messages that mention you are always read.")
                    Toggle("Post my big moments to Hall of Legends", isOn: Binding(get: { push.legends },
                                                                                  set: { push.legends = $0; Task { await push.save() } }))
                        .accessibilityHint("When you conquer a dungeon or reach a new Endless Descent or Spire milestone in the game, #hall-of-legends hears about it.")
                    NavigationLink("Blocked players (\(chat.blocked.count))") { BlockedView() }
                }
                Section("Community") {
                    NavigationLink("Community rules") {
                        List(RulesView.rules, id: \.self) { Text($0) }.navigationTitle("Community rules")
                    }
                    Link("Terms of Service", destination: URL(string: "https://dungen-descent.org/terms")!)
                    Link("Privacy Policy", destination: URL(string: "https://dungen-descent.org/privacy")!)
                    Link("Contact support", destination: URL(string: "https://dungen-descent.org/support")!)
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if chat.isDeveloper {
                    Section {
                        NavigationLink("Roles: moderators, testers, trusted") { RolesView() }
                        NavigationLink("Bans") { BansView() }
                        NavigationLink("Reports") { ReportsView() }
                        Text("Channels: use New channel on the Channels tab, and Edit, Move or Delete in each channel's actions.")
                            .font(.footnote)
                    } header: { Text("Developer mode") } footer: { Text("Only your account sees this.") }
                } else if chat.isMod {
                    Section("Moderator tools") {
                        NavigationLink("Reports") { ReportsView() }
                        NavigationLink("Bans") { BansView() }
                        NavigationLink("Testers") { RolesView() }
                    }
                }
                Section("Account") {
                    Button("Sign out") { account.signOut() }
                    Button("Delete my chat profile", role: .destructive) { confirmChatDelete = true }
                    Button("Delete my whole Dungeon Descent account", role: .destructive) { confirmAccountDelete = true }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete your chat profile?", isPresented: $confirmChatDelete, titleVisibility: .visible) {
                Button("Delete chat profile", role: .destructive) {
                    Task {
                        if let uid = chat.member?.uid { await ChatService.deleteChatData(uid: uid) }
                        account.signOut()
                        Speech.say("Your chat profile is deleted. Your Dungeon Descent account and game saves are kept.")
                    }
                }
            } message: {
                Text("This removes you from chat: your profile, blocks and notification settings. Your Dungeon Descent account, username and game saves are kept.")
            }
            .confirmationDialog("Delete your whole account?", isPresented: $confirmAccountDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { _ = await account.deleteWholeAccount() } }
            } message: {
                Text("This deletes your Dungeon Descent account for good: chat, your username, your cloud save and your leaderboard places. Saves on your devices stay. This can't be undone.")
            }
    }
}

struct BlockedView: View {
    @EnvironmentObject var chat: ChatService

    var body: some View {
        List {
            if chat.blocked.isEmpty { Text("You haven't blocked anyone.") }
            ForEach(chat.blocked.sorted { $0.value < $1.value }, id: \.key) { pair in
                HStack {
                    Text(pair.value)
                    Spacer()
                    Button("Unblock") { Task { await chat.unblock(uid: pair.key); Speech.say("\(pair.value) is unblocked.") } }
                        .accessibilityLabel("Unblock \(pair.value)")
                }
            }
        }
        .navigationTitle("Blocked players")
    }
}

struct ReportsView: View {
    @EnvironmentObject var chat: ChatService
    @State private var reports: [ChatService.Report] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && reports.isEmpty { Text("No reports. All clear.") }
            ForEach(reports) { r in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(r.authorName) in a \(r.kind == "channel" ? "channel" : r.kind == "dm" ? "private message" : "group")").font(.headline)
                    Text("“\(r.text)”")
                    if !r.reason.isEmpty { Text("Reason: \(r.reason)").font(.subheadline) }
                    Text("Reported by \(r.byName), \(r.date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                    if !r.context.isEmpty {
                        DisclosureGroup("Messages around it") { ForEach(r.context, id: \.self) { Text($0).font(.caption) } }
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    Button("Dismiss") { Task { await chat.dismiss(r); await reload() } }
                }
                .accessibilityActions {
                    if r.kind == "channel" {
                        Button("Delete the message") { Task { Speech.say(await chat.deleteReported(r) ? "Deleted." : "Couldn't delete it."); await chat.dismiss(r); await reload() } }
                    }
                    Button("Ban \(r.authorName)") { Task { Speech.say(await chat.ban(uid: r.authorUID, reason: "\(r.authorName): reported, \"\(r.text.prefix(80))\"") ? "\(r.authorName) is banned." : "Couldn't ban."); await chat.dismiss(r); await reload() } }
                    Button("Dismiss the report") { Task { await chat.dismiss(r); await reload() } }
                }
                .contextMenu {
                    if r.kind == "channel" { Button("Delete the message") { Task { _ = await chat.deleteReported(r); await chat.dismiss(r); await reload() } } }
                    Button("Ban \(r.authorName)") { Task { _ = await chat.ban(uid: r.authorUID, reason: "\(r.authorName): reported, \"\(r.text.prefix(80))\""); await chat.dismiss(r); await reload() } }
                    Button("Dismiss") { Task { await chat.dismiss(r); await reload() } }
                }
            }
        }
        .navigationTitle("Reports")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        reports = await chat.reports()
        loaded = true
    }
}

struct BansView: View {
    @EnvironmentObject var chat: ChatService
    @State private var bans: [(uid: String, reason: String)] = []
    @State private var name = ""
    @State private var reason = ""

    var body: some View {
        List {
            Section("Ban by username") {
                TextField("Username", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Reason", text: $reason)
                Button("Ban from chat", role: .destructive) {
                    let n = name, why = reason
                    Task {
                        guard let m = await chat.findMember(username: n) else { Speech.say("No chat member is called \(n)."); return }
                        if m.uid == chat.member?.uid { Speech.say("You can't ban yourself."); return }
                        let ok = await chat.ban(uid: m.uid, reason: "\(m.username): \(why.isEmpty ? "no reason given" : why)")
                        Speech.say(ok ? "\(m.username) is banned from chat." : "Couldn't ban \(m.username).")
                        if ok { name = ""; reason = ""; bans = await chat.bans() }
                    }
                }
                .disabled(name.isEmpty)
            }
            if bans.isEmpty { Text("Nobody is banned.") }
            ForEach(bans, id: \.uid) { b in
                HStack {
                    Text(b.reason.isEmpty ? b.uid : b.reason).font(.subheadline)
                    Spacer()
                    Button("Unban") { Task { _ = await chat.unban(uid: b.uid); Speech.say("Unbanned."); bans = await chat.bans() } }
                        .accessibilityLabel("Unban. \(b.reason)")
                }
            }
        }
        .navigationTitle("Bans")
        .task { bans = await chat.bans() }
    }
}

/// Moderators mark testers; the developer also makes moderators and marks
/// accounts trusted (private messages and groups right away, like the App
/// Review account).
struct RolesView: View {
    @EnvironmentObject var chat: ChatService
    @State private var name = ""
    @State private var found: Member?
    @State private var status = ""

    var body: some View {
        Form {
            Section("Find a member") {
                TextField("Username", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Find") {
                    Task {
                        found = await chat.findMember(username: name)
                        status = found == nil ? "No chat member is called \(name)." : ""
                        if !status.isEmpty { Speech.say(status) }
                    }
                }
            }
            if let m = found {
                Section(m.username) {
                    roleToggle("Tester (sees the testers channel)", field: "tester", value: m.tester, m)
                    if chat.isDeveloper {
                        roleToggle("Moderator", field: "mod", value: m.mod, m)
                        roleToggle("Trusted (no one-day wait)", field: "trusted", value: m.trusted, m)
                    }
                }
            }
            if !status.isEmpty { Section { Text(status) } }
        }
        .navigationTitle("Roles")
    }

    private func roleToggle(_ title: String, field: String, value: Bool, _ m: Member) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { on in
            Task {
                let ok = await chat.setRole(field, on, for: m.uid)
                Speech.say(ok ? "Saved." : "Couldn't change that.")
                found = await chat.findMember(username: m.username)
            }
        }))
    }
}
