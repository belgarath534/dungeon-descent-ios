import SwiftUI
import DungeonCore

/// #spirit-builder-overlay: 25 Soul Fragments make a spirit of your own.
struct SpiritBuilderView: View {
    @EnvironmentObject var game: GameModel
    let onClose: () -> Void
    @State private var name = ""
    @State private var icon = CustomSpirits.icons[0]
    @State private var ability: String?
    @State private var error = ""
    @State private var built: String?

    var body: some View {
        let frags = CustomSpirits.fragments(game.store)
        WebScreen {
            HStack {
                Text("🔮 Spirit Builder").font(Theme.decorative(18)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("✕ Close") { onClose() }.buttonStyle(WebButtonStyle(kind: .ghost)).accessibilityLabel("Close spirit builder")
            }
            Text("\(frags) of \(CustomSpirits.cost) Soul Fragments collected.")
                .font(Theme.cinzel(11)).foregroundStyle(Color(hex: 0xaa88ff))
            if let built {
                Text(built).font(Theme.crimson(15, italic: true)).foregroundStyle(Theme.textSecondary)
                Button("Done") { onClose() }.buttonStyle(WebButtonStyle(kind: .gold))
            } else if frags < CustomSpirits.cost {
                notEnough(frags)
            } else {
                form
            }
        }
        .onAppear {
            Feedback.announce(frags >= CustomSpirits.cost
                ? "Spirit Builder. You have \(frags) fragments. Name your spirit, choose an icon and ability, then press Build."
                : "Spirit Builder. \(frags) of 25 fragments. Keep killing enemies.", after: 0.4)
        }
    }

    private func notEnough(_ frags: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Soul Fragments drop from 40% of the enemies you defeat. Collect 25 to forge a spirit companion of your own — any character can take it into the dungeon.")
                .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: 0x111111))
                    Rectangle().fill(Color(hex: 0xaa44ff)).frame(width: g.size.width * CGFloat(frags) / CGFloat(CustomSpirits.cost))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            Text("\(frags) of 25. \(CustomSpirits.cost - frags) more needed.").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NAME").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            TextField("Name your spirit...", text: $name)
                .font(Theme.cinzel(13)).padding(10)
                .background(Color(hex: 0x0a0a0a)).overlay(Rectangle().stroke(Color(hex: 0x333333)))
                .onChange(of: name) { v in if v.count > 24 { name = String(v.prefix(24)) } }
                .accessibilityLabel("Spirit name")
            Text("ICON").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            FlowRow(spacing: 6) {
                ForEach(CustomSpirits.icons, id: \.self) { i in
                    Button(i) { icon = i; Feedback.announce("Icon \(i) selected.") }
                        .font(.system(size: 26)).padding(8)
                        .background(i == icon ? Theme.gold.opacity(0.15) : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(i == icon ? Theme.gold : Theme.borderDim, lineWidth: 2))
                        .accessibilityLabel("Select icon \(i)")
                        .accessibilityAddTraits(i == icon ? .isSelected : [])
                }
            }
            Text("ABILITY").font(Theme.cinzel(10.4)).tracking(2).foregroundStyle(Theme.goldDim)
            ForEach(CustomSpirits.abilities) { a in
                let on = ability == a.id
                Button { ability = a.id; Feedback.announce("\(a.label) selected.") } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.label).font(Theme.cinzel(12.5)).foregroundStyle(on ? Theme.gold : Theme.textSecondary)
                        Text(a.desc).font(Theme.crimson(11.5, italic: true)).foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 12)
                    .background(on ? Theme.gold.opacity(0.08) : .clear)
                    .overlay(Rectangle().stroke(on ? Theme.gold : Theme.borderDim))
                }
                .accessibilityLabel("\(a.label). \(a.desc)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            if !error.isEmpty { Text(error).font(Theme.cinzel(10.4)).foregroundStyle(Color(hex: 0xff5555)) }
            Button("🔮 Build Spirit — 25 Fragments") { build() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity)
                .accessibilityLabel("Build spirit for 25 soul fragments")
        }
    }

    private func build() {
        let a = ability ?? ""
        if let p = CustomSpirits.build(name: name, icon: icon, ability: a, store: game.store) {
            error = p
            Feedback.announce(p)
            return
        }
        game.achievements.increment("customSpiritBuilt")
        _ = game.achievements.check()
        Sound.sfx("sfx-unlock")
        let desc = CustomSpirits.abilities.first { $0.id == a }?.desc ?? ""
        let msg = "Spirit created! \(icon) \(name.trimmingCharacters(in: .whitespaces)). \(desc) Every character can pick it from the spirit picker. It wakes at level 5."
        built = msg
        Feedback.announce(msg)
    }
}
