import SwiftUI
import DungeonCore

/// Help, Credits and What's New text from index.html, pulled by
/// swift/tools/extract-static-screens.py into statics.json.
struct Statics: Decodable {
    struct HelpEntry: Decodable { let title: String; let body: String }
    struct HelpTab: Decodable { let id: String; let label: String; let entries: [HelpEntry] }
    struct Help: Decodable { let intro: String; let tabs: [HelpTab] }
    struct CreditLine: Decodable { let kind: String; let text: String }
    struct CreditSection: Decodable { let title: String; let label: String; let lines: [CreditLine] }
    struct Credits: Decodable { let title: String; let sub: String; let sections: [CreditSection] }
    struct Version: Decodable { let num: String; let date: String; let label: String; let changes: [String] }

    let help: Help
    let credits: Credits
    let whatsnew: [Version]

    static let shared: Statics? = {
        guard let url = Bundle.main.url(forResource: "statics", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Statics.self, from: data)
    }()
}

// MARK: The Graveyard (#screen-graveyard)

@MainActor
struct GraveyardView: View {
    @EnvironmentObject var game: GameModel

    struct Stone {
        let name, race, cls, dungeon, difficulty, killedBy, journal, date: String
        let level, topFloor: Int
    }

    private var stones: [Stone] {
        guard let raw = game.store.getItem("dd_graveyard"), let d = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([JSONValue].self, from: d) else { return [] }
        return list.compactMap { v in
            guard case .object(let o) = v else { return nil }
            func s(_ k: String) -> String {
                switch o[k] {
                case .string(let x)?: return x
                case .number(let n)?: return String(Int(n))
                case .array(let a)?:
                    return a.compactMap { e -> String? in
                        if case .object(let j) = e, case .string(let t)? = j["text"] { return t }
                        if case .string(let t) = e { return t }
                        return nil
                    }.joined(separator: " · ")
                case .object(let j)?: if case .string(let t)? = j["text"] { return t }; return ""
                default: return ""
                }
            }
            func n(_ k: String) -> Int { if case .number(let x)? = o[k] { return Int(x) }; return 0 }
            return Stone(name: s("name").isEmpty ? "Unknown" : s("name"), race: s("race"), cls: s("cls"),
                         dungeon: s("dungeon"), difficulty: s("difficulty"),
                         killedBy: s("killedBy").isEmpty ? "unknown causes" : s("killedBy"),
                         journal: s("journal"), date: s("date"), level: max(1, n("level")), topFloor: n("topFloor"))
        }
    }

    var body: some View {
        let list = stones
        WebScreen {
            ScreenHeader(title: "⚰️ The Graveyard")
            Text("The dungeon remembers what you forget.").font(Theme.crimson(14.4, italic: true)).foregroundStyle(Color(hex: 0x555555))
            Text("Characters you have deleted or lost to the dark.").font(Theme.crimson(13)).foregroundStyle(Theme.textDim)
                .padding(.bottom, 12)
            if list.isEmpty {
                Text("No one has fallen yet. The graveyard waits.")
                    .font(Theme.cinzel(12)).italic().foregroundStyle(Color(hex: 0x555555))
                    .frame(maxWidth: .infinity).padding(30)
            }
            ForEach(Array(list.enumerated()), id: \.offset) { _, e in stone(e) }
        }
        .onAppear {
            Feedback.announce(list.isEmpty ? "The Graveyard. No fallen characters yet. The graveyard waits."
                              : "The Graveyard. \(list.count) fallen champion\(list.count != 1 ? "s" : ""). Swipe through to read each tombstone.")
        }
    }

    private func stone(_ e: Stone) -> some View {
        let fell = e.killedBy != "unknown causes"
        return VStack(spacing: 4) {
            Text("⚰").font(.system(size: 24)).padding(.bottom, 4)
            Text(e.name).font(Theme.cinzel(13.6)).foregroundStyle(Color(hex: 0x888888))
            Text("\(e.race) \(e.cls) Level \(e.level)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x555555)).padding(.bottom, 4)
            Text("\(e.dungeon)\(e.difficulty.isEmpty ? "" : " " + e.difficulty)").font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x444444))
            if fell {
                Text("Fell to \(e.killedBy)\(e.topFloor > 0 ? " on floor \(e.topFloor)" : "")").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x666666))
            } else {
                Text("Removed from the roster.").font(Theme.cinzel(10.4)).italic().foregroundStyle(Color(hex: 0x444444))
            }
            if !e.journal.isEmpty {
                Text(e.journal).font(Theme.cinzel(9.9)).italic().foregroundStyle(Color(hex: 0x555555))
                    .padding(.top, 8)
                    .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x111111)).frame(height: 1) }
            }
            Text(e.date).font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x333333)).padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(hex: 0x050505))
        .overlay(Rectangle().stroke(Color(hex: 0x1a1a1a)))
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x444444)).frame(height: 2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.name) the \(e.race) \(e.cls). Level \(e.level). \(fell ? "Fell to \(e.killedBy)." : "Deleted.")\(e.topFloor > 0 ? " Reached floor \(e.topFloor)." : "")\(e.journal.isEmpty ? "" : " " + e.journal)")
    }
}

// MARK: Help (#screen-help)

@MainActor
struct HelpView: View {
    @State private var tab = "basics"

    var body: some View {
        let help = Statics.shared?.help
        WebScreen {
            ScreenHeader(title: "❓ Help & Guide")
            if let help {
                Text(help.intro).font(Theme.crimson(13.6, italic: true)).foregroundStyle(Theme.textSecondary).padding(.bottom, 10)
                FlowRow(spacing: 0) {
                    ForEach(help.tabs, id: \.id) { t in
                        let on = tab == t.id
                        Button {
                            tab = t.id
                            Feedback.announce("\(t.label). \(t.entries.count) topics.")
                        } label: {
                            Text(t.label).font(Theme.cinzel(10.4)).tracking(1).textCase(.uppercase)
                                .foregroundStyle(on ? Theme.gold : Theme.textDim)
                                .padding(.vertical, 10).padding(.horizontal, 10).frame(minHeight: 44)
                                .background(on ? Color(hex: 0x1e1a10) : Color(hex: 0x12100d))
                                .overlay(Rectangle().stroke(Theme.borderDim))
                                .overlay(alignment: .bottom) { if on { Rectangle().fill(Theme.gold).frame(height: 2) } }
                        }
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.bottom, 14)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Help sections")
                ForEach(Array((help.tabs.first { $0.id == tab }?.entries ?? []).enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(e.title).font(Theme.cinzel(14)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                        Text(e.body).font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).lineSpacing(4)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bgPanel).overlay(Rectangle().stroke(Theme.borderDim))
                }
            }
        }
    }
}

// MARK: Credits (#screen-credits)

@MainActor
struct CreditsView: View {
    var body: some View {
        let c = Statics.shared?.credits
        WebScreen {
            ScreenHeader(title: "")
            if let c {
                VStack(spacing: 8) {
                    Text(c.title).font(Theme.decorative(32, black: true)).foregroundStyle(Theme.gold)
                        .accessibilityAddTraits(.isHeader)
                    Text(c.sub).font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)
                ForEach(Array(c.sections.enumerated()), id: \.offset) { _, s in
                    VStack(spacing: 6) {
                        Text(s.title).font(Theme.cinzel(11.2)).tracking(3.5).textCase(.uppercase).foregroundStyle(Theme.goldDim)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(s.lines.enumerated()), id: \.offset) { _, l in
                            if l.kind == "name" {
                                Text(l.text).font(Theme.decorative(20)).foregroundStyle(Theme.ashLight)
                            } else {
                                Text(l.text).font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
            }
        }
        .onAppear {
            Sound.track("credits")
            Feedback.announce("Credits. Dungeon Descent. Created by Leo. Built with Claude. Certified by the DDDI.")
        }
    }
}

// MARK: What's New (#screen-whatsnew)

@MainActor
struct WhatsNewView: View {
    @State private var visible = 10

    var body: some View {
        let versions = Statics.shared?.whatsnew ?? []
        WebScreen {
            ScreenHeader(title: "What's New")
            ForEach(Array(versions.prefix(visible).enumerated()), id: \.offset) { i, v in
                VStack(alignment: .leading, spacing: 6) {
                    Text(v.num).font(Theme.cinzel(14, weight: .semibold)).foregroundStyle(i == 0 ? Theme.gold : Theme.ashLight)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel(v.label.isEmpty ? v.num : v.label)
                    if !v.date.isEmpty {
                        Text(v.date).font(Theme.crimson(13, italic: true)).foregroundStyle(Theme.goldDim)
                    }
                    ForEach(Array(v.changes.enumerated()), id: \.offset) { _, c in
                        Text("• " + c).font(Theme.crimson(13.5)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                    }
                }
                .padding(.vertical, 14).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.bgPanel)
                .overlay(Rectangle().stroke(Theme.borderDim))
                .overlay(alignment: .leading) { Rectangle().fill(i == 0 ? Theme.gold : Theme.borderGlow).frame(width: 3) }
            }
            if versions.count > visible {
                Button("Load More (\(versions.count - visible) remaining)") { visible += 10 }
                    .buttonStyle(WebButtonStyle(kind: .ghost))
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { Feedback.announce("What is New screen. Patch notes for every version.") }
    }
}

/// #whats-new-popup: the newest patch notes, once after each update.
struct WhatsNewPopup: View {
    static let version = "11.7.3"
    static let seenKey = "dd_whats_new_seen"
    let close: () -> Void
    @AccessibilityFocusState private var focus: Bool

    var body: some View {
        let v = Statics.shared?.whatsnew.first
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("🎉 v\(Self.version)").font(Theme.decorative(20)).foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($focus)
                        if let d = v?.date, !d.isEmpty {
                            Text(d).font(Theme.cinzel(11)).tracking(2).foregroundStyle(Theme.textDim).frame(maxWidth: .infinity)
                        }
                        ForEach(Array((v?.changes ?? []).enumerated()), id: \.offset) { _, c in
                            Text("• " + c).font(Theme.crimson(14)).foregroundStyle(Theme.textSecondary).lineSpacing(3)
                        }
                    }
                    .padding(22)
                }
                Button("⚔ Continue", action: close).buttonStyle(WebButtonStyle(kind: .gold))
                    .accessibilityLabel("Continue to the game")
                    .padding([.horizontal, .bottom], 18)
            }
            .frame(maxWidth: 480, maxHeight: 620)
            .background(Color(hex: 0x0a0a0a))
            .overlay(Rectangle().stroke(Color(hex: 0x443300)))
            .padding(24)
        }
        .onAppear {
            Feedback.announce("What is new in version \(Self.version). Press Continue to start playing.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = true }
        }
    }
}
