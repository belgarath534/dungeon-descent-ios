import SwiftUI
import DungeonCore

/// Holds the Blacksmith's `Forge` and writes every change back: into the run
/// in a dungeon, or into the saved gear and stash on the main menu.
@MainActor
final class BlacksmithModel: ObservableObject {
    @Published var forge: Forge
    @Published var message = ""
    let game: GameModel
    let fromMenu: Bool
    private let commit: (Forge, Int) -> Void
    private var sp: Int
    private let maxSp: Int

    init(game: GameModel, forge: Forge, fromMenu: Bool, sp: Int = 0, maxSp: Int = 0, commit: @escaping (Forge, Int) -> Void) {
        self.game = game
        self.forge = forge
        self.fromMenu = fromMenu
        self.sp = sp
        self.maxSp = maxSp
        self.commit = commit
    }

    /// On the main menu: the saved gear, the stash and your global gold.
    static func menu(_ game: GameModel) -> BlacksmithModel {
        let stash = game.globalInventory
        let f = Forge(weapon: stash.equippedWeapon, armor: stash.equippedArmor, bag: stash.items, gold: game.wallet.gold, prof: nil)
        return BlacksmithModel(game: game, forge: f, fromMenu: true) { f, _ in
            stash.save(f.bag)
            stash.saveEquipped(weapon: f.weapon, armor: f.armor)
        }
    }

    private func done(_ r: (ok: Bool, message: String), sound: String = "sfx-unlock") {
        message = r.message
        if r.ok {
            Sound.sfx(sound)
            commit(forge, sp)
            forge.stashed = []
            _ = game.achievements.check()
        }
        Feedback.announce(r.message)
    }

    func upgrade(_ slot: Blacksmith.Slot) { done(Blacksmith.upgrade(slot, &forge, wallet: game.wallet, store: game.store)) }
    func buyWeapon(_ i: Item) { done(Blacksmith.buyWeapon(i, &forge, wallet: game.wallet, store: game.store), sound: "sfx-purchase") }
    /// 12.2: the Mountainbreaker, from 5 Heartstone Shards.
    /// Saved like a bought weapon: into the bag and the saved stash.
    func forgeMountainbreaker() {
        var bag: [Item]? = forge.bag
        let r = Mountainbreaker.forge(store: game.store, bag: &bag)
        if r.ok, let b = bag {
            forge.bag = b
            forge.stashed.append(Mountainbreaker.weapon)
        }
        done(r, sound: "sfx-unlock")
    }
    /// 12.2.1: a forged Mountainbreaker that went missing comes back.
    func recoverMountainbreaker() {
        let r = Mountainbreaker.recover(store: game.store)
        if r.ok { forge.bag.append(Mountainbreaker.recovered) }
        done(r, sound: "sfx-unlock")
    }
    func buyArmor(_ i: Item) { done(Blacksmith.buyArmor(i, &forge, wallet: game.wallet), sound: "sfx-purchase") }
    func sell(_ index: Int) { done(Blacksmith.sell(at: index, &forge, wallet: game.wallet, store: game.store), sound: "sfx-purchase") }
    func repair() { done(Blacksmith.repair(&forge, wallet: game.wallet)) }

    func reforge() {
        var d = SystemDice()
        done(Blacksmith.reforge(&forge, wallet: game.wallet, dice: &d))
    }

    func raiseRarity() {
        var d = SystemDice()
        done(Blacksmith.raiseRarity(&forge, wallet: game.wallet, dice: &d))
    }

    func equip(_ index: Int) {
        let msg = Blacksmith.equip(at: index, &forge, sp: &sp, maxSp: maxSp)
        done((true, msg), sound: "sfx-select")
    }

    func unequip(_ slot: Blacksmith.Slot) { done((true, Blacksmith.unequip(slot, &forge)), sound: "sfx-select") }
}
