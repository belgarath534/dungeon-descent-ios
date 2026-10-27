import SwiftUI
import FirebaseDatabase
import DungeonCore

/// The shared Void Reaper ("void_reaper" in the Realtime Database), live.
/// Any client moves the cycle along (wake, expire, restart), every strike is
/// a transaction so two players hitting at once both count, and everyone who
/// struck in a cycle that ended in a kill collects the reward.
@MainActor
final class VoidReaperLive: ObservableObject {
    static let shared = VoidReaperLive()

    @Published private(set) var state: VoidReaper.State?
    private var handle: DatabaseHandle?
    private var store: GameStore?
    private var dice = SystemDice()
    private var seeding = false

    private var ref: DatabaseReference { Database.database().reference(withPath: "void_reaper") }
    static var now: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// initVoidReaper: listen once, from the main menu.
    func start(store: GameStore) {
        self.store = store
        guard handle == nil else { return }
        handle = ref.observe(.value) { [weak self] snap in
            let dict = snap.value as? [String: Any]
            Task { @MainActor in self?.received(dict) }
        }
    }

    private func received(_ dict: [String: Any]?) {
        guard let dict else {
            state = nil
            seedIfEmpty()
            return
        }
        let s = VoidReaper.State(dict)
        state = s
        advance(s)
        collectReward(s)
    }

    /// vrSeedState, only after checking the database really is empty.
    private func seedIfEmpty() {
        guard !seeding else { return }
        seeding = true
        ref.getData { [weak self] _, snap in
            Task { @MainActor in
                guard let self else { return }
                if snap?.value as? [String: Any] == nil {
                    var fields = VoidReaper.restartFields(now: Self.now, dice: &self.dice)
                    fields["punishmentUntil"] = 0
                    self.ref.setValue(fields)
                }
                self.seeding = false
            }
        }
    }

    /// vrCheckServerTransitions
    private func advance(_ s: VoidReaper.State) {
        let now = Self.now
        switch VoidReaper.transition(s, now: now) {
        case .none: break
        case .restart:
            ref.updateChildValues(VoidReaper.restartFields(now: now, dice: &dice))
        case .wake:
            ref.updateChildValues(["awake": true, "awakenedAt": now])
            systemChat("🌑 THE VOID REAPER HAS AWAKENED. You have \(Int(VoidReaper.windowHours)) hours. Fight together.")
        case .expire:
            var f = VoidReaper.restartFields(now: now, dice: &dice)
            f["windowExpiredAt"] = now
            f["punishmentUntil"] = now + VoidReaper.punishHours * 3_600_000
            ref.updateChildValues(f)
            systemChat("💀 The Void Reaper was not stopped. All dungeons are cursed for \(Int(VoidReaper.punishHours)) hours.")
        }
    }

    func systemChat(_ msg: String) {
        Database.database().reference(withPath: "global_chat").childByAutoId().setValue([
            "username": "⚔ VOID EVENT", "message": msg, "timestamp": Self.now, "system": true,
        ])
    }

    /// The Void Curse is on: enemies everywhere are 50% stronger.
    var cursed: Bool { state?.cursed(now: Self.now) ?? false }

    // MARK: Striking

    enum Strike { case hit(newHp: Int), killingBlow, gone, failed }

    /// vrAttack's write, as a transaction on the shared HP.
    func strike(heavy: Bool, username: String) async -> Strike {
        let dmg = VoidReaper.globalDamage(heavy: heavy)
        let cycle = state?.countdownStart ?? 0
        final class Box: @unchecked Sendable { var killed = false }
        let box = Box()
        return await withCheckedContinuation { (cont: CheckedContinuation<Strike, Never>) in
            ref.runTransactionBlock({ data in
                guard var d = data.value as? [String: Any] else { return .success(withValue: data) }
                let s = VoidReaper.State(d)
                guard s.awake, !s.defeated, s.currentHp > 0 else { return .abort() }
                let hp = max(0, s.currentHp - dmg)
                d["currentHp"] = hp
                d["killCount"] = s.killCount + 1
                d["lastKiller"] = username
                if hp == 0 {
                    d["defeated"] = true
                    d["awake"] = false
                    d["lastDefeatedCycle"] = s.countdownStart
                    box.killed = true
                } else {
                    box.killed = false
                }
                data.value = d
                return .success(withValue: data)
            }) { error, committed, snap in
                Task { @MainActor in
                    guard error == nil else { cont.resume(returning: .failed); return }
                    guard committed else { cont.resume(returning: .gone); return }
                    // You struck in this cycle: you're owed the reward if it falls.
                    self.store?.setItem("dd_vr_struck_cycle", String(Int(cycle)))
                    let hp = VoidReaper.State((snap?.value as? [String: Any]) ?? [:]).currentHp
                    cont.resume(returning: box.killed ? .killingBlow : .hit(newHp: hp))
                }
            }
        }
    }

    // MARK: Rewards

    /// Everyone who struck in the cycle that fell: 2000 gold and 50 Mystery
    /// Coins, once. (The web version paid only the killing blow, and put the
    /// gold on the character where nothing reads it.)
    var onReward: ((Int, Int) -> Void)?

    private func collectReward(_ s: VoidReaper.State) {
        guard let store, s.lastDefeatedCycle > 0,
              let struck = store.getItem("dd_vr_struck_cycle"), Double(struck) == s.lastDefeatedCycle,
              store.getItem("dd_vr_rewarded_cycle") != struck else { return }
        store.setItem("dd_vr_rewarded_cycle", struck)
        onReward?(VoidReaper.goldReward, VoidReaper.coinReward)
    }

    // MARK: The menu banner (updateVRMenuBanner)

    var banner: String? {
        guard let s = state else { return "🌑 The Void — Initializing..." }
        let now = Self.now
        if s.cursed(now: now) {
            let mins = Int(((s.punishmentUntil - now) / 60000).rounded(.up))
            return "💀 VOID CURSE ACTIVE — All enemies +50% stronger for " + (mins > 60 ? "\(Int((Double(mins) / 60).rounded(.up)))h" : "\(mins)m") + " more."
        }
        if s.defeated { return "🌑 The Void — Dormant. The cycle resets." }
        if s.isAwake(now: now) {
            return "🌑 THE VOID REAPER AWAKENS — \(s.hoursLeft(now: now))h remaining. Global HP: \(s.currentHp.formatted()) / \(s.totalHp.formatted()). Fight together!"
        }
        let date = s.targetWakeDate > 0 ? Date(timeIntervalSince1970: s.targetWakeDate / 1000).formatted(.dateTime.month(.abbreviated).day()) : "soon"
        let d = s.daysLeft(now: now)
        return "🌑 The Void Stirs — \(s.pct(now: now))% awakened. \(d) day\(d == 1 ? "" : "s") until it wakes (\(date))."
    }

    var awake: Bool { state?.isAwake(now: Self.now) ?? false }
}

/// #screen-void-reaper and its fight, victory and death.
struct VoidReaperView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @ObservedObject var live = VoidReaperLive.shared
    @State private var charIndex = 0
    @State private var fight: VoidReaper.Fight?
    @State private var log: [String] = []
    @State private var stage = 0  // 0 choose, 1 fight, 2 victory, 3 death
    @State private var busy = false
    @State private var dice = SystemDice()
    private let blue = Color(hex: 0xa0c0ff)

    var body: some View {
        WebScreen {
            Button("← Menu") { Sound.track("menu"); router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
            Text("🌑 The Void Reaper").font(Theme.decorative(22)).foregroundStyle(blue).accessibilityAddTraits(.isHeader)
            switch stage {
            case 1: if let f = fight { fightView(f) }
            case 2: victory
            case 3: death
            default: choose
            }
        }
        .onAppear {
            Sound.track("void-reaper")
            if let s = live.state {
                Feedback.announce("Global Void Reaper. HP: \(s.currentHp.formatted()) of \(s.totalHp.formatted()). \(s.hoursLeft(now: VoidReaperLive.now)) hours remaining. \(s.killCount) strikes so far. Each hit deals \(VoidReaper.playerDamage) damage. Choose a character and fight.")
            }
        }
    }

    private func bar(_ value: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x111111))
                Rectangle().fill(color).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 12).accessibilityHidden(true)
    }

    private func bossInfo(_ s: VoidReaper.State) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WORLD BOSS — ALL PLAYERS").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Color(hex: 0x555555))
            bar(Double(s.currentHp) / Double(s.totalHp), Color(hex: 0x6666ff))
            Text("\(s.currentHp.formatted()) / \(s.totalHp.formatted()) HP").font(Theme.cinzel(12)).foregroundStyle(blue)
            Text("\(s.hoursLeft(now: VoidReaperLive.now))h remaining · \(s.killCount) strikes · each strike deals \(VoidReaper.playerDamage) damage")
                .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x888888))
            if let k = s.lastKiller { Text("Last strike by: \(k)").font(Theme.crimson(12, italic: true)).foregroundStyle(Color(hex: 0xcc8844)) }
            Text("Kill reward: \(VoidReaper.goldReward.formatted()) gold + \(VoidReaper.coinReward) Mystery Coins for everyone who struck")
                .font(Theme.crimson(12)).foregroundStyle(Color(hex: 0x44cc88))
        }
        .padding(12).overlay(Rectangle().stroke(Color(hex: 0x2a1a4a)))
        .accessibilityElement(children: .combine)
    }

    // MARK: Choose

    @ViewBuilder
    private var choose: some View {
        if let s = live.state, live.awake {
            bossInfo(s)
            Text("Choose your champion").font(Theme.cinzel(12)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                Button("\(ch.name) — \(ch.cls) (Lv \(ch.persistLevel ?? 1))") {
                    charIndex = i
                    Feedback.announce("\(ch.name) selected.")
                }
                .buttonStyle(WebButtonStyle(kind: i == charIndex ? .gold : .ghost))
                .accessibilityAddTraits(i == charIndex ? .isSelected : [])
            }
            Button("🌑 Face The Void Reaper") { begin() }
                .buttonStyle(WebButtonStyle(kind: .red)).disabled(game.characters.isEmpty)
        } else {
            Text(live.banner ?? "The Void Reaper has not yet awakened.").font(Theme.crimson(15)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func begin() {
        guard game.characters.indices.contains(charIndex), let s = live.state, live.awake, s.currentHp > 0 else {
            Feedback.announce("The Void Reaper has not awakened yet.")
            return
        }
        fight = VoidReaper.Fight(game.characters[charIndex])
        log = []
        stage = 1
        Feedback.announce("You face the Void Reaper. Global HP: \(s.currentHp.formatted()). Your HP: \(fight?.hp ?? 0). Each attack deals \(VoidReaper.playerDamage) to the shared boss. Bring it down together.")
    }

    // MARK: Fight

    private func fightView(_ f: VoidReaper.Fight) -> some View {
        let s = live.state ?? VoidReaper.State()
        return VStack(alignment: .leading, spacing: 10) {
            Text(s.phase == 1 ? "Phase 1 — The Void Watches" : s.phase == 2 ? "Phase 2 — The Void Hungers" : "Final Phase — The Void Consumes")
                .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xff8844))
            bossInfo(s)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(f.name)").font(Theme.cinzel(11)).foregroundStyle(Theme.gold)
                bar(Double(f.hp) / Double(f.maxHp), Color(hex: 0x44cc44))
                Text("\(f.hp) / \(f.maxHp) HP · 🧪 \(f.potions)").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your HP \(f.hp) of \(f.maxHp). \(f.potions) potions.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                Button("⚔ Attack") { swing(.attack) }.buttonStyle(WebButtonStyle(kind: .red)).disabled(busy)
                    .accessibilityLabel("Attack, \(VoidReaper.playerDamage) damage to the shared boss")
                Button("💥 Heavy") { swing(.heavy) }.buttonStyle(WebButtonStyle(kind: .red)).disabled(busy)
                    .accessibilityLabel("Heavy strike, \(VoidReaper.globalDamage(heavy: true)) damage to the shared boss")
                Button("🛡 Defend") { swing(.defend) }.buttonStyle(WebButtonStyle(kind: .ghost)).disabled(busy)
                    .accessibilityLabel("Defend and strike back, \(VoidReaper.playerDamage) damage, take far less")
                Button("🧪 Potion (\(f.potions))") { drink() }.buttonStyle(WebButtonStyle(kind: .ghost)).disabled(busy)
                    .accessibilityLabel("Use a health potion. \(f.potions) remaining.")
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(log.prefix(12).enumerated()), id: \.offset) { _, l in
                    Text(l).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x999999))
                }
            }
            .accessibilityElement(children: .combine).accessibilityLabel("Combat log")
        }
    }

    private func swing(_ type: VoidReaper.Swing) {
        guard var f = fight, !busy else { return }
        busy = true
        let phase = live.state?.phase ?? 1
        let name = GlobalChat(store: game.store).username ?? game.characters[charIndex].name
        Sound.sfx(type == .heavy ? "sfx-heavy-hit" : "sfx-attack")
        Task {
            let result = await live.strike(heavy: type == .heavy, username: name)
            busy = false
            let dmg = VoidReaper.globalDamage(heavy: type == .heavy)
            switch result {
            case .gone:
                Feedback.announce("The Void Reaper has already fallen.")
                stage = 0
                return
            case .failed:
                Feedback.announce("Your strike didn't reach the Void. Check your connection and try again.")
                return
            case .killingBlow:
                live.systemChat("🌑 \(name) dealt the killing blow! The Void Reaper has been defeated. Everyone who struck earns \(VoidReaper.goldReward.formatted()) gold + \(VoidReaper.coinReward) Mystery Coins. The cycle resets.")
                stage = 2
                Sound.sfx("sfx-victory")
                Feedback.announce("Victory! You dealt the killing blow. The Void Reaper has been defeated! You and everyone who struck earn \(VoidReaper.goldReward.formatted()) gold and \(VoidReaper.coinReward) Mystery Coins. The dungeons are safe. For now.")
                return
            case .hit(let hp):
                let total = live.state?.totalHp ?? VoidReaper.globalHp
                let before = hp + dmg
                var lines = [type == .heavy ? "💥 Heavy strike — \(dmg) damage to the Void Reaper!" : type == .defend ? "🛡 Defended and struck back — \(dmg) damage!" : "⚔ Attack — \(dmg) damage!"]
                if before * 100 > total * 66 && hp * 100 <= total * 66 {
                    lines.append("⚡ Phase 2 — The Void Hungers!")
                    live.systemChat("⚡ Phase 2 — The Void Hungers. HP: \(hp.formatted()). Keep pushing!")
                } else if before * 100 > total * 33 && hp * 100 <= total * 33 {
                    lines.append("🔥 FINAL PHASE — The Void Consumes!")
                    live.systemChat("🔥 FINAL PHASE — The Void Consumes. \(hp.formatted()) HP remaining. Finish it!")
                }
                let back = VoidReaper.counter(&f, type, phase: phase, dice: &dice)
                lines.append(type == .defend ? "🛡 Defended — reduced to \(back) damage. Your HP: \(f.hp)." : "The Void Reaper strikes — \(back) damage! Your HP: \(f.hp).")
                fight = f
                log.insert(contentsOf: lines.reversed(), at: 0)
                if f.dead {
                    stage = 3
                    Sound.sfx("sfx-hurt")
                    Feedback.announce("You have fallen. Your damage to the global boss carries on. Return and attack again — every hit counts.")
                } else {
                    Feedback.announce(lines.joined(separator: " ") + " Global HP: \(hp.formatted()).")
                }
            }
        }
    }

    private func drink() {
        guard var f = fight else { return }
        guard let out = VoidReaper.heal(&f, phase: live.state?.phase ?? 1, dice: &dice) else {
            Feedback.announce("No potions remaining. Fight on.")
            return
        }
        fight = f
        Sound.sfx("sfx-potion")
        let lines = ["🧪 Potion used — +\(out.healed) HP. Potions left: \(f.potions).", "The Void Reaper strikes — \(out.hit) damage! Your HP: \(f.hp)."]
        log.insert(contentsOf: lines.reversed(), at: 0)
        if f.dead {
            stage = 3
            Feedback.announce("You have fallen. Return and attack again — every hit counts.")
        } else {
            Feedback.announce(lines.joined(separator: " "))
        }
    }

    private var victory: some View {
        VStack(spacing: 12) {
            Text("🌑 THE VOID REAPER IS DEFEATED").font(Theme.decorative(18)).foregroundStyle(Color(hex: 0x44ff88)).accessibilityAddTraits(.isHeader)
            Text("+\(VoidReaper.goldReward.formatted()) gold and +\(VoidReaper.coinReward) Mystery Coins for you and everyone who struck.")
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button("← Main Menu") { Sound.track("menu"); router.goTo(.menu) }.buttonStyle(WebButtonStyle(kind: .gold))
        }
    }

    private var death: some View {
        VStack(spacing: 12) {
            Text("💀 Fallen to the Void").font(Theme.decorative(18)).foregroundStyle(Color(hex: 0xaa4444)).accessibilityAddTraits(.isHeader)
            Text("Your damage to the global boss carries on. Return and attack again — every hit counts.")
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button("↩ Fight Again") { begin() }.buttonStyle(WebButtonStyle(kind: .red))
            Button("← Main Menu") { Sound.track("menu"); router.goTo(.menu) }.buttonStyle(WebButtonStyle(kind: .ghost))
        }
    }
}
