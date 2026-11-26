import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

/// Signing in with the same account as Dungeon Descent (Apple, Google or
/// email), the same way the game does (CloudAccount.swift in the game).
@MainActor
final class Account: NSObject, ObservableObject {
    @Published private(set) var user: FirebaseAuth.User?
    @Published var message = ""
    @Published private(set) var busy = false

    private var handle: AuthStateDidChangeListenerHandle?
    private var appleContinuation: CheckedContinuation<ASAuthorization, Error>?

    /// The game's Firestore database (usernames, profiles and saves live there).
    static var db: Firestore { Firestore.firestore(database: "dungeon-descent") }

    func start() {
        guard handle == nil else { return }
        user = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, u in
            Task { @MainActor in self?.user = u }
        }
    }

    private func say(_ text: String) {
        message = text
        Speech.say(text)
    }

    // MARK: Email

    func signIn(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty else { say("Enter your email and password."); return }
        busy = true; defer { busy = false }
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
            message = ""
            Speech.say("Signed in.")
        } catch {
            say(Self.signInMessage(error))
        }
    }

    func signUp(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, !password.isEmpty else { say("Enter your email and password."); return }
        guard password.count >= 6 else { say("The password needs at least 6 characters."); return }
        busy = true; defer { busy = false }
        do {
            let r = try await Auth.auth().createUser(withEmail: email, password: password)
            try? await Self.db.collection("users").document(r.user.uid)
                .setData(["email": r.user.email ?? "", "createdAt": Date().timeIntervalSince1970 * 1000], merge: true)
            message = ""
            Speech.say("Account created.")
        } catch {
            let code = AuthErrorCode(rawValue: (error as NSError).code)
            say(code == .emailAlreadyInUse ? "That email already has an account. Sign in instead."
                : code == .invalidEmail ? "That email address isn't valid."
                : code == .weakPassword ? "That password is too weak. Use at least 6 characters."
                : code == .networkError ? "No connection. Check your internet and try again."
                : "Couldn't create the account: \(error.localizedDescription)")
        }
    }

    private static func signInMessage(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .userNotFound: return "No account with that email. Create one instead."
        case .wrongPassword, .invalidCredential: return "Wrong email or password."
        case .invalidEmail: return "That email address isn't valid."
        case .networkError: return "No connection. Check your internet and try again."
        default: return "Couldn't sign in: \(error.localizedDescription)"
        }
    }

    func resetPassword(email: String) async {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty else { say("Type your email address first."); return }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            say("A password reset email is on its way to \(email).")
        } catch {
            say("Couldn't send the reset email. Check the address.")
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        guard let clientID = FirebaseApp.app()?.options.clientID, let presenter = Self.topViewController() else {
            say("Google sign in isn't ready. Check your connection."); return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        busy = true; defer { busy = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw AccountError.noToken }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: credential)
            message = ""
            Speech.say("Signed in with Google.")
        } catch {
            if (error as? GIDSignInError)?.code == .canceled { message = ""; return }
            say("Google sign in failed: \(error.localizedDescription)")
        }
    }

    // MARK: Apple

    func signInWithApple() async {
        let nonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
        busy = true; defer { busy = false }
        do {
            let auth = try await withCheckedThrowingContinuation { (c: CheckedContinuation<ASAuthorization, Error>) in
                appleContinuation = c
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
            guard let apple = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = apple.identityToken, let token = String(data: data, encoding: .utf8) else { throw AccountError.noToken }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
            try await Auth.auth().signIn(with: credential)
            message = ""
            Speech.say("Signed in with Apple.")
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

    // MARK: Signing out and deleting

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        Speech.say("Signed out.")
    }

    /// Deletes the whole Dungeon Descent account, like the game's Delete
    /// Account: chat profile, cloud save, profile, leaderboard entry,
    /// username, then the login itself.
    func deleteWholeAccount() async -> Bool {
        guard let u = Auth.auth().currentUser else { return false }
        let uid = u.uid
        let db = Self.db
        await ChatService.deleteChatData(uid: uid)
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
            Speech.say("Your account is deleted.")
            return true
        } catch {
            say("To delete your account, sign out, sign in again, and then delete it right away. Apple and Google ask for a recent sign in.")
            return false
        }
    }

    enum AccountError: LocalizedError {
        case noToken
        var errorDescription: String? { "No sign-in token came back." }
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

extension Account: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in appleContinuation?.resume(returning: authorization); appleContinuation = nil }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in appleContinuation?.resume(throwing: error); appleContinuation = nil }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

/// VoiceOver announcements.
enum Speech {
    static func say(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
