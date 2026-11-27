import SwiftUI
import FirebaseFirestore

/// Where a tapped notification wants to go.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var open: (kind: String, room: String)?
    /// The message to jump to once it's open (from a reply, mention or reaction).
    var focus: String?
}

/// A conversation to open, optionally at one message.
struct OpenTarget: Identifiable, Hashable {
    let room: Room
    var focus: String? = nil
    var id: String { room.path + "#" + (focus ?? "") }
}

struct MainView: View {
    @EnvironmentObject var chat: ChatService
    @ObservedObject private var router = Router.shared
    @State private var opened: OpenTarget?
    @State private var tab = Self.firstTab

    private static var firstTab: Int {
        #if DEBUG
        return ScreenshotMode.startTab
        #else
        return 0
        #endif
    }

    var body: some View {
        TabView(selection: $tab) {
            ChannelsView().tabItem { Label("Channels", systemImage: "number") }
                .badge(chat.unreadChannels).tag(0)
            MessagesView().tabItem { Label("Messages", systemImage: "envelope") }
                .badge(chat.unreadDMs + chat.unreadGroups).tag(1)
            ActivityView().tabItem { Label("Activity", systemImage: "bell") }
                .badge(chat.unreadActivity).tag(2)
            CommunityView().tabItem { Label("Community", systemImage: "trophy") }.tag(3)
            MeView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
        }
        .onAppear {
            #if DEBUG
            ScreenshotMode.openRoom()
            #endif
        }
        .sheet(item: $opened) { t in
            NavigationStack {
                ConversationView(room: t.room, focus: t.focus)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { opened = nil } } }
            }
        }
        .onChange(of: router.open?.room, initial: true) { _, _ in openPending() }
        .onChange(of: chat.channels.count) { _, _ in openPending() }
        .onChange(of: chat.dms.count) { _, _ in openPending() }
        .onChange(of: chat.groups.count) { _, _ in openPending() }
    }

    /// Opens the conversation a tapped notification points to, once it's known.
    private func openPending() {
        guard let (kind, id) = router.open else { return }
        if let room = chat.room(kind: kind, id: id) {
            opened = OpenTarget(room: room, focus: router.focus)
            router.open = nil
            router.focus = nil
        }
    }
}

struct ChannelsView: View {
    @EnvironmentObject var chat: ChatService
    @State private var editing: ChannelEdit?
    @State private var deleting: Channel?
    @State private var showingOnline = false

    var body: some View {
        NavigationStack {
            List {
                if chat.banned {
                    Text("You've been banned from chat. You can still read, but not post.").foregroundStyle(.orange)
                }
                Button {
                    showingOnline = true
                } label: {
                    Label("\(chat.online.count) \(chat.online.count == 1 ? "player" : "players") online", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityHint("Shows who's online.")
                ForEach(chat.visibleChannels) { c in
                    NavigationLink(value: Room(kind: .channel, id: c.id, title: c.name, path: "chat_channels/\(c.id)",
                                               canPost: !c.modsPost || chat.isMod)) {
                        VStack(alignment: .leading) {
                            HStack {
                                if chat.myPinned.contains(c.id) { Image(systemName: "pin.fill").accessibilityHidden(true) }
                                Text("# " + c.name).font(.headline)
                                if let n = chat.unread[c.id], n > 0 {
                                    Text(n > 99 ? "99+ new" : "\(n) new").font(.caption.bold()).foregroundStyle(.black)
                                        .padding(.horizontal, 6).background(Capsule().fill(Color.accentColor))
                                }
                            }
                            if !c.topic.isEmpty { Text(c.topic).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(c.name + (chat.myPinned.contains(c.id) ? ", pinned" : "") + ((chat.unread[c.id] ?? 0) > 0 ? ", \(chat.unread[c.id]!) new" : "")
                                            + (c.topic.isEmpty ? "" : ". " + c.topic) + (c.modsPost ? ". Read only" : "")
                                            + (c.testersOnly ? ". Testers only" : ""))
                    }
                    .accessibilityActions {
                        Button(chat.myPinned.contains(c.id) ? "Unpin from the top" : "Pin to the top") { chat.togglePinned(c) }
                        if chat.isDeveloper { channelActions(c) }
                    }
                    .contextMenu {
                        Button(chat.myPinned.contains(c.id) ? "Unpin from the top" : "Pin to the top") { chat.togglePinned(c) }
                        if chat.isDeveloper { channelActions(c) }
                    }
                }
                if chat.channels.isEmpty { Text("Loading channels…") }
            }
            .navigationTitle("Channels")
            .navigationDestination(for: Room.self) { ConversationView(room: $0) }
            .task { await chat.refreshUnread() }
            .refreshable { await chat.refreshUnread(); await chat.refreshOnline() }
            .toolbar { if chat.isDeveloper { Button("New channel") { editing = .new } } }
            .sheet(item: $editing) { ChannelEditor(editing: $0) }
            .sheet(isPresented: $showingOnline) { OnlineView() }
            .confirmationDialog("Delete #\(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete channel", role: .destructive) {
                    if let c = deleting { Task { Speech.say(await chat.deleteChannel(c) ? "Channel deleted." : "Couldn't delete it.") } }
                    deleting = nil
                }
            } message: { Text("The channel disappears for everyone. Its old messages stay stored but can't be reached from the app.") }
        }
    }

    @ViewBuilder private func channelActions(_ c: Channel) -> some View {
        Button("Edit channel") { editing = .edit(c) }
        Button("Move up") { Task { await chat.moveChannel(c, by: -1) } }
        Button("Move down") { Task { await chat.moveChannel(c, by: 1) } }
        Button("Delete channel", role: .destructive) { deleting = c }
    }
}

/// The developer's channel editor (new or existing).
enum ChannelEdit: Identifiable {
    case new
    case edit(Channel)
    var id: String { if case .edit(let c) = self { return c.id } else { return "new" } }
}

struct ChannelEditor: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let editing: ChannelEdit
    @State private var name = ""
    @State private var topic = ""
    @State private var modsPost = false
    @State private var testersOnly = false
    @State private var problem = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Channel name, like co-op-rooms", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Topic (optional)", text: $topic)
                }
                Section {
                    Toggle("Only moderators can post", isOn: $modsPost)
                    Toggle("Only testers can see it", isOn: $testersOnly)
                }
                if !problem.isEmpty { Section { Text(problem).foregroundStyle(.orange) } }
            }
            .navigationTitle(isNew ? "New channel" : "Edit channel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") {
                        Task {
                            if let p = await chat.saveChannel(id: existing?.id, name: name, topic: topic, modsPost: modsPost, testersOnly: testersOnly) {
                                problem = p; Speech.say(p)
                            } else {
                                Speech.say(isNew ? "Channel created." : "Channel saved.")
                                dismiss()
                            }
                        }
                    }
                }
            }
            .onAppear {
                if let c = existing { name = c.name; topic = c.topic; modsPost = c.modsPost; testersOnly = c.testersOnly }
            }
        }
    }

    private var existing: Channel? { if case .edit(let c) = editing { return c } else { return nil } }
    private var isNew: Bool { existing == nil }
}

/// One room's messages, newest at the bottom, with a box to write in.
struct ConversationView: View {
    @EnvironmentObject var chat: ChatService
    let room: Room
    /// A message to jump to and read out when it opens.
    let focus: String?
    @AccessibilityFocusState private var voiceOverOn: String?
    @State private var highlighted: String?
    @State private var messages: [ChatMessage] = []
    @State private var listener: ListenerRegistration?
    @State private var draft = ""
    @State private var replyTo: ChatMessage?
    @State private var reporting: ChatMessage?
    @State private var reason = ""
    @State private var blocking: ChatMessage?
    @State private var problem = ""
    @State private var dmRoom: Room?
    @State private var showInfo = false
    @State private var reacting: ChatMessage?
    @State private var profileUID: ProfileTarget?
    @State private var pinned: [ChatMessage] = []
    @FocusState private var typing: Bool
    private var myUID: String? { chat.member?.uid }

    init(room: Room, focus: String? = nil) {
        self.room = room
        self.focus = focus
    }

    private var shown: [ChatMessage] { messages.filter { chat.blocked[$0.uid] == nil } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List {
                    if !pinned.isEmpty {
                        DisclosureGroup("📌 Pinned (\(pinned.count))") {
                            ForEach(pinned) { p in
                                Text("\(p.username): \(p.text)")
                                    .accessibilityActions { if chat.isMod { Button("Unpin") { Task { _ = await chat.pin(p, in: room, false); await loadPinned() } } } }
                            }
                        }
                    }
                    ForEach(shown) { m in
                        row(m).id(m.id)
                            .listRowBackground(highlighted == m.id ? Color.accentColor.opacity(0.18) : nil)
                            .accessibilityFocused($voiceOverOn, equals: m.id)
                    }
                }
                .listStyle(.plain)
                .onChange(of: shown.last?.id) { _, id in
                    if let id, highlighted == nil { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: shown.count) { _, _ in
                    // Jump to the message this was opened for, once it has loaded.
                    guard let focus, highlighted == nil, let m = shown.first(where: { $0.id == focus }) else { return }
                    highlighted = focus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        proxy.scrollTo(focus, anchor: .center)
                        voiceOverOn = focus
                        Speech.say("\(m.username): \(m.text)")
                    }
                }
            }
            if room.canPost && !chat.banned { composer } else {
                Text(chat.banned ? "You're banned from posting." : "Only moderators post here.")
                    .font(.footnote).foregroundStyle(.secondary).padding(8)
            }
        }
        .navigationTitle(room.kind == .channel ? "# " + room.title : room.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if room.kind == .group {
                Button("Group info") { showInfo = true }
            }
        }
        .sheet(isPresented: $showInfo) { GroupInfoView(roomID: room.id) }
        .sheet(item: $profileUID) { ProfileView(uid: $0.id) }
        .task { await loadPinned() }
        .confirmationDialog("React to \(reacting?.username ?? "")'s message", isPresented: Binding(get: { reacting != nil }, set: { if !$0 { reacting = nil } }), titleVisibility: .visible) {
            ForEach(ChatService.reactionEmojis, id: \.self) { e in
                Button("\(e) \(ChatService.reactionNames[e] ?? "")") {
                    if let m = reacting { Task { _ = await chat.react(m, in: room, e); Speech.say("Reacted \(ChatService.reactionNames[e] ?? e).") } }
                    reacting = nil
                }
            }
            if let m = reacting, let me = myUID, m.reactions[me] != nil {
                Button("Remove my reaction", role: .destructive) { Task { _ = await chat.react(m, in: room, nil) }; reacting = nil }
            }
        }
        .navigationDestination(item: $dmRoom) { ConversationView(room: $0) }
        .onAppear { startListening(); chat.markRead(room) }
        .onDisappear { listener?.remove(); listener = nil; chat.markRead(room) }
        .alert("Report this message", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            TextField("What's wrong? (optional)", text: $reason)
            Button("Send report") {
                if let m = reporting {
                    let i = messages.firstIndex(of: m) ?? 0
                    let around = Array(messages[max(0, i - 5)..<min(messages.count, i + 3)])
                    Task {
                        let ok = await chat.report(m, in: room, context: around, reason: reason)
                        Speech.say(ok ? "Report sent. A moderator will look at it within 24 hours." : "The report couldn't be sent. Check your connection.")
                        reason = ""
                    }
                }
                reporting = nil
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        }
        .confirmationDialog("Block \(blocking?.username ?? "")?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let m = blocking { Task { await chat.block(uid: m.uid, name: m.username) } }
                blocking = nil
            }
        } message: {
            Text("You won't see their messages, and they can't message you or add you to groups. You can unblock them in Settings.")
        }
    }

    private func startListening() {
        guard listener == nil else { return }
        var first = true
        listener = chat.listen(room) { list in
            let new = list.filter { m in !messages.contains(where: { $0.id == m.id }) }
            messages = list
            chat.markRead(room)
            if !first {
                for m in new where m.uid != myUID && chat.blocked[m.uid] == nil {
                    let mentioned = chat.member.map { m.mentions($0.username) } ?? false
                    if mentioned { Speech.say("\(m.username) mentioned you: \(m.text)") }
                    else if chat.readAloud { Speech.say("\(m.username): \(m.text)") }
                }
            }
            first = false
        }
    }

    @ViewBuilder private func row(_ m: ChatMessage) -> some View {
        let reply = m.replyTo.flatMap { id in messages.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 2) {
            if let reply { Text("↪ \(reply.username): \(reply.text)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack {
                Text(m.username).font(.subheadline.bold())
                Text(m.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
            Text(m.text).fontWeight(mentionsMe(m) ? .bold : .regular)
            if !m.reactions.isEmpty { Text(m.reactionSummary).font(.caption) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((reply.map { "Replying to \($0.username). " } ?? "") + "\(m.username): \(m.text)"
                            + (mentionsMe(m) ? ". Mentions you" : "")
                            + (m.reactions.isEmpty ? "" : ". Reactions: " + readable(m.reactions))
                            + (m.pinned ? ". Pinned" : ""))
        .accessibilityValue(m.date.formatted(.relative(presentation: .named)))
        .accessibilityActions { actions(m) }
        .contextMenu { actions(m) }
        .swipeActions(edge: .trailing) {
            if m.uid != myUID { Button("Report") { reporting = m }.tint(.orange) }
        }
    }

    @ViewBuilder private func actions(_ m: ChatMessage) -> some View {
        if room.canPost && !chat.banned { Button("Reply") { replyTo = m; typing = true } }
        if !chat.banned { Button("React") { reacting = m } }
        if m.uid != "hall-of-legends" { Button("View \(m.uid == myUID ? "your" : m.username + "'s") profile") { profileUID = ProfileTarget(id: m.uid) } }
        if chat.isMod && room.kind == .channel {
            Button(m.pinned ? "Unpin message" : "Pin message") {
                Task { Speech.say(await chat.pin(m, in: room, !m.pinned) ? (m.pinned ? "Unpinned." : "Pinned.") : "Couldn't change the pin."); await loadPinned() }
            }
        }
        if m.uid != myUID && m.uid != "hall-of-legends" {
            if room.kind != .dm {
                Button("Message \(m.username) privately") {
                    Task {
                        let (r, p) = await chat.openDM(with: m.uid, name: m.username)
                        if let r { dmRoom = r } else if let p { problem = p; Speech.say(p) }
                    }
                }
            }
            Button("Report") { reporting = m }
            Button("Block \(m.username)") { blocking = m }
        }
        if m.uid == myUID || (chat.isMod && room.kind == .channel) {
            Button("Delete message", role: .destructive) {
                Task { Speech.say(await chat.delete(m, in: room) ? "Message deleted." : "Couldn't delete it.") }
            }
        }
        if chat.isMod && room.kind == .channel && m.uid != myUID {
            Button("Ban \(m.username) from chat", role: .destructive) {
                Task { Speech.say(await chat.ban(uid: m.uid, reason: "\(m.username): in #\(room.title), \"\(m.text.prefix(80))\"") ? "\(m.username) is banned." : "Couldn't ban.") }
            }
        }
    }

    private func mentionsMe(_ m: ChatMessage) -> Bool { m.uid != myUID && (chat.member.map { m.mentions($0.username) } ?? false) }

    private func readable(_ r: [String: String]) -> String {
        Dictionary(grouping: r.values, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            .map { "\($0.1) \(ChatService.reactionNames[$0.0] ?? $0.0)" }.joined(separator: ", ")
    }

    private func loadPinned() async {
        guard room.kind == .channel else { return }
        pinned = await chat.pinnedMessages(room)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let r = replyTo {
                HStack {
                    Text("Replying to \(r.username)").font(.caption)
                    Spacer()
                    Button("Cancel reply") { replyTo = nil }.font(.caption)
                }
            }
            if !problem.isEmpty { Text(problem).font(.caption).foregroundStyle(.orange) }
            HStack {
                TextField(room.kind == .channel ? "Message #\(room.title)" : "Message \(room.title)", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($typing)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    let text = draft
                    let reply = replyTo?.id
                    Task {
                        if let p = await chat.send(text, in: room, replyTo: reply) {
                            problem = p
                            Speech.say(p)
                        } else {
                            draft = ""; replyTo = nil; problem = ""
                            Speech.say("Sent.")
                        }
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(8)
        .background(.bar)
    }
}

/// Private messages and group chats, in one list.
struct MessagesView: View {
    @EnvironmentObject var chat: ChatService
    @State private var newName = ""
    @State private var asking = false
    @State private var naming = false
    @State private var groupName = ""
    @State private var opened: Room?

    var body: some View {
        NavigationStack {
            List {
                Section("Private messages") {
                    ForEach(chat.dms.filter { r in !r.members.keys.contains { chat.blocked[$0] != nil } }) { r in
                        NavigationLink(value: r) {
                            Text(r.title + (chat.isNew(r) ? ", new" : "")).fontWeight(chat.isNew(r) ? .bold : .regular)
                        }
                    }
                    if chat.dms.isEmpty {
                        Text("No private messages yet. To message someone, use \"Message privately\" on one of their messages, or New, then Private message.")
                    }
                    Toggle("Accept private messages", isOn: Binding(get: { chat.member?.dmOff != true },
                                                                     set: { on in Task { await chat.setDMsOff(!on) } }))
                }
                Section("Groups") {
                    ForEach(chat.groups) { g in
                        NavigationLink(value: g) {
                            Text(g.title + (chat.isNew(g) ? ", new" : "")).fontWeight(chat.isNew(g) ? .bold : .regular)
                                .accessibilityLabel("\(g.title)\(chat.isNew(g) ? ", new" : ""), group, \(g.members.count) \(g.members.count == 1 ? "person" : "people")")
                        }
                    }
                    if chat.groups.isEmpty { Text("No groups yet. Make one with New, then Group, and add people by their username.") }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                Menu("New") {
                    Button("Private message") { asking = true }
                    Button("Group") { naming = true }
                }
            }
            .navigationDestination(for: Room.self) { ConversationView(room: $0) }
            .navigationDestination(item: $opened) { ConversationView(room: $0) }
            .alert("Message who?", isPresented: $asking) {
                TextField("Their username", text: $newName)
                Button("Open") {
                    let name = newName
                    newName = ""
                    Task {
                        guard let m = await chat.findMember(username: name) else { Speech.say("No chat member is called \(name)."); return }
                        let (r, p) = await chat.openDM(with: m.uid, name: m.username)
                        if let r { opened = r } else if let p { Speech.say(p) }
                    }
                }
                Button("Cancel", role: .cancel) { newName = "" }
            }
            .alert("New group", isPresented: $naming) {
                TextField("Group name", text: $groupName)
                Button("Create") {
                    let n = groupName
                    groupName = ""
                    Task {
                        let (r, p) = await chat.createGroup(name: n)
                        if let r { opened = r; Speech.say("Group created. Use Group info to add people.") } else if let p { Speech.say(p) }
                    }
                }
                Button("Cancel", role: .cancel) { groupName = "" }
            }
        }
    }
}

struct GroupInfoView: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let roomID: String
    @State private var adding = ""
    @State private var renaming = ""
    @State private var problem = ""
    private var room: Room? { chat.groups.first { $0.id == roomID } }
    private var isOwner: Bool { room?.owner == chat.member?.uid }

    var body: some View {
        NavigationStack {
            Form {
                if let room {
                    Section("\(room.members.count) of 20 people") {
                        ForEach(room.members.sorted { $0.value.lowercased() < $1.value.lowercased() }, id: \.key) { pair in
                            let uid = pair.key, name = pair.value
                            HStack {
                                Text(name + (uid == room.owner ? " (owner)" : ""))
                                Spacer()
                                if isOwner && uid != room.owner {
                                    Button("Remove", role: .destructive) { Task { _ = await chat.removeFromGroup(room, uid: uid) } }
                                        .accessibilityLabel("Remove \(name)")
                                }
                            }
                        }
                    }
                    if isOwner {
                        Section("Add someone") {
                            TextField("Their username", text: $adding).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Button("Add") {
                                let n = adding
                                Task {
                                    if let p = await chat.addToGroup(room, username: n) { problem = p; Speech.say(p) }
                                    else { adding = ""; problem = ""; Speech.say("\(n) added.") }
                                }
                            }
                        }
                        Section("Rename") {
                            TextField(room.title, text: $renaming)
                            Button("Rename") { Task { if let p = await chat.renameGroup(room, to: renaming) { Speech.say(p) } else { Speech.say("Renamed.") } } }
                        }
                    }
                    if !problem.isEmpty { Section { Text(problem).foregroundStyle(.orange) } }
                    Section {
                        Button(isOwner && room.members.count == 1 ? "Delete group" : "Leave group", role: .destructive) {
                            Task {
                                if let p = await chat.leaveGroup(room) { Speech.say(p) } else { Speech.say("You left the group."); dismiss() }
                            }
                        }
                    } footer: {
                        if isOwner && room.members.count > 1 { Text("If you leave, the group goes to another member.") }
                    }
                } else {
                    Text("You're no longer in this group.")
                }
            }
            .navigationTitle(room?.title ?? "Group")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Who's online right now.
struct OnlineView: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if chat.online.isEmpty { Text("Nobody else is online right now.") }
                ForEach(chat.online, id: \.self) { Text($0) }
            }
            .navigationTitle("\(chat.online.count) online")
            .toolbar { Button("Done") { dismiss() } }
            .refreshable { await chat.refreshOnline() }
            .task { await chat.refreshOnline() }
        }
    }
}

struct ProfileTarget: Identifiable { let id: String }

/// A player's profile: role, when they joined, online, High Score, and what
/// you can do (message, block).
struct ProfileView: View {
    @EnvironmentObject var chat: ChatService
    @Environment(\.dismiss) private var dismiss
    let uid: String
    @State private var profile: Profile?
    @State private var loaded = false
    @State private var dmRoom: Room?

    init(uid: String) { self.uid = uid }

    var body: some View {
        NavigationStack {
            Form {
                if let p = profile {
                    Section {
                        LabeledContent("Username", value: p.username)
                        LabeledContent("Role", value: p.role)
                        LabeledContent("Status", value: p.online ? "Online now" : "Offline")
                        if let j = p.joined { LabeledContent("Joined chat", value: j.formatted(date: .abbreviated, time: .omitted)) }
                        if !p.favClass.isEmpty { LabeledContent("Favorite class", value: ChatService.className(p.favClass)) }
                    }
                    if !p.bio.isEmpty { Section("About") { Text(p.bio) } }
                    if p.highScore != nil || p.endlessFloor != nil || p.weeklyScore != nil {
                        Section("In the game") {
                            if let s = p.highScore { LabeledContent("High Score", value: s.formatted()) }
                            if let f = p.endlessFloor { LabeledContent("Endless Descent best", value: "Floor \(f.formatted())") }
                            if let w = p.weeklyScore { LabeledContent("Weekly Ladder this week", value: w.formatted()) }
                        }
                    }
                    if p.uid != chat.member?.uid {
                        Section {
                            Button("Message \(p.username) privately") {
                                Task {
                                    let (r, problem) = await chat.openDM(with: p.uid, name: p.username)
                                    if let r { dmRoom = r } else if let problem { Speech.say(problem) }
                                }
                            }
                            if chat.blocked[p.uid] == nil {
                                Button("Block \(p.username)", role: .destructive) { Task { await chat.block(uid: p.uid, name: p.username); dismiss() } }
                            } else {
                                Button("Unblock \(p.username)") { Task { await chat.unblock(uid: p.uid) } }
                            }
                        }
                    }
                } else if loaded {
                    Text("This player isn't in chat anymore.")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(profile?.username ?? "Profile")
            .navigationDestination(item: $dmRoom) { ConversationView(room: $0) }
            .toolbar { Button("Done") { dismiss() } }
            .task { profile = await chat.profile(uid: uid); loaded = true }
        }
    }
}
