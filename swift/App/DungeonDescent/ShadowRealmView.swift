import SwiftUI
import DungeonCore

/// The Shadow Realm's screens: #screen-shadow-intro, -charselect, -combat
/// and -death.
struct ShadowRealmView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router

    enum Stage { case intro, choose, fight, dead }
    @State private var stage = Stage.intro
    @State private var pick = 0
    @State private var s: ShadowRealm.State?
    @State private var log: [String] = []
    @State private var waveCleared = false
    @State private var board: [ShadowRealm.Record] = []
    @State private var dice = SystemDice()

    private static let purple = Color(hex: 0xbb66ff), purpleBorder = Color(hex: 0x6a0dad)

    var body: some View {
        WebScreen {
            switch stage {
            case .intro: intro
            case .choose: choose
            case .fight: if let s { fight(s) }
            case .dead: dead
            }
        }
        .onAppear {
            Feedback.announce("The Shadow Realm. You were not supposed to find this. A secret mode — endless waves of shadow entities. How long can you survive? Press Enter the Shadow to continue.", after: 0.4)
        }
    }

    private func big(_ text: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.cinzel(13)).tracking(1.5).foregroundStyle(Self.purple)
                .frame(maxWidth: .infinity).padding(14)
                .background(Color(hex: 0x0d0010)).overlay(Rectangle().stroke(Self.purpleBorder, lineWidth: 2))
        }
        .accessibilityLabel(label)
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Text("🌑").font(.system(size: 56)).accessibilityHidden(true)
            Text("— classified —").font(Theme.cinzel(10)).tracking(4).foregroundStyle(Color(hex: 0x555555))
            Text("The Shadow Realm").font(Theme.decorative(24)).foregroundStyle(Self.purple).accessibilityAddTraits(.isHeader)
            Group {
                Text("You were not supposed to find this.")
                Text("This place exists between the dungeon floors — a rift where shadow entities drift endlessly, waiting for something strong enough to fight.")
                Text("There are no floors here. No exits. Only waves. They will not stop. Neither will you — until you fall.")
            }
            .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            big("⚔ Enter the Shadow", "Enter the Shadow Realm — select your character") {
                pick = 0
                stage = .choose
                Feedback.announce("Shadow Realm. Choose your champion. Swipe through your characters, then press Begin.", after: 0.3)
            }
            Button("← Retreat") { router.goTo(.menu) }.buttonStyle(MenuButtonStyle()).accessibilityLabel("Return to main menu")
        }
        .frame(maxWidth: .infinity)
    }

    private var choose: some View {
        let chars = game.characters
        return VStack(spacing: 14) {
            Text("shadow realm").font(Theme.cinzel(10)).tracking(4).textCase(.uppercase).foregroundStyle(Color(hex: 0x555555))
            Text("Choose Your Champion").font(Theme.decorative(20)).foregroundStyle(Self.purple).accessibilityAddTraits(.isHeader)
            Text("Who faces the shadow?").font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            if chars.isEmpty {
                Text("No characters found. Create one first.").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0x555555))
            } else {
                let ch = chars[min(pick, chars.count - 1)]
                let lvl = ch.persistLevel ?? 1
                HStack {
                    Button("◀") { pick = (pick - 1 + chars.count) % chars.count; sayPick() }.accessibilityLabel("Previous character")
                    VStack(spacing: 4) {
                        Text(ch.name).font(Theme.decorative(15)).foregroundStyle(Self.purple)
                        Text("Lv\(lvl) \(ch.race) \(ch.cls)").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x888888))
                        Text("\(pick + 1) / \(chars.count)").font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x555555))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(ch.name), level \(lvl) \(ch.race) \(ch.cls). Character \(pick + 1) of \(chars.count)")
                    Button("▶") { pick = (pick + 1) % chars.count; sayPick() }.accessibilityLabel("Next character")
                }
                .font(Theme.cinzel(18)).foregroundStyle(Self.purple)
                big("🌑 Begin", "Begin the Shadow Realm with selected character") { begin(ch) }
            }
            Button("← Back") { stage = .intro }.buttonStyle(MenuButtonStyle()).accessibilityLabel("Go back to intro")
        }
        .frame(maxWidth: .infinity)
    }

    private func sayPick() {
        let ch = game.characters[pick]
        Feedback.announce("\(ch.name), level \(ch.persistLevel ?? 1) \(ch.race) \(ch.cls). Character \(pick + 1) of \(game.characters.count)")
    }

    private func begin(_ ch: PlayerCharacter) {
        var st = ShadowRealm.start(ch, weapon: game.globalInventory.equippedWeapon, armor: game.globalInventory.equippedArmor)
        log = []
        let line = ShadowRealm.spawn(&st, dice: &dice)
        log.append(line)
        s = st
        waveCleared = false
        stage = .fight
        Sound.track("void-reaper")
        Feedback.announce("Entering the Shadow Realm. \(st.name). Wave 1. HP: \(st.hp). The shadows stir. " + spawnLine(st, line), after: 0.4)
    }

    private func spawnLine(_ st: ShadowRealm.State, _ line: String) -> String {
        guard let e = st.enemy else { return line }
        return line + " HP: \(e.hp). Attack: \(e.atk.lowerBound) to \(e.atk.upperBound)."
    }

    private func fight(_ st: ShadowRealm.State) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("🌑 SHADOW REALM").font(Theme.decorative(12)).foregroundStyle(Self.purple)
                    Text("\(st.name) the \(st.cls)").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x888888))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Wave \(st.wave)").font(Theme.decorative(14)).foregroundStyle(Self.purple)
                    Text("Kills: \(st.kills)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
                }
            }
            .accessibilityElement(children: .combine)
            Text("HP: \(st.hp) / \(st.maxHp)").font(Theme.cinzel(11.5)).foregroundStyle(Theme.ashLight)
            Bar(value: Double(st.hp) / Double(max(1, st.maxHp)), colors: [Color(hex: 0x6a0dad), Self.purple], track: Color(hex: 0x1a0028), height: 8)
                .accessibilityHidden(true)
            if let e = st.enemy {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(e.icon) \(e.name)\(e.isBoss ? " 👑" : "")").font(Theme.cinzel(13)).foregroundStyle(Theme.ashLight)
                    Text("HP: \(e.hp) / \(e.maxHp)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x888888))
                    Bar(value: Double(e.hp) / Double(max(1, e.maxHp)), colors: [Theme.blood, Theme.bloodBright], track: Color(hex: 0x1a0808), height: 6)
                        .accessibilityHidden(true)
                }
                .padding(12).background(Color(hex: 0x0a0010)).overlay(Rectangle().stroke(Self.purpleBorder))
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(log.suffix(8).enumerated()), id: \.offset) { _, l in
                    Text(l).font(Theme.crimson(12.5)).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Combat log")
            if waveCleared {
                big("⚔ Next Wave", "Face the next wave") { nextWave() }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Button("⚔ Attack") { act(.attack) }.buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Attack the shadow entity")
                    Button("💥 Heavy") { act(.heavy) }.buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Heavy strike — more damage, may miss")
                    Button("🛡 Defend") { act(.defend) }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Defend and counterattack")
                    Button("🧪 Potion (\(st.potions))") { potion() }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Use health potion")
                }
            }
            Button("← Retreat") { retreat() }.buttonStyle(MenuButtonStyle()).accessibilityLabel("Retreat to main menu — your score will be saved")
        }
    }

    private func act(_ a: ShadowRealm.Action) {
        guard var st = s else { return }
        let t = ShadowRealm.act(&st, a, dice: &dice)
        s = st
        log += t.lines
        Sound.sfx(t.killed ? "sfx-victory" : a == .heavy ? "sfx-heavy-hit" : "sfx-attack")
        if t.died { die(); return }
        if t.killed { waveCleared = true }
        Feedback.announce(t.lines.joined(separator: " ") + (t.killed ? "" : " Your HP: \(st.hp) of \(st.maxHp)."))
    }

    private func potion() {
        guard var st = s, let line = ShadowRealm.drink(&st) else { Feedback.announce("No potions left."); return }
        s = st
        log.append(line)
        Sound.sfx("sfx-potion")
        Feedback.announce(line)
    }

    private func nextWave() {
        guard var st = s else { return }
        st.wave += 1
        log = []
        let line = ShadowRealm.spawn(&st, dice: &dice)
        log.append(line)
        s = st
        waveCleared = false
        Feedback.success()
        Feedback.announce(spawnLine(st, line))
    }

    /// shadowRetreat: leaving mid-fight counts as falling.
    private func retreat() {
        if !waveCleared { die(); return }
        Sound.track("menu")
        router.goTo(.menu)
        Feedback.announce("You retreat from the Shadow Realm.")
    }

    private func die() {
        guard let st = s else { return }
        board = ShadowRealm.record(st, store: game.store)
        stage = .dead
        Sound.sfx("sfx-death")
        Feedback.announce("You have been consumed by the shadow. Wave \(st.wave). \(st.kills) enemies destroyed. Leaderboard updated.", after: 0.4)
    }

    private var dead: some View {
        VStack(spacing: 12) {
            Text("🌑").font(.system(size: 52)).accessibilityHidden(true)
            Text("Consumed by Shadow").font(Theme.decorative(20)).foregroundStyle(Self.purple).accessibilityAddTraits(.isHeader)
            if let st = s {
                Text("Fell on Wave \(st.wave)").font(Theme.cinzel(14)).foregroundStyle(Theme.ashLight)
                Text("\(st.kills) shadow entit\(st.kills == 1 ? "y" : "ies") destroyed.").font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("🏆 Shadow Realm — Best Runs").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xffd700)).accessibilityAddTraits(.isHeader)
                if board.isEmpty { Text("No records yet.").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0x444444)) }
                ForEach(Array(board.enumerated()), id: \.offset) { i, r in
                    let mine = r.name == s?.name && r.wave == s?.wave && r.kills == s?.kills
                    HStack {
                        Text("\(i == 0 ? "🥇" : i == 1 ? "🥈" : i == 2 ? "🥉" : "\(i + 1).") \(r.name) (\(r.cls))")
                        Spacer()
                        Text("Wave \(r.wave) · \(r.kills) kills")
                    }
                    .font(Theme.cinzel(11)).foregroundStyle(mine ? Self.purple : i == 0 ? Color(hex: 0xffd700) : Color(hex: 0x888888))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(i + 1). \(r.name), wave \(r.wave), \(r.kills) kills")
                }
            }
            .padding(12).frame(maxWidth: .infinity).background(Color(hex: 0x0a0010)).overlay(Rectangle().stroke(Self.purpleBorder))
            big("🌑 Try Again", "Enter the Shadow Realm again") { pick = 0; stage = .choose }
            Button("← Main Menu") { Sound.track("menu"); router.goTo(.menu) }.buttonStyle(MenuButtonStyle()).accessibilityLabel("Return to main menu")
        }
        .frame(maxWidth: .infinity)
    }
}
