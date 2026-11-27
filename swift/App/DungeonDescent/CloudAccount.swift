import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import DungeonCore

/// The account system (ACCOUNT SYSTEM — BETA): the same Firebase project,
/// sign-in methods and cloud save as the web version, so one account and
/// one save work in both. The cloud save is the "saves/{uid}" document in
/// the "dungeon-descent" Firestore database, holding the same save keys as
/// strings, exactly like syncToCloud() writes them.
@MainActor
final class CloudAccount: NSObject, ObservableObject {
    static let shared = CloudAccount()

    /// The developer's account (Leo), the same one the Firestore rules'
    /// isDev() trusts. Developer Tools only exist for it.
    static let developerUID = "WgqZGmnPKeYIymlMkx0aAg8G2T52"
    /// Signed in as the developer.
    var isDeveloper: Bool { (user ?? Auth.auth().currentUser)?.uid == Self.developerUID }

    @Published private(set) var user: User?
    /// The line under the buttons (#account-error / #account-sync-indicator).
    @Published var message = ""
    @Published var messageColor: UInt32 = 0xff4444
    @Published private(set) var busy = false
    /// Both this device and the cloud have a save: which one to keep.
    @Published var choosingSave = false

    weak var game: GameModel?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var lastAutoSync = Date.distantPast
    private var appleNonce: String?
    private var appleContinuation: CheckedContinuation<ASAuthorization, Error>?

    /// The save keys syncToCloud sends, by their field name in the cloud document.
    static let fields: [(field: String, key: String)] = [
        ("chars", "dd_chars"), ("unlocks", "dd_unlocks"), ("achievements", "dd_achievements"),
        ("globalStats", "dd_global_stats"), ("coinUpgrades", "dd_coin_upgrades"), ("raidData", "dd_raid"),
        ("medusa", "dd_medusa"), ("voidReaper", "dd_void_reaper"), ("username", "dd_username"),
        ("titleTag", "dd_title_tag"), ("srPromptSeen", "dd_sr_prompt_seen"), ("accessSettings", "dd_access"),
    ]

    /// Called once at launch, before anything uses Firebase.
    static func configure() {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
    }

    private var db: Firestore { Firestore.firestore(database: "dungeon-descent") }

    func start(game: GameModel) {
        self.game = game
        game.onDeath = { [weak self] d in Task { await self?.postDeath(d) } }
        game.onLegend = { [weak self] e, info in Task { await self?.postLegend(e, info) } }
        guard authHandle == nil else { return }
        user = Auth.auth().currentUser
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
        // Opening the game: a newer save from another device comes down.
        if user != nil { Task { await checkCloud(launch: true) } }
    }

    var signedIn: Bool { user != nil }

    /// "☁ LEO" on the menu, from the username or the email.
    var shortName: String? {
        guard let u = user else { return nil }
        let name = game?.store.getItem("dd_username") ?? u.displayName ?? u.email ?? "Signed in"
        return String(name.prefix(3)).uppercased()
    }

    var displayLine: String {
        guard let u = user else { return "" }
        let name = displayName
        return u.email.map { "\(name) (\($0))" } ?? name
    }

    /// generateFallbackUsername: "Leo#x7k" from the email and the account id.
    static func fallbackName(email: String?, uid: String) -> String {
        let local = (email ?? "").split(separator: "@").first.map(String.init) ?? ""
        let letters = local.filter { $0.isASCII && $0.isLetter }
        let prefix = letters.count >= 3 ? letters.prefix(1).uppercased() + letters.dropFirst().prefix(2).lowercased()
            : !letters.isEmpty ? letters.prefix(1).uppercased() + letters.dropFirst().lowercased()
            : "Anon"
        return prefix + "#" + String(uid.suffix(3))
    }

    /// getDisplayName: the chosen username, or the fallback.
    var displayName: String {
        guard let u = user else { return "Adventurer" }
        if let n = game?.store.getItem("dd_username"), !n.isEmpty { return n }
        return Self.fallbackName(email: u.email, uid: u.uid)
    }

    /// getPlayerTitle
    var title: String {
        if let t = game?.store.getItem("dd_title"), !t.isEmpty { return t }
        return "Wanderer"
    }

    private func say(_ text: String, color: UInt32 = 0xff4444) {
        message = text
        messageColor = color
        Feedback.announce(text)
    }

    // MARK: Email

    /// accountSignIn
    func signIn(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty else { say("Please enter email and password."); return }
        busy = true
        defer { busy = false }
        message = "Signing in..."
        messageColor = 0x888888
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            message = ""
            Feedback.announce("Signed in successfully. Syncing your save data.")
            try? await db.collection("users").document(result.user.uid)
                .setData(["email": result.user.email ?? "", "updatedAt": Self.now], merge: true)
            await afterSignIn()
        } catch {
            say(Self.signInMessage(error))
        }
    }

    /// accountSignUp
    func signUp(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty else { say("Please enter email and password."); return }
        guard password.count >= 6 else { say("Password must be at least 6 characters."); return }
        busy = true
        defer { busy = false }
        message = "Creating account..."
        messageColor = 0x888888
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            message = ""
            Feedback.announce("Account created! Syncing your save data to the cloud.")
            await sync(silent: false)
            try? await db.collection("users").document(result.user.uid)
                .setData(["email": result.user.email ?? "", "createdAt": Self.now], merge: true)
        } catch {
            let code = AuthErrorCode(rawValue: (error as NSError).code)
            say(code == .emailAlreadyInUse ? "Email already in use. Try signing in."
                : code == .invalidEmail ? "Invalid email address."
                : code == .weakPassword ? "Password too weak. Use at least 6 characters."
                : code == .networkError ? "Network error. Check your connection."
                : "Sign up failed: \(error.localizedDescription)")
        }
    }

    private static func signInMessage(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .userNotFound: return "No account found. Try creating one."
        case .wrongPassword: return "Wrong password."
        case .invalidEmail: return "Invalid email address."
        case .invalidCredential: return "Wrong email or password."
        case .operationNotAllowed: return "Email sign-in not enabled in Firebase console."
        case .networkError: return "Network error. Check your connection."
        default: return "Sign in failed: \(error.localizedDescription)"
        }
    }

    /// accountForgotPassword
    func resetPassword(email: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { say("Enter your email address first."); return }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            message = "Password reset email sent! Check your inbox."
            messageColor = 0x44ff88
            Feedback.announce("Password reset email sent to \(email). Check your inbox.")
        } catch {
            say("Could not send reset email. Check the address.")
        }
    }

    // MARK: Google

    /// accountGoogleLogin: Google's own sign-in sheet, then Firebase.
    func signInWithGoogle() async {
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else { say("Cloud not ready. Check connection."); return }
        guard let presenter = Self.topViewController() else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        busy = true
        defer { busy = false }
        message = "Opening Google sign in..."
        messageColor = 0x888888
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw CloudError.noToken }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                           accessToken: result.user.accessToken.tokenString)
            message = "Signing into Firebase..."
            try await Auth.auth().signIn(with: credential)
            message = ""
            Feedback.announce("Signed in with Google. Syncing your save data.")
            await afterSignIn()
        } catch {
            if (error as? GIDSignInError)?.code == .canceled { message = ""; return }
            say("Google sign in failed: \(error.localizedDescription)")
        }
        #else
        say("Google sign in isn't available on this device. Use Apple or email.")
        #endif
    }

    // MARK: Apple

    /// accountAppleLogin: Sign in with Apple, then Firebase with the same nonce.
    func signInWithApple() async {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        busy = true
        defer { busy = false }
        message = "Opening Apple sign in..."
        messageColor = 0x888888
        do {
            let auth = try await withCheckedThrowingContinuation { (c: CheckedContinuation<ASAuthorization, Error>) in
                appleContinuation = c
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
            guard let apple = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = apple.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                throw CloudError.noToken
            }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
            message = "Signing into Firebase..."
            try await Auth.auth().signIn(with: credential)
            message = ""
            Feedback.announce("Signed in with Apple. Syncing your save data.")
            await afterSignIn()
        } catch {
            if (error as? ASAuthorizationError)?.code == .canceled { message = ""; return }
            say("Apple sign in failed: \(error.localizedDescription)")
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var gen = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(gen.next() % UInt64(chars.count))] })
    }

    // MARK: Saves

    private static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// Which kind of device wrote the cloud save.
    static var platform: String {
        #if targetEnvironment(macCatalyst)
        return "mac"
        #elseif os(visionOS)
        return "vision"
        #else
        return "ios"
        #endif
    }

    private func cloudSave() async throws -> [String: Any]? {
        guard let uid = user?.uid ?? Auth.auth().currentUser?.uid else { return nil }
        let snap = try await db.collection("saves").document(uid).getDocument()
        return snap.exists ? snap.data() : nil
    }

    /// After signing in: like the web version, a cloud save comes down and no
    /// cloud save means this device's goes up. When both exist, the player
    /// chooses, so a Swift save isn't silently replaced by an older one.
    private func afterSignIn() async {
        user = Auth.auth().currentUser
        await checkCloud(launch: true)
    }

    private var lastCheck = Date.distantPast

    /// CLOUD SYNC (CloudSync in DungeonCore): a newer save from another device
    /// comes down by itself, this device's progress goes up, and only when
    /// both changed does the player choose. Coming back to the app, a newer
    /// save is only loaded when nothing changed here (never mid-run).
    func checkCloud(launch: Bool) async {
        guard let game, signedIn else { return }
        if !launch && Date().timeIntervalSince(lastCheck) < 300 { return }
        lastCheck = Date()
        do {
            guard let cloud = try await cloudSave(), cloud["chars"] != nil || cloud["full"] != nil else {
                await sync(silent: true)
                return
            }
            let store = game.store
            let savedAt = (cloud["savedAt"] as? NSNumber)?.doubleValue ?? 0
            var last = CloudSync.number(store.getItem(CloudSync.lastKey))
            // The newest cloud save is this device's own (its note of having
            // sent it can be lost when iOS freezes the app right after the
            // upload): nobody else changed it, so never ask about it.
            if savedAt > last, (cloud["savedDevice"] as? String) == Self.deviceId {
                last = savedAt
                store.setItem(CloudSync.lastKey, String(Int(savedAt)))
            }
            var dirty = CloudSync.number(store.getItem(CloudSync.dirtyKey))
            // Nothing played here yet: there's nothing to lose.
            if game.characters.isEmpty && last == 0 { dirty = 0 }
            // An old cloud save (no savedAt) and a device that never synced.
            let cloudAt = savedAt > 0 ? savedAt : (last == 0 ? 1 : 0)
            switch CloudSync.decide(cloudSavedAt: cloudAt, lastSync: last, dirtyAt: dirty) {
            case .pull:
                restore(cloud, quiet: !launch)
                Feedback.announce("Loaded your newer save from your other device.", after: 1)
            case .ask:
                if launch {
                    choosingSave = true
                    Feedback.announce("This device and your cloud account both have newer progress. Choose which one to keep.")
                }
            case .push:
                await sync(silent: true)
            case .nothing:
                break
            }
        } catch {
            if launch { message = "Couldn't reach your cloud save." }
        }
    }

    /// This install's id, kept outside the save (so it never syncs): which
    /// device wrote a cloud save.
    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "swift_device_id") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "swift_device_id")
        return id
    }

    /// The choice when both have a save.
    func keepCloudSave() async {
        choosingSave = false
        do {
            if let cloud = try await cloudSave() { restore(cloud) }
        } catch {
            say("Load failed. Check your connection.")
        }
    }

    func keepDeviceSave() async {
        choosingSave = false
        await sync(silent: false)
    }

    /// loadFromCloud
    func load() async {
        Feedback.announce("Loading your save data from the cloud. Please wait.")
        do {
            guard let cloud = try await cloudSave() else {
                say("No cloud save found. Starting fresh.", color: 0xffaa44)
                return
            }
            restore(cloud)
        } catch {
            say("Load failed. Check your connection.")
        }
    }

    private func restore(_ cloud: [String: Any], quiet: Bool = false) {
        // The whole save (12.0), then the old fields on top: they're written
        // together, and an older app may have written only the old ones since.
        var data = CloudSync.decode(cloud["full"] as? String) ?? [:]
        for (field, key) in Self.fields {
            if let s = cloud[field] as? String, !s.isEmpty { data[key] = s }
        }
        game?.importWebSave(data, keepSwiftRuns: true)
        // Loading isn't progress: this device now matches the cloud.
        let savedAt = (cloud["savedAt"] as? NSNumber)?.doubleValue ?? 0
        let mark = String(Int(savedAt))
        game?.store.setItem(CloudSync.lastKey, mark)
        game?.store.setItem(CloudSync.dirtyKey, mark)
        game?.saveNow()
        if !quiet { say("Load complete. Your save data has been restored from the cloud.", color: 0x44ff88) }
    }

    /// syncToCloud. Silent syncs don't speak (the web version's auto-sync).
    /// The near-the-size-limit warning was given this session.
    private var warnedSaveSize = false

    func sync(silent: Bool) async {
        guard let uid = user?.uid ?? Auth.auth().currentUser?.uid else {
            if !silent { say("Not signed in. Please sign in first.", color: 0xffaa44) }
            return
        }
        guard let store = game?.store else { return }
        if !silent {
            message = "⏳ Syncing..."
            messageColor = 0xffaa44
            Feedback.announce("Syncing your save data to the cloud. Please wait.")
        }
        var data: [String: Any] = [:]
        for (field, key) in Self.fields { data[field] = store.getItem(key).map { $0 as Any } ?? NSNull() }
        let savedAt = Self.now
        if let snapshot = game?.snapshot(), let full = CloudSync.encode(CloudSync.full(snapshot)) {
            data["full"] = full
            data["savedAt"] = savedAt
            data["savedBy"] = Self.platform
            data["savedDevice"] = Self.deviceId
        }
        // 12.3: character slots are unlimited, but a cloud save is one record
        // of at most 1 MB. Warn while there's still room.
        let bytes = data.values.reduce(0) { $0 + (($1 as? String)?.utf8.count ?? 0) }
        if bytes > 850_000 && !warnedSaveSize {
            warnedSaveSize = true
            Feedback.announce("Your save is close to the cloud's size limit. Delete characters you don't play any more, or the cloud backup will stop working.", after: 1)
        }
        do {
            try await db.collection("saves").document(uid).setData(data, merge: true)
            if data["full"] != nil {
                store.setItem(CloudSync.lastKey, String(Int(savedAt)))
                // Written to disk now: the app is often frozen right after.
                game?.saveNow()
            }
            lastAutoSync = Date()
            if !silent { say("✓ Synced to cloud! Your save data is backed up.", color: 0x44ff88) }
        } catch {
            if bytes > 1_000_000 {
                say("✗ Your save is too big for the cloud (\(bytes / 1000) KB of 1,000). Delete characters you don't play any more, then sync again.")
            } else if !silent { say("✗ Sync failed. Check your connection and try again.") }
        }
    }

    /// Leaving the app: send any progress now, whatever the 2-minute limit,
    /// and ask iOS for the time to finish before the app is frozen. (The end
    /// of a run often never reached the cloud, so the next launch, or another
    /// device, found two different saves and asked which to keep.)
    func syncOnLeave() {
        guard signedIn, let store = game?.store,
              CloudSync.number(store.getItem(CloudSync.dirtyKey)) > CloudSync.number(store.getItem(CloudSync.lastKey)) else { return }
        #if os(iOS) || os(visionOS)
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "dd.cloudsync") {
            UIApplication.shared.endBackgroundTask(bg); bg = .invalid
        }
        Task { @MainActor in
            await sync(silent: true)
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg); bg = .invalid }
        }
        #else
        Task { await sync(silent: true) }
        #endif
    }

    /// The silent background sync, at most every 2 minutes (initAccountSync).
    func autoSync() {
        guard signedIn, Date().timeIntervalSince(lastAutoSync) >= 120 else { return }
        if let store = game?.store,
           CloudSync.number(store.getItem(CloudSync.dirtyKey)) <= CloudSync.number(store.getItem(CloudSync.lastKey)) { return }
        lastAutoSync = Date()
        Task { await sync(silent: true) }
    }

    // MARK: Username

    /// checkUsername
    static func usernameProblem(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Enter a username." }
        if n.count < 3 { return "Username must be at least 3 characters." }
        if n.count > 20 { return "Username must be 20 characters or fewer." }
        if !n.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) {
            return "Username can only contain letters, numbers, and underscores."
        }
        return nil
    }

    /// submitUsername / saveUsername: reserved in "usernames" so no one else takes it.
    func setUsername(_ raw: String) async {
        let name = raw.trimmingCharacters(in: .whitespaces)
        if let problem = Self.usernameProblem(name) { say(problem); return }
        guard let u = Auth.auth().currentUser else { say("Not signed in."); return }
        message = "Checking availability..."
        messageColor = 0xffaa44
        do {
            let ref = db.collection("usernames").document(name.lowercased())
            let snap = try await ref.getDocument()
            if snap.exists, let owner = snap.data()?["uid"] as? String, owner != u.uid {
                say("That username is already taken. Try another.")
                return
            }
            try await ref.setData(["uid": u.uid, "username": name])
            try await db.collection("users").document(u.uid)
                .setData(["username": name, "email": u.email ?? "", "updatedAt": Self.now], merge: true)
            game?.store.setItem("dd_username", name)
            objectWillChange.send()
            say("Username set to \(name). You are now on the leaderboard.", color: 0x44ff88)
        } catch {
            say((error as NSError).code == FirestoreErrorCode.Code.permissionDenied.rawValue
                ? "Permission denied by server. Try again later." : "Could not save the username. Check your connection.")
        }
    }

    // MARK: Leaderboard

    struct LeaderboardEntry: Identifiable {
        let id: String
        let username: String
        let score: Int
    }

    /// uploadToLeaderboard: "leaderboard/{uid}" with the High Score total.
    func uploadScore() async -> Bool {
        guard let u = Auth.auth().currentUser, let store = game?.store else {
            Feedback.announce("You need to sign in to upload your score. Go to Settings then Account.")
            return false
        }
        let total = HighScore.load(store).total
        guard total > 0 else {
            Feedback.announce("No score to upload yet. Play some runs first.")
            return false
        }
        Feedback.announce("Uploading your score of \(total.formatted()) points to the leaderboard.")
        do {
            try await db.collection("leaderboard").document(u.uid).setData([
                "uid": u.uid, "username": "\(displayName) · \(title)", "score": total,
                "tag": title, "updatedAt": Self.now,
            ])
            Feedback.announce("Score uploaded successfully. Check the leaderboard to see your rank.")
            return true
        } catch {
            Feedback.announce("Upload failed. Check your connection.")
            return false
        }
    }

    /// loadGlobalLeaderboard: the top 20. Nil when it couldn't load.
    func leaderboard() async -> [LeaderboardEntry]? {
        do {
            let snap = try await db.collection("leaderboard").order(by: "score", descending: true).limit(to: 20).getDocuments()
            let list = snap.documents.map { d in
                let data = d.data()
                return LeaderboardEntry(id: (data["uid"] as? String) ?? d.documentID,
                                        username: (data["username"] as? String) ?? "Anonymous",
                                        score: (data["score"] as? NSNumber)?.intValue ?? 0)
            }
            checkWeeklyReward(list)
            return list
        } catch {
            return nil
        }
    }

    /// checkWeeklyReward: number 1 gets 3 Mystery Coins once a week.
    private func checkWeeklyReward(_ list: [LeaderboardEntry]) {
        guard let me = user?.uid, list.first?.id == me, let game else { return }
        let key = "weekly_reward_" + Self.weekKey()
        guard game.store.getItem(key) == nil else { return }
        game.store.setItem(key, "1")
        game.addMysteryCoins(3)
        Feedback.announce("Weekly Champion! You are number 1 on the global leaderboard this week. 3 Mystery Coins have been added to your account.")
    }

    /// getWeekKey: "2026_w44".
    static func weekKey(_ now: Date = Date()) -> String {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let startDay = cal.component(.weekday, from: start) - 1
        let week = Int(((now.timeIntervalSince(start) / 86400 + Double(startDay) + 1) / 7).rounded(.up))
        return "\(year)_w\(week)"
    }

    // MARK: Inbox

    struct InboxMessage: Identifiable {
        let id: String
        let from: String
        let message: String
        let coins: Int
        let claimed: Bool
        let createdAt: Double
    }

    /// loadInbox: the newest 20 messages from the developer. Nil when it couldn't load.
    func inbox() async -> [InboxMessage]? {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snap = try await db.collection("users").document(uid).collection("inbox")
                .order(by: "createdAt", descending: true).limit(to: 20).getDocuments()
            return snap.documents.map { d in
                let x = d.data()
                return InboxMessage(id: d.documentID, from: (x["from"] as? String) ?? "Dungeon Descent",
                                    message: (x["message"] as? String) ?? "",
                                    coins: (x["coins"] as? NSNumber)?.intValue ?? 0,
                                    claimed: (x["claimed"] as? Bool) ?? false,
                                    createdAt: (x["createdAt"] as? NSNumber)?.doubleValue ?? 0)
            }
        } catch {
            return nil
        }
    }

    /// claimInboxMessage
    func claim(_ m: InboxMessage) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, !m.claimed else { return false }
        do {
            try await db.collection("users").document(uid).collection("inbox").document(m.id)
                .updateData(["claimed": true, "claimedAt": Self.now])
            if m.coins > 0 {
                game?.addMysteryCoins(m.coins)
                Feedback.announce("\(m.coins) Mystery Coins claimed and added to your account.")
            }
            return true
        } catch {
            Feedback.announce("Could not claim. Try again.")
            return false
        }
    }

    /// devSendCoins: Mystery Coins into a player's inbox, found by their
    /// email. Returns what to show and say.
    func devSendCoins(email: String, coins: Int, message: String) async -> (ok: Bool, text: String) {
        guard !email.isEmpty else { return (false, "Enter player email.") }
        guard coins >= 1 else { return (false, "Enter coin amount.") }
        guard let me = Auth.auth().currentUser else { return (false, "Sign in first (Settings → Account).") }
        let gift: [String: Any] = ["from": "Leo — Developer", "message": message.isEmpty ? "A gift from the developer of Dungeon Descent." : message,
                                   "coins": coins, "claimed": false, "createdAt": Self.now]
        do {
            let found = try await db.collection("users").whereField("email", isEqualTo: email).limit(to: 1).getDocuments()
            if let doc = found.documents.first {
                try await db.collection("users").document(doc.documentID).collection("inbox").addDocument(data: gift)
                let x = doc.data()
                let name = (x["username"] as? String) ?? Self.fallbackName(email: x["email"] as? String, uid: doc.documentID)
                return (true, "✓ Sent \(coins) coins to \(name)!")
            }
            guard me.email == email else { return (false, "Player not found. They may need to sign in first.") }
            try await db.collection("users").document(me.uid).collection("inbox").addDocument(data: gift)
            try await db.collection("users").document(me.uid).setData(["email": email, "updatedAt": Self.now], merge: true)
            return (true, "✓ Sent \(coins) coins to yourself!")
        } catch {
            return (false, "Could not send. \(error.localizedDescription)")
        }
    }

    // MARK: Tournament

    /// uploadTournamentScore: "tournament/{season}/scores/{uid}". The web
    /// version stored and showed the player's email; this stores the
    /// leaderboard name in that field instead, so web players see a name.
    func uploadTournament(score: Int, season: Tournament.Season) async {
        guard let u = Auth.auth().currentUser else { return }
        try? await db.collection("tournament").document(season.key).collection("scores").document(u.uid).setData([
            "uid": u.uid, "email": displayName, "score": score, "updatedAt": Self.now, "seasonName": season.name,
        ])
    }

    /// The Weekly Ladder: one score per player per week, kept with the
    /// Tournament's scores (the same Firestore rules cover it).
    func uploadLadder(score: Int, season: String, name: String) async {
        guard let u = Auth.auth().currentUser else { return }
        try? await db.collection("tournament").document(season).collection("scores").document(u.uid).setData([
            "uid": u.uid, "email": displayName, "score": score, "updatedAt": Self.now, "seasonName": season, "character": name,
        ])
    }

    func ladder(_ season: String) async -> [LeaderboardEntry] {
        guard let snap = try? await db.collection("tournament").document(season).collection("scores")
            .order(by: "score", descending: true).limit(to: 10).getDocuments() else { return [] }
        return snap.documents.map { d in
            let x = d.data()
            var name = (x["email"] as? String) ?? "Anonymous"
            if name.contains("@") { name = Self.fallbackName(email: name, uid: (x["uid"] as? String) ?? d.documentID) }
            return LeaderboardEntry(id: (x["uid"] as? String) ?? d.documentID, username: name,
                                    score: (x["score"] as? NSNumber)?.intValue ?? 0)
        }
    }

    /// Endless Descent rivals: the 50 best floors, without your own.
    func afkRivals() async -> [AFKRivals.Rival] {
        guard let snap = try? await db.collection("tournament").document(AFKRivals.season).collection("scores")
            .order(by: "score", descending: true).limit(to: 51).getDocuments() else { return [] }
        let me = Auth.auth().currentUser?.uid
        return snap.documents.compactMap { d in
            let x = d.data()
            guard d.documentID != me, let floor = (x["score"] as? NSNumber)?.intValue, floor > 0 else { return nil }
            var name = (x["character"] as? String) ?? (x["email"] as? String) ?? "A rival"
            if name.contains("@") { name = Self.fallbackName(email: name, uid: d.documentID) }
            return AFKRivals.Rival(name: name, floor: floor)
        }
    }

    /// The Daily World Boss: everyone's damage today, added up (nil when the
    /// database can't be reached).
    func worldBossDamage(_ season: String) async -> Int? {
        guard let snap = try? await db.collection("tournament").document(season).collection("scores").getDocuments()
        else { return nil }
        return snap.documents.reduce(0) { $0 + ((($1.data()["score"]) as? NSNumber)?.intValue ?? 0) }
    }

    /// loadTournamentLeaderboard: the season's top 10.
    func tournamentLeaderboard(_ season: Tournament.Season) async -> [LeaderboardEntry] {
        guard let snap = try? await db.collection("tournament").document(season.key).collection("scores")
            .order(by: "score", descending: true).limit(to: 10).getDocuments() else { return [] }
        return snap.documents.map { d in
            let x = d.data()
            var name = (x["email"] as? String) ?? "Anonymous"
            // Older entries hold a real email address: show only the fallback name.
            if name.contains("@") { name = Self.fallbackName(email: name, uid: (x["uid"] as? String) ?? d.documentID) }
            return LeaderboardEntry(id: (x["uid"] as? String) ?? d.documentID, username: name,
                                    score: (x["score"] as? NSNumber)?.intValue ?? 0)
        }
    }

    // MARK: Obituary

    struct Obituary: Identifiable {
        let id: String
        let name, dungeon, killedBy: String
        let floor: Int
        let timestamp: Double
        let isLocal: Bool
    }

    /// postDeathToObituary: every death goes to the shared "deaths" list,
    /// signed in or not, like the web version.
    func postDeath(_ d: GameModel.DeathNotice) async {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        _ = try? await db.collection("deaths").addDocument(data: [
            "name": d.name.isEmpty ? "Unknown" : d.name, "cls": d.cls.isEmpty ? "Warrior" : d.cls,
            "floor": max(1, d.floor), "dungeon": d.dungeon.isEmpty ? "Unknown" : d.dungeon,
            "killedBy": d.killedBy.isEmpty ? "unknown causes" : d.killedBy,
            "kills": d.kills, "gold": d.gold, "date": f.string(from: Date()), "timestamp": Self.now,
        ])
    }

    /// 12.3: a big moment for Dungeon Descent Chat's #hall-of-legends. The
    /// chat's server checks the sign-in and writes a fixed sentence; it only
    /// posts for chat members who haven't turned it off, at most every 10 min.
    func postLegend(_ event: String, _ info: [String: Any]) async {
        guard let u = Auth.auth().currentUser, let token = try? await u.getIDToken(),
              let url = URL(string: "https://us-central1-dungeon-descent-fbaf2.cloudfunctions.net/chatPush/legend") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = info
        body["event"] = event
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// loadObituary: the 15 newest deaths worldwide. Nil when offline (the
    /// screen then shows this device's Graveyard, like the web version).
    func obituary() async -> [Obituary]? {
        do {
            let snap = try await db.collection("deaths").order(by: "timestamp", descending: true).limit(to: 15).getDocuments()
            return snap.documents.map { doc in
                let x = doc.data()
                return Obituary(id: doc.documentID, name: (x["name"] as? String) ?? "Unknown Hero",
                                dungeon: (x["dungeon"] as? String) ?? "an unknown dungeon",
                                killedBy: (x["killedBy"] as? String) ?? "unknown causes",
                                floor: (x["floor"] as? NSNumber)?.intValue ?? 1,
                                timestamp: (x["timestamp"] as? NSNumber)?.doubleValue ?? 0, isLocal: false)
            }
        } catch {
            return nil
        }
    }

    // MARK: Signing out and deleting

    func signOut() {
        do {
            try Auth.auth().signOut()
            #if canImport(GoogleSignIn)
            GIDSignIn.sharedInstance.signOut()
            #endif
            user = nil
            say("Signed out successfully. You can sign back in anytime.", color: 0x44ff88)
        } catch {
            say("Sign out failed: \(error.localizedDescription)")
        }
    }

    /// _fbDeleteAccount: the cloud save, the profile and its inbox, the
    /// leaderboard entry, the reserved username, then the login itself.
    /// Saves on this device are kept.
    func deleteAccount() async {
        guard let u = Auth.auth().currentUser else { say("Not signed in."); return }
        message = "⏳ Deleting account..."
        messageColor = 0xffaa44
        let uid = u.uid
        let profile = try? await db.collection("users").document(uid).getDocument().data()
        try? await db.collection("saves").document(uid).delete()
        if let inbox = try? await db.collection("users").document(uid).collection("inbox").getDocuments() {
            for d in inbox.documents { try? await d.reference.delete() }
        }
        try? await db.collection("users").document(uid).delete()
        try? await db.collection("leaderboard").document(uid).delete()
        if let name = profile?["username"] as? String {
            try? await db.collection("usernames").document(name.lowercased()).delete()
        }
        do {
            try await u.delete()
            user = nil
            say("Account and cloud save deleted. Saves on this device are untouched.", color: 0x44ff88)
        } catch {
            say("Could not delete. Try signing in again first.")
        }
    }

    // MARK: Helpers

    enum CloudError: LocalizedError {
        case noToken
        var errorDescription: String? { "No sign-in token was returned." }
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

extension CloudAccount: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            appleContinuation?.resume(returning: authorization)
            appleContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            appleContinuation?.resume(throwing: error)
            appleContinuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            CloudAccount.topViewController()?.view.window ?? ASPresentationAnchor()
        }
    }
}
