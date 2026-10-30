import SwiftUI
import UIKit
import DungeonCore

/// #screen-void-mode: before, during, the victory with its reward code, and defeat.
struct VoidModeView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var v: VoidMode?
    @State private var log: [String] = []
    @State private var code = ""
    @State private var leveled = 0
    @State private var dice = SystemDice()
    private let purple = Color(hex: 0xaa44ff)

    var body: some View {
        WebScreen {
            Button("← Menu") { Sound.track("menu"); router.goTo(.menu) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Back to main menu")
            Text("🌑 Void Mode").font(Theme.decorative(22)).foregroundStyle(Color(hex: 0xcc88ff)).accessibilityAddTraits(.isHeader)
            if let v {
                if v.won { victory } else if v.lost { defeat(v) } else { fight(v) }
            } else {
                intro
            }
        }
    }

    // MARK: Before

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You Are The Darkness").font(Theme.cinzel(13)).foregroundStyle(purple)
            Text("Five waves of heroes are coming to defeat you. They carry torches and hope. They will find neither. As the Void Commander you have 500 HP and four abilities. Survive all five waves and your legend will be encoded into a shareable reward code — and every one of your characters goes up 3 levels.")
                .font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR ABILITIES").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim)
                Text("🌑 Void Blast — 40-70 damage. Cooldown: 2 turns.")
                Text("🛡 Shadow Shield — Reduce all damage by 60% for 2 turns. Cooldown: 3 turns.")
                Text("💀 Soul Drain — Steal 30-50 HP from target. Cooldown: 3 turns.")
                Text("⚔ Dark Strike — 20-35 damage. No cooldown.")
            }
            .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xcccccc))
            .accessibilityElement(children: .combine)
            Text("Wave 1 — A lone Warrior. Weak. Overconfident.\nWave 2 — A Paladin and an Archer. They think numbers will save them.\nWave 3 — Two Warriors and a Mage. Getting serious.\nWave 4 — Three heroes including an Elite. They have a plan.\nWave 5 — A full party of 4. One of them is legendary.")
                .font(Theme.crimson(13)).foregroundStyle(Theme.textDim)
            Button("🌑 Become The Void") { start() }
                .buttonStyle(WebButtonStyle(kind: .gold))
                .accessibilityLabel("Begin Void Mode, face five waves of heroes")
        }
    }

    private func start() {
        let fresh = VoidMode()
        v = fresh
        log = ["Wave 1: " + fresh.heroes.map(\.name).joined(separator: ", ")]
        Sound.track("void-reaper")
        Feedback.announce("Void Mode begins. Wave 1 of 5. \(fresh.hero?.name ?? "") approaches. You have 500 HP. Choose your action.")
    }

    // MARK: Fighting

    private func bar(_ value: Double, _ color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x1a0a22))
                Rectangle().fill(color).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 10).accessibilityHidden(true)
    }

    private func fight(_ v: VoidMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wave \(v.wave + 1) of 5")
                Spacer()
                Text("Turn \(v.turn)")
            }
            .font(Theme.cinzel(10.4)).foregroundStyle(purple)
            VStack(alignment: .leading, spacing: 4) {
                Text("Void Commander").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xcc88ff))
                bar(Double(v.hp) / Double(VoidMode.maxHp), purple)
                Text("\(v.hp) / \(VoidMode.maxHp) HP").font(Theme.cinzel(10)).foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Void Commander, \(v.hp) of \(VoidMode.maxHp) HP")
            if let e = v.hero, !v.waveCleared {
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.title).font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xff6644))
                    bar(Double(e.hp) / Double(e.maxHp), Color(hex: 0xcc3322))
                    Text("\(e.hp) / \(e.maxHp) HP").font(Theme.cinzel(10)).foregroundStyle(Theme.textSecondary)
                    Text(e.desc).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
                }
                .padding(10).overlay(Rectangle().stroke(Color(hex: 0x442222)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(e.title), \(e.hp) of \(e.maxHp) HP. \(e.desc)")
            }
            if v.waveCleared {
                Button("Continue → Next Wave") { next() }
                    .buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Continue to next wave")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ability(.blast, "🌑 Void Blast", v.blastCooldown, "Void Blast, 40 to 70 damage, 2 turn cooldown")
                    ability(.shield, "🛡 Shadow Shield", v.shieldCooldown, "Shadow Shield, reduce damage by 60 percent for 2 turns")
                    ability(.drain, "💀 Soul Drain", v.drainCooldown, "Soul Drain, steal 30 to 50 HP from enemy")
                    ability(.strike, "⚔ Dark Strike", 0, "Dark Strike, basic attack 20 to 35 damage")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(log.suffix(14).enumerated().reversed()), id: \.offset) { _, l in
                    Text(l).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x999999)).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10).background(Color.black.opacity(0.4))
            .accessibilityElement(children: .combine).accessibilityLabel("Void combat log")
        }
    }

    private func ability(_ a: VoidMode.Action, _ title: String, _ cd: Int, _ label: String) -> some View {
        Button(cd > 0 ? "\(title) (\(cd))" : title) { act(a) }
            .buttonStyle(WebButtonStyle(kind: a == .strike ? .ghost : .gold))
            .opacity(cd > 0 ? 0.5 : 1)
            .accessibilityLabel(cd > 0 ? "\(label). On cooldown, \(cd) turn\(cd == 1 ? "" : "s")" : label)
    }

    private func act(_ a: VoidMode.Action) {
        guard var cur = v else { return }
        let s = cur.act(a, dice: &dice)
        v = cur
        guard s.acted else {
            Feedback.announce(s.log.joined(separator: " "))
            return
        }
        log += s.log
        Sound.sfx(a == .shield ? "sfx-confirm" : a == .drain ? "sfx-potion" : "sfx-attack")
        if s.heroFell != nil { Sound.sfx("sfx-enemy-die") }
        if cur.won { win(); return }
        if cur.lost {
            Sound.sfx("sfx-hurt")
            Feedback.warning()
            Feedback.announce("The Void has fallen. \(cur.hero?.name ?? "The heroes") defeated you on wave \(cur.wave + 1). Try again.")
            return
        }
        var said = s.log.joined(separator: " ")
        if cur.waveCleared { said += " Press Continue for wave \(cur.wave + 2)." }
        Feedback.announce(said)
    }

    private func next() {
        guard var cur = v else { return }
        let line = cur.nextWave()
        v = cur
        log.append(line)
        Feedback.announce(line)
    }

    // MARK: The end

    /// voidVictory: every character +3 levels (up to 50) and a reward code.
    private func win() {
        var n = 0
        for i in game.characters.indices {
            game.updateCharacter(i) { $0.persistLevel = min(50, ($0.persistLevel ?? 1) + 3) }
            n += 1
        }
        leveled = n
        code = VoidMode.newCode(store: game.store, dice: &dice)
        game.achievements.setMax("voidConqueror", 1)
        _ = game.achievements.check()
        Sound.sfx("sfx-victory")
        Feedback.success()
        Feedback.announce("THE VOID PREVAILS! All five waves defeated. All \(n) characters leveled up by 3. Your reward code is \(code.map(String.init).joined(separator: " ")). Share it with anyone. Press Copy Code to copy it.")
    }

    private var victory: some View {
        VStack(spacing: 12) {
            Text("🌑 THE VOID PREVAILS").font(Theme.decorative(20)).foregroundStyle(Color(hex: 0xcc88ff)).accessibilityAddTraits(.isHeader)
            Text("Five waves defeated. All heroes broken. The dungeons remember this.").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 6) {
                Text("YOUR REWARD CODE").font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.textDim)
                Text(code).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0xcc88ff))
                    .accessibilityLabel("Reward code: " + code.map(String.init).joined(separator: " "))
                Text("Share this code. Anyone who enters it gets a reward (Settings → General → Enter Code).")
                    .font(Theme.crimson(12)).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
                Button("📋 Copy Code") {
                    UIPasteboard.general.string = code
                    Feedback.announce("Code copied: \(code.map(String.init).joined(separator: " ")). Share it with anyone.")
                }
                .buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Copy reward code")
            }
            .padding(14).overlay(Rectangle().stroke(purple))
            Text("\(leveled) character\(leveled == 1 ? "" : "s") leveled up by 3!").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x44ff88))
            Button("← Return to Menu") { Sound.track("menu"); router.goTo(.menu) }.buttonStyle(WebButtonStyle(kind: .ghost))
        }
    }

    private func defeat(_ cur: VoidMode) -> some View {
        VStack(spacing: 12) {
            Text("THE VOID HAS FALLEN").font(Theme.decorative(20)).foregroundStyle(Color(hex: 0xaa4444)).accessibilityAddTraits(.isHeader)
            Text("\(cur.hero?.name ?? "The heroes") ended your reign on wave \(cur.wave + 1). The Void retreats — for now.")
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            Button("↩ Try Again") { start() }.buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Try Void Mode again")
            Button("← Menu") { Sound.track("menu"); router.goTo(.menu) }.buttonStyle(WebButtonStyle(kind: .ghost))
        }
    }
}

/// Settings → General → Enter Reward Code.
struct RewardCodeBox: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var text = ""
    @State private var result = ""
    @State private var ok = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter Reward Code").font(Theme.cinzel(11.2)).tracking(2).foregroundStyle(Theme.goldDim)
            Text("Have a VOID code from someone who beat Void Mode, or a birthday code? Enter it here for a reward.")
                .font(Theme.crimson(12.5, italic: true)).foregroundStyle(Theme.textDim)
            TextField("VOID-XXXX-XXXX", text: $text)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(size: 15, design: .monospaced)).foregroundStyle(Color(hex: 0xcc88ff))
                .padding(10).background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                .accessibilityLabel("Enter reward code")
            Button("🌑 Redeem Code") { redeem() }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Redeem reward code")
            if !result.isEmpty {
                Text(result).font(Theme.cinzel(10.4)).foregroundStyle(ok ? Color(hex: 0x44ff88) : Color(hex: 0xff4444))
            }
        }
    }

    private func redeem() {
        // SHADOW opens the secret Shadow Realm.
        if text.trimmingCharacters(in: .whitespaces).uppercased() == ShadowRealm.code {
            text = ""
            result = ""
            router.goTo(.shadowRealm)
            return
        }
        let out = RewardCodes.redeem(text, store: game.store)
        if out.gold > 0 { game.wallet.addGold(out.gold) }
        if out.coins > 0 { game.addMysteryCoins(out.coins) }
        if out.sword && !game.globalInventory.items.contains(where: { $0.id == "golden-sword" }) {
            game.globalInventory.add(RewardCodes.goldenSword)
        }
        ok = out.ok
        result = out.message
        if out.ok { text = ""; Sound.sfx("sfx-unlock") } else { Sound.sfx("sfx-select") }
        Feedback.announce(out.message)
    }
}
