import SwiftUI
import DungeonCore

/// Settings → Developer Tools (#ov-dev-password, #ov-dev-tools,
/// #ov-change-dev-pw). The run tools work while you're in a dungeon (Settings
/// from the pause menu); the true ending and screen reader prompt tools wait
/// for those systems.
struct DevToolsPanel: View {
    @EnvironmentObject var game: GameModel
    /// The run in progress, when Settings was opened from the dungeon.
    var run: RunModel?
    /// Called after three wrong passwords: the category is gone for this launch.
    var lockedOut: () -> Void

    /// _devPasswordAttempts / _devToolsLocked, for this launch of the app.
    static var attempts = 0
    static var locked = false

    @State private var unlocked = false
    @State private var password = ""
    @State private var error = ""
    @State private var changing = false
    @State private var newPw = ""
    @State private var confirmPw = ""
    @State private var changeError = ""
    @State private var email = ""
    @State private var coins = ""
    @State private var note = ""
    @State private var sendStatus = ""
    @State private var sendOK = false
    @State private var sending = false
    @State private var prize = VoidMode.Prize.gold500
    @State private var codeLabel = ""
    @State private var code: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if unlocked { tools } else { gate }
        }
        .onAppear {
            focused = true
            Feedback.announce("Developer Tools. Enter the password to continue.", after: 0.3)
        }
    }

    // MARK: Password

    private var gate: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEVELOPER TOOLS").font(Theme.cinzel(9.6)).tracking(4).foregroundStyle(Color(hex: 0x555555))
            Text("Enter the password to continue.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            SecureField("", text: $password, prompt: Text("••••").foregroundColor(Theme.textDim))
                .focused($focused)
                .font(Theme.cinzel(16)).foregroundStyle(Theme.textPrimary)
                .padding(10).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                .onSubmit(check)
                .onChange(of: password) { password = String($0.prefix(10)) }
                .accessibilityLabel("Developer password input")
            if !error.isEmpty { Text(error).font(Theme.cinzel(11.5)).foregroundStyle(Theme.bloodBright) }
            Button("Enter", action: check).buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Submit password")
        }
    }

    private func check() {
        guard !Self.locked else { lockedOut(); return }
        if password == DevTools.password(game.store) {
            Self.attempts = 0
            unlocked = true
            Feedback.announce("Developer Tools unlocked. Use caution.")
            return
        }
        Self.attempts += 1
        password = ""
        if Self.attempts >= 3 {
            Self.locked = true
            Feedback.announce("Access denied. Developer Tools have been removed.")
            lockedOut()
            return
        }
        let left = 3 - Self.attempts
        error = "Incorrect. \(left) attempt\(left == 1 ? "" : "s") remaining."
        Feedback.announce("Incorrect password. \(left) attempts remaining.")
        focused = true
    }

    // MARK: Tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("🔧 DEVELOPER TOOLS").font(Theme.cinzel(9.6)).tracking(4).foregroundStyle(Color(hex: 0x555555)).padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
            changePassword
            row("💎 Give 1M Diamonds", "Adds 1,000,000 diamonds for testing the gun shop.", "Give", label: "Add 1 million diamonds") {
                game.wallet.addDiamonds(1_000_000)
                Feedback.announce("1 million diamonds added.")
            }
            row("🔫 Unlock All Guns", "Unlocks every gun instantly for testing.", "Unlock", label: "Unlock all guns") {
                DevTools.unlockAllGuns(game.store)
                game.wallet.addDiamonds(99_999)
                Feedback.announce("All guns unlocked.")
            }
            row("🔩 Give All Gun Parts", "Adds 99 of every gun part for testing crafting.", "Give", label: "Give all gun parts") {
                DevTools.giveAllGunParts(game.store)
                Feedback.announce("99 of every gun part added.")
            }
            row("Unlock All Dungeons", "Unlocks every dungeon instantly.", "Unlock", label: "Unlock all dungeons") {
                DevTools.unlockAll(game.store)
                game.refresh()
                Feedback.announce("Dev: all dungeons unlocked, including The Infernal Descent.")
            }
            row("Reset All Unlocks", "Locks everything except the Crypt.", "Reset", label: "Reset all dungeon unlocks") {
                DevTools.resetUnlocks(game.store)
                game.refresh()
                Feedback.announce("Dev: all dungeon unlocks reset. Only Crypt of Malachar available.")
            }
            row("Void Reaper — Force Awaken", "Skip countdown, awaken immediately.", "Awaken", label: "Force awaken void reaper") {
                Task { Feedback.announce(await VoidReaperLive.shared.devAwaken()) }
            }
            row("Void Reaper — Reset", "Reset countdown back to 0%.", "Reset", label: "Reset void reaper") {
                Task { Feedback.announce(await VoidReaperLive.shared.devReset()) }
            }
            row("Medusa — Force Spawn", "Forces Medusa to spawn next Hollow room.", "Spawn", label: "Force Medusa spawn") {
                inRun { $0.devForce(medusa: true) }
            }
            row("Jump to Floor 10", "Skips to floor 10 boss fight instantly.", "Jump", label: "Jump to floor 10") {
                inRun { $0.devJumpFloor10() }
            }
            row("God Mode HP", "Sets your HP to 1,000,000 for testing. Only works in dungeon.", "God Mode", label: "God mode HP") {
                inRun { $0.devGodMode() }
            }
            row("Force Ambush", "Triggers an ambush fight in the next room.", "Force", label: "Force ambush") {
                inRun { $0.devForce(medusa: false) }
            }
            sendCoins
            generator
        }
    }

    private func inRun(_ act: (RunModel) -> Void) {
        guard let run else { Feedback.announce("You must be in a dungeon first."); return }
        act(run)
    }

    private func row(_ name: String, _ desc: String, _ button: String, label: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(Theme.cinzel(13)).foregroundStyle(Theme.ashLight)
                Text(desc).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(button, action: action).buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel(label)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderDim).frame(height: 1) }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, label: String, secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.textDim))
            } else {
                TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.textDim))
            }
        }
        .font(Theme.crimson(15)).foregroundStyle(Theme.textPrimary)
        .padding(10).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
        .accessibilityLabel(label)
    }

    private var changePassword: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🔑 Change Password").font(Theme.cinzel(13)).foregroundStyle(Theme.ashLight)
                Spacer()
                Button(changing ? "Cancel" : "Change") {
                    changing.toggle()
                    newPw = ""; confirmPw = ""; changeError = ""
                    Feedback.announce(changing ? "Change developer password. Enter new password twice then press Confirm." : "Cancelled.")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel(changing ? "Cancel" : "Change developer tools password")
            }
            if changing {
                field("New password", $newPw, label: "New password", secure: true)
                field("Confirm password", $confirmPw, label: "Confirm new password", secure: true)
                if !changeError.isEmpty { Text(changeError).font(Theme.cinzel(11.5)).foregroundStyle(Theme.bloodBright) }
                Button("Confirm") {
                    if let problem = DevTools.changePassword(newPw, confirm: confirmPw, store: game.store) {
                        changeError = problem
                        Feedback.announce(problem)
                        if problem == "Passwords do not match." { confirmPw = "" }
                    } else {
                        changing = false
                        Feedback.announce("Password changed. New password saved.")
                    }
                }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("Confirm new password")
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderDim).frame(height: 1) }
    }

    private var sendCoins: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🪙 SEND MYSTERY COINS").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader)
            field("Player email address", $email, label: "Player email")
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            field("Coins to send", $coins, label: "Number of coins").keyboardType(.numberPad)
            field("Message (optional)", $note, label: "Message")
            Button(sending ? "⏳ Looking up player..." : "Send Coins") {
                sending = true
                let n = min(999, jsParseInt(coins) ?? 0)
                Task {
                    let out = await CloudAccount.shared.devSendCoins(email: email.trimmingCharacters(in: .whitespaces), coins: n,
                                                                    message: note.trimmingCharacters(in: .whitespaces))
                    sending = false
                    sendOK = out.ok
                    sendStatus = out.text
                    Feedback.announce(out.text)
                    if out.ok { email = ""; coins = ""; note = "" }
                }
            }
            .buttonStyle(WebButtonStyle(kind: .gold)).disabled(sending)
            .accessibilityLabel("Send coins to player")
            if !sendStatus.isEmpty {
                Text(sendStatus).font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: sendOK ? 0x44ff88 : 0xff4444))
            }
        }
        .padding(.top, 20)
    }

    private var generator: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🌑 GENERATE REWARD CODE").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
                .accessibilityAddTraits(.isHeader)
            Text("Generate a shareable VOID code with a specific reward. Share it on YouTube, Discord, or anywhere.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            Picker("Select reward for generated code", selection: $prize) {
                ForEach(VoidMode.Prize.allCases, id: \.self) { Text($0.label.prefix(1).uppercased() + $0.label.dropFirst()).tag($0) }
            }
            .pickerStyle(.menu).tint(Theme.gold)
            field("e.g. Happy Birthday, Dungeon Descent!", $codeLabel, label: "Optional code label")
                .onChange(of: codeLabel) { codeLabel = String($0.prefix(30)) }
            Button("🌑 Generate Code") {
                var d = SystemDice()
                let c = DevTools.rewardCode(for: prize, dice: &d)
                code = c
                Feedback.announce("Code generated: \(c). Reward: \(prize.label). Press Copy Code to copy it.")
            }
            .buttonStyle(WebButtonStyle(kind: .gold))
            .accessibilityLabel("Generate reward code")
            if let code {
                Text("Your code:").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
                Text(code).font(Theme.cinzel(18, weight: .bold)).foregroundStyle(Color(hex: 0xa0a0ff)).textSelection(.enabled)
                Text("Reward: \(prize.label)\(codeLabel.isEmpty ? "" : " — \(codeLabel)")").font(Theme.cinzel(11)).foregroundStyle(Theme.textSecondary)
                Button("📋 Copy Code") {
                    UIPasteboard.general.string = code
                    Feedback.announce("Code copied: \(code)")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Copy generated code to clipboard")
            }
        }
        .padding(.top, 20)
    }
}
