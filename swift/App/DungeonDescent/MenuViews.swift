import SwiftUI
import DungeonCore

/// The main menu, laid out like the web version's #screen-menu: same
/// order, same text and the same VoiceOver labels. Modes that aren't in the
/// Swift version yet stay in the list and say so when chosen.
struct MainMenuView: View {
    /// The Command Center's claim daily: open the reward when the menu shows.
    static var openDailyOnAppear = false
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @Environment(\.openURL) private var openURL
    @StateObject private var webImport = WebImportFlow()
    @State private var trophies = 0
    @State private var familiar = ""
    @State private var quitting = false
    @State private var toast: String?
    @State private var daily: DailyDescent.Status?
    @State private var dailyOpen = false
    @State private var familiarOpen = false
    @State private var trophiesOpen = false
    @State private var birthdayOpen = false
    @State private var whatsNewOpen = false
    @ObservedObject private var reaper = VoidReaperLive.shared

    enum Action {
        case go(Router.Screen)
        case url(String)
        case quit
        case notYet
    }

    struct Entry: Identifiable {
        let id: String
        let text: String
        let label: String
        var color: Color? = nil
        var border: Color? = nil
        var beta = false
        var action: Action = .notYet
        var separatorBefore = false
    }

    static let purple = Color(hex: 0xcc88ff), purpleBorder = Color(hex: 0xaa66ff)

    static let entries: [Entry] = [
        Entry(id: "multiplayer", text: "⚔️👥 Multiplayer", label: "PVP Arena, fight another player in real time turn based combat",
              color: Color(hex: 0x88aaff), border: Color(hex: 0x4466ff), beta: true, action: .go(.multiplayer)),
        Entry(id: "hideseek", text: "🕯️ Hide and Seek", label: "Hide and Seek, something is chasing you, find the way out",
              color: Color(hex: 0xbb88ee), border: Color(hex: 0x663399), beta: true, action: .go(.hideseek)),
        Entry(id: "leo", text: "🎬 Leo Audio Gaming", label: "Visit Leo Audio Gaming on YouTube, opens in new tab",
              color: Color(hex: 0xff4444), border: Color(hex: 0xff0000),
              action: .url("https://www.youtube.com/@leo09393"), separatorBefore: true),
        Entry(id: "bestiary", text: "📖 Bestiary", label: "Bestiary, view all enemies you have encountered", action: .go(.bestiary)),
        Entry(id: "quests", text: "📜 Quests", label: "Quests and achievements", action: .go(.quests)),
        Entry(id: "coinshop", text: "🪙 Coin Shop", label: "Mystery Coin Shop, spend your Mystery Coins on permanent upgrades", action: .go(.coinshop)),
        Entry(id: "afk", text: "⬇ Endless Descent", label: "Endless Descent, AFK mode", action: .go(.afk)),
        Entry(id: "spire", text: "🗼 The Spire", label: "The Spire, climb 1800 floors to face The Time Eater", action: .go(.spire)),
        Entry(id: "void", text: "🌑 Void Mode", label: "Void Mode, become the Void Commander and survive five waves of heroes", action: .go(.voidmode)),
        Entry(id: "command", text: "⌨️ Command Center", label: "Command Center — type or speak commands to control the game", action: .go(.commandCenter)),
        Entry(id: "spellbook", text: "📖 Spell Book", label: "Spell Book — view your learned spells", color: purple, border: purpleBorder, action: .go(.spellbook)),
        Entry(id: "arcane", text: "✨ Arcane Shop", label: "Arcane Shop — buy spell scrolls and the spell book", color: purple, border: purpleBorder, action: .go(.arcane)),
        Entry(id: "graveyard", text: "⚰️ The Graveyard", label: "The Graveyard, memorial for your fallen and deleted characters", action: .go(.graveyard)),
        Entry(id: "obituary", text: "☠️ Obituary", label: "Obituary, see recent deaths from players around the world", action: .go(.obituary)),
        Entry(id: "challenges", text: "🔥 Challenges", label: "Challenges — The Gauntlet and Daily Dungeon", action: .go(.challenges)),
        Entry(id: "blacksmith", text: "⚒ Blacksmith", label: "Blacksmith — upgrade and buy weapons using your global gold", action: .go(.blacksmith)),
        Entry(id: "mine", text: "⛏ The Mine", label: "The Mine — dig for diamonds, gun parts, and rare loot",
              color: Color(hex: 0xc8a832), border: Color(hex: 0x8b6914), action: .go(.mine)),
        Entry(id: "bossrush", text: "👑 Boss Rush", label: "Boss Rush, fight all nine bosses back to back", action: .go(.bossrush)),
        Entry(id: "tournament", text: "🏆 Tournament", label: "Tournament, compete against other players for the highest score", action: .go(.tournament)),
        Entry(id: "chronicles", text: "📚 Chronicles", label: "The Chronicles, lore and history of the dungeons", action: .go(.chronicles)),
        Entry(id: "codex", text: "📖 Codex", label: "The Codex, world lore enemy lore and artifacts unlocked through gameplay", action: .go(.codex)),
        Entry(id: "creator", text: "⚔ Enemy Creator", label: "Community Enemy Creator, build an enemy and set it loose in the dungeon", action: .go(.enemyCreator)),
        Entry(id: "chat", text: "💬 Global Chat", label: "Global Chat, talk to other players", action: .go(.chat)),
        Entry(id: "bounty", text: "📋 Bounty Board", label: "The Bounty Board — register for bounties and earn rewards", action: .go(.bounty)),
        Entry(id: "siege", text: "🏰 The Siege", label: "The Siege — defend your fortress against waves of enemies", action: .go(.siege)),
        Entry(id: "whatsnew", text: "⭐ What's New", label: "What's New, see the full patch notes for every version", action: .go(.whatsnew)),
        Entry(id: "help", text: "❓ Help", label: "Help, full game manual and guide", action: .go(.help)),
        Entry(id: "records", text: "🏛️ Hall of Records", label: "Hall of Records, view your lifetime stats and claim milestone awards", action: .go(.records)),
        Entry(id: "highscore", text: "🏆 High Score", label: "High score, view your lifetime score and rank", action: .go(.highscore)),
        Entry(id: "events", text: "🎃 Events", label: "Seasonal events, see active and upcoming events", action: .go(.events)),
        Entry(id: "credits", text: "📜 Credits", label: "Credits, see who made the game", action: .go(.credits)),
        Entry(id: "raid", text: "⚔️ Raid", label: "Raid, survive five waves of enemies for daily rewards", action: .go(.raid)),
        Entry(id: "settings", text: "⚙ Settings", label: "Settings, adjust music and sound", action: .go(.settings), separatorBefore: true),
        Entry(id: "quit", text: "🕯 Quit", label: "Quit Dungeon Descent", action: .quit),
    ]

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Settings → Gameplay → Hide Menu Items.
    private var hiddenEntries: Set<String> {
        var h = MenuPrefs.hidden(game.store)
        // toggleCommandCenter (Settings → Accessibility).
        if game.store.getItem("dd_command_center") == "off" { h.insert("command") }
        return h
    }

    var body: some View {
        ZStack {
            WebBackground()
            // #menu-logo-bg: the logo fills the page, faint, behind everything.
            Image("MenuLogo")
                .resizable()
                .scaledToFill()
                .opacity(0.18)
                .ignoresSafeArea()
                // Read from the top of the list below: as its own full-screen
                // element it came after the last button, so swiping past
                // the end jumped VoiceOver back to the top.
                .accessibilityHidden(true)
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Dungeon Descent game logo")
                        .accessibilityAddTraits(.isImage)
                    header
                    Ornament()
                    nav
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.top, 36)
                .padding(.bottom, 80)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(Theme.cinzel(12))
                        .foregroundStyle(Theme.ash)
                        .padding(12)
                        .background(Color(hex: 0x130f0a))
                        .overlay(Rectangle().stroke(Theme.borderDim))
                        .padding(.bottom, 30)
                        .accessibilityHidden(true)
                }
                .transition(.opacity)
            }
            if quitting { quitOverlay }
            if dailyOpen, let d = daily { dailyOverlay(d.next) }
            if trophiesOpen { TrophyOverlay { trophiesOpen = false } }
            if birthdayOpen { BirthdayOverlay { birthdayOpen = false } }
            if whatsNewOpen {
                WhatsNewPopup {
                    whatsNewOpen = false
                    game.store.setItem(WhatsNewPopup.seenKey, WhatsNewPopup.version)
                }
            }
            if familiarOpen {
                FamiliarOverlay { familiarOpen = false; familiar = game.familiarBadge }
            }
        }
        .onAppear {
            Sound.track("menu")
            Sound.ambient(nil)
            // showWhatsNewPopup: once after each update
            if game.store.getItem(WhatsNewPopup.seenKey) != WhatsNewPopup.version { whatsNewOpen = true }
            trophies = game.achievements.trophies
            familiar = game.familiarBadge
            daily = DailyDescent.status(game.store)
            Presence.shared.start(game.store)
            CustomSpirits.reload(game.store)
            if Self.openDailyOnAppear, let d = daily {
                Self.openDailyOnAppear = false
                if d.claimed {
                    Feedback.announce("You already claimed today's reward. Come back tomorrow for Day \(d.streak + 1).", after: 0.4)
                } else {
                    dailyOpen = true
                    Feedback.announce("Daily Descent. Day \(d.next.day) streak. Today's reward: \(d.next.name). Press Claim Reward to collect.", after: 0.4)
                }
            }
            if game.shouldOfferWebImport { webImport.check(game, quietIfEmpty: true) }
            reaper.onReward = { [weak game] gold, coins in
                guard let game else { return }
                game.wallet.addGold(gold)
                game.addMysteryCoins(coins)
                game.achievements.increment("voidReaperDefeated")
                _ = game.achievements.check()
                Sound.sfx("sfx-victory")
                Feedback.announce("The Void Reaper has fallen! You struck it this cycle: \(gold) gold and \(coins) Mystery Coins are yours.")
            }
            reaper.start(store: game.store)
        }
        .webImportAlerts(webImport, game: game)
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text("⚔ a dark descent awaits ⚔")
                .font(Theme.cinzel(10.4))
                .tracking(5.7)
                .textCase(.uppercase)
                .foregroundStyle(Theme.goldDim)
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("Dungeon\nDescent")
                .font(Theme.decorative(50, black: true, relativeTo: .largeTitle))
                .tracking(3)
                .lineSpacing(0)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.35), radius: 15)
                .shadow(color: .black.opacity(0.9), radius: 2, y: 2)
                .minimumScaleFactor(0.6)
                .accessibilityLabel("Dungeon Descent")
                .accessibilityAddTraits(.isHeader)
            Text("by Leo Productions")
                .font(Theme.cinzel(10.4))
                .tracking(2.6)
                .foregroundStyle(Color(hex: 0x666666))
                .padding(.top, 2)
                .padding(.bottom, 10)
            Link(destination: URL(string: "https://discord.gg/3FbYrQysRN")!) {
                Text("💬 Join our Discord")
                    .font(Theme.cinzel(9.6))
                    .tracking(1.9)
                    .foregroundStyle(Color(hex: 0x5865F2))
            }
            .accessibilityLabel("Join the Dungeon Descent Discord server")
            .padding(.bottom, 14)

            // #menu-streak-badge
            if let d = daily { dailyBadge(d) }
            // #menu-birthday-badge: March 23, the game's birthday.
            if Events.active() == "birthday" {
                Button("🎂 Happy Birthday, Dungeon Descent!") {
                    birthdayOpen = true
                    Feedback.announce("Birthday screen. Dungeon Descent. Born March 23 2025. Built by Leo Productions. Tap Claim Birthday Reward.", after: 0.3)
                }
                .font(Theme.decorative(11.5)).foregroundStyle(Color(hex: 0xffd700))
                .padding(.vertical, 8).padding(.horizontal, 16)
                .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x887700)))
                .shadow(color: Color(hex: 0xffd700).opacity(0.4), radius: 6)
                .padding(.vertical, 4)
                .accessibilityLabel("Happy Birthday Dungeon Descent! Tap to celebrate")
            }

            Button("🏆 \(trophies)") { openTrophies() }
                .font(Theme.cinzel(12.8, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Color(hex: 0xffdd44))
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Color(red: 10 / 255, green: 5 / 255, blue: 0).opacity(0.85))
                .overlay(Rectangle().stroke(Color(hex: 0xcc9944)))
                .shadow(color: Color(hex: 0xcc9944).opacity(0.3), radius: 6)
                .padding(.vertical, 4)
                .accessibilityLabel("Your trophies — press to view")
                .accessibilityValue("\(trophies)")
            Button(familiar) { openFamiliar() }
                .font(Theme.cinzel(12.8, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Color(hex: 0xaaddff))
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .background(Color(red: 5 / 255, green: 10 / 255, blue: 15 / 255).opacity(0.85))
                .overlay(Rectangle().stroke(Color(hex: 0x4488aa)))
                .shadow(color: Color(hex: 0x4488aa).opacity(0.3), radius: 6)
                .padding(.vertical, 4)
                .accessibilityLabel("Your familiar — press to view its bond level")
                .accessibilityValue(familiar)
            // Your wealth, near the top so it's never out of reach.
            Text("💰 \(game.gold)   💎 \(game.diamonds)   🪙 \(game.mysteryCoins)")
                .font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xffdd44))
                .padding(.vertical, 4)
                .accessibilityLabel("Your gold, \(game.gold). Diamonds, \(game.diamonds). Mystery Coins, \(game.mysteryCoins).")
            // #seasonal-currency-display
            if let cur = Events.current()?.currency {
                let n = Events.currency(cur.key, store: game.store)
                Text("\(cur.icon) \(n) \(cur.name)")
                    .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xe0c080))
                    .padding(.vertical, 4)
            }
            Text("\"Not all who enter are lost — most are.\"")
                .font(Theme.crimson(16, italic: true))
                .foregroundStyle(Theme.ash)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            // #vr-menu-banner and #vr-menu-btn
            if let b = reaper.banner {
                Text(b).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xa0a0ff))
                    .multilineTextAlignment(.center).padding(.top, 8).frame(maxWidth: 340)
                if reaper.awake && !hiddenEntries.contains("voidreaper") {
                    Button("🌑 Face The Void Reaper") { router.goTo(.voidreaper) }
                        .buttonStyle(MenuButtonStyle(color: Color(hex: 0xa0a0ff), border: Color(hex: 0x4433aa)))
                        .frame(maxWidth: 320).padding(.top, 4)
                }
            }
            // #menu-event-banner
            let lines = Events.bannerLines()
            if !lines.isEmpty {
                VStack(spacing: 4) {
                    ForEach(lines, id: \.self) { Text($0) }
                }
                .font(Theme.cinzel(11.2)).tracking(1.7).foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6).padding(.horizontal, 16)
                .frame(maxWidth: 320)
                .overlay(Rectangle().stroke(Theme.goldDim))
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var nav: some View {
        VStack(spacing: 3) {
            Button {
                router.goTo(.charlist)
            } label: {
                Text("⚔ Play ⚔")
            }
            .buttonStyle(MenuButtonStyle(primary: true))
            .accessibilityLabel("Play, choose or create your character")

            ForEach(Self.entries.filter { !hiddenEntries.contains($0.id) }) { e in
                if e.separatorBefore { MenuSeparator() }
                Button {
                    run(e)
                } label: {
                    HStack(spacing: 6) {
                        Text(e.text)
                        if e.beta { Text("BETA").font(Theme.cinzel(9.6)).opacity(0.7) }
                    }
                }
                .buttonStyle(MenuButtonStyle(color: e.color, border: e.border))
                .accessibilityLabel(e.label)
                // #menu-btn-seasonal-shop: only while an event has a shop.
                if e.id == "command", let cur = Events.current()?.currency {
                    Button { router.goTo(.seasonalshop) } label: { Text(cur.shop) }
                        .buttonStyle(MenuButtonStyle(color: Color(hex: 0xffaa44), border: Color(hex: 0xaa6600)))
                        .accessibilityLabel("Open seasonal shop, \(cur.shop)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main menu")
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("v\(version) · Release")
                .font(Theme.cinzel(9.3))
                .tracking(2.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 28)
                .accessibilityLabel("Version \(version.replacingOccurrences(of: ".", with: " point ")), Release")
            OnlineCount()
            Text("💰 \(game.gold)")
                .accessibilityLabel("Your global gold, \(game.gold)")
            Text("💎 \(game.diamonds)")
                .accessibilityLabel("Your diamonds, \(game.diamonds)")
        }
        .font(Theme.crimson())
        .foregroundStyle(Theme.textPrimary)
    }

    private var quitOverlay: some View {
        WebOverlay(danger: true) {
            OverlayTitle(text: "Abandon the Dark?", red: true)
            OverlayText(text: "The dungeon will remember your cowardice.")
            HStack(spacing: 10) {
                Button("Flee") { router.goTo(.quit) }
                    .buttonStyle(WebButtonStyle(kind: .red))
                    .accessibilityLabel("Yes quit the game")
                Button("Stay and Fight") { quitting = false }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("No stay and continue")
            }
        }
    }

    /// openTrophyOverlay
    private func openTrophies() {
        trophiesOpen = true
        Feedback.announce("Trophies. You have \(game.achievements.trophies) trophies. \(game.achievements.unlockedIDs.count) achievements unlocked.", after: 0.3)
    }

    private func openFamiliar() {
        let f = Familiar.load(game.store)
        familiarOpen = true
        Feedback.announce("\(f.displayName). Bond level \(f.level). \(f.intoLevel) of 30 toward the next level." + (f.title.isEmpty ? "" : " Title: \(f.title)."), after: 0.3)
    }

    /// Daily Descent: tap to see today's reward, or hear when the next one is.
    private func dailyBadge(_ d: DailyDescent.Status) -> some View {
        Button {
            if d.claimed {
                Feedback.announce("You already claimed today's reward. Come back tomorrow for Day \(d.streak + 1).")
            } else {
                dailyOpen = true
                Feedback.announce("Daily Descent. Day \(d.next.day) streak. Today's reward: \(d.next.name). Press Claim Reward to collect.", after: 0.4)
            }
        } label: {
            Text(d.claimed ? "🔥 Day \(d.streak) Streak ✓ Claimed" : "🔥 Day \(d.next.day) — Tap to Claim!")
                .font(Theme.cinzel(11.5))
                .foregroundStyle(Color(hex: d.claimed ? 0x668844 : 0xcc8844))
                .padding(.vertical, 6).padding(.horizontal, 16)
                .background(Color(red: 10 / 255, green: 5 / 255, blue: 0))
                .overlay(Rectangle().stroke(Color(hex: d.claimed ? 0x334422 : 0x443300)))
        }
        .padding(.vertical, 4)
        .accessibilityLabel(d.claimed ? "Daily Descent. Day \(d.streak) streak. Already claimed today. Come back tomorrow."
                                      : "Daily Descent. Day \(d.next.day) reward ready. Tap to claim.")
    }

    /// #ov-daily-descent
    private func dailyOverlay(_ r: DailyDescent.Reward) -> some View {
        WebOverlay {
            Text("DAILY DESCENT").font(Theme.cinzel(10.4)).tracking(4).foregroundStyle(Color(hex: 0x888888))
                .accessibilityHidden(true)
            OverlayTitle(text: "Today's Offering")
            Text("🔥 Day \(r.day) Streak").font(Theme.cinzel(12.8)).foregroundStyle(Color(hex: 0xcc8844))
            Text(r.icon).font(.system(size: 48)).accessibilityHidden(true)
            Text(r.name).font(Theme.decorative(16)).foregroundStyle(Color(hex: 0xe0c080))
            OverlayText(text: r.desc)
            HStack(spacing: 10) {
                ForEach(r.parts, id: \.self) { part in
                    Text(part).font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xe0c080))
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(Color(hex: 0x1a1000))
                        .overlay(Rectangle().stroke(Color(hex: 0x443300)))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rewards: " + r.parts.map { String($0.split(separator: " ", maxSplits: 1).last ?? "") }.joined(separator: ", "))
            Button("⚔ Claim Reward") { claimDaily() }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("Claim your daily reward")
            // Where today sits in this week of the cycle; a crown on day 30.
            let pos = (r.day - 1) % 7 + 1
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { i in
                    Text(i == pos && (r.day - 1) % 30 == 29 ? "👑" : "\(i)")
                        .font(Theme.cinzel(9.6))
                        .foregroundStyle(i <= pos ? Theme.gold : Color(hex: 0x444444))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(i <= pos ? Theme.gold.opacity(0.2) : Color(hex: 0x0a0a0a)))
                        .overlay(Circle().stroke(i <= pos ? Theme.gold : Color(hex: 0x333333)))
                        .shadow(color: i == pos ? Theme.gold.opacity(0.6) : .clear, radius: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly streak progress: day \(pos) of 7")
        }
    }

    private func claimDaily() {
        guard let r = DailyDescent.claim(store: game.store, wallet: game.wallet) else {
            dailyOpen = false
            return
        }
        Sound.sfx("sfx-unlock")
        dailyOpen = false
        daily = DailyDescent.status(game.store)
        Feedback.announce("Claimed! \(r.gold) gold added. \(r.bonus != nil ? "Bonus reward also added. " : "")Come back tomorrow to continue your streak.")
    }

    private func run(_ e: Entry) {
        switch e.action {
        case .go(let screen): router.goTo(screen)
        case .url(let s): if let u = URL(string: s) { openURL(u) }
        case .quit: quitting = true
        case .notYet: notYet(e.text.drop { !$0.isLetter }.description)
        }
    }

    /// A mode that isn't in the Swift version yet.
    private func notYet(_ name: String) {
        Sound.sfx("sfx-select")
        let msg = "\(name) isn't in the Swift version yet. Coming soon."
        Feedback.announce(msg)
        withAnimation { toast = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { if toast == msg { toast = nil } }
        }
    }
}

/// A volume slider VoiceOver reads as a percentage and adjusts in 10% steps.
struct VolumeSlider: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        Slider(value: $value, in: 0...1, step: 0.05) { Text(label) }
            .accessibilityLabel(label)
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(1, value + 0.1)
                case .decrement: value = max(0, value - 0.1)
                @unknown default: break
                }
            }
    }
}

/// Finding and importing the web version's save, with the questions it asks.
@MainActor
final class WebImportFlow: ObservableObject {
    @Published var checking = false
    @Published var found: [String: String]? = nil
    @Published var nothingFound = false
    private let importer = WebSaveImporter()

    func check(_ game: GameModel, quietIfEmpty: Bool) {
        guard !checking else { return }
        checking = true
        importer.read { [weak self] data in
            guard let self else { return }
            self.checking = false
            if GameModel.summarize(data).characters.isEmpty && data[StoreKey.globalGold] == nil {
                if quietIfEmpty { game.skipWebImport() } else { self.nothingFound = true }
            } else {
                self.found = data
            }
        }
    }

    func summary() -> String {
        guard let data = found else { return "" }
        let s = GameModel.summarize(data)
        let names = s.characters.map { "\($0.name) the \($0.race) \($0.cls)" }
        var text = names.isEmpty ? "No characters" : "\(names.count) character\(names.count == 1 ? "" : "s"): " + names.joined(separator: ", ")
        text += ". \(s.gold) gold, \(s.diamonds) diamonds."
        return text
    }
}

extension View {
    @MainActor
    func webImportAlerts(_ flow: WebImportFlow, game: GameModel) -> some View {
        self
            .alert("Import your web version save?", isPresented: Binding(
                get: { flow.found != nil },
                set: { if !$0 { flow.found = nil } }
            )) {
                Button("Import") {
                    if let data = flow.found {
                        game.importWebSave(data)
                        Feedback.announce("Save imported. \(game.characters.count) characters ready.")
                    }
                    flow.found = nil
                }
                Button("Not now", role: .cancel) {
                    game.skipWebImport()
                    flow.found = nil
                }
            } message: {
                Text("Found on this iPhone: \(flow.summary()) Importing replaces what's in the Swift version. You can do it later from Settings.")
            }
            .alert("No web version save found", isPresented: Binding(
                get: { flow.nothingFound },
                set: { flow.nothingFound = $0 }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There's no save from the web version of Dungeon Descent on this iPhone.")
            }
    }
}

/// #ov-familiar: your familiar's bond, its name, and which one it is.
struct FamiliarOverlay: View {
    @EnvironmentObject var game: GameModel
    let close: () -> Void
    @State private var f: Familiar.State?
    @State private var name = ""

    var body: some View {
        WebOverlay {
            HStack {
                Text("Your Familiar").font(Theme.decorative(16)).foregroundStyle(Color(hex: 0xaaddff)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("✕ Close", action: close).buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Close familiar")
            }
            if let f {
                let glow: [Double] = [0, 6, 10, 16]
                let stage = f.level >= 20 ? 3 : f.level >= 10 ? 2 : f.level >= 5 ? 1 : 0
                Text(f.kind.icon + (f.badge.isEmpty ? "" : " " + f.badge)).font(.system(size: 52))
                    .shadow(color: Color(hex: 0xffdd44).opacity(stage == 0 ? 0 : 0.9), radius: glow[stage])
                    .accessibilityHidden(true)
                Text(f.displayName.prefix(1).uppercased() + f.displayName.dropFirst()).font(Theme.cinzel(15)).foregroundStyle(Theme.ashLight)
                Text("Bond Level \(f.level)" + (f.title.isEmpty ? "" : " — \(f.title)")).font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xaaddff))
                Bar(value: Double(f.intoLevel) / 30, colors: [Color(hex: 0x4488aa), Color(hex: 0xaaddff)], track: Color(hex: 0x0a1520), height: 6)
                    .accessibilityLabel("Bond progress").accessibilityValue("\(f.intoLevel) of 30")
                Text("Bond grows from fights won, rooms searched, and dungeons cleared.").font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                Text("NAME YOUR FAMILIAR").font(Theme.cinzel(9.9)).tracking(1.5).foregroundStyle(Color(hex: 0x888888))
                HStack {
                    TextField("", text: $name, prompt: Text("Give it a name...").foregroundColor(Theme.textDim))
                        .font(Theme.cinzel(13)).foregroundStyle(Theme.textPrimary)
                        .padding(8).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                        .onChange(of: name) { name = String($0.prefix(20)) }
                        .accessibilityLabel("Familiar name")
                    Button("Save") {
                        Familiar.rename(name, store: game.store)
                        reload()
                        let n = name.trimmingCharacters(in: .whitespaces)
                        Feedback.announce(n.isEmpty ? "Familiar name cleared." : "Familiar renamed to \(n).")
                    }
                    .buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Save familiar name")
                }
                Text("CHOOSE YOUR FAMILIAR").font(Theme.cinzel(9.9)).tracking(1.5).foregroundStyle(Color(hex: 0x888888))
                ForEach(Familiar.species, id: \.id) { sp in species(sp, f) }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let s = Familiar.load(game.store)
        f = s
        name = s.name
    }

    @ViewBuilder
    private func species(_ sp: Familiar.Species, _ f: Familiar.State) -> some View {
        let active = sp.id == f.speciesId
        if Familiar.isUnlocked(sp, f, achievements: game.achievements) {
            Button {
                Familiar.choose(sp.id, store: game.store, achievements: game.achievements)
                reload()
                Feedback.announce("\(Familiar.load(game.store).displayName) is now your familiar.")
            } label: {
                HStack(spacing: 10) {
                    Text(sp.icon).font(.system(size: 20))
                    Text(sp.label + (active ? " (active)" : "")).font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xaaddff))
                    Spacer()
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(Color(hex: active ? 0x0a1520 : 0x080808))
                .overlay(Rectangle().stroke(Color(hex: active ? 0x4488aa : 0x222222)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(active ? "\(sp.label), currently active" : "Choose \(sp.label) as your familiar")
        } else {
            HStack(spacing: 10) {
                Text("🔒").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text(sp.label).font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x666666))
                    Text("Locked — " + sp.unlock).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x555555))
                }
                Spacer()
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(Color(hex: 0x080808)).overlay(Rectangle().stroke(Color(hex: 0x222222))).opacity(0.5)
            .accessibilityElement(children: .combine)
        }
    }
}

/// #ov-trophies: your trophies and every achievement you've unlocked.
struct TrophyOverlay: View {
    @EnvironmentObject var game: GameModel
    let close: () -> Void

    var body: some View {
        let ids = game.achievements.unlockedIDs
        let list = ids.compactMap { id in AchievementBook.all.first { $0.id == id } }
        WebOverlay {
            HStack {
                Text("🏆 Your Trophies").font(Theme.decorative(16)).foregroundStyle(Color(hex: 0xffdd44)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("✕ Close", action: close).buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Close trophies")
            }
            Text("\(game.achievements.trophies)").font(Theme.decorative(40)).foregroundStyle(Color(hex: 0xffdd44))
            Text("Total Trophies Earned").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
            Text("UNLOCKED ACHIEVEMENTS").font(Theme.cinzel(9.9)).tracking(1.5).foregroundStyle(Color(hex: 0x888888))
            ScrollView {
                VStack(spacing: 6) {
                    if list.isEmpty {
                        Text("No achievements yet. Start playing!").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x444444)).padding(20)
                    }
                    ForEach(list) { a in
                        HStack(spacing: 10) {
                            Text(a.icon).font(.system(size: 20)).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name).font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xcc9944))
                                Text(a.desc).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x777777))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("+\(a.trophies) 🏆").font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x887700))
                        }
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(Color(hex: 0x080808)).overlay(Rectangle().stroke(Color(hex: 0x222222)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }
}

/// #ov-birthday (openBirthdayScreen, claimBirthdayReward): 500 gold once a
/// year and the year's code (DDBD26, DDBD27 …) for the full birthday package
/// in Redeem Code. The web version only knew 2026; Swift counts the years.
struct BirthdayOverlay: View {
    @EnvironmentObject var game: GameModel
    let close: () -> Void
    @State private var showCode = false

    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var code: String { "DDBD\(year % 100)" }
    private var ordinal: String {
        let n = year - 2025
        return ["", "ONE", "TWO", "THREE", "FOUR", "FIVE"].indices.contains(n) ? ["", "ONE", "TWO", "THREE", "FOUR", "FIVE"][n] : "\(n)"
    }

    var body: some View {
        WebOverlay {
            Text("🎂").font(.system(size: 52)).accessibilityHidden(true)
            Text("YEAR \(ordinal)").font(Theme.cinzel(11)).tracking(4).foregroundStyle(Color(hex: 0xffd700))
            OverlayTitle(text: "Dungeon Descent")
            Text("Born March 23, 2025").font(Theme.cinzel(11.5)).foregroundStyle(Theme.textSecondary)
            Text("Still Descending — March 23, \(String(year))").font(Theme.cinzel(11.5)).foregroundStyle(Theme.textSecondary)
            Text("Built by Leo Productions").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
            Button("🎁 Claim Birthday Reward") { claim() }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("Claim birthday reward — 500 gold plus unlock code")
            Button("← Back to Menu") { Sound.track("menu"); close() }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Close birthday screen")
            if showCode {
                Text("YOUR BIRTHDAY CODE").font(Theme.cinzel(10)).tracking(2).foregroundStyle(Theme.goldDim)
                Text(code).font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xffd700)).textSelection(.enabled)
                OverlayText(text: "Go to Settings → Redeem Code and paste this to unlock your full birthday rewards.")
                Button("📋 Copy Code") {
                    UIPasteboard.general.string = code
                    Feedback.announce("Code copied. Go to Settings then Redeem Code and paste it.")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost))
                .accessibilityLabel("Copy birthday code to clipboard")
            }
        }
        .onAppear { Sound.track("menu-birthday") }
    }

    private var spelled: String { code.map(String.init).joined(separator: " ") }

    private func claim() {
        let key = "dd_birthday_claimed_\(year)"
        showCode = true
        if game.store.getItem(key) != nil {
            Feedback.announce("Already claimed. Here is your code again. \(spelled).")
            return
        }
        game.wallet.addGold(500)
        game.store.setItem(key, "true")
        Sound.sfx("sfx-unlock")
        Feedback.announce("Birthday reward claimed! 500 gold added. Your code is \(spelled). Go to Settings, Redeem Code, enter it for the full birthday package.")
    }
}

/// #menu-online-count. Its own view, so a player coming online redraws only
/// this line, not the whole menu (which made VoiceOver jump back to the top).
/// It stays in place even at 0 so nothing appears or disappears under focus.
struct OnlineCount: View {
    @ObservedObject private var presence = Presence.shared

    var body: some View {
        let n = presence.online
        Text(n > 0 ? "⚔ \(n) player\(n == 1 ? "" : "s") online" : " ")
            .font(Theme.cinzel(8.8)).tracking(1).foregroundStyle(Color(hex: 0x444444))
            .accessibilityLabel("\(n) players currently online")
            .accessibilityHidden(n == 0)
    }
}
