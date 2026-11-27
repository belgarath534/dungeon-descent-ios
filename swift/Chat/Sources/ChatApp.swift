import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        #if DEBUG
        ScreenshotMode.setUp()
        #endif
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in Push.shared.gotToken(token) }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // Tapping a notification opens its conversation.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let kind = info["kind"] as? String, let room = info["room"] as? String else { return }
        let mid = info["mid"] as? String
        await MainActor.run {
            Router.shared.focus = mid
            Router.shared.open = (kind, room)
        }
    }

    // Show notifications even while the app is open (with their sound).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}

@main
struct DungeonDescentChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var account = Account()
    @StateObject private var chat = ChatService()
    @StateObject private var push = Push.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(account)
                .environmentObject(chat)
                .environmentObject(push)
                .onAppear { account.start() }
                .onChange(of: account.user?.uid, initial: true) { _, uid in
                    chat.start(uid: uid)
                    if uid != nil { Task { await push.load() } }
                }
                .onChange(of: scenePhase) { _, phase in chat.presence(active: phase == .active) }
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.96, green: 0.78, blue: 0.31))
        }
    }
}

/// Sign in → username → the rules → notifications → the chat.
struct RootView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var push: Push

    var body: some View {
        Group {
            if account.user == nil {
                SignInView()
            } else if !chat.memberLoaded || !push.loaded {
                ProgressView("Loading")
            } else if chat.member == nil {
                UsernameView()
            } else if chat.member?.agreed != true {
                RulesView()
            } else if !push.chosen {
                NotificationSetupView(firstTime: true)
            } else {
                MainView()
            }
        }
        .animation(.default, value: chat.member)
    }
}
