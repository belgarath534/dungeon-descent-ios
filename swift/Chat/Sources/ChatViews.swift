import SwiftUI
import FirebaseFirestore

struct MainView: View {
    var body: some View {
        TabView {
            ChannelsView().tabItem { Label("Channels", systemImage: "number") }
            MessagesView().tabItem { Label("Messages", systemImage: "envelope") }
            GroupsView().tabItem { Label("Groups", systemImage: "person.3") }
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

struct ChannelsView: View {
    @EnvironmentObject var chat: ChatService
    @State private var editing: ChannelEdit?
    @State private var deleting: Channel?

    var body: some View {
        NavigationStack {
            List {
                if chat.banned {
                    Text("You've been banned from chat. You can still read, but not post.").foregroundStyle(.orange)
                }
                ForEach(chat.channels.filter { !$0.testersOnly || chat.isTester }) { c in
                    NavigationLink(value: Room(kind: .channel, id: c.id, title: c.name, path: "chat_channels/\(c.id)",
                                               canPost: !c.modsPost || chat.isMod)) {
                        VStack(alignment: .leading) {
                            Text("# " + c.name).font(.headline)
                            if !c.topic.isEmpty { Text(c.topic).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(c.name + (c.topic.isEmpty ? "" : ". " + c.topic) + (c.modsPost ? ". Read only" : "")
                                            + (c.testersOnly ? ". Testers only" : ""))
                    }
                    .accessibilityActions { if chat.isDeveloper { channelActions(c) } }
                    .contextMenu { if chat.isDeveloper { channelActions(c) } }
                }
                if chat.channels.isEmpty { Text("Loading channels…") }
            }
            .navigationTitle("Channels")
            .navigationDestination(for: Room.self) { ConversationView(room: $0) }
            .toolbar { if chat.isDeveloper { Button("New channel") { editing = .new } } }
            .sheet(item: $editing) { ChannelEditor(editing: $0) }
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
    @FocusState private var typing: Bool
    private var myUID: String? { chat.member?.uid }

    private var shown: [ChatMessage] { messages.filter { chat.blocked[$0.uid] == nil } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                List(shown) { m in
                    row(m).id(m.id)
                }
                .listStyle(.plain)
                .onChange(of: shown.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
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
        .navigationDestination(item: $dmRoom) { ConversationView(room: $0) }
        .onAppear(perform: startListening)
        .onDisappear { listener?.remove(); listener = nil }
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
            if !first {
                for m in new where m.uid != myUID && chat.blocked[m.uid] == nil {
                    Speech.say("\(m.username): \(m.text)")
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
                Text(m.date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            Text(m.text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((reply.map { "Replying to \($0.username). " } ?? "") + "\(m.username): \(m.text)")
        .accessibilityValue(m.date.formatted(.relative(presentation: .named)))
        .accessibilityActions { actions(m) }
        .contextMenu { actions(m) }
        .swipeActions(edge: .trailing) {
            if m.uid != myUID { Button("Report") { reporting = m }.tint(.orange) }
        }
    }

    @ViewBuilder private func actions(_ m: ChatMessage) -> some View {
        if room.canPost && !chat.banned { Button("Reply") { replyTo = m; typing = true } }
        if m.uid != myUID {
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

struct MessagesView: View {
    @EnvironmentObject var chat: ChatService
    @State private var newName = ""
    @State private var asking = false
    @State private var opened: Room?

    var body: some View {
        NavigationStack {
            List {
                ForEach(chat.dms.filter { r in !r.members.keys.contains { chat.blocked[$0] != nil } }) { r in
                    NavigationLink(value: r) { Text(r.title) }
                }
                if chat.dms.isEmpty {
                    Text("No private messages yet. To message someone, use \"Message privately\" on one of their messages, or the New message button.")
                }
                Toggle("Accept private messages", isOn: Binding(get: { chat.member?.dmOff != true },
                                                                 set: { on in Task { await chat.setDMsOff(!on) } }))
            }
            .navigationTitle("Messages")
            .toolbar { Button("New message") { asking = true } }
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
        }
    }
}

struct GroupsView: View {
    @EnvironmentObject var chat: ChatService
    @State private var naming = false
    @State private var name = ""
    @State private var opened: Room?

    var body: some View {
        NavigationStack {
            List {
                ForEach(chat.groups) { g in
                    NavigationLink(value: g) {
                        Text(g.title)
                            .accessibilityLabel("\(g.title), \(g.members.count) \(g.members.count == 1 ? "person" : "people")")
                    }
                }
                if chat.groups.isEmpty { Text("No groups yet. Make one with New group, then add people by their username.") }
            }
            .navigationTitle("Groups")
            .toolbar { Button("New group") { naming = true } }
            .navigationDestination(for: Room.self) { ConversationView(room: $0) }
            .navigationDestination(item: $opened) { ConversationView(room: $0) }
            .alert("New group", isPresented: $naming) {
                TextField("Group name", text: $name)
                Button("Create") {
                    let n = name
                    name = ""
                    Task {
                        let (r, p) = await chat.createGroup(name: n)
                        if let r { opened = r; Speech.say("Group created. Use Group info to add people.") } else if let p { Speech.say(p) }
                    }
                }
                Button("Cancel", role: .cancel) { name = "" }
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
