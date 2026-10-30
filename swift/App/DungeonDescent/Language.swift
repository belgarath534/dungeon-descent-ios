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

    private static var bundle: Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// The translation of a whole line, or the line itself.
    static func t(_ s: String) -> String { code == "en" ? s : bundle.localizedString(forKey: s, value: s, table: nil) }

    /// Picks a language. Screens switch at once; the save keeps dd_lang like the web version.
    static func set(_ code: String, store: GameStore) {
        UserDefaults.standard.set(code, forKey: key)
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        store.setItem("dd_lang", Self.code)
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
