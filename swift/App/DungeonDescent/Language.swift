import SwiftUI
import Combine
import DungeonCore

/// The game's language (setLanguage, dd_lang): English or Portuguese, or
/// whatever the iPhone is set to. The Portuguese comes from the web version's
/// tables (Localizable.xcstrings, made by swift/tools/extract-translations.js);
/// text that isn't in them yet stays in English.
enum Language {
    static let key = "swift_language"
    static let choices: [(code: String, label: String)] = [("", "📱 Device language"), ("en", "🇬🇧 English"), ("pt-BR", "🇧🇷 Português")]

    /// "en", "pt-BR", or "" to follow the iPhone.
    static var choice: String { UserDefaults.standard.string(forKey: key) ?? "" }

    /// The language actually in use.
    static var code: String {
        if !choice.isEmpty { return choice }
        return (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("pt") ? "pt-BR" : "en"
    }

    static var locale: Locale { Locale(identifier: code) }

    private static var cached: (code: String, bundle: Bundle)?

    private static var bundle: Bundle {
        let c = code
        if let b = cached, b.code == c { return b.bundle }
        let b = Bundle.main.path(forResource: c, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        cached = (c, b)
        return b
    }

    /// The translation of a whole line, or the line itself. Lines with numbers
    /// and names in them go through `Patterns`; a line made of several
    /// sentences is translated a sentence at a time.
    static func t(_ s: String) -> String {
        guard code == "en" ? false : !s.isEmpty else { return s }
        if let hit = memo[s] { return hit }
        let out = translate(s)
        if memo.count > 4000 { memo.removeAll() }
        memo[s] = out
        return out
    }

    private static var memo: [String: String] = [:]

    private static func exact(_ s: String) -> String? {
        let v = bundle.localizedString(forKey: s, value: "\u{0}", table: nil)
        return v == "\u{0}" ? nil : v
    }

    private static func translate(_ s: String) -> String {
        if let v = exact(s) { return v }
        if let v = Patterns.apply(s, part: { exact($0) ?? $0 }) { return v }
        // Several sentences: each on its own.
        let parts = s.split(separator: " ", omittingEmptySubsequences: false).reduce(into: [""]) { acc, w in
            let last = acc[acc.count - 1]
            acc[acc.count - 1] = last.isEmpty ? String(w) : last + " " + w
            if let c = w.last, ".!?".contains(c) { acc.append("") }
        }.filter { !$0.isEmpty }
        guard parts.count > 1 else { return s }
        return parts.map { p in exact(p) ?? Patterns.apply(p, part: { exact($0) ?? $0 }) ?? p }.joined(separator: " ")
    }

    /// Picks a language. Screens switch at once; the save keeps dd_lang like the web version.
    static func set(_ code: String, store: GameStore) {
        UserDefaults.standard.set(code, forKey: key)
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        store.setItem("dd_lang", Self.code)
        memo.removeAll()
        changed.send()
    }

    /// Tells the root view to redraw in the new language.
    static let changed = PassthroughSubject<Void, Never>()
}

/// #settings-panel-language
struct LanguagePanel: View {
    @EnvironmentObject var game: GameModel
    @State private var choice = Language.choice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🌍 Language").font(Theme.decorative(17.6)).foregroundStyle(Theme.gold).accessibilityAddTraits(.isHeader)
            Text("Game Language").font(Theme.cinzel(13)).foregroundStyle(Theme.ashLight)
            ForEach(Language.choices, id: \.code) { c in
                Button(c.label) {
                    choice = c.code
                    Language.set(c.code, store: game.store)
                    Feedback.announce(Language.t(c.code == "pt-BR" ? "Language set to Portuguese." : "Language set to English."))
                }
                .buttonStyle(ToggleButtonStyle(on: choice == c.code))
                .accessibilityAddTraits(choice == c.code ? .isSelected : [])
            }
            Text("Most of the game is translated from the web version's Portuguese. Newer text stays in English until it's translated.")
                .font(Theme.crimson(12, italic: true)).foregroundStyle(Theme.textDim)
        }
    }
}

// Text, buttons and VoiceOver labels made from a String (rather than a
// literal, which SwiftUI already looks up) go through the translations too,
// so menus, notes and headings built in code show in Portuguese.
extension Text {
    @_disfavoredOverload
    init(_ content: String) { self.init(verbatim: Language.t(content)) }
}

extension Button where Label == Text {
    @_disfavoredOverload
    init(_ title: String, action: @escaping () -> Void) {
        self.init(action: action) { Text(verbatim: Language.t(title)) }
    }
}

extension View {
    @_disfavoredOverload
    func accessibilityLabel(_ label: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityLabel(Text(verbatim: Language.t(label)))
    }

    @_disfavoredOverload
    func accessibilityHint(_ hint: String) -> ModifiedContent<Self, AccessibilityAttachmentModifier> {
        accessibilityHint(Text(verbatim: Language.t(hint)))
    }
}

/// Portuguese for lines with numbers and names in them. Each English
/// template's {0}, {1} … match anything; names are looked up on their own.
enum Patterns {
    static let pt: [(String, String)] = [
        ("A {0} attacks! {1} HP.", "Um {0} ataca! {1} de HP."),
        ("{0} A {1} attacks! {2} HP.", "{0} Um {1} ataca! {2} de HP."),
        ("Elite enemy! {0}. {1} {2} HP.", "Inimigo elite! {0}. {1} {2} de HP."),
        ("You attack for {0} damage.", "Você ataca causando {0} de dano."),
        ("CRITICAL HIT! You strike for {0} damage!", "ACERTO CRÍTICO! Você golpeia causando {0} de dano!"),
        ("Heavy strike lands for {0} damage!", "O golpe pesado acerta causando {0} de dano!"),
        ("You defend, dealing {0} and bracing for the counter.", "Você se defende, causa {0} e se prepara para o contra-ataque."),
        ("{0} attacks for {1} damage.", "{0} ataca causando {1} de dano."),
        ("{0} strikes for {1} — you absorb {2}. You take {3} damage.", "{0} golpeia causando {1} — você absorve {2}. Você sofre {3} de dano."),
        ("{0} misses you!", "{0} erra você!"),
        ("{0} cannot act this turn!", "{0} não pode agir neste turno!"),
        ("You avoid {0}'s attack completely!", "Você desvia completamente do ataque de {0}!"),
        ("{0} takes {1} damage over time. ({2} turns left)", "{0} sofre {1} de dano contínuo. ({2} turnos restantes)"),
        ("{0} is defeated! You gain {1} gold and {2} XP.", "{0} foi derrotado! Você ganha {1} de ouro e {2} de XP."),
        ("{0} defeated.", "{0} derrotado."),
        ("{0} falls!", "{0} cai!"),
        ("☠ {0} falls!", "☠ {0} cai!"),
        ("{0} damage is reflected back at {1}!", "{0} de dano é refletido de volta em {1}!"),
        ("Your shield absorbs {0}. You take {1} damage.", "Seu escudo absorve {0}. Você sofre {1} de dano."),
        ("Your shield absorbs all {0} damage!", "Seu escudo absorve todos os {0} de dano!"),
        ("You regenerate {0} HP.", "Você regenera {0} de HP."),
        ("Level up! You are now level {0}. You have {1} level points to spend.", "Subiu de nível! Agora você está no nível {0}. Você tem {1} pontos de nível para gastar."),
        ("Level up! You are now level {0}. You have {1} Level Points. Spend them to increase your stats. Unspent points carry over.", "Subiu de nível! Agora você está no nível {0}. Você tem {1} Pontos de Nível. Gaste-os para melhorar seus atributos. Pontos não gastos são mantidos."),
        ("Floor {0} complete.", "Andar {0} concluído."),
        ("Floor {0}: {1}. {2} lives.", "Andar {0}: {1}. {2} vidas."),
        ("Floor {0}: {1}. {2} life.", "Andar {0}: {1}. {2} vida."),
        ("Floor {0} · Room {1}", "Andar {0} · Sala {1}"),
        ("You descend to floor {0}: {1}.", "Você desce para o andar {0}: {1}."),
        ("Descended into {0} on {1} difficulty.", "Desceu em {0} na dificuldade {1}."),
        ("Run resumed on floor {0}. HP {1} of {2}.", "Partida retomada no andar {0}. HP {1} de {2}."),
        ("📦 Found: {0}!", "📦 Encontrado: {0}!"),
        ("📦 Material dropped: {0}!", "📦 Material obtido: {0}!"),
        ("🧪 Found: {0} (Alchemy ingredient)", "🧪 Encontrado: {0} (ingrediente de alquimia)"),
        ("✨ Starting skill: {0}. {1}", "✨ Habilidade inicial: {0}. {1}"),
        ("✨ You unlocked {0}. {1}", "✨ Você desbloqueou {0}. {1}"),
        ("You unlocked: {0}. {1} Continuing your descent.", "Você desbloqueou: {0}. {1} Continuando sua descida."),
        ("You chose {0}. {1}", "Você escolheu {0}. {1}"),
        ("👾 {0} fights beside you.", "👾 {0} luta ao seu lado."),
        ("👾 {0} attacks for {1} damage!", "👾 {0} ataca causando {1} de dano!"),
        ("{0} rises before you. {1} HP.", "{0} se ergue diante de você. {1} de HP."),
        ("{0} activated. They will fight alongside you.", "{0} ativado. Ele lutará ao seu lado."),
        ("{0} released.", "{0} libertado."),
        ("🪤 {0} captured as a minion!", "🪤 {0} capturado como lacaio!"),
        ("You already have a {0} as a minion.", "Você já tem um {0} como lacaio."),
        ("🎆 You launch fireworks into the night sky! +{0} XP", "🎆 Você lança fogos de artifício no céu noturno! +{0} de XP"),
        ("💥 The sticky bomb explodes for {0} damage!", "💥 A bomba adesiva explode causando {0} de dano!"),
        ("A creature stirs — {0}, unleashed by {1}.", "Uma criatura se agita — {0}, liberada por {1}."),
        ("Defeated. All lives lost. {0} fell on floor {1}.", "Derrotado. Todas as vidas perdidas. {0} caiu no andar {1}."),
        ("You died. {0} lives remaining. Restored to 40 percent health.", "Você morreu. {0} vidas restantes. Restaurado para 40 por cento da vida."),
        ("You died. {0} life remaining. Restored to 40 percent health.", "Você morreu. {0} vida restante. Restaurado para 40 por cento da vida."),
        ("You have {0} gold.", "Você tem {0} de ouro."),
        ("{0} of {1} Soul Fragments collected.", "{0} de {1} Fragmentos de Alma coletados."),
        ("⚔ {0} players online", "⚔ {0} jogadores online"),
        ("⚔ {0} player online", "⚔ {0} jogador online"),
        ("Phase {0} of {1}", "Fase {0} de {1}"),
        ("Lv {0} / {1}", "Nv {0} / {1}"),
    ]

    private static let compiled: [(NSRegularExpression, String, Int)] = pt.compactMap { en, out in
        var rx = NSRegularExpression.escapedPattern(for: en)
        var n = 0
        while let r = rx.range(of: "\\{\(n)\\}") ?? rx.range(of: "\\{\(n)}") ?? rx.range(of: "{\(n)}") {
            rx.replaceSubrange(r, with: "(.+?)")
            n += 1
        }
        guard let re = try? NSRegularExpression(pattern: "^" + rx + "$", options: [.dotMatchesLineSeparators]) else { return nil }
        return (re, out, n)
    }

    /// The Portuguese line, or nil when no template fits.
    static func apply(_ s: String, part: (String) -> String) -> String? {
        let ns = s as NSString
        for (re, out, n) in compiled {
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
            var line = out
            for i in 0..<n {
                let piece = ns.substring(with: m.range(at: i + 1))
                line = line.replacingOccurrences(of: "{\(i)}", with: part(piece))
            }
            return line
        }
        return nil
    }
}
