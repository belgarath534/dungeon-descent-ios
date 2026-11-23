import Foundation

/// 12.1: the web version's secret console codes, typed (or spoken) in the
/// Command Center. Only the fun ones: codes that gave gold, trophies or
/// unlocked dungeons aren't here (App Store rules on codes that unlock things).
public enum SecretCodes {
    /// Chaos Mode (the Konami code): each kill's gold is a hundredth or
    /// twenty times, and each enemy is a third, normal or three times as
    /// strong. Set by the app from dd_chaos_mode.
    nonisolated(unsafe) public static var chaos = false

    public static func isChaos(_ store: GameStore) -> Bool { store.getItem("dd_chaos_mode") == "1" }

    public static func setChaos(_ on: Bool, _ store: GameStore) {
        if on { store.setItem("dd_chaos_mode", "1") } else { store.removeItem("dd_chaos_mode") }
        chaos = on
    }

    /// What a code does, or nil when it isn't one (the Command Center goes on).
    public static func run(_ raw: String, store: GameStore, now: Date = Date(), calendar: Calendar = .current) -> String? {
        let code = raw.uppercased().filter { !$0.isWhitespace }
        let md = calendar.dateComponents([.month, .day], from: now)
        func minion(_ id: String, _ name: String, _ icon: String, _ atk: Int) -> String {
            var list = Home.minions(store)
            guard !list.contains(where: { $0.id == id }) else { return "\(name) is already one of your minions." }
            guard list.count < Home.maxMinions else { return "You already have \(Home.maxMinions) minions. Release one at Home first." }
            list.append(Minion(id: id, name: name, icon: icon, atk: atk, tier: "elite", capturedOn: (now.timeIntervalSince1970 * 1000).rounded()))
            Home.saveMinions(list, store)
            return "\(icon) \(name) joins your minions."
        }
        switch code {
        case "UUDDLRLRBA", "KONAMI":
            setChaos(true, store)
            return "THE KONAMI CODE. You know the old ways. CHAOS MODE ACTIVATED. Nothing is safe. Everything is possible. Enemies and gold are unpredictable. Type CHAOS to turn it off."
        case "CHAOS":
            let on = !isChaos(store)
            setChaos(on, store)
            return on ? "CHAOS MODE ACTIVATED. Enemies and gold are unpredictable." : "Chaos mode disabled."
        case "JULIO":
            return "... He was never really gone. JULIO has been spotted."
        case "WITNESS":
            return "It was always watching. " + minion("the-witness", "The Witness", "🦈", 12)
        case "4":
            guard md.month == 7, md.day == 4 else { return "This code only works on the Fourth of July." }
            return "Happy Fourth of July. A patriot answers your call. " + minion("liberty-eagle", "Liberty Eagle", "🦅", 18)
        case "BRAZIL":
            guard md.month == 9, md.day == 7 else { return "This code only works on September 7th, Brazil Independence Day." }
            return "🇧🇷 INDEPENDÊNCIA DO BRASIL! 7 de Setembro de 1822. Ordem e Progresso."
        case "IAMLEO", "GIVEGOLD", "TROPHIES", "ABYSSAL", "INFERNAL":
            return "That code belongs to the old console. It doesn't work here."
        case "SECRETS", "CODES":
            return "Some codes are famous. Some are personal. Some are obvious. Some only work on certain days."
        default:
            return nil
        }
    }

    /// Chaos gold for one kill.
    static func gold(_ g: Int, dice: inout some Dice) -> Int {
        guard chaos else { return g }
        return dice.chance(0.5) ? max(1, g / 100) : g * 20
    }

    /// Chaos strength for one enemy (not bosses).
    static func shape(_ e: inout Enemy, dice: inout some Dice) {
        guard chaos, !e.isBoss else { return }
        let r = dice.roll(0...2)
        let m = r == 0 ? 0.3 : r == 1 ? 1.0 : 3.0
        guard m != 1 else { return }
        e.hp = max(1, jsRound(Double(e.hp) * m))
        e.maxHp = e.hp
        let lo = max(1, jsRound(Double(e.atk.lowerBound) * m)), hi = max(1, jsRound(Double(e.atk.upperBound) * m))
        e.atk = lo...max(lo, hi)
    }
}
