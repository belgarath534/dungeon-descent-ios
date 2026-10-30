import SwiftUI
import DungeonCore

/// "Your Champions", the web version's #screen-charlist: the quick slider,
/// a card per character with Play, Stats, Export and Delete, Import and
/// Export, and Create New Character.
@MainActor
struct CharacterListView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @State private var sliderIndex = 0
    @State private var dialog: Dialog?
    @State private var pendingDelete: Int?
    @State private var statsFor: Int?
    /// Export: choosing a character (nil index) or showing its code.
    @State private var exporting = false
    @State private var exportFor: Int?
    @State private var importing = false
    @State private var importText = ""
    @State private var newDungeon: DungeonUnlockNews.Info?

    /// ov-confirm, reused by Play for New Game+ and resuming.
    struct Dialog {
        let title: String
        let text: String
        let ok: String
        let cancel: String
        let onOK: () -> Void
        let onCancel: () -> Void
    }

    static let classIcons = ["Warrior": "⚔️", "Monk": "🥋", "Assassin": "🗡️", "Paladin": "🛡️", "Naturalist": "🌿",
                             "Sorcerer": "🔮", "Necromancer": "💀", "Berserker": "🪓", "Bard": "🎵", "Alchemist": "⚗️",
                             "BloodKnight": "🩸", "Druid": "🌙", "Warlock": "🧿", "DeathKnight": "💀", "Ranger": "🏹",
                             "Sentinel": "🛡", "Cleric": "✝️", "Wizard": "🧙"]

    /// .diff-Wanderer and the rest: text color and border.
    static func difficultyColors(_ d: String) -> (Color, Color) {
        switch d {
        case "Wanderer": return (Color(hex: 0x7aaa7a), Color(hex: 0x3a6a3a))
        case "Ironblood": return (Color(hex: 0xc9a227), Color(hex: 0x7a6018))
        case "Condemned": return (Color(hex: 0xc0392b), Color(hex: 0x6a1a1a))
        case "Forsaken": return (Color(hex: 0x9a40a0), Color(hex: 0x5a205a))
        case "Nightmare", "Insane": return (Color(hex: 0xc060c0), Color(hex: 0x7a107a))
        default: return (Theme.ash, Theme.borderDim)
        }
    }

    var body: some View {
        ZStack {
            WebScreen {
                ScreenHeader(title: "Your Champions",
                             subtitle: "Choose a warrior to continue, or forge a new legend.") {
                    Button("☠ Death Log") { router.goTo(.deathlog) }
                        .buttonStyle(BackButtonStyle())
                        .accessibilityLabel("View death log for all characters")
                }
                if !game.characters.isEmpty { slider }
                list
                HStack(spacing: 8) {
                    if game.characters.count < 5 {
                        Button("📥 Import") { importText = ""; importing = true; Feedback.announce("Import character. Paste your export code into the text area then press Import.", after: 0.3) }
                            .buttonStyle(WebButtonStyle(kind: .ghost))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Import a character from a code")
                    }
                    Button("📤 Export") { startExport() }
                        .buttonStyle(WebButtonStyle(kind: .ghost))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Export a character as a code")
                }
                if !game.isRosterFull {
                    Button {
                        Sound.sfx("sfx-select")
                        router.goTo(.creation)
                    } label: {
                        HStack(spacing: 10) {
                            Text("✦").accessibilityHidden(true)
                            Text("Create New Character")
                            Text("✦").accessibilityHidden(true)
                        }
                        .font(Theme.cinzel(12))
                        .tracking(3)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .overlay(Rectangle().stroke(Theme.borderDim, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .accessibilityLabel("Create a new character")
                } else {
                    Text("Maximum of \(GameData.maxCharacters) characters. Delete one to create a new legend.")
                        .font(Theme.crimson(12, italic: true))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
            }
            if let d = dialog { confirmOverlay(d) }
            if let i = pendingDelete { deleteOverlay(i) }
            if exporting { exportOverlay }
            if importing { importOverlay }
            if let n = newDungeon {
                WebOverlay {
                    Text(n.icon).font(.system(size: 48)).accessibilityHidden(true)
                    Text("NEW DUNGEON UNLOCKED").font(Theme.cinzel(11)).tracking(3).foregroundStyle(Theme.goldDim)
                    OverlayTitle(text: n.dungeon)
                    OverlayText(text: n.desc)
                    Text(n.details).font(Theme.cinzel(10.4)).foregroundStyle(Theme.textSecondary)
                    Button("⚔ Descend") { newDungeon = nil }
                        .buttonStyle(WebButtonStyle(kind: .gold))
                        .accessibilityLabel("Descend into the new dungeon")
                }
            }
            if let i = statsFor, game.characters.indices.contains(i) {
                // viewCharStats: the saved run if there is one, else a fresh look at the character.
                let ch = game.characters[i]
                StatsOverlay(run: game.savedRun(for: i) ?? Run(character: ch), deaths: ch.deaths) { statsFor = nil }
            }
        }
        .onAppear {
            let n = game.characters.count
            Feedback.announce("Character list updated. \(n) character\(n != 1 ? "s" : "") available.")
            // checkDungeonUnlockPopups: one new dungeon at a time.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let news = DungeonUnlockNews.next(unlocked: game.unlockedDungeons(), store: game.store) else { return }
                newDungeon = news
                Sound.sfx("sfx-unlock")
                Feedback.success()
                Feedback.announce("New dungeon unlocked! \(news.dungeon). \(news.desc) \(news.details)")
            }
        }
    }

    // MARK: Slider

    private var slider: some View {
        let chars = game.characters
        let i = min(sliderIndex, chars.count - 1)
        let ch = chars[i]
        let sliderButton = { (text: String, color: Color, border: Color) in
            Text(text).font(Theme.cinzel(11.5)).foregroundStyle(color)
                .padding(.vertical, 8).padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color(hex: 0x1a1000))
                .overlay(Rectangle().stroke(border))
        }
        return HStack(spacing: 10) {
            Button { step(-1) } label: { sliderButton("◀", Color(hex: 0xaaaaaa), Color(hex: 0x555555)) }
                .accessibilityLabel("Previous character")
            VStack(spacing: 2) {
                Text("\(ch.name) — \(ch.cls)").font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0xe0c080))
                Text("Level \(ch.persistLevel ?? 1) · \(ch.race) · \(ch.dungeon)").font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x666666))
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Character selector")
            .accessibilityValue("\(ch.name) — \(ch.cls). Level \(ch.persistLevel ?? 1) · \(ch.race) · \(ch.dungeon)")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
            Button { step(1) } label: { sliderButton("▶", Color(hex: 0xaaaaaa), Color(hex: 0x555555)) }
                .accessibilityLabel("Next character")
            Button { play(i) } label: { sliderButton("⚔ Play", Color(hex: 0xe0c080), Color(hex: 0xe0c080)) }
                .accessibilityLabel("Play selected character")
        }
        .padding(12)
        .background(Color(hex: 0x0a0800))
        .overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
        .padding(.bottom, 12)
    }

    private func step(_ dir: Int) {
        let n = game.characters.count
        guard n > 0 else { return }
        sliderIndex = (min(sliderIndex, n - 1) + dir + n) % n
        let ch = game.characters[sliderIndex]
        Feedback.announce("\(ch.name). Level \(ch.persistLevel ?? 1) \(ch.cls). \(ch.dungeon). \(ch.difficulty). Press Play to enter the dungeon.")
    }

    // MARK: Cards

    @ViewBuilder
    private var list: some View {
        if game.characters.isEmpty {
            Text("No champions yet. Create your first character.")
                .font(Theme.cinzel(12))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(32)
                .overlay(Rectangle().stroke(Theme.borderDim))
        } else {
            VStack(spacing: 10) {
                ForEach(Array(game.characters.enumerated()), id: \.element.created) { i, ch in
                    card(ch, i)
                }
            }
            .padding(.bottom, 20)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Character list")
        }
    }

    private func card(_ ch: PlayerCharacter, _ i: Int) -> some View {
        let info = GameData.classInfo(ch.cls)
        let level = ch.persistLevel ?? 1
        let resumable = game.savedRun(for: i) != nil && !ch.completed
        let playLabel = resumable ? "▶ Resume" : ch.completed ? "✦ NG+" : "⚔ Play"
        let (diffColor, diffBorder) = Self.difficultyColors(ch.difficulty)
        let deaths = ch.deaths
        let origin: String = { if case .string(let b)? = ch.extra["backstoryName"], !b.isEmpty { return " Origin: \(b)." }; return "" }()

        return HStack(alignment: .center, spacing: 18) {
            Text(Self.classIcons[ch.cls] ?? "⚔️").font(.system(size: 29)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    FlowRow {
                        Text(ch.name).font(Theme.cinzel(16, weight: .semibold)).foregroundStyle(Theme.ashLight)
                        badge(ch.cls, Theme.goldDim, Theme.borderDim)
                        badge("Lv \(level)", Color(hex: 0xffaa00), Color(hex: 0xffaa00), bg: Color(hex: 0x1a1000))
                        if ch.runMode == "legacy" {
                            badge("🌑 Legacy · Tier \(ch.dungeonTier ?? 1)", Color(hex: 0xaa66ff), Color(hex: 0x6644aa),
                                  bg: Color(red: 100 / 255, green: 50 / 255, blue: 200 / 255).opacity(0.15))
                        }
                    }
                    .padding(.bottom, 4)
                    Text("\(ch.race) · \(ch.prof) · \(ch.dungeon)\(ch.endlessBestText)")
                        .font(Theme.crimson(12.8, italic: true))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 6)
                    HStack(spacing: 8) {
                        if ch.completed {
                            Text("✦ Completed — \(ch.dungeon)").foregroundStyle(Color(hex: 0x7aaa7a))
                        } else if ch.floor == 0 {
                            Text("Ready to descend.").italic().foregroundStyle(Theme.textDim)
                        } else {
                            Text("Floor \(ch.floor) / 10")
                        }
                        Text(ch.difficulty).font(Theme.cinzel(9.9)).foregroundStyle(diffColor)
                            .padding(.vertical, 2).padding(.horizontal, 8)
                            .overlay(Rectangle().stroke(diffBorder))
                    }
                    .font(Theme.crimson(15))
                    FlowRow {
                        pip("HP \(info.maxHp)", hi: true)
                        pip("ATK \(info.atk.lowerBound)-\(info.atk.upperBound)", hi: true)
                        pip("DEF \(info.def)", hi: false)
                        if ch.ngPlus { pip("NG+", hi: true) }
                    }
                    .padding(.top, 6)
                    if ch.spiritsEarned > 0 {
                        Text("✦ \(ch.spiritsEarned) Spirit\(ch.spiritsEarned > 1 ? "s" : "") Earned")
                            .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xc080f0))
                            .padding(.vertical, 2).padding(.horizontal, 8)
                            .overlay(Rectangle().stroke(Color(hex: 0x5a20a0)))
                            .padding(.top, 4)
                    }
                    if !deaths.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(deaths.suffix(2).enumerated()), id: \.offset) { _, d in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("☠").font(.system(size: 11)).foregroundStyle(Theme.blood)
                                    Text("Floor \(d.floor) — \(d.killedBy)").italic().foregroundStyle(Theme.textSecondary)
                                }
                                .font(Theme.crimson(11.5))
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                // The card's own label, read before its buttons.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(ch.name) the \(ch.race) \(ch.cls). Level \(level). \(ch.dungeon). \(ch.difficulty).\(origin)")
                .accessibilityAddTraits(.isStaticText)

                FlowRow(spacing: 6) {
                    charButton(playLabel, Theme.gold, Theme.goldDim) { play(i) }
                        .accessibilityLabel("\(playLabel) \(ch.name) Level \(level) \(ch.cls)")
                    charButton("📊 Stats", Theme.textSecondary, Theme.borderDim) { statsFor = i }
                        .accessibilityLabel("View stats for \(ch.name)")
                    charButton("📤 Export", Theme.textSecondary, Theme.borderDim) { showExport(i) }
                        .accessibilityLabel("Export \(ch.name)")
                    charButton("🗑 Delete", Color(hex: 0xc06060), Color(hex: 0x6a2020)) { pendingDelete = i }
                        .accessibilityLabel("Delete \(ch.name)")
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.borderGlow).frame(width: 3) }
        .accessibilityElement(children: .contain)
    }

    private func badge(_ text: String, _ color: Color, _ border: Color, bg: Color = .clear) -> some View {
        Text(text).font(Theme.cinzel(10.4)).foregroundStyle(color)
            .padding(.vertical, 1).padding(.horizontal, 7)
            .background(bg)
            .overlay(Rectangle().stroke(border))
    }

    private func pip(_ text: String, hi: Bool) -> some View {
        Text(text).font(Theme.cinzel(9.6)).tracking(0.5)
            .foregroundStyle(hi ? Theme.goldDim : Theme.textDim)
            .padding(.vertical, 2).padding(.horizontal, 8)
            .background(Theme.bgDeep)
            .overlay(Rectangle().stroke(hi ? Theme.borderGlow : Theme.borderDim))
    }

    private func charButton(_ text: String, _ color: Color, _ border: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.cinzel(10.4)).tracking(0.5).foregroundStyle(color)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .frame(minHeight: 44)
                .overlay(Rectangle().stroke(border))
        }
    }

    // MARK: Play (playChar)

    private func play(_ i: Int) {
        guard game.characters.indices.contains(i) else { return }
        Sound.sfx("sfx-confirm")
        let ch = game.characters[i]
        let id = ch.created
        if ch.completed {
            dialog = Dialog(title: "Start New Game Plus?",
                            text: "\(ch.name) has completed \(ch.dungeon). Start a New Game Plus run? Enemies will be stronger.",
                            ok: "Begin NG+", cancel: "← Back",
                            onOK: {
                                game.updateCharacter(i) { $0.startNewGamePlus() }
                                game.clearRun(for: i)
                                router.goTo(.dungeon(id, resume: false))
                            },
                            onCancel: {})
            return
        }
        if let s = game.savedRun(for: i) {
            dialog = Dialog(title: "Resume Your Run?",
                            text: "\(ch.name) was on floor \(s.floor) with \(s.hp) HP when you left. Resume exactly where you were?",
                            ok: "▶ Resume Run", cancel: "✦ Start Fresh",
                            onOK: { router.goTo(.dungeon(id, resume: true)) },
                            onCancel: {
                                game.clearRun(for: i)
                                router.goTo(.dungeon(id, resume: false))
                            })
            return
        }
        Feedback.announce("\(ch.name) descends into \(ch.dungeon). Good luck.")
        router.goTo(.dungeon(id, resume: false))
    }

    private func confirmOverlay(_ d: Dialog) -> some View {
        WebOverlay {
            OverlayTitle(text: d.title)
            OverlayText(text: d.text)
            HStack(spacing: 10) {
                Button(d.ok) { dialog = nil; d.onOK() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                Button(d.cancel) { dialog = nil; d.onCancel() }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
            }
        }
    }

    private func deleteOverlay(_ i: Int) -> some View {
        let name = game.characters.indices.contains(i) ? game.characters[i].name : ""
        return WebOverlay(danger: true) {
            OverlayTitle(text: "Delete Character?", red: true)
            OverlayText(text: "\"\(name)\" will be lost to the dark forever. This cannot be undone.")
            HStack(spacing: 10) {
                Button("Delete") {
                    pendingDelete = nil
                    game.buryCharacter(at: i)
                    Feedback.announce("\(name) has been deleted.")
                }
                .buttonStyle(WebButtonStyle(kind: .red))
                .accessibilityLabel("Yes delete this character")
                Button("Keep") { pendingDelete = nil }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Cancel keep this character")
            }
        }
    }

    // MARK: Export and import (exportCharacter, importCharacter)

    private func startExport() {
        guard !game.characters.isEmpty else { Feedback.announce("No characters to export."); return }
        if game.characters.count == 1 { showExport(0); return }
        exportFor = nil
        exporting = true
        let n = game.characters.count
        Feedback.announce("Export character. \(n) characters available. Choose one.", after: 0.3)
    }

    private func showExport(_ i: Int) {
        exportFor = i
        exporting = true
        Feedback.announce("Export code for \(game.characters[i].name). The code is shown. Copy it and use it on another device.", after: 0.3)
    }

    private var exportOverlay: some View {
        WebOverlay {
            Text("CHARACTER EXPORT CODE").font(Theme.cinzel(12.8)).tracking(3).foregroundStyle(Theme.goldDim)
            if let i = exportFor, game.characters.indices.contains(i), let code = CharacterCode.export(game.characters[i]) {
                OverlayTitle(text: game.characters[i].name)
                Text(code).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0xcccccc))
                    .lineLimit(5).truncationMode(.middle).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                    .accessibilityLabel("Export code for \(game.characters[i].name)")
                OverlayText(text: "Copy this code and paste it on another device to import this character.")
                Button("📋 Copy Code") {
                    UIPasteboard.general.string = code
                    Feedback.announce("Code copied for \(game.characters[i].name).")
                }
                .buttonStyle(WebButtonStyle(kind: .gold))
            } else {
                ForEach(Array(game.characters.enumerated()), id: \.offset) { i, ch in
                    Button("\(ch.name) — \(ch.race) \(ch.cls)") { showExport(i) }.buttonStyle(WebButtonStyle(kind: .ghost))
                        .accessibilityLabel("Export \(ch.name)")
                }
            }
            Button("Close") { exporting = false }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Close export overlay")
        }
    }

    private var importOverlay: some View {
        WebOverlay {
            Text("IMPORT CHARACTER").font(Theme.cinzel(12.8)).tracking(3).foregroundStyle(Theme.goldDim)
            OverlayText(text: "Paste the export code from another device below.")
            TextField("", text: $importText, prompt: Text("Paste code here...").foregroundColor(Theme.textDim), axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: 0xcccccc))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(10).background(Color(hex: 0x111111)).overlay(Rectangle().stroke(Theme.borderDim))
                .accessibilityLabel("Paste your character import code here")
            HStack(spacing: 10) {
                Button("Import") { confirmImport() }.buttonStyle(WebButtonStyle(kind: .gold)).accessibilityLabel("Confirm import")
                Button("Cancel") { importing = false }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Cancel import")
            }
        }
    }

    private func confirmImport() {
        let code = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { Feedback.announce("No code entered. Please paste an export code."); return }
        guard let ch = CharacterCode.read(code) else {
            Feedback.announce("Invalid code. Could not import. Make sure you copied the full code.")
            return
        }
        guard !game.isRosterFull, game.create(ch) else { Feedback.announce("Character slots full. Delete a character first."); return }
        importing = false
        Sound.sfx("sfx-unlock")
        Feedback.announce("Character imported. \(ch.name) the \(ch.race) \(ch.cls) is ready to play.")
    }
}

/// #screen-deathlog: every character's deaths and the total.
struct DeathLogView: View {
    @EnvironmentObject var game: GameModel

    var body: some View {
        WebScreen {
            ScreenHeader(title: "☠ Death Log", subtitle: "Every fall. Every run. Every moment the dungeon won.",
                         backLabel: "← Characters", backHint: "Back to character list", back: .charlist)
            if game.characters.isEmpty {
                Text("No characters yet.")
                    .font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0x555555))
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                ForEach(game.characters, id: \.created) { ch in
                    character(ch)
                }
                let total = game.characters.reduce(0) { $0 + $1.deaths.count }
                VStack(spacing: 4) {
                    Text("Total across all characters").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555))
                    Text("☠ \(total) death\(total != 1 ? "s" : "")").font(Theme.cinzel(16)).foregroundStyle(Color(hex: 0xff6666))
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(Color(hex: 0x0a0a0a))
                .overlay(Rectangle().stroke(Color(hex: 0x222222)))
                .padding(.top, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total: \(total) deaths across \(game.characters.count) characters.")
            }
        }
        .onAppear {
            let n = game.characters.count
            let total = game.characters.reduce(0) { $0 + $1.deaths.count }
            Feedback.announce(n == 0 ? "No characters found."
                              : "Death Log. \(n) character\(n != 1 ? "s" : ""). \(total) total deaths.")
        }
    }

    @ViewBuilder
    private func character(_ ch: PlayerCharacter) -> some View {
        let deaths = ch.deaths
        let level = ch.persistLevel ?? 1
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(CharacterListView.classIcons[ch.cls] ?? "⚔️") \(ch.name)").font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0xe0c080))
                Spacer()
                Text("Lv \(level) \(ch.cls)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xffaa00))
            }
            Text("☠ \(deaths.count) death\(deaths.count != 1 ? "s" : "")").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555))
        }
        .padding(14)
        .background(Color(hex: 0x0a0800))
        .overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xe0c080)).frame(height: 2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ch.name) the \(ch.cls). Level \(level). \(deaths.count) deaths.")

        if deaths.isEmpty {
            Text("\(ch.name) still lives. No deaths recorded.")
                .font(Theme.cinzel(10.9)).italic().foregroundStyle(Color(hex: 0x444444))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(Color(hex: 0x050505))
                .overlay(Rectangle().stroke(Color(hex: 0x111111)))
                .padding(.bottom, 12)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(deaths.enumerated()), id: \.offset) { n, d in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("☠ Floor \(d.floor) — \(d.killedBy)").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xff6666))
                            Spacer()
                            Text(d.date).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x444444))
                        }
                        Text("\(d.dungeon)\(d.diff.isEmpty ? "" : " · " + d.diff) · Lv \(max(d.level, 1))")
                            .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x666666))
                        HStack(spacing: 12) {
                            Text("⚔ \(d.kills) kills")
                            Text("💰 \(d.gold)g")
                            if d.bestDmg > 0 { Text("💥 \(d.bestDmg) best") }
                        }
                        .font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555))
                        Text(d.flavor).font(Theme.cinzel(9.9)).italic().foregroundStyle(Color(hex: 0x333333)).padding(.top, 2)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x050505))
                    .overlay(Rectangle().stroke(Color(hex: 0x1a1a1a)))
                    .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x441111)).frame(width: 2) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Death \(n + 1). \(d.dungeon.isEmpty ? "Unknown" : d.dungeon). Floor \(d.floor). Killed by \(d.killedBy). Level \(max(d.level, 1)). \(d.kills) kills. \(d.date).")
                }
            }
            .padding(.bottom, 16)
        }
    }
}

/// Lays children out in rows that wrap, like the web's flex-wrap rows.
struct FlowRow: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
