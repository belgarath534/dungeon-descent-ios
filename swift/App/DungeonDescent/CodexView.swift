import SwiftUI
import DungeonCore

/// The web version's #screen-codex: world lore, enemy lore and artifacts,
/// each unlocked by something done in the game.
@MainActor
struct CodexView: View {
    @EnvironmentObject var game: GameModel
    @State private var tab = "world"

    private var codex: UIText.Codex? { UIText.shared.codex }

    /// Each entry's unlockCondition.
    private func isUnlocked(_ id: String) -> Bool {
        let kills = game.bestiaryKills
        let stat = game.achievements.stat
        let store = game.store
        func n(_ key: String) -> Int { jsParseInt(store.getItem(key)) ?? 0 }
        switch id {
        case "codex-w-crypt": return stat("dungeonClears") >= 1 || (kills["crypt-skeleton"] ?? 0) >= 1
        case "codex-w-ashbound": return (kills["ash-cinder-hound"] ?? 0) >= 1 || stat("ashComplete") >= 1
        case "codex-w-frosthold": return (kills["frost-ice-wraith"] ?? 0) >= 1 || stat("frostComplete") >= 1
        case "codex-w-hollow": return (kills["hollow-grief-shade"] ?? 0) >= 1 || stat("hollowComplete") >= 1
        case "codex-w-mine": return stat("mineMaxDepth") >= 5
        case "codex-w-spire": return stat("spireFloor") >= 10
        case "codex-w-dddi": return n("dd_stories_read") >= 3 || stat("storiesRead") >= 3
        case "codex-w-void": return n("dd_void_fragments") >= 5
        case "codex-e-skeletons": return (kills["crypt-skeleton"] ?? 0) >= 10
        case "codex-e-void-wraith": return (kills["void-wraith"] ?? 0) >= 1
        case "codex-e-mine-bosses": return stat("mineMaxDepth") >= 10
        case "codex-a-music-box":
            return game.globalInventory.items.contains { $0.name == "Music Box" || $0.type == "music-box" }
        case "codex-a-void-fragments": return n("dd_void_fragments") >= 1
        case "codex-a-guns":
            guard let s = store.getItem("dd_owned_guns"), let d = s.data(using: .utf8),
                  let guns = try? JSONDecoder().decode([JSONValue].self, from: d) else { return false }
            return !guns.isEmpty
        default: return false
        }
    }

    var body: some View {
        let all = (codex?.world ?? []) + (codex?.enemy ?? []) + (codex?.artifacts ?? [])
        let unlocked = all.filter { isUnlocked($0.id) }.count
        let pct = all.isEmpty ? 0 : jsRound(Double(unlocked) / Double(all.count) * 100)
        let entries = tab == "world" ? codex?.world : tab == "enemy" ? codex?.enemy : codex?.artifacts
        WebScreen {
            ScreenHeader(title: "The Codex")
            Text("Knowledge earned through descent. Lore unlocked through experience.")
                .font(Theme.cinzel(9.6)).foregroundStyle(Color(hex: 0x666666))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                tabButton("world", "📖 World", "World Lore tab")
                tabButton("enemy", "💀 Enemies", "Enemy Lore tab")
                tabButton("artifacts", "⚗️ Artifacts", "Artifacts tab")
            }
            VStack(spacing: 10) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x111111))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0x333333)))
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xc8a832))
                            .frame(width: g.size.width * CGFloat(pct) / 100)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text("\(unlocked) / \(all.count) entries unlocked (\(pct)%)")
                    .font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x555555))
                    .frame(maxWidth: .infinity)
            }
            ForEach(entries ?? []) { e in card(e) }
        }
        .onAppear { Sound.track("codex") }
        .onDisappear { Sound.track("menu") }
    }

    private func tabButton(_ id: String, _ text: String, _ label: String) -> some View {
        let on = tab == id
        return Button {
            Sound.sfx("sfx-select")
            tab = id
        } label: {
            Text(text).font(Theme.cinzel(10.4)).foregroundStyle(on ? Color(hex: 0xc8a832) : Color(hex: 0x666666))
                .frame(maxWidth: .infinity).padding(8)
                .background(on ? Color(hex: 0x1a1000) : Color(hex: 0x0a0800))
                .overlay(Rectangle().stroke(on ? Color(hex: 0xc8a832) : Color(hex: 0x443300)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    @ViewBuilder
    private func card(_ e: UIText.Codex.Entry) -> some View {
        let open = isUnlocked(e.id)
        VStack(alignment: .leading, spacing: 8) {
            if open {
                Text("\(e.icon) \(e.title)").font(Theme.cinzel(12)).foregroundStyle(Color(hex: 0xc8a832))
                    .accessibilityAddTraits(.isHeader)
                Text(e.body).font(Theme.cinzel(9.9)).foregroundStyle(Color(hex: 0xaaaaaa)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("🔒 \(e.unlockHint)").font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0x444444))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(8)
                    .accessibilityLabel("Locked entry. \(e.unlockHint)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0a0800))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(open ? Color(hex: 0x443300) : Color(hex: 0x222222)))
        .accessibilityElement(children: .combine)
    }
}
