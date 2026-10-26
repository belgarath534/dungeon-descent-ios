import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

/// The account system (ACCOUNT SYSTEM — BETA): the same Firebase project,
/// sign-in methods and cloud save as the web version, so one account and
/// one save work in both. The cloud save is the "saves/{uid}" document in
/// the "dungeon-descent" Firestore database, holding the same save keys as
/// strings, exactly like syncToCloud() writes them.
@MainActor
final class CloudAccount: NSObject, ObservableObject {
    static let shared = CloudAccount()

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
        guard authHandle == nil else { return }
        user = Auth.auth().currentUser
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
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
        let name = game?.store.getItem("dd_username") ?? u.displayName ?? "Adventurer"
        return u.email.map { "\(name) (\($0))" } ?? name
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
        guard let game else { return }
        do {
            guard let cloud = try await cloudSave(), cloud["chars"] != nil else {
                await sync(silent: false)
                return
            }
            if game.characters.isEmpty {
                restore(cloud)
            } else {
                choosingSave = true
                Feedback.announce("This device and your cloud account both have a save. Choose which one to keep.")
            }
        } catch {
            say("Load failed. Check your connection.")
        }
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

    private func restore(_ cloud: [String: Any]) {
        var data: [String: String] = [:]
        for (field, key) in Self.fields {
            if let s = cloud[field] as? String, !s.isEmpty { data[key] = s }
        }
        game?.importWebSave(data)
        game?.saveNow()
        say("Load complete. Your save data has been restored from the cloud.", color: 0x44ff88)
    }

    /// syncToCloud. Silent syncs don't speak (the web version's auto-sync).
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
        do {
            try await db.collection("saves").document(uid).setData(data, merge: true)
            lastAutoSync = Date()
            if !silent { say("✓ Synced to cloud! Your save data is backed up.", color: 0x44ff88) }
        } catch {
            if !silent { say("✗ Sync failed. Check your connection and try again.") }
        }
    }

    /// The silent background sync, at most every 2 minutes (initAccountSync).
    func autoSync() {
        guard signedIn, Date().timeIntervalSince(lastAutoSync) >= 120 else { return }
        lastAutoSync = Date()
        Task { await sync(silent: true) }
    }

    // MARK: Signing out and deleting

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
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
