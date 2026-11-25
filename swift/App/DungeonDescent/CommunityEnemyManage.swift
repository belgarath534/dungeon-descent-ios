import SwiftUI
import DungeonCore

/// A page title and its line under it.
private func heading(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(Theme.decorative(19.2)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
        Text(subtitle).font(Theme.crimson(13.1, italic: true)).foregroundStyle(Theme.textSecondary)
    }
    .padding(.bottom, 8)
}

/// 12.2: My Enemies. The community enemies you made, each with Edit: rename
/// it, change its description, change its type (fresh stats in that type's
/// range) or re-roll its stats, or delete it from everyone's dungeons.
struct MyEnemiesView: View {
    @EnvironmentObject var game: GameModel
    @ObservedObject private var pool = CommunityEnemyStore.shared
    let close: () -> Void
    @State private var loading = true
    @State private var editing: CommunityEnemies.Entry?

    private var username: String? { GlobalChat(store: game.store).username }

    var body: some View {
        WebScreen {
            Button("← Back to Community Enemies") { close() }
                .buttonStyle(BackButtonStyle())
                .accessibilityLabel("Back to community enemies")
            heading("My Enemies", "The enemies you made. Rename them, make them stronger, or delete them.")
            if loading {
                Text("Finding your enemies...").font(Theme.cinzel(10.4)).foregroundStyle(Theme.textDim).padding(20)
            } else if pool.mine.isEmpty {
                Text("You haven't made any enemies yet, or they were made under a different name. Enemies made from this version on are always yours to edit.")
                    .font(Theme.crimson(14, italic: true)).foregroundStyle(Theme.textSecondary).padding(.vertical, 10)
            }
            ForEach(pool.mine) { e in
                Button { editing = e } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(e.icon) \(e.name)" as String).font(Theme.cinzel(13)).foregroundStyle(Theme.textPrimary)
                        Text("\(e.type) · HP \(e.hp) · ATK \(e.atk) · DEF \(e.def) · ⚔ \(e.kills) kills" as String)
                            .font(Theme.cinzel(9.3)).foregroundStyle(Color(hex: 0x909090))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Theme.bgStone).overlay(Rectangle().stroke(Color(hex: 0x554488)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(e.name). \(e.type), HP \(e.hp), attack \(e.atk), defense \(e.def). \(e.kills) kills." as String)
            }
        }
        .task {
            await pool.loadMine(username: username)
            loading = false
            Feedback.announce(pool.mine.isEmpty ? "My Enemies. You have no enemies to edit yet."
                              : "My Enemies. \(pool.mine.count). Choose one to edit it.")
        }
        .fullScreenCover(item: $editing) { e in
            EditEnemyView(enemy: e, username: username) { editing = nil }
        }
    }
}

struct EditEnemyView: View {
    @ObservedObject private var pool = CommunityEnemyStore.shared
    let enemy: CommunityEnemies.Entry
    let username: String?
    let close: () -> Void
    @State private var name = ""
    @State private var desc = ""
    @State private var kind = CommunityEnemies.Kind.common
    @State private var preview: CommunityEnemies.Entry?
    @State private var message = ""
    @State private var busy = false
    @State private var confirmingDelete = false
    @State private var dice = SystemDice()

    var body: some View {
        let shown = preview ?? enemy
        WebScreen {
            Button("← Back to My Enemies") { close() }
                .buttonStyle(BackButtonStyle())
                .accessibilityLabel("Back to my enemies without saving")
            heading("Edit \(enemy.name)", "Changes reach every player's dungeon.")
            label("Name")
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Enemy name")
                .onChange(of: name) { v in if v.count > 30 { name = String(v.prefix(30)) } }
            label("Description")
            TextField("Description", text: $desc, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5).accessibilityLabel("Enemy description")
                .onChange(of: desc) { v in if v.count > 200 { desc = String(v.prefix(200)) } }
            label("Type")
            Picker("Type", selection: $kind) {
                ForEach(CommunityEnemies.Kind.allCases, id: \.self) { k in Text(k.label).tag(k) }
            }
            .pickerStyle(.menu).accessibilityLabel("Enemy type. A new type rolls new stats in that type's range.")
            .onChange(of: kind) { _ in roll(reroll: false) }
            Text("Stats: HP \(shown.hp) · ATK \(shown.atk) · DEF \(shown.def)" as String)
                .font(Theme.cinzel(11)).foregroundStyle(Theme.gold).padding(.top, 6)
                .accessibilityLabel("Stats. HP \(shown.hp), attack \(shown.atk), defense \(shown.def)." as String)
            Button("🎲 Re-roll Stats") { roll(reroll: true) }
                .buttonStyle(WebButtonStyle(kind: .ghost)).frame(maxWidth: .infinity)
                .accessibilityLabel("Re-roll stats within this type's range")
            Button(busy ? "Saving..." : "💾 Save Changes") { save() }
                .buttonStyle(WebButtonStyle(kind: .gold)).frame(maxWidth: .infinity).disabled(busy)
            if !message.isEmpty {
                Text(message).font(Theme.cinzel(10.9)).foregroundStyle(Color(hex: 0xa0d4a0))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            Button("🗑 Delete This Enemy") { confirmingDelete = true }
                .buttonStyle(WebButtonStyle(kind: .red)).frame(maxWidth: .infinity).padding(.top, 20)
                .accessibilityLabel("Delete \(enemy.name) from every dungeon")
        }
        .onAppear {
            name = enemy.name
            desc = enemy.desc
            kind = CommunityEnemies.Kind(rawValue: enemy.type) ?? .common
            Feedback.announce("Edit \(enemy.name).", after: 0.3)
        }
        .alert("Delete \(enemy.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It will leave every player's dungeon. This can't be undone from the game.")
        }
    }

    private func label(_ t: String) -> some View {
        Text(t.uppercased()).font(Theme.cinzel(9.6)).tracking(2).foregroundStyle(Theme.goldDim).padding(.top, 8)
            .accessibilityHidden(true)
    }

    /// Rolls the preview's stats (a new type always rolls fresh ones).
    private func roll(reroll: Bool) {
        let r = CommunityEnemies.edit(preview ?? enemy, name: name.isEmpty ? enemy.name : name, desc: desc,
                                      kind: kind, reroll: reroll, dice: &dice)
        guard r.problem == nil else { return }
        var p = preview ?? enemy
        p.type = r.entry.type; p.icon = r.entry.icon; p.hp = r.entry.hp; p.atk = r.entry.atk; p.def = r.entry.def
        preview = p
        Sound.sfx("sfx-select")
        Feedback.announce("New stats. HP \(p.hp), attack \(p.atk), defense \(p.def). Save to keep them.")
    }

    private func save() {
        var base = preview ?? enemy
        base.type = kind.rawValue
        let r = CommunityEnemies.edit(base, name: name, desc: desc, kind: kind, reroll: false, dice: &dice)
        if let p = r.problem { message = p; Feedback.announce(p); return }
        busy = true
        Task {
            let err = await pool.save(r.entry, username: username)
            busy = false
            if let err { message = err; Feedback.announce(err); return }
            Sound.sfx("sfx-confirm")
            message = "Saved. \(r.entry.name) is updated in every dungeon."
            Feedback.announce(message)
        }
    }

    private func remove() {
        busy = true
        Task {
            let err = await pool.delete(enemy, username: username)
            busy = false
            if let err { message = err; Feedback.announce(err); return }
            Feedback.announce("\(enemy.name) has been deleted from every dungeon.")
            close()
        }
    }
}
