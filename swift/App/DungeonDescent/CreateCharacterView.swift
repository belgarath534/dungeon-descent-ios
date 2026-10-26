import SwiftUI
import DungeonCore

/// The web version's creation screen data, pulled from index.html by
/// swift/tools/extract-creation.py into creation.json.
struct CreationData: Decodable {
    struct Part: Decodable {
        let cls: String
        let text: String
        let hidden: Bool
        let color: String
    }
    struct Card: Decodable {
        let id: String
        let kind: String
        let key: String
        let label: String
        let disabled: Bool
        let parts: [Part]
    }
    struct Step: Decodable {
        let step: Int
        let heading: String
        let title: String
        let desc: String
        let cards: [Card]
    }
    struct Slider: Decodable {
        let order: [String]
        let descs: [String: String]
    }
    struct Spirit: Decodable {
        let id: String
        let name: String
        let icon: String
        let rarity: String?
        let ability: String?
    }
    struct Backstory: Decodable {
        let id: String
        let name: String
        let bonus: String
        let desc: String
        let journal: String
    }

    let steps: [Step]
    let sliders: [String: Slider]
    let names: [String: [String]]
    let spirits: [String: [Spirit]]
    let backstories: [Backstory]
    let statLegend: [String]

    static let shared: CreationData = {
        guard let url = Bundle.main.url(forResource: "creation", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode(CreationData.self, from: data) else {
            return CreationData(steps: [], sliders: [:], names: [:], spirits: [:], backstories: [], statLegend: [])
        }
        return d
    }()

    func step(_ n: Int) -> Step? { steps.first { $0.step == n } }
}

/// A color from the web version's inline styles: "#aa8844" or "var(--gold-dim)".
func webColor(_ css: String) -> Color? {
    let v = css.trimmingCharacters(in: .whitespaces)
    let vars: [String: Color] = ["--gold": Theme.gold, "--gold-dim": Theme.goldDim, "--gold-bright": Theme.goldBright,
                                 "--text-dim": Theme.textDim, "--text-secondary": Theme.textSecondary,
                                 "--text-primary": Theme.textPrimary, "--ash": Theme.ash, "--ash-light": Theme.ashLight,
                                 "--blood": Theme.blood, "--blood-bright": Theme.bloodBright]
    if v.hasPrefix("var(") {
        return vars[String(v.dropFirst(4).dropLast())]
    }
    guard v.hasPrefix("#") else { return nil }
    var hex = String(v.dropFirst())
    if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
    guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
    return Color(hex: n)
}

/// "Forge Your Legend": the web version's twelve creation steps.
@MainActor
struct CreateCharacterView: View {
    @EnvironmentObject var game: GameModel
    @EnvironmentObject var router: Router
    @AccessibilityFocusState private var titleFocused: Bool

    private let data = CreationData.shared

    // NC in the web version
    @State private var step = 1
    @State private var cls: String?
    @State private var race: String?
    @State private var prof: String?
    @State private var name = ""
    @State private var dungeon: String?
    @State private var diff: String?
    @State private var runMode = "classic"
    @State private var spirit: String?
    @State private var corruption = false
    @State private var hardcore = false
    @State private var hunter = false
    @State private var guidePersonality = "encouraging"
    @State private var companionName = ""
    @State private var backstory: String?

    @State private var showLegend = false
    @State private var confirming = false
    @State private var sliderIndex: [String: Int] = [:]
    @State private var toast: String?

    static let stepLabels = ["Class", "Race", "Profession", "Name", "Dungeon", "Fate", "Mode", "Spirit",
                             "Corruption", "Hunter", "Guide", "Origin"]
    static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
    static let spokenNames = ["", "Choose Your Class", "Choose Your Race", "Choose Your Profession", "Name Your Character",
                              "Choose Your Dungeon", "Choose Your Difficulty", "Choose Your Run Mode", "Choose Your Spirit",
                              "Corruption Mode", "Hunter Mode", "Your Guide", "Your Origin"]
    static let dungeonOrder = ["Crypt of Malachar", "The Ashbound Wastes", "Frosthold Abyss", "The Sunken Archives",
                               "The Hollow", "The Whispering Forest", "The Infernal Descent", "The Abyssal Deep"]
    static let diffOrder = ["Wanderer", "Ironblood", "Condemned", "Forsaken", "Nightmare", "Insane", "Endless"]
    static let diffDescs = ["Wanderer": "3 lives · Normal damage", "Ironblood": "1 life · +10% damage",
                            "Condemned": "1 life · +25% damage", "Forsaken": "1 life · +50% damage",
                            "Nightmare": "1 life · Nightmare enemies", "Insane": "1 life · Sanity bar",
                            "Endless": "Infinite floors · No victory"]
    static let warnings = ["Wanderer": "Wanderer: 3 lives. Good for learning.",
                           "Ironblood": "Warning — Ironblood: 1 life. One death ends your run.",
                           "Condemned": "Warning — Condemned: 1 life, empowered enemies.",
                           "Forsaken": "Final warning — Forsaken: 1 life, maximum difficulty. Most never return."]

    var body: some View {
        ZStack {
            WebScreen {
                ScreenHeader(title: "Forge Your Legend", backLabel: "← Cancel",
                             backHint: "Cancel and return to character list", back: .charlist)
                    .padding(.bottom, 14)
                stepsNav
                panel
            }
            if confirming { confirmOverlay }
            if let toast {
                VStack {
                    Spacer()
                    Text(toast).font(Theme.cinzel(12)).foregroundStyle(Theme.ash).padding(12)
                        .background(Color(hex: 0x130f0a)).overlay(Rectangle().stroke(Theme.borderDim))
                        .padding(.bottom, 30)
                }
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Steps nav and panel

    private var stepsNav: some View {
        HStack(spacing: 0) {
            ForEach(1...12, id: \.self) { n in
                VStack(spacing: 2) {
                    Text(Self.numerals[n - 1]).font(Theme.cinzel(10.4))
                        .foregroundStyle(n == step ? Theme.gold : n < step ? Theme.goldDim : Theme.textDim)
                    Text(Self.stepLabels[n - 1]).font(Theme.cinzel(7.2)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(n == step ? Theme.ashLight : Theme.textDim)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(.vertical, 10).padding(.horizontal, 1)
                .frame(maxWidth: .infinity)
                .background(n == step ? Color(hex: 0x1e1a10) : n < step ? Color(hex: 0x16140d) : Color(hex: 0x12100d))
                .overlay(alignment: .bottom) {
                    if n <= step { Rectangle().fill(n == step ? Theme.gold : Theme.goldDim).frame(height: 2) }
                }
                .overlay(alignment: .trailing) {
                    if n < 12 { Rectangle().fill(Theme.borderDim).frame(width: 1) }
                }
            }
        }
        .overlay(Rectangle().stroke(Theme.borderDim))
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Creation steps")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let s = data.step(step) {
                Text(s.heading).font(Theme.cinzel(11.2)).tracking(4.5).textCase(.uppercase)
                    .foregroundStyle(Theme.goldDim).padding(.bottom, 6)
                Text(s.title).font(Theme.decorative(20)).foregroundStyle(Theme.textPrimary).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                stepBody(s)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgPanel)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderGlow).frame(height: 2) }
        .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
    }

    private func desc(_ s: CreationData.Step) -> some View {
        Text(s.desc).font(Theme.crimson(16, italic: true)).foregroundStyle(Theme.textSecondary)
            .lineSpacing(3).padding(.bottom, 20)
    }

    @ViewBuilder
    private func stepBody(_ s: CreationData.Step) -> some View {
        switch step {
        case 1:
            Button("❓ What do stats mean?") {
                showLegend.toggle()
            }
            .font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xaa8844))
            .padding(.vertical, 5).padding(.horizontal, 12)
            .background(Color(hex: 0x0a0800)).overlay(Rectangle().stroke(Color(hex: 0x443300)))
            .padding(.bottom, 10)
            .accessibilityLabel("What do the stats mean? Tap to learn.")
            if showLegend {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(data.statLegend, id: \.self) { Text($0) }
                }
                .font(Theme.cinzel(10.4)).foregroundStyle(Theme.ash)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x0a0500)).overlay(Rectangle().stroke(Color(hex: 0x221100)))
                .padding(.bottom, 12)
            }
            desc(s)
            listSlider("class", label: "Class selector", prev: "Previous class", next: "Next class",
                       name: cls ?? "Warrior", sub: data.sliders["class"]?.descs[cls ?? "Warrior"] ?? "") { stepList("class", $0) }
            cardGrid(s.cards, min: 150) { $0.key == cls } pick: { pickClass($0.key) }
            buttons(back: nil, next: "Continue to Race →")
        case 2:
            desc(s)
            listSlider("race", label: "Race selector", prev: "Previous race", next: "Next race",
                       name: race ?? "Human", sub: data.sliders["race"]?.descs[race ?? "Human"] ?? "") { stepList("race", $0) }
            cardGrid(s.cards, min: 140) { $0.key == race } pick: { pickRace($0.key) }
            buttons(back: "← Back", next: "Continue to Profession →")
        case 3:
            desc(s)
            listSlider("prof", label: "Profession selector", prev: "Previous profession", next: "Next profession",
                       name: prof ?? "Blacksmith", sub: data.sliders["prof"]?.descs[prof ?? "Blacksmith"] ?? "") { stepList("prof", $0) }
            cardGrid(s.cards, min: 140) { $0.key == prof } pick: { pickProf($0.key) }
            buttons(back: "← Back", next: "Continue to Dungeon →")
        case 4: nameStep(s)
        case 5: dungeonStep(s)
        case 6: fateStep(s)
        case 7: runModeStep(s)
        case 8: spiritStep(s)
        case 9:
            desc(s)
            cardGrid(s.cards, min: 140) { ($0.id == "corruption-on-btn") == corruption } pick: { c in
                corruption = c.id == "corruption-on-btn"
                Feedback.announce(corruption ? "Corruption Mode ON. Every death darkens your soul." : "Standard Mode. No corruption.")
            }
            buttons(back: "← Back", next: "Next →", nextHint: "Continue to hunter mode step", backHint: "Back to spirit selection")
        case 10:
            desc(s)
            cardGrid(s.cards, min: 140) { ($0.id == "hunter-on-btn") == hunter } pick: { c in
                hunter = c.id == "hunter-on-btn"
                Feedback.announce(hunter ? "Hunter Mode ON. Something will hunt you through the dungeon. Every move you make, it moves too."
                                  : "Hunter Mode OFF. No hunter.")
            }
            buttons(back: "← Back", next: "Next →", nextHint: "Continue to companion guide step", backHint: "Back to corruption step")
        case 11: guideStep(s)
        default: originStep(s)
        }
    }

    // MARK: Cards

    private func cardGrid(_ cards: [CreationData.Card], min: CGFloat, selected: @escaping (CreationData.Card) -> Bool,
                          pick: @escaping (CreationData.Card) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, c in
                CreationCard(card: c, selected: selected(c)) { pick(c) }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: Slider

    private func listSlider(_ key: String, label: String, prev: String, next: String, name: String, sub: String,
                            step: @escaping (Int) -> Void) -> some View {
        WebSlider(label: label, prevLabel: prev, nextLabel: next, name: name, sub: sub, step: step)
    }

    private func stepList(_ key: String, _ dir: Int) {
        guard let s = data.sliders[key], !s.order.isEmpty else { return }
        let i = ((sliderIndex[key] ?? 0) + dir + s.order.count) % s.order.count
        sliderIndex[key] = i
        let v = s.order[i]
        switch key {
        case "class": pickClass(v, quiet: true)
        case "race": pickRace(v, quiet: true)
        default: pickProf(v, quiet: true)
        }
        Feedback.announce("\(v). \(s.descs[v] ?? "").")
    }

    private func pickClass(_ v: String, quiet: Bool = false) {
        cls = v
        if !quiet { Feedback.announce("\(v) selected.") }
    }

    private func pickRace(_ v: String, quiet: Bool = false) {
        race = v
        if !quiet { Feedback.announce("\(v) selected.") }
    }

    private func pickProf(_ v: String, quiet: Bool = false) {
        prof = v
        if !quiet { Feedback.announce("\(v) selected.") }
    }

    // MARK: Step 4: name

    @ViewBuilder
    private func nameStep(_ s: CreationData.Step) -> some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        desc(s)
        Text("Character Name").font(Theme.cinzel(11.2)).tracking(3.4).textCase(.uppercase)
            .foregroundStyle(Theme.goldDim).padding(.bottom, 8)
            .accessibilityHidden(true)
        HStack(spacing: 8) {
            TextField("", text: $name, prompt: Text("Enter your name, brave soul...").font(Theme.crimson(16, italic: true)).foregroundColor(Theme.textDim))
                .font(Theme.cinzel(17.6))
                .tracking(1.4)
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(Theme.bgStone)
                .overlay(Rectangle().stroke(Theme.borderDim))
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderGlow).frame(height: 2) }
                .accessibilityLabel("Enter character name, maximum 24 characters")
                .onChange(of: name) { v in if v.count > 24 { name = String(v.prefix(24)) } }
            Button("🎲 Generate") { generateName() }
                .font(Theme.cinzel(11.5)).foregroundStyle(Theme.gold)
                .padding(.vertical, 12).padding(.horizontal, 12)
                .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Theme.goldDim))
                .accessibilityLabel("Generate a random fantasy name")
        }
        .padding(.bottom, 8)
        Text(trimmed.isEmpty ? "Name must be between 2 and 24 characters."
             : trimmed.count < 2 ? "Name is too short." : "\(trimmed.count) characters.")
            .font(Theme.crimson(12.8, italic: true)).foregroundStyle(Theme.textDim)
            .padding(.bottom, 24)
        buttons(back: "← Back", next: "Continue to Dungeon →", nextDisabled: trimmed.count < 2)
    }

    private func generateName() {
        let n = data.names
        guard let p = n["prefixes"]?.randomElement(), let suf = n["suffixes"]?.randomElement() else { return }
        let mid = Double.random(in: 0..<1) > 0.4 ? (n["mids"]?.randomElement() ?? "") : ""
        var v = p + mid + suf
        v = v.prefix(1).uppercased() + v.dropFirst().lowercased()
        if v.count > 18 { v = String(v.prefix(18)) }
        name = v
        Feedback.announce("Generated name: \(v). Press Generate again for a different name.")
    }

    // MARK: Step 5: dungeon

    private var unlocked: [String] { game.unlockedDungeons() }

    private func isLocked(_ c: CreationData.Card) -> Bool {
        if c.key == "The Shadow World" { return true }
        return !unlocked.contains(c.key)
    }

    @ViewBuilder
    private func dungeonStep(_ s: CreationData.Step) -> some View {
        let i = sliderIndex["dungeon"] ?? 0
        let d = Self.dungeonOrder[i]
        desc(s)
        WebSlider(label: "Dungeon selector", prevLabel: "Previous dungeon", nextLabel: "Next dungeon",
                  name: dungeon ?? d, sub: unlocked.contains(dungeon ?? d) ? "Unlocked" : "Locked") { stepDungeon($0) }
        VStack(spacing: 10) {
            ForEach(Array(s.cards.enumerated()), id: \.offset) { _, c in
                let locked = isLocked(c)
                CreationCard(card: c, selected: dungeon == c.key, locked: locked,
                             label: dungeonLabel(c, locked: locked), lockText: locked ? nil : unlockText(c)) { pickDungeon(c) }
            }
        }
        .padding(.bottom, 24)
        buttons(back: "← Back", next: "Continue to Fate →")
    }

    private func dungeonLabel(_ c: CreationData.Card, locked: Bool) -> String {
        guard !locked else { return c.label }
        switch c.key {
        case "The Infernal Descent": return "The Infernal, unlocked, dungeon of pure darkness, 10 floors. Press to select."
        case "The Abyssal Deep": return "The Abyssal Deep. Unlocked. The Leviathan awaits."
        default: return "\(c.key), unlocked, 10 floors. Press to select."
        }
    }

    private func unlockText(_ c: CreationData.Card) -> String? {
        switch c.key {
        case "The Infernal Descent": return "🔥 UNLOCKED — The gate is open"
        case "The Abyssal Deep": return nil
        default: return "✦ UNLOCKED · 10 Floors"
        }
    }

    private func pickDungeon(_ c: CreationData.Card) {
        if isLocked(c) {
            switch c.key {
            case "The Infernal Descent":
                let have = game.achievements.trophies
                let left = max(0, 100 - have)
                Feedback.announce("The Infernal Gate is sealed. You need 100 trophies to unlock it. You have \(have) trophies. \(left > 0 ? "\(left) more needed." : "")")
                showToast("🏆 Need 100 trophies to unlock The Infernal. You have \(have).")
            case "The Abyssal Deep":
                Feedback.announce("The Abyssal Deep is sealed. Complete The Infernal Descent first to unlock it.")
                showToast("🌊 Complete The Infernal Descent to unlock The Abyssal Deep.")
            case "The Shadow World":
                Feedback.announce("The Shadow World is sealed. It has waited 3000 years. It isn't in the Swift version yet.")
                showToast("🌑 The Shadow World isn't in the Swift version yet.")
            default: break
            }
            return
        }
        dungeon = c.key
        if let i = Self.dungeonOrder.firstIndex(of: c.key) { sliderIndex["dungeon"] = i }
        Feedback.announce("\(c.key) selected.")
    }

    private func stepDungeon(_ dir: Int) {
        let cur = sliderIndex["dungeon"] ?? 0
        let n = Self.dungeonOrder.count
        let i = (cur + dir + n) % n
        let d = Self.dungeonOrder[i]
        guard unlocked.contains(d) else {
            Feedback.announce("\(d) is locked. Complete previous dungeons to unlock.")
            return
        }
        sliderIndex["dungeon"] = i
        dungeon = d
        Feedback.announce("\(d) selected.")
    }

    // MARK: Step 6: fate

    @ViewBuilder
    private func fateStep(_ s: CreationData.Step) -> some View {
        let fates = s.cards.filter { !$0.key.isEmpty }
        let hc = s.cards.filter { $0.key.isEmpty }
        desc(s)
        WebSlider(label: "Difficulty selector", prevLabel: "Previous difficulty", nextLabel: "Next difficulty",
                  name: diff ?? "Wanderer", sub: Self.diffDescs[diff ?? "Wanderer"] ?? "") { dir in
            let n = Self.diffOrder.count
            let i = ((sliderIndex["diff"] ?? 0) + dir + n) % n
            sliderIndex["diff"] = i
            pickDiff(Self.diffOrder[i])
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)], spacing: 10) {
            ForEach(Array(fates.enumerated()), id: \.offset) { _, c in
                CreationCard(card: c, selected: diff == c.key) { pickDiff(c.key) }
            }
        }
        .padding(.bottom, 24)

        VStack(alignment: .leading, spacing: 8) {
            Text("💀 Hardcore Mode").font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0xcc0000))
            Text("Death is permanent. One life. If you die, your character is deleted forever. No second chances.")
                .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x996666))
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(hc.enumerated()), id: \.offset) { _, c in
                    CreationCard(card: c, selected: (c.id == "hardcore-on-btn") == hardcore,
                                 selectedBorder: Color(hex: 0xcc0000)) {
                        pickHardcore(c.id == "hardcore-on-btn")
                    }
                }
            }
            if hardcore {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠ Warning — This Cannot Be Undone").font(Theme.decorative(12.5)).foregroundStyle(Color(hex: 0xcc0000))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• You have **one life**. No extra lives. No resurrection.")
                        Text("• If you die, your character is **permanently deleted** from save data.")
                        Text("• No retry. No continue. No recovery.")
                        Text("• Cloud saves will not restore a deleted hardcore character.")
                        Text("If you are sure, continue. If not, select Standard above.")
                    }
                    .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xcc6666))
                }
                .padding(.vertical, 12).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x1a0000))
                .overlay(Rectangle().stroke(Color(hex: 0xcc0000)))
                .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0xcc0000)).frame(width: 4) }
            }
        }
        .padding(.bottom, 24)

        VStack(alignment: .leading, spacing: 0) {
            Text("Your Legend — Review Before You Descend").font(Theme.cinzel(10.4)).tracking(4.2).textCase(.uppercase)
                .foregroundStyle(Theme.goldDim).padding(.bottom, 14)
            summaryRow("Name", name.trimmingCharacters(in: .whitespaces), hi: true)
            summaryRow("Class", cls)
            summaryRow("Race", race)
            summaryRow("Profession", prof)
            summaryRow("Dungeon", dungeon)
            summaryRow("Difficulty", diff)
        }
        .padding(.vertical, 20).padding(.horizontal, 24)
        .background(Theme.bgDeep)
        .overlay(Rectangle().stroke(Theme.borderDim))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.goldDim).frame(width: 3) }
        .padding(.bottom, 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Character summary")
        buttons(back: "← Back", next: "Next →", nextHint: "Continue to run mode step")
    }

    private func summaryRow(_ key: String, _ value: String?, hi: Bool = false) -> some View {
        HStack {
            Text(key).font(Theme.cinzel(11.2)).foregroundStyle(Theme.textDim)
            Spacer()
            Text((value ?? "").isEmpty ? "—" : value!).font(Theme.cinzel(13.6, weight: .semibold))
                .foregroundStyle(hi ? Theme.gold : Theme.ashLight)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 58 / 255, green: 46 / 255, blue: 34 / 255).opacity(0.5)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func pickDiff(_ d: String) {
        diff = d
        if let i = Self.diffOrder.firstIndex(of: d) { sliderIndex["diff"] = i }
        Feedback.announce("\(d) difficulty selected.")
    }

    private func pickHardcore(_ on: Bool) {
        hardcore = on
        Feedback.announce(on ? "Warning. Hardcore Mode enabled. You have one life. If you die, your character is permanently deleted from save data. There is no retry, no continue, and no recovery. Select Standard above if you are not sure."
                          : "Standard mode selected. Normal gameplay. Hardcore Mode disabled.")
    }

    // MARK: Step 7: run mode

    @ViewBuilder
    private func runModeStep(_ s: CreationData.Step) -> some View {
        desc(s)
        VStack(spacing: 10) {
            ForEach(Array(s.cards.enumerated()), id: \.offset) { _, c in
                let mode = c.id == "mode-legacy" ? "legacy" : "classic"
                CreationCard(card: c, selected: runMode == mode,
                             selectedBorder: mode == "legacy" ? Color(hex: 0x6644aa) : Color(hex: 0xaa8844)) {
                    pickRunMode(mode)
                }
            }
        }
        .padding(.bottom, 12)
        Text(runMode == "classic"
             ? "Classic Run selected. You will start fresh at Level 1 every time you descend. Die and your journey ends. The roguelike experience."
             : "Legacy Mode selected. Your level carries over between runs. Complete this dungeon to raise its tier. Die and you keep your level but the dungeon resets. Build one legend over a long time.")
            .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x666666)).lineSpacing(6)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x222222)))
            .padding(.bottom, 16)
        buttons(back: "← Back", next: "Next →", nextHint: "Continue to spirit step", backHint: "Back to difficulty")
    }

    private func pickRunMode(_ mode: String) {
        runMode = mode
        Feedback.announce(mode == "classic" ? "Classic Run selected. Fresh start every run." : "Legacy Mode selected. Your level persists between runs.")
    }

    // MARK: Step 8: spirit

    private var availableSpirits: [CreationData.Spirit] {
        var earned = Set<String>()
        for ch in game.characters {
            if case .array(let a)? = ch.extra["earnedSpirits"] {
                for v in a { if case .string(let id) = v { earned.insert(id) } }
            }
        }
        return (data.spirits["starter"] ?? [])
            + (data.spirits["rare"] ?? []).filter { earned.contains($0.id) }
            + (data.spirits["elite"] ?? []).filter { earned.contains($0.id) }
    }

    @ViewBuilder
    private func spiritStep(_ s: CreationData.Step) -> some View {
        desc(s)
        VStack(spacing: 10) {
            ForEach(availableSpirits, id: \.id) { sp in
                let sel = spirit == sp.id
                Button {
                    spirit = sp.id
                    Feedback.announce("\(sp.name) selected. \(sp.ability ?? "")")
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("\(sp.icon) \(sp.name)").font(Theme.cinzel(12.5)).foregroundStyle(sel ? Theme.gold : Color(hex: 0xe0c080))
                            if sp.rarity == "rare" { tag("RARE", Theme.gold, Theme.goldDim) }
                            if sp.rarity == "elite" { tag("ELITE", Color(hex: 0xcc88ff), Color(hex: 0x884499)) }
                        }
                        Text("✦ \(sp.ability ?? "")").font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0x666666))
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(sel ? Theme.gold.opacity(0.08) : Theme.bgStone)
                    .overlay(Rectangle().stroke(sel ? Theme.gold : Color(hex: 0x333333)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sp.name). \(sp.ability ?? "")")
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spirit selection")
        buttons(back: "← Back", next: "Continue →", nextHint: "Continue to corruption step", backHint: "Back to run mode")
    }

    private func tag(_ t: String, _ c: Color, _ b: Color) -> some View {
        Text(t).font(Theme.cinzel(8.8)).foregroundStyle(c).padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(Rectangle().stroke(b))
    }

    // MARK: Step 11: guide

    @ViewBuilder
    private func guideStep(_ s: CreationData.Step) -> some View {
        desc(s)
        HStack(spacing: 14) {
            Image("GuidePortrait").resizable().scaledToFill().frame(width: 72, height: 72).clipped()
                .overlay(Rectangle().stroke(Color(hex: 0x6644aa)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Guide").font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0xcc88ff))
                Text("She will walk with you through every dungeon. What will you call her?")
                    .font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0x888888))
            }
        }
        .padding(.bottom, 12)
        TextField("", text: $companionName, prompt: Text("Enter her name...").foregroundColor(Theme.textDim))
            .font(Theme.cinzel(15)).foregroundStyle(Theme.textPrimary)
            .autocorrectionDisabled()
            .padding(12).background(Theme.bgStone).overlay(Rectangle().stroke(Color(hex: 0x6644aa)))
            .accessibilityLabel("Enter your guide name")
            .onChange(of: companionName) { v in if v.count > 20 { companionName = String(v.prefix(20)) } }
        if !companionName.isEmpty {
            Text("\(companionName) will guide you through the dungeon.").font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xaa88dd))
                .padding(.top, 6)
        }
        Text("Her Personality").font(Theme.cinzel(11.5)).foregroundStyle(Color(hex: 0xaa88dd)).padding(.top, 14).padding(.bottom, 8)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            personality("encouraging", "💛 Encouraging", "Always lifts you up")
            personality("sarcastic", "😏 Sarcastic", "Dry humor, roasts you")
            personality("mysterious", "🌙 Mysterious", "Speaks in riddles")
            personality("calm", "🌊 Calm", "Minimal, only when it matters")
        }
        .padding(.bottom, 24)
        HStack(spacing: 8) {
            Button("← Back") { go(10) }.buttonStyle(CreationButtonStyle(kind: .secondary))
                .accessibilityLabel("Back to hunter mode")
            Spacer()
            Button("Skip →") { saveCompanion() }.buttonStyle(CreationButtonStyle(kind: .ghost))
                .accessibilityLabel("Skip guide and continue to origin")
            Button("Continue →") { saveCompanion() }.buttonStyle(CreationButtonStyle(kind: .primary))
                .accessibilityLabel("Continue to origin")
        }
    }

    private func personality(_ id: String, _ title: String, _ sub: String) -> some View {
        let sel = guidePersonality == id
        return Button {
            guidePersonality = id
            Feedback.announce("Guide personality set to \(id).")
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.cinzel(12)).foregroundStyle(Theme.ashLight)
                Text(sub).font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x777777))
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.bgStone)
            .overlay(Rectangle().stroke(sel ? Color(hex: 0x6644aa) : Color(hex: 0x333333)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(sel ? .isSelected : [])
    }

    private func saveCompanion() {
        let n = companionName.trimmingCharacters(in: .whitespaces)
        game.store.setItem("dd_companion_name", n.isEmpty ? "Mira" : n)
        go(12)
    }

    // MARK: Step 12: origin

    @ViewBuilder
    private func originStep(_ s: CreationData.Step) -> some View {
        let list = data.backstories
        let i = sliderIndex["bk"] ?? 0
        desc(s)
        if !list.isEmpty {
            WebSlider(label: "Backstory selector", prevLabel: "Previous backstory", nextLabel: "Next backstory",
                      name: list[i].name, sub: list[i].bonus) { dir in
                let j = (i + dir + list.count) % list.count
                sliderIndex["bk"] = j
                pickBackstory(list[j])
            }
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), spacing: 8, alignment: .top)], spacing: 8) {
            ForEach(list, id: \.id) { b in
                let sel = backstory == b.id
                Button { pickBackstory(b) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.name).font(Theme.cinzel(12.5)).foregroundStyle(Theme.goldDim)
                        Text(b.desc).font(Theme.crimson(10.9)).foregroundStyle(Theme.textDim)
                        Text("✦ \(b.bonus)").font(Theme.crimson(10.4, italic: true)).foregroundStyle(Theme.gold).padding(.top, 2)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(sel ? Theme.gold.opacity(0.06) : Theme.bgPanel)
                    .overlay(Rectangle().stroke(sel ? Theme.gold : Theme.borderDim))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(b.name). \(b.desc). Bonus: \(b.bonus)")
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
        .padding(.bottom, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your backstory")
        HStack(spacing: 8) {
            Button("← Back") { go(11) }.buttonStyle(CreationButtonStyle(kind: .secondary))
                .accessibilityLabel("Back to companion guide")
            Spacer()
            Button("Skip ↓") { openConfirm() }.buttonStyle(CreationButtonStyle(kind: .ghost))
                .accessibilityLabel("Skip backstory and descend now")
            Button("⚔ Descend") { openConfirm() }.buttonStyle(CreationButtonStyle(kind: .primary))
                .accessibilityLabel("Descend with chosen backstory")
        }
    }

    private func pickBackstory(_ b: CreationData.Backstory) {
        backstory = b.id
        if let j = data.backstories.firstIndex(where: { $0.id == b.id }) { sliderIndex["bk"] = j }
        Feedback.announce("\(b.name) selected. \(b.desc). Bonus: \(b.bonus)")
    }

    // MARK: Moving between steps (cStep)

    private func buttons(back: String?, next: String, nextHint: String? = nil, backHint: String? = nil,
                         nextDisabled: Bool = false) -> some View {
        HStack(spacing: 12) {
            if let back {
                Button(back) { go(step - 1) }
                    .buttonStyle(CreationButtonStyle(kind: .secondary))
                    .accessibilityLabel(backHint ?? back)
            }
            Spacer()
            Button(next) { go(step + 1) }
                .buttonStyle(CreationButtonStyle(kind: .primary, disabled: nextDisabled))
                .disabled(nextDisabled)
                .accessibilityLabel(nextHint ?? next)
        }
    }

    private func go(_ n: Int) {
        if n > step {
            switch step {
            case 1 where cls == nil: Feedback.announce("Please select a class first."); return
            case 2 where race == nil: Feedback.announce("Please select a race first."); return
            case 3 where prof == nil: Feedback.announce("Please select a profession first."); return
            case 4 where name.trimmingCharacters(in: .whitespaces).count < 2:
                Feedback.announce("Please enter a name of at least 2 characters."); return
            case 5 where dungeon == nil: Feedback.announce("Please select a dungeon first."); return
            case 6 where diff == nil: diff = "Wanderer"
            case 8 where spirit == nil: spirit = availableSpirits.first?.id
            default: break
            }
        }
        guard (1...12).contains(n) else { return }
        step = n
        Feedback.announce("Step \(n) of 12. \(Self.spokenNames[n]). Use the options below to make your selection.")
        switch n {
        case 5:
            if dungeon == nil, let first = Self.dungeonOrder.first(where: { unlocked.contains($0) }) {
                dungeon = first
                Feedback.announce("\(first) selected.")
            }
        case 6:
            if diff == nil { pickDiff("Wanderer") }
        case 7:
            pickRunMode(runMode)
        case 8:
            let all = availableSpirits
            let earned = all.filter { $0.rarity == "rare" || $0.rarity == "elite" }.count
            Feedback.announce("Spirit selection. \(all.count) spirits available. \(earned) earned spirits unlocked.")
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { titleFocused = true }
    }

    // MARK: Confirm and create (openConfirmDialog, finalizeChar)

    private func openConfirm() {
        confirming = true
        let warn = Self.warnings[diff ?? ""]
        Feedback.announce("Confirm character. \(warn.map { $0 + " " } ?? "")Press Descend to confirm.")
    }

    private var confirmOverlay: some View {
        let n = name.trimmingCharacters(in: .whitespaces)
        return WebOverlay {
            OverlayTitle(text: "⚔ Enter the Dungeon?")
            OverlayText(text: "\(n) the \(race ?? "") \(cls ?? "") (\(prof ?? "")) will enter \(dungeon ?? "").")
            if let w = Self.warnings[diff ?? ""] {
                Text(w).font(Theme.cinzel(12.8)).foregroundStyle(Theme.bloodBright)
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(Theme.blood.opacity(0.08)).overlay(Rectangle().stroke(Theme.blood))
            }
            HStack(spacing: 10) {
                Button("Descend") { finalize() }
                    .buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Confirm and descend")
                Button("Go Back") { confirming = false }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .accessibilityLabel("Go back and change choices")
            }
        }
    }

    private func finalize() {
        guard let cls, let race, let prof, let dungeon else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let chosenSpirit = spirit ?? availableSpirits.first?.id
        var ch = PlayerCharacter(name: n, cls: cls, race: race, prof: prof, dungeon: dungeon,
                                 difficulty: GameData.Difficulty(rawValue: diff ?? "Wanderer") ?? .wanderer,
                                 runMode: runMode, spirit: chosenSpirit, corruptionMode: corruption,
                                 hunterMode: hunter, hardcoreMode: hardcore, guidePersonality: guidePersonality)
        var originLine = ""
        if let id = backstory, let b = data.backstories.first(where: { $0.id == id }) {
            ch.extra["backstory"] = .string(b.id)
            ch.extra["backstoryName"] = .string(b.name)
            let c = Calendar.current.dateComponents([.month, .day], from: Date())
            ch.extra["journal"] = .array([.object(["time": .string("\(c.month ?? 1)/\(c.day ?? 1) Floor 0"), "text": .string(b.journal)])])
            originLine = " Backstory: \(b.name). \(b.desc). Bonus: \(b.bonus)"
        }
        guard game.create(ch) else { return }
        confirming = false
        let spiritName = availableSpirits.first { $0.id == chosenSpirit }?.name ?? chosenSpirit
        var msg = "\(n) created." + (runMode == "legacy" ? " Legacy Mode active." : " Classic Run.")
        if let spiritName { msg += " Spirit: \(spiritName)." }
        if corruption { msg += " Corruption Mode ON." }
        if hunter { msg += " Hunter Mode ON. Something will be hunting you." }
        msg += originLine.isEmpty ? "" : originLine
        Feedback.announce(msg + " Returning to character list.")
        router.goTo(.charlist)
    }

    private func showToast(_ s: String) {
        withAnimation { toast = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { if toast == s { toast = nil } } }
    }
}

/// The ◀ name ▶ slider the web version puts above every set of choices.
/// VoiceOver swipes up and down on it to move through the options.
struct WebSlider: View {
    let label: String
    let prevLabel: String
    let nextLabel: String
    let name: String
    let sub: String
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            arrow("◀", prevLabel) { step(-1) }
            VStack(spacing: 2) {
                Text(name).font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0xe0c080))
                Text(sub).font(Theme.cinzel(10)).foregroundStyle(Color(hex: 0x666666))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(sub.isEmpty ? name : "\(name) — \(sub)")
            .accessibilityAdjustableAction { dir in
                switch dir {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
            arrow("▶", nextLabel) { step(1) }
        }
        .padding(12)
        .background(Color(hex: 0x0a0800))
        .overlay(Rectangle().stroke(Color(hex: 0x2a2010)))
        .padding(.bottom, 12)
    }

    private func arrow(_ t: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(Theme.cinzel(13)).foregroundStyle(Color(hex: 0xaaaaaa))
                .padding(.vertical, 8).padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color(hex: 0x1a1000)).overlay(Rectangle().stroke(Color(hex: 0x555555)))
        }
        .accessibilityLabel(label)
    }
}

/// .btn-primary, .btn-secondary and .btn-ghost in the creation steps.
struct CreationButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind
    var disabled = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(Theme.cinzel(12, weight: kind == .primary ? .bold : .regular))
            .tracking(2.4)
            .textCase(.uppercase)
            .foregroundStyle(kind == .primary ? (disabled ? Theme.textDim : Theme.bgVoid)
                             : down ? Theme.ashLight : (kind == .ghost ? Theme.ash : Theme.textSecondary))
            .padding(.vertical, 12)
            .padding(.horizontal, kind == .primary ? 20 : 16)
            .frame(minHeight: 44)
            .background(kind == .primary ? (disabled ? Theme.borderDim : down ? Theme.goldBright : Theme.gold) : Color.clear)
            .overlay(Rectangle().stroke(kind == .primary ? .clear : (down ? Theme.ashLight : Theme.borderDim)))
    }
}

/// One creation card (class, race, profession, dungeon, fate, mode …) drawn
/// from the web version's markup: its text pieces keep their classes' styles.
struct CreationCard: View {
    let card: CreationData.Card
    let selected: Bool
    var locked = false
    var label: String? = nil
    /// Replaces the dungeon card's lock line once it's unlocked.
    var lockText: String? = nil
    var selectedBorder: Color = Theme.gold
    let action: () -> Void

    private var centered: Bool { card.kind == "race-card" || card.kind == "prof-card" }

    var body: some View {
        Button(action: action) {
            Group {
                if card.kind == "dungeon-card" {
                    HStack(alignment: .top, spacing: 16) {
                        if let icon = card.parts.first(where: { $0.cls == "dungeon-icon" }) {
                            Text(icon.text).font(.system(size: 32))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(card.parts.filter { $0.cls != "dungeon-icon" }.enumerated()), id: \.offset) { _, p in
                                piece(p)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(alignment: centered ? .center : .leading, spacing: 3) {
                        let pips = card.parts.filter { $0.cls == "stat-pip" }
                        ForEach(Array(card.parts.filter { $0.cls != "stat-pip" }.enumerated()), id: \.offset) { _, p in
                            piece(p)
                        }
                        if !pips.isEmpty {
                            FlowRow(spacing: 8) {
                                ForEach(Array(pips.enumerated()), id: \.offset) { _, p in
                                    Text(p.text).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x3a3020))
                                        .padding(.vertical, 2).padding(.horizontal, 6)
                                        .background(Theme.bgDeep).overlay(Rectangle().stroke(Theme.borderDim))
                                }
                            }
                            .padding(.top, 7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                }
            }
            .multilineTextAlignment(centered ? .center : .leading)
            .padding(card.kind == "dungeon-card" ? 18 : 16)
            .background(selected ? Color(hex: 0x2a2010) : Theme.bgStone)
            .overlay(Rectangle().stroke(selected ? selectedBorder : borderColor))
            .overlay(alignment: .topTrailing) {
                if selected && card.kind == "class-card" {
                    Text("✦").font(.system(size: 11)).foregroundStyle(Theme.gold).padding(.top, 8).padding(.trailing, 10)
                }
            }
            .shadow(color: selected ? Theme.gold.opacity(0.12) : .clear, radius: 6)
            .opacity(locked ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? card.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var borderColor: Color {
        card.key == "Insane" ? Color(hex: 0x8b0000) : Theme.borderDim
    }

    @ViewBuilder
    private func piece(_ p: CreationData.Part) -> some View {
        switch p.cls {
        case "class-icon": Text(p.text).font(.system(size: 26)).padding(.bottom, 3)
        case "race-icon", "prof-icon": Text(p.text).font(.system(size: 22)).padding(.bottom, 3)
        case "class-name", "race-name", "prof-name": Text(p.text).font(Theme.cinzel(13.1)).foregroundStyle(Theme.ashLight)
        case "class-role": Text(p.text).font(Theme.cinzel(12)).italic().foregroundStyle(Theme.goldDim).padding(.bottom, 5)
        case "class-desc": Text(p.text).font(Theme.crimson(12.8)).foregroundStyle(Theme.textDim).lineSpacing(2)
        case "race-trait": Text(p.text).font(Theme.crimson(11.2, italic: true)).foregroundStyle(Theme.goldDim)
        case "prof-bonus": Text(p.text).font(Theme.crimson(11.2, italic: true)).foregroundStyle(Theme.bloodBright)
        case "dungeon-name": Text(p.text).font(Theme.cinzel(15.2)).foregroundStyle(Theme.ashLight)
        case "dungeon-lore": Text(p.text).font(Theme.crimson(13.1, italic: true)).foregroundStyle(Theme.textDim).lineSpacing(2)
        case "dungeon-lock", "dungeon-unlock-note":
            if let lockText {
                Text(lockText).font(Theme.cinzel(11.2)).foregroundStyle(lockText.hasPrefix("🔥") ? Color(hex: 0xff4444) : Color(hex: 0x7aaa7a)).padding(.top, 4)
            } else {
                Text(p.text).font(Theme.cinzel(11.2)).foregroundStyle(Theme.blood).padding(.top, 4)
            }
        case "diff-name": Text(p.text).font(Theme.cinzel(13.6)).foregroundStyle(Theme.ashLight)
        case "diff-lives": Text(p.text).font(Theme.crimson(12)).foregroundStyle(Theme.bloodBright)
        case "diff-desc": Text(p.text).font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
        default:
            Text(p.text).font(Theme.cinzel(10.9)).foregroundStyle(webColor(p.color) ?? Color(hex: 0xaaaaaa)).lineSpacing(3)
        }
    }
}
