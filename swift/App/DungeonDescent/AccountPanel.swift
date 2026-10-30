import SwiftUI
import DungeonCore

/// The web version's #ov-account panel, shown from Settings → Account.
@MainActor
struct AccountPanel: View {
    @ObservedObject var cloud = CloudAccount.shared
    @EnvironmentObject var game: GameModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmDelete = false
    @State private var username = ""
    @State private var pickingTitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ICloudBackupSection().padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 6) {
                Text("⚠ ALPHA FEATURE").font(Theme.cinzel(10.4)).tracking(3).foregroundStyle(Color(hex: 0x6666ff))
                (Text("This account system is in Alpha. An account is ")
                    + Text("not required").foregroundColor(Color(hex: 0xaaaaaa)).bold()
                    + Text(" to play. The game always saves on this device no matter what. If you sign in, your save is also backed up to the cloud, and the same account works in the web version."))
                    .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x888888)).lineSpacing(4)
                Text(cloud.signedIn ? "✓ Cloud connected — \(cloud.user?.email ?? "")" : "○ Cloud available — sign in to sync")
                    .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888)).padding(.top, 2)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0a1a))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x333366)))
            .accessibilityElement(children: .combine)
            .padding(.bottom, 20)

            Text("☁ ACCOUNT").font(Theme.cinzel(9.6)).tracking(3.8).foregroundStyle(Color(hex: 0x555555))
                .padding(.bottom, 16).accessibilityAddTraits(.isHeader)

            Text(cloud.signedIn ? "Signed in" : "Not signed in — saving on this device")
                .font(Theme.cinzel(12)).foregroundStyle(cloud.signedIn ? Color(hex: 0x44ff88) : Color(hex: 0x888888))
                .frame(maxWidth: .infinity).padding(.bottom, 16)

            if cloud.signedIn { signedInSection } else { loginSection }

            Text(cloud.message).font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: cloud.messageColor))
                .frame(maxWidth: .infinity, minHeight: 18).multilineTextAlignment(.center).padding(.top, 8)
                .accessibilityHidden(cloud.message.isEmpty)
        }
        .disabled(cloud.busy)
        .fullScreenCover(isPresented: $pickingTitle) {
            ZStack {
                Theme.bgVoid.ignoresSafeArea()
                TitlePicker(name: cloud.displayName) { pickingTitle = false }
            }
            .environmentObject(game)
        }
        .alert("Choose a save", isPresented: $cloud.choosingSave) {
            Button("Use the cloud save") { Task { await cloud.keepCloudSave() } }
            Button("Keep this device's save") { Task { await cloud.keepDeviceSave() } }
        } message: {
            Text("This device and your cloud account both have a save. The cloud save replaces the characters on this device. Keeping this device's save uploads it over the cloud one.")
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text).textContentType(.password)
            } else {
                TextField(placeholder, text: text).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .font(Theme.cinzel(12)).foregroundStyle(.white)
        .padding(10)
        .background(Color(hex: 0x0a0a0a))
        .overlay(Rectangle().stroke(Color(hex: 0x333333)))
        .accessibilityLabel(placeholder)
        .padding(.bottom, 8)
    }

    private func button(_ title: String, bg: UInt32, border: UInt32, fg: UInt32, label: String,
                        action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(Theme.cinzel(12)).foregroundStyle(Color(hex: fg))
                .frame(maxWidth: .infinity).padding(12)
                .background(Color(hex: bg)).overlay(Rectangle().stroke(Color(hex: border)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .padding(.bottom, 8)
    }

    private var loginSection: some View {
        VStack(spacing: 0) {
            field("Email address", text: $email, secure: false)
            field("Password", text: $password, secure: true)
            button("Sign In", bg: 0x0a1a0a, border: 0x336633, fg: 0xaaffaa, label: "Sign in with email and password") {
                await cloud.signIn(email: email, password: password)
            }
            button("Create Account", bg: 0x0a0a1a, border: 0x333366, fg: 0xaaaaff, label: "Create new account") {
                await cloud.signUp(email: email, password: password)
            }
            button("🔵 Sign in with Google", bg: 0x1a0a0a, border: 0x663333, fg: 0xffaaaa, label: "Sign in with Google") {
                await cloud.signInWithGoogle()
            }
            button("🍎 Sign in with Apple", bg: 0x0a0a0a, border: 0x444444, fg: 0xcccccc, label: "Sign in with Apple") {
                await cloud.signInWithApple()
            }
            Button("Forgot password?") { Task { await cloud.resetPassword(email: email) } }
                .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555)).underline()
                .padding(8)
                .accessibilityLabel("Forgot password")
        }
    }

    private var signedInSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Signed in as").font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0x888888))
                Text(cloud.displayLine).font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0xaaffaa))
            }
            .frame(maxWidth: .infinity).padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            Text("Leaderboard name: \(cloud.displayName) · \(cloud.title)")
                .font(Theme.cinzel(11.2)).foregroundStyle(Color(hex: 0xffdd44))
                .frame(maxWidth: .infinity).padding(6)
                .background(Color(hex: 0x1a1400)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                .padding(.bottom, 8)
            TextField("Username (3–20 letters, numbers or _)", text: $username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(Theme.cinzel(12)).foregroundStyle(.white)
                .padding(10).background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                .accessibilityLabel("Username")
                .padding(.bottom, 8)
            button("🏷 Set Username", bg: 0x1a1400, border: 0xffdd44, fg: 0xffdd44, label: "Set username") {
                await cloud.setUsername(username)
            }
            button("🏷 Change Title", bg: 0x1a1400, border: 0xffdd44, fg: 0xffdd44, label: "Change your title") {
                pickingTitle = true
                Feedback.announce("Choose your title. First 10 titles are free. Others cost Mystery Coins.", after: 0.3)
            }
            button("☁ Sync Save to Cloud", bg: 0x0a1a0a, border: 0x336633, fg: 0xaaffaa, label: "Sync save to cloud now") {
                await cloud.sync(silent: false)
            }
            button("⬇ Load Save from Cloud", bg: 0x0a0a1a, border: 0x333366, fg: 0xaaaaff,
                   label: "Load save from cloud. Replaces the characters on this device.") {
                await cloud.load()
            }
            button("Sign Out", bg: 0x1a1a0a, border: 0x666633, fg: 0xffffaa, label: "Sign out") {
                cloud.signOut()
            }
            button(confirmDelete ? "⚠ Tap again to delete" : "Delete Account", bg: 0x1a0a0a, border: 0x663333, fg: 0xff6666,
                   label: confirmDelete ? "Confirm delete account" : "Delete account and its cloud save") {
                if confirmDelete {
                    confirmDelete = false
                    await cloud.deleteAccount()
                } else {
                    confirmDelete = true
                    Feedback.announce("Tap Delete Account again to confirm. This deletes your account and its cloud save. Saves on this device are kept.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { confirmDelete = false }
                }
            }
        }
    }
}

/// #ov-title-picker
struct TitlePicker: View {
    @EnvironmentObject var game: GameModel
    let name: String
    let close: () -> Void
    @State private var version = 0

    var body: some View {
        let _ = version
        let store = game.store
        let current = Titles.current(store)
        let coins = CoinShop.coins(store)
        WebOverlay {
            HStack {
                Text("Choose Your Title").font(Theme.decorative(15)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("← Back", action: close).buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Close")
            }
            Text("Currently: \(name) the \(current)").font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
            Text("🪙 \(coins) Mystery Coins available").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xffdd44))
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Titles.listed(store), id: \.tag) { t in row(t.tag, t.cost, current: current, coins: coins) }
                }
            }
            .frame(maxHeight: 380)
        }
    }

    private func row(_ tag: String, _ cost: Int, current: String, coins: Int) -> some View {
        let owned = Titles.isOwned(tag, game.store)
        let isCurrent = tag == current
        return HStack {
            Text("\(name) the \(tag)\(isCurrent ? " ✓" : "")").font(Theme.cinzel(12)).foregroundStyle(isCurrent ? Theme.gold : Color(hex: 0xaaaaaa))
            Spacer()
            if isCurrent {
                Text("Active").font(Theme.cinzel(10.4)).foregroundStyle(Theme.gold)
            } else if owned {
                Button("Select") { pick(tag) }.buttonStyle(SmallGhostStyle(color: Color(hex: 0xaaffaa)))
                    .accessibilityLabel("Select title \(name) the \(tag)")
            } else if coins >= cost {
                Button("🪙 \(cost)") { buy(tag, cost) }.buttonStyle(SmallGhostStyle(color: Color(hex: 0xffdd44)))
                    .accessibilityLabel("Buy title \(tag) for \(cost) mystery coins")
            } else {
                Text("🪙 \(cost)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x444444))
                    .accessibilityLabel("\(tag) costs \(cost) mystery coins, not enough coins")
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(isCurrent ? Theme.gold.opacity(0.1) : Color(hex: 0x0a0a0a))
        .overlay(Rectangle().stroke(isCurrent ? Theme.gold : Color(hex: 0x1a1a1a)))
    }

    private func pick(_ tag: String) {
        Titles.select(tag, store: game.store)
        version += 1
        Feedback.announce("Title changed to \(name) the \(tag).")
    }

    private func buy(_ tag: String, _ cost: Int) {
        guard Titles.buy(tag, store: game.store) else { Feedback.announce("Not enough Mystery Coins."); return }
        version += 1
        Sound.sfx("sfx-unlock")
        Feedback.announce("Title unlocked: \(tag). \(CoinShop.coins(game.store)) coins remaining. Title changed to \(name) the \(tag).")
    }
}
