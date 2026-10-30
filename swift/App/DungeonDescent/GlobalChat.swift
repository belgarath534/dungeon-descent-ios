import SwiftUI
import FirebaseDatabase
import DungeonCore

/// GLOBAL CHAT SYSTEM: the shared "global_chat" list in the web version's
/// Realtime Database, so Swift and web players talk in the same room. Every
/// message from someone else has Report and Block (the UGC safety rules).
@MainActor
final class GlobalChat: ObservableObject {
    struct Message: Identifiable, Equatable {
        let id: String
        let username: String
        let message: String
        let timestamp: Double
        let system: Bool
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var status = "Loading messages..."
    private var handle: DatabaseHandle?
    private var seen: Set<String> = []
    private var firstLoad = true
    let store: GameStore

    init(store: GameStore) { self.store = store }

    private var ref: DatabaseReference { Database.database().reference(withPath: "global_chat") }

    static let badWords = ["fuck", "shit", "ass", "bitch", "cunt", "dick", "cock", "pussy", "nigger", "nigga", "faggot", "fag",
                           "retard", "whore", "slut", "bastard", "piss", "asshole", "motherfucker", "bullshit"]

    /// chatContainsBadWord. The web version matched inside words, so "class",
    /// "pass" and "assassin" were refused; here only whole words count.
    static func hasBadWord(_ text: String) -> Bool {
        let words = text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return words.contains { badWords.contains($0) }
    }

    var username: String? {
        guard let n = store.getItem("dd_chat_username"), !n.isEmpty else { return nil }
        return n
    }

    /// chatSetUsername
    func setUsername(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if name.count < 2 { return "Username must be at least 2 characters." }
        if name.count > 20 { return "Username too long. Max 20 characters." }
        if Self.hasBadWord(name) { return "That username is not allowed. Please choose another." }
        store.setItem("dd_chat_username", name)
        objectWillChange.send()
        Feedback.announce("Username set to \(name). You can now chat.")
        return nil
    }

    // MARK: Blocking and hiding (ugcBlock, ugcHide)

    private func list(_ key: String) -> [String] {
        guard let s = store.getItem(key), let d = s.data(using: .utf8),
              let v = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return v
    }

    private func setList(_ key: String, _ v: [String]) {
        if let d = try? JSONEncoder().encode(v), let s = String(data: d, encoding: .utf8) { store.setItem(key, s) }
    }

    func isBlocked(_ name: String) -> Bool { list("dd_blocked_players").contains(name.trimmingCharacters(in: .whitespaces).lowercased()) }

    func block(_ name: String) {
        var l = list("dd_blocked_players")
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if !l.contains(key) { l.append(key); setList("dd_blocked_players", l) }
        refilter()
        Feedback.announce("\(name) is blocked. You will not see their messages or enemies anymore.")
    }

    func unblockAll() {
        setList("dd_blocked_players", [])
        setList("dd_hidden_content", [])
        refilter()
        Feedback.announce("Everyone is unblocked, and hidden messages and enemies are shown again.")
    }

    var blockedCount: Int { list("dd_blocked_players").count }

    private func hide(_ id: String) {
        var l = list("dd_hidden_content")
        if !l.contains(id) { l.append(id); setList("dd_hidden_content", Array(l.suffix(500))) }
    }

    /// The one-time Terms of Service agreement before posting (ugcRequireAgreement).
    var agreed: Bool { store.getItem("dd_ugc_terms_ok") == "1" }

    func agree() {
        store.setItem("dd_ugc_terms_ok", "1")
        objectWillChange.send()
        Feedback.announce("Thank you. You agreed to the Terms of Service.")
    }

    // MARK: Live messages

    private var all: [Message] = []

    /// chatLoadMessages: the last 50, updated live.
    func open() {
        guard handle == nil else { return }
        status = "Loading messages..."
        firstLoad = true
        handle = ref.queryOrdered(byChild: "timestamp").queryLimited(toLast: 50).observe(.value, with: { [weak self] snap in
            var list: [Message] = []
            for case let child as DataSnapshot in snap.children {
                guard let v = child.value as? [String: Any] else { continue }
                list.append(Message(id: child.key, username: (v["username"] as? String) ?? "Unknown",
                                    message: (v["message"] as? String) ?? "",
                                    timestamp: (v["timestamp"] as? NSNumber)?.doubleValue ?? 0,
                                    system: (v["system"] as? Bool) ?? false))
            }
            Task { @MainActor in self?.received(list) }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in self?.status = "Could not load messages. Check your connection." }
        })
    }

    func close() {
        if let h = handle { ref.removeObserver(withHandle: h) }
        handle = nil
    }

    private func received(_ list: [Message]) {
        all = list
        let me = username
        // New messages from others are read out, like the web version's live region.
        if !firstLoad {
            for m in list where !seen.contains(m.id) && m.username != me && !isBlocked(m.username) {
                Feedback.announce("\(m.username) said \(m.message)")
            }
        }
        firstLoad = false
        seen.formUnion(list.map(\.id))
        refilter()
    }

    private func refilter() {
        let hidden = Set(list("dd_hidden_content"))
        messages = all.filter { !isBlocked($0.username) && !hidden.contains($0.id) }
        status = messages.isEmpty ? "No messages yet. Be the first to say something!" : ""
    }

    /// chatSend. Returns a problem to read out, or nil when it was sent.
    func send(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name = username else { return "Please set a username first." }
        if text.isEmpty { return "Please type a message first." }
        if text.count > 200 { return "Message too long. Maximum 200 characters." }
        if Self.hasBadWord(text) { return "Your message contains inappropriate content and was not sent." }
        ref.childByAutoId().setValue([
            "username": name, "message": text, "timestamp": (Date().timeIntervalSince1970 * 1000).rounded(),
        ]) { error, _ in
            if error != nil { Task { @MainActor in Feedback.announce("Failed to send message. Check your connection.") } }
        }
        return nil
    }

    /// ugcReport: hidden here right away, and sent to the developer.
    func report(_ m: Message, reason: String) async {
        hide(m.id)
        refilter()
        let payload: [String: String] = [
            "type": "Content report: message",
            "message": "REPORTED MESSAGE\nAuthor: \(m.username)\nContent: \(m.message.prefix(300))\nID: \(m.id)\nReason: \(reason.isEmpty ? "not given" : reason)\nReported by: \(username ?? "no chat username")\nTime: \(ISO8601DateFormatter().string(from: Date()))",
            "email": CloudAccount.shared.user?.email ?? "no-reply@dungen-descent.org",
            "platform": "ios-swift",
            "gameVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        ]
        var req = URLRequest(url: URL(string: "https://formspree.io/f/mkjnkenn")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else { throw URLError(.badServerResponse) }
            Feedback.announce("Report sent. Thank you. The developer reviews reports within 24 hours. It is hidden for you now.")
        } catch {
            Feedback.announce("The report could not be sent. Check your connection. It is hidden for you now.")
        }
    }

    /// chatFormatTime
    static func ago(_ ts: Double) -> String {
        let s = Int((Date().timeIntervalSince1970 * 1000 - ts) / 1000)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}

/// The web version's #screen-chat.
@MainActor
struct GlobalChatView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @StateObject private var chat: GlobalChat
    @State private var draft = ""
    @State private var nameDraft = ""
    @State private var nameError = ""
    @State private var askingTerms = false
    @State private var reporting: GlobalChat.Message?
    @State private var reportReason = ""
    @State private var blocking: GlobalChat.Message?
    /// Opened from the dungeon: back closes the chat instead of going to the menu.
    var onClose: (() -> Void)? = nil

    init(store: GameStore, onClose: (() -> Void)? = nil) {
        _chat = StateObject(wrappedValue: GlobalChat(store: store))
        self.onClose = onClose
    }

    var body: some View {
        WebScreen {
            if let onClose {
                Button("← Back to Dungeon", action: onClose).buttonStyle(BackButtonStyle())
                    .accessibilityLabel("Close chat and return to the dungeon")
                Text("💬 Global Chat").font(Theme.decorative(20)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            } else {
                ScreenHeader(title: "💬 Global Chat")
            }
            Text("Talk to players around the world. By chatting you agree to the Terms of Service at dungen-descent.org/terms: no tolerance for objectionable content or abusive players. Every message has Report and Block buttons.")
                .font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x888888)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            messagesBox
            if chat.username == nil { namePrompt } else { inputArea }
        }
        .onAppear { chat.open() }
        .onDisappear { chat.close() }
        .alert("Before you post", isPresented: $askingTerms) {
            Button("I agree") { chat.agree(); sendDraft() }
            Button("Cancel", role: .cancel) { Feedback.announce("You need to agree to the Terms of Service to post.") }
        } message: {
            Text("Chat messages and community enemies are seen by all players. By continuing you agree to the Dungeon Descent Terms of Service at dungen-descent.org/terms. There is no tolerance for objectionable content or abusive players. Content that breaks the rules is removed. You can report or block anyone. Do you agree?")
        }
        .alert("Report this message", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            TextField("Reason (optional)", text: $reportReason)
            Button("Send report") {
                if let m = reporting { Task { await chat.report(m, reason: reportReason) } }
                reporting = nil
            }
            Button("Cancel", role: .cancel) { reporting = nil; Feedback.announce("Report cancelled.") }
        } message: {
            Text("What is wrong with it? For example: offensive, harassment, spam. You can also leave this empty.")
        }
        .alert("Block \(blocking?.username ?? "")?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } })) {
            Button("Block", role: .destructive) {
                if let m = blocking { chat.block(m.username) }
                blocking = nil
            }
            Button("Cancel", role: .cancel) { blocking = nil }
        } message: {
            Text("You will no longer see their chat messages or community enemies. You can unblock everyone later in Settings, Chat.")
        }
    }

    private var messagesBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            if chat.messages.isEmpty {
                Text(chat.status).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x444444))
                    .frame(maxWidth: .infinity).padding(20)
            }
            ForEach(chat.messages) { m in
                let mine = m.username == chat.username
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(m.username).font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: mine ? 0xc8a832 : 0x88aacc))
                        Text(m.timestamp > 0 ? GlobalChat.ago(m.timestamp) : "").font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0x333333))
                    }
                    Text(m.message).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xaaaaaa))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.username) said \(m.message). \(m.timestamp > 0 ? GlobalChat.ago(m.timestamp) : "")")
                if !mine && !m.system {
                    HStack(spacing: 6) {
                        ugcButton("Report", label: "Report message by \(m.username)") { reportReason = ""; reporting = m }
                        ugcButton("Block", label: "Block \(m.username)") { blocking = m }
                    }
                    .padding(.top, 4)
                }
                Rectangle().fill(Color(hex: 0x111111)).frame(height: 1).padding(.vertical, 6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x060600))
        .overlay(Rectangle().stroke(Color(hex: 0x221100)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat messages")
    }

    private func ugcButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0xc8a832))
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
            .accessibilityLabel(label)
    }

    private var namePrompt: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose a username to start chatting").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xc8a832))
            HStack(spacing: 8) {
                TextField("Your username", text: $nameDraft)
                    .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xcccccc))
                    .padding(8).background(Color(hex: 0x060600)).overlay(Rectangle().stroke(Color(hex: 0x332200)))
                    .accessibilityLabel("Enter username")
                    .onSubmit(setName)
                Button("Go", action: setName)
                    .font(Theme.cinzel(10.4)).foregroundStyle(Theme.gold)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Theme.gold))
                    .accessibilityLabel("Set username")
            }
            if !nameError.isEmpty {
                Text(nameError).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0xcc4444))
            }
        }
        .padding(12)
        .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
    }

    private func setName() {
        if let e = chat.setUsername(nameDraft) {
            nameError = e
            Feedback.announce(e)
        } else {
            nameError = ""
        }
    }

    private var inputArea: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Type a message...", text: $draft)
                    .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xcccccc))
                    .padding(10).background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
                    .accessibilityLabel("Chat message, maximum 200 characters")
                    .submitLabel(.send)
                    .onSubmit(trySend)
                    .onChange(of: draft) { v in if v.count > 200 { draft = String(v.prefix(200)) } }
                Button("Send", action: trySend)
                    .font(Theme.cinzel(11.2)).foregroundStyle(Theme.gold)
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Theme.gold))
                    .accessibilityLabel("Send message")
            }
            Text("\(draft.count) / 200").font(Theme.cinzel(8.8)).foregroundStyle(Color(hex: 0x333333))
                .accessibilityHidden(true)
        }
    }

    private func trySend() {
        guard chat.agreed else {
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty { askingTerms = true }
            else { Feedback.announce("Please type a message first.") }
            return
        }
        sendDraft()
    }

    private func sendDraft() {
        if let problem = chat.send(draft) {
            Feedback.announce(problem)
            if problem.hasPrefix("Your message contains") { draft = "" }
        } else {
            draft = ""
        }
    }
}

/// Settings → Chat: the chat username and unblocking everyone.
@MainActor
struct ChatSettingsPanel: View {
    @StateObject private var chat: GlobalChat
    @State private var name = ""
    @State private var status = ""
    @State private var dungeonButton = false

    init(store: GameStore) {
        _chat = StateObject(wrappedValue: GlobalChat(store: store))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("💬 Chat").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            Toggle(isOn: Binding(get: { chat.store.getItem("dd_chat_dungeon") == "1" },
                                 set: { chat.store.setItem("dd_chat_dungeon", $0 ? "1" : "0"); dungeonButton = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Chat in Dungeon").font(Theme.cinzel(13)).foregroundStyle(Theme.ashLight)
                    Text("Adds a chat button inside the dungeon screen").font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                }
            }
            .tint(Theme.gold)
            .accessibilityLabel("Toggle dungeon chat button")
            .padding(.bottom, 8)
            Text("CHAT USERNAME").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            TextField(chat.username ?? "Your username", text: $name)
                .font(Theme.cinzel(12)).foregroundStyle(.white)
                .padding(10).background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                .accessibilityLabel("Chat username\(chat.username.map { ", currently \($0)" } ?? "")")
            Button("Save Username") {
                if let e = chat.setUsername(name) { status = e; Feedback.announce(e) }
                else { status = "Username saved: \(name)" }
            }
            .buttonStyle(WebButtonStyle(kind: .gold))
            if !status.isEmpty {
                Text(status).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x44cc88))
            }
            Text("BLOCKED PLAYERS").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim).padding(.top, 14)
            Text(chat.blockedCount == 0 ? "You have not blocked anyone."
                 : "You have blocked \(chat.blockedCount) player\(chat.blockedCount == 1 ? "" : "s").")
                .font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary)
            Button("Unblock Everyone") { chat.unblockAll() }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Unblock everyone and show hidden messages again")
        }
    }
}
