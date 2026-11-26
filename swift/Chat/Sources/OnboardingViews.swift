import SwiftUI

struct SignInView: View {
    @EnvironmentObject var account: Account
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Welcome to Dungeon Descent Chat, the community for Dungeon Descent players. Sign in with the same account you use in the game.")
                }
                Section {
                    Button("Sign in with Apple") { Task { await account.signInWithApple() } }
                    Button("Sign in with Google") { Task { await account.signInWithGoogle() } }
                }
                Section(creating ? "Create an account with email" : "Sign in with email") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                    Button(creating ? "Create account" : "Sign in") {
                        Task { creating ? await account.signUp(email: email, password: password)
                                        : await account.signIn(email: email, password: password) }
                    }
                    .disabled(account.busy)
                    Button(creating ? "I already have an account" : "Create a new account") { creating.toggle() }
                    if !creating {
                        Button("Forgot password") { Task { await account.resetPassword(email: email) } }
                    }
                }
                if !account.message.isEmpty {
                    Section { Text(account.message).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("DD Chat")
        }
    }
}

struct UsernameView: View {
    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var account: Account
    @State private var name = ""
    @State private var problem = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let game = chat.gameUsername {
                        Text("Your username in Dungeon Descent is \(game). Use it here too, so friends know it's you.")
                    } else {
                        Text("Pick a username. It's how other players see you, here and in the game. 3 to 20 letters, numbers or underscores.")
                    }
                }
                Section {
                    TextField("Username", text: $name)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(busy ? "Saving…" : "Continue") {
                        busy = true
                        Task {
                            problem = await chat.join(username: name) ?? ""
                            if !problem.isEmpty { Speech.say(problem) }
                            busy = false
                        }
                    }
                    .disabled(busy || name.isEmpty)
                }
                if !problem.isEmpty { Section { Text(problem).foregroundStyle(.orange) } }
                Section { Button("Sign out", role: .destructive) { account.signOut() } }
            }
            .navigationTitle("Your username")
            .onAppear { if name.isEmpty { name = chat.gameUsername ?? "" } }
            .onChange(of: chat.gameUsername) { _, n in if name.isEmpty { name = n ?? "" } }
        }
    }
}

struct RulesView: View {
    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var account: Account

    static let rules = [
        "Be kind. No harassment, hate, threats or bullying.",
        "No swearing or sexual content. A filter blocks the worst words.",
        "No spam, scams or sharing other people's private information.",
        "Report anything that breaks these rules. Moderators review every report within 24 hours.",
        "Breaking the rules gets your messages removed, and can get you banned from chat.",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Community rules") {
                    ForEach(Self.rules, id: \.self) { Text($0) }
                }
                Section {
                    Text("Messages in channels are seen by every member. Private messages and group chats are seen only by the people in them. You can report or block anyone, any time. By continuing you agree to these rules and to the Dungeon Descent Terms of Service at dungen-descent.org/terms.")
                    Button("I agree") { Task { await chat.agreeToRules() } }
                }
                Section { Button("Sign out", role: .destructive) { account.signOut() } }
            }
            .navigationTitle("Before you start")
        }
    }
}

/// "Which channels should notify you?" — asked once at the start, and again
/// from Settings.
struct NotificationSetupView: View {
    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var push: Push
    var firstTime = false

    var body: some View {
        let form = Form {
            if firstTime {
                Section { Text("Which channels should notify you? You can change this any time in Settings.") }
            }
            Section("Channels") {
                ForEach(chat.channels.filter { !$0.testersOnly || chat.isTester }) { c in
                    Toggle(c.name, isOn: Binding(get: { push.channels.contains(c.id) },
                                                 set: { on in if on { push.channels.insert(c.id) } else { push.channels.remove(c.id) } }))
                    if push.channels.contains(c.id) { SoundPicker(key: c.id) }
                }
            }
            Section("Private messages and groups") {
                Toggle("Private messages", isOn: $push.dms)
                if push.dms { SoundPicker(key: "dm") }
                Toggle("Group chats", isOn: $push.groups)
                if push.groups { SoundPicker(key: "group") }
            }
            Section {
                Button(firstTime ? "Done" : "Save") {
                    Task {
                        await push.save()
                        await push.requestPermission()
                        Speech.say("Notifications saved.")
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        if firstTime { NavigationStack { form } } else { form }
    }
}

struct SoundPicker: View {
    @EnvironmentObject var push: Push
    let key: String

    var body: some View {
        Picker("Sound", selection: Binding(get: { push.soundFor[key] ?? "" },
                                           set: { push.soundFor[key] = $0; push.preview($0) })) {
            ForEach(Push.sounds) { Text($0.name).tag($0.id) }
        }
        .accessibilityHint("Plays the sound when you pick it.")
    }
}
