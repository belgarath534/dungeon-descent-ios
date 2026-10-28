import SwiftUI
import UIKit
import UserNotifications
import FirebaseAuth
import DungeonCore

// MARK: - Notifications

/// scheduleAllNotifications: the game's reminders, as local notifications.
/// Preferences live in "dd_notif_prefs" like the web version.
@MainActor
enum GameNotifications {
    static let prefs: [(key: String, name: String, desc: String, on: Bool)] = [
        ("daily", "Daily Dungeon Reset", "Notified at midnight when the daily dungeon resets.", true),
        ("streak", "Streak Reminder", "Reminded at 7PM to claim your daily reward before midnight.", true),
        ("night", "Night Mode", "Notified at 8PM when night mode activates (+50% gold).", true),
        ("morning", "Morning Reminder", "A morning nudge at 9AM to start your descent.", false),
        ("void", "Void Reaper Warning", "Warned when the Void Reaper is about to expire.", true),
        ("comeback", "Comeback Reminder", "Reminded if you haven't played in 48 hours.", true),
        ("events", "Seasonal Events", "Halloween, Christmas, July 4th, Brazil Day, Valentine's, and more.", true),
        ("ambush", "Ambush Day", "Warned when Ambush Day begins (4x per year).", true),
        ("friday13", "Friday the 13th", "Notified when Friday the 13th arrives.", true),
        ("xpweekend", "XP Weekend", "Notified every Saturday — double XP all weekend.", true),
        ("voidweek", "Void Week", "Notified every Monday — double gold, stronger enemies.", true),
        ("bloodmoon", "Blood Moon", "Notified on the 1st of each month — higher risk, higher reward.", true),
        ("architect", "Architect Week", "Notified on the 8th of each month — bonus XP and unique encounters.", true),
    ]

    static func load(_ store: GameStore) -> [String: Bool] {
        var out = Dictionary(uniqueKeysWithValues: prefs.map { ($0.key, $0.on) })
        if let s = store.getItem("dd_notif_prefs"), let d = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for (k, v) in o { if let n = v as? NSNumber { out[k] = n.intValue != 0 } }
        }
        return out
    }

    static func save(_ p: [String: Bool], _ store: GameStore) {
        let o = p.mapValues { $0 ? 1 : 0 }
        if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) { store.setItem("dd_notif_prefs", s) }
    }

    /// Asks for permission when asked to (Save & Apply); otherwise only
    /// refreshes what's scheduled if permission was already given.
    static func apply(_ store: GameStore, ask: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if !allowed && ask && settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        guard allowed else { return false }
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("dd-") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        let p = load(store)
        func add(_ id: String, _ title: String, _ body: String, _ trigger: UNNotificationTrigger) {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            center.add(UNNotificationRequest(identifier: "dd-" + id, content: c, trigger: trigger))
        }
        func daily(_ h: Int, _ m: Int) -> UNNotificationTrigger {
            UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: h, minute: m), repeats: true)
        }
        func once(_ date: Date) -> UNNotificationTrigger? {
            let t = date.timeIntervalSinceNow
            return t > 60 ? UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false) : nil
        }
        /// The next time a month and day comes round, at an hour.
        func next(_ month: Int, _ day: Int, _ hour: Int) -> UNNotificationTrigger {
            UNCalendarNotificationTrigger(dateMatching: DateComponents(month: month, day: day, hour: hour), repeats: true)
        }
        if p["daily"] == true { add("daily", "📅 A New Dungeon Awaits", "The dungeon has reset. A new challenge descends into the dark.", daily(0, 1)) }
        if p["streak"] == true { add("streak", "🔥 Your Streak Is Waiting", "Claim your daily descent before midnight or lose your streak.", daily(19, 0)) }
        if p["night"] == true { add("night", "🌙 Night Mode Is Active", "+50% gold and cheaper shop prices. The dark rewards the bold.", daily(20, 0)) }
        if p["morning"] == true { add("morning", "⚔ The Dungeon Awaits", "A new day. New enemies. New loot. Descend.", daily(9, 0)) }
        // Two hours before the awake Void Reaper's window closes. (The web
        // version fired 14 hours after you opened the app, awake or not.)
        if p["void"] == true, let s = VoidReaperLive.shared.state, s.isAwake(now: Date().timeIntervalSince1970 * 1000),
           let t = once(Date(timeIntervalSince1970: (s.awakenedAt + 22 * 3_600_000) / 1000)) {
            add("void", "🌑 The Void Reaper Stirs", "Two hours remain before the dungeon suffers. Defeat it or face consequences.", t)
        }
        if p["comeback"] == true, let t = once(Date().addingTimeInterval(48 * 3600)) {
            add("comeback", "⚔ The Dungeon Misses You", "Your streak is at risk. The darkness grows without a hero.", t)
        }
        if p["events"] == true {
            add("halloween", "🎃 The Dungeon Grows Darker", "Halloween has begun. Something ancient stirs in the crypt.", next(10, 25, 9))
            add("christmas", "🎄 A Cursed Gift Awaits", "Christmas descends on the dungeon. Festive enemies and rewards await.", next(12, 20, 9))
            add("july4", "🎆 The Redcoats Invade", "76% bonus gold and XP all week. The Fourth of July event has begun.", next(7, 1, 9))
            add("cinco", "🌮 El Taco Blade Awaits", "Cinco de Mayo is here. One day only — +50% XP and the El Taco Blade in the Blacksmith.", next(5, 5, 9))
            add("brazil", "🇧🇷 Brasil Independente", "Brazil Independence Day. The dungeon flies the green and gold. Bonus gold and XP today.", next(9, 7, 9))
            add("valentines", "💘 The Heartbreaker Stirs", "Valentine's Day event. Love is a curse. The Heartbreaker enemy has entered the dungeon.", next(2, 13, 9))
            add("stpatricks", "☘ The Luck o' the Dungeon", "St. Patrick's Day. Extra gold drops and Lucky Potion available in the shop.", next(3, 14, 9))
            add("birthday", "🎂 The Dungeon Celebrates", "It's the creator's birthday. A special gift awaits in the dungeon today.", next(3, 23, 9))
        }
        if p["ambush"] == true {
            for m in [1, 4, 7, 10] {
                add("ambush-\(m)", "⚔ Ambush Day Has Begun", "Every battle today is a multi-enemy ambush. Enter at your own risk.", next(m, 15, 8))
            }
        }
        // (The web version scheduled this one even with its switch off.)
        if p["friday13"] == true {
            let cal = Calendar.current
            var d = cal.startOfDay(for: Date().addingTimeInterval(86_400))
            for _ in 0..<400 {
                if cal.component(.day, from: d) == 13 && cal.component(.weekday, from: d) == 6,
                   let at = cal.date(bySettingHour: 8, minute: 0, second: 0, of: d), let t = once(at) {
                    add("friday13", "💀 Friday the 13th", "Cursed enemies have entered the dungeon. Danger and rare loot await.", t)
                    break
                }
                d = d.addingTimeInterval(86_400)
            }
        }
        if p["xpweekend"] == true {
            add("xpweekend", "⚡ XP Weekend Has Begun", "Double XP all weekend. The best time to level up your characters.",
                UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 8, minute: 0, weekday: 7), repeats: true))
        }
        if p["voidweek"] == true {
            add("voidweek", "🌑 Void Week Descends", "Double gold this week. But enemies are stronger. Enter at your own risk.",
                UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 8, minute: 0, weekday: 2), repeats: true))
        }
        if p["bloodmoon"] == true {
            add("bloodmoon", "🔴 The Blood Moon Rises", "Enemies hit harder this week but gold flows freely. High risk, high reward.",
                UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 1, hour: 8, minute: 0), repeats: true))
        }
        if p["architect"] == true {
            add("architect", "🏛 Architect Week Begins", "Bonus XP this week and unique encounters with The Architect.",
                UNCalendarNotificationTrigger(dateMatching: DateComponents(day: 8, hour: 8, minute: 0), repeats: true))
        }
        return true
    }
}

/// #settings-panel-notifications
struct NotificationsPanel: View {
    @EnvironmentObject var game: GameModel
    @State private var prefs: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🔔 Notifications").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text("Choose what the game can notify you about. You can change these anytime.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            ForEach(GameNotifications.prefs.indices, id: \.self) { i in
                let p = GameNotifications.prefs[i]
                if p.key == "xpweekend" {
                    Text("WEEKLY EVENTS").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim).padding(.top, 6)
                }
                let on = prefs[p.key] ?? p.on
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(Theme.cinzel(11.2)).tracking(2).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                        Text(p.desc).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    Button(on ? "On" : "Off") {
                        prefs[p.key] = !on
                        GameNotifications.save(prefs, game.store)
                        Feedback.announce("\(p.name) notifications \(on ? "disabled" : "enabled").")
                    }
                    .buttonStyle(ToggleButtonStyle(on: on))
                    .accessibilityLabel("\(p.name), currently \(on ? "on" : "off"). \(p.desc)")
                }
            }
            Button("Save & Apply Changes") {
                Task {
                    let ok = await GameNotifications.apply(game.store, ask: true)
                    Feedback.announce(ok ? "Notification preferences saved and applied."
                                         : "Notifications are turned off for Dungeon Descent. Allow them in the iPhone's Settings app, under Notifications.")
                }
            }
            .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
            .accessibilityLabel("Save and reschedule notifications")
        }
        .onAppear { prefs = GameNotifications.load(game.store) }
    }
}

// MARK: - Redeem Code and Send Feedback

/// #settings-panel-redeem
struct RedeemPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎁 Redeem Code").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text("Enter a promo code or birthday code to unlock exclusive rewards. Each code can only be redeemed once per device.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            RewardCodeBox()
        }
    }
}

/// #settings-panel-feedback: straight to the developer (the same Formspree form).
struct FeedbackPanel: View {
    @State private var kind = "Bug report"
    @State private var message = ""
    @State private var status = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("💬 Send Feedback").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text("Bug reports, feature ideas, or anything else — this goes straight to the developer. Mention what dungeon and floor you were on if it's a bug.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            Text("TYPE").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            HStack(spacing: 6) {
                ForEach(["Bug report", "Feature suggestion", "Something else"], id: \.self) { k in
                    Button(k) { kind = k; Feedback.announce("\(k) selected.") }
                        .buttonStyle(ToggleButtonStyle(on: kind == k))
                        .accessibilityAddTraits(kind == k ? .isSelected : [])
                }
            }
            Text("MESSAGE").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            TextField("", text: $message, prompt: Text("What happened, or what you'd like to see...").foregroundColor(Theme.textDim), axis: .vertical)
                .lineLimit(5...10)
                .font(Theme.crimson(15)).foregroundStyle(Theme.textPrimary)
                .padding(10).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                .accessibilityLabel("Feedback message")
            Button(sending ? "Sending..." : "📨 Send") { send() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .disabled(sending)
                .accessibilityLabel("Send feedback")
            if !status.isEmpty {
                Text(status).font(Theme.cinzel(11)).foregroundStyle(status.hasPrefix("✅") ? Color(hex: 0x44ff88) : Color(hex: 0xff4444))
            }
        }
    }

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status = "Please write a message first."
            Feedback.announce(status)
            return
        }
        sending = true
        let email = Auth.auth().currentUser?.email ?? "no-reply@dungen-descent.org"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let body: [String: String] = ["type": kind, "message": text, "email": email, "platform": "ios-swift",
                                      "gameVersion": version, "_replyto": email]
        Task {
            var req = URLRequest(url: URL(string: "https://formspree.io/f/mkjnkenn")!)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            let ok = ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            sending = false
            if ok { message = "" }
            status = ok ? "✅ Sent. Thank you!" : "Could not send. Check your connection and try again."
            Feedback.announce(ok ? "Feedback sent. Thank you!" : "Could not send feedback. Check your connection and try again.")
        }
    }
}

// MARK: - Hide Menu Items

/// MENU_TOGGLE_ITEMS: which main menu buttons show ("dd_menu_prefs", by the
/// web version's button ids).
enum MenuPrefs {
    static let items: [(id: String, entry: String, label: String, icon: String)] = [
        ("menu-btn-raid", "raid", "Daily Raid", "⚔"), ("menu-btn-bossrush", "bossrush", "Boss Rush", "👑"),
        ("tournament-menu-btn", "tournament", "Tournament", "🏆"), ("menu-btn-afk", "afk", "Endless Descent", "⬇"),
        ("menu-btn-void", "void", "Void Mode", "🌑"), ("vr-menu-btn", "voidreaper", "Void Reaper", "🌑"),
        ("menu-btn-spire", "spire", "The Spire", "🗼"), ("menu-btn-siege", "siege", "The Siege", "🏰"),
        ("menu-btn-challenges", "challenges", "Challenges", "🔥"), ("menu-btn-events", "events", "Events", "✦"),
        ("menu-btn-highscore", "highscore", "High Score", "📊"), ("menu-btn-chronicles", "chronicles", "Chronicles", "📚"),
        ("menu-btn-graveyard", "graveyard", "The Graveyard", "⚰️"), ("menu-btn-obituary", "obituary", "Obituary", "☠️"),
        ("menu-btn-bounty", "bounty", "Bounty Board", "📋"), ("menu-btn-blacksmith", "blacksmith", "Blacksmith", "⚒"),
        ("menu-btn-mine", "mine", "The Mine", "⛏"),
    ]

    static func hidden(_ store: GameStore) -> Set<String> {
        guard let s = store.getItem("dd_menu_prefs"), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return Set(items.filter { (o[$0.id] as? Bool) == false }.map(\.entry))
    }

    static func set(_ webID: String, shown: Bool, _ store: GameStore) {
        var o: [String: Any] = [:]
        if let s = store.getItem("dd_menu_prefs"), let d = s.data(using: .utf8),
           let old = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { o = old }
        o[webID] = shown
        if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) { store.setItem("dd_menu_prefs", s) }
    }
}

/// #settings-panel-hidemenu
struct HideMenuPanel: View {
    @EnvironmentObject var game: GameModel
    @State private var hidden: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🙈 Hide Menu Items").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text("Your progress and data are never deleted. Items can be re-enabled here at any time.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            ForEach(MenuPrefs.items.indices, id: \.self) { i in
                let item = MenuPrefs.items[i]
                let on = !hidden.contains(item.entry)
                HStack {
                    Text("\(item.icon) \(item.label)").font(Theme.cinzel(12.5)).foregroundStyle(Theme.ashLight).accessibilityHidden(true)
                    Spacer()
                    Button(on ? "Show" : "Hide") {
                        MenuPrefs.set(item.id, shown: !on, game.store)
                        hidden = MenuPrefs.hidden(game.store)
                        Feedback.announce(item.label + (on ? " hidden." : " shown."))
                    }
                    .buttonStyle(ToggleButtonStyle(on: on))
                    .accessibilityLabel("\(item.label), currently \(on ? "visible" : "hidden")")
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
            }
        }
        .onAppear { hidden = MenuPrefs.hidden(game.store) }
    }
}

// MARK: - Achievement sound

/// The sound for an ordinary achievement ("dd_ach_sound"); rarer tiers keep their own.
enum AchievementSound {
    static let options = [("sfx-unlock", "Classic Unlock", "The default achievement chime"),
                          ("sfx-levelup", "Level Up Fanfare", "A triumphant level up fanfare"),
                          ("sfx-victory", "Victory Chime", "The boss defeat victory sound")]
    static var current: String { UserDefaults.standard.string(forKey: "swift_ach_sound") ?? "sfx-unlock" }
    static func set(_ id: String, store: GameStore) {
        UserDefaults.standard.set(id, forKey: "swift_ach_sound")
        store.setItem("dd_ach_sound", id)
    }
}

struct AchievementSoundPicker: View {
    @EnvironmentObject var game: GameModel
    @State private var current = AchievementSound.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🏆 Achievement Sound").font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
            Text("Choose the sound that plays when you unlock an achievement. Preview each one before picking.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
            ForEach(AchievementSound.options.indices, id: \.self) { i in
                let opt = AchievementSound.options[i]
                HStack {
                    Button("▶ Preview") { Sound.sfx(opt.0); Feedback.announce("Previewing \(opt.1).") }
                        .buttonStyle(ToggleButtonStyle(on: false))
                        .accessibilityLabel("Preview \(opt.1)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opt.1).font(Theme.cinzel(11.5)).foregroundStyle(Theme.ashLight)
                        Text(opt.2).font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim)
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    Button(current == opt.0 ? "✅ Selected" : "Select") {
                        AchievementSound.set(opt.0, store: game.store)
                        current = opt.0
                        Sound.sfx(opt.0)
                        Feedback.announce("\(opt.1) selected as achievement sound.")
                    }
                    .buttonStyle(ToggleButtonStyle(on: current == opt.0))
                    .accessibilityLabel(current == opt.0 ? "\(opt.1), selected" : "Select \(opt.1) as achievement sound")
                }
            }
        }
        .padding(.vertical, 12)
        .onAppear {
            if let saved = game.store.getItem("dd_ach_sound"), AchievementSound.options.contains(where: { $0.0 == saved }) {
                UserDefaults.standard.set(saved, forKey: "swift_ach_sound")
                current = saved
            }
        }
    }
}

// MARK: - Save codes

/// exportSaveCode / importSaveCode: the whole save as a "DD-v96-" code (the
/// same format as the web version, so codes work both ways).
struct SaveCodeBox: View {
    @EnvironmentObject var game: GameModel
    @State private var code = ""
    @State private var paste = ""
    @State private var result = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export Save Code").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Theme.goldDim)
            Text("Generate a code containing all your save data. Copy it to back up or transfer to another device.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            Button("📋 Copy Code") { export() }.buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Export save code and copy it")
            Text("Import Save Code").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Theme.goldDim).padding(.top, 6)
            Text("Paste a save code from this game or the web version. It replaces your current save.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            TextField("", text: $paste, prompt: Text("Paste your save code here...").foregroundColor(Theme.textDim))
                .font(Theme.crimson(14)).foregroundStyle(Theme.textPrimary)
                .padding(10).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                .accessibilityLabel("Save code to import")
            HStack {
                Button("📥 Paste") { paste = UIPasteboard.general.string ?? "" ; Feedback.announce(paste.isEmpty ? "Nothing to paste." : "Code pasted.") }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Paste save code from the clipboard")
                Button("⬆ Import") { importCode() }.buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Import save code")
            }
            if !result.isEmpty {
                Text(result).font(Theme.cinzel(11)).foregroundStyle(result.hasPrefix("✅") ? Color(hex: 0x44cc44) : Color(hex: 0xff4444))
            }
        }
    }

    private func export() {
        game.saveNow()
        let data = game.snapshot().filter { $0.key.hasPrefix("dd_") }
        guard !data.isEmpty, let json = try? JSONSerialization.data(withJSONObject: data) else {
            Feedback.announce("No save data found. Play the game first to generate save data.")
            return
        }
        code = "DD-v96-" + json.base64EncodedString()
        UIPasteboard.general.string = code
        result = "✅ Copied to clipboard! \(data.count) data entries."
        Feedback.announce("Save code generated and copied. \(data.count) data entries exported.")
    }

    private func importCode() {
        let c = paste.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { result = "No code entered."; Feedback.announce("Please paste a save code first."); return }
        var json: Data?
        if c.hasPrefix("DD-v96-") {
            json = Data(base64Encoded: String(c.dropFirst(7)))
        } else if c.hasPrefix("DD2-"), let d = Data(base64Encoded: String(c.dropFirst(4))), let s = String(data: d, encoding: .utf8) {
            json = s.replacingOccurrences(of: "\"~", with: "\"dd_").data(using: .utf8)
        }
        guard let json, let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            result = "Invalid code."
            Feedback.announce("Invalid save code. Make sure you copied the full code.")
            return
        }
        let data = o.compactMapValues { $0 as? String }.filter { $0.key.hasPrefix("dd_") }
        game.importWebSave(data, keepSwiftRuns: true)
        paste = ""
        result = "✅ Save restored! \(data.count) entries loaded."
        Feedback.announce("Save restored! \(data.count) entries loaded.")
    }
}
