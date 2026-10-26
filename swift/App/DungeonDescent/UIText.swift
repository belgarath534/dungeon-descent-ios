import Foundation
import DungeonCore

/// The dungeon screen's text from the web version (DEATH_LINES, DEFEAT_QUOTES,
/// CLOSING_LINES), pulled by swift/tools/extract-game-data.js into uitext.json.
struct UIText: Decodable {
    let deathLines: [String: [String: [String]]]
    let defeatQuotes: [String: [String]]
    let nightmareDefeatQuotes: [String]
    let closingLines: [String: [String: String]]

    static let shared: UIText = {
        guard let url = Bundle.main.url(forResource: "uitext", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode(UIText.self, from: data) else {
            return UIText(deathLines: [:], defeatQuotes: [:], nightmareDefeatQuotes: [], closingLines: [:])
        }
        return t
    }()

    /// getDeathCinematicLine: special killers in The Hollow, bosses, then by depth.
    func deathLine(killer: String, floor: Int, dungeon: String) -> String {
        let lines = deathLines[dungeon] ?? deathLines["Crypt of Malachar"] ?? [:]
        if dungeon == "The Hollow" {
            let special = ["Medusa": "medusa", "Lord Phorcys": "lord_phorcys", "The Weeping Child": "weeping_child",
                           "The Music Box": "music_box", "The Oldest Guest": "oldest_guest"]
            if let key = special[killer], let l = lines[key]?.randomElement() { return l }
        }
        let bosses = ["Malachar", "The Eternal Pyre", "The Eternal Winter", "The Last Resident",
                      "The House Itself", "The Grieving One", "The Head Archivist", "The Void Below"]
        if bosses.contains(where: { killer.contains($0) }), let l = lines["boss"]?.randomElement() { return l }
        let pool = floor <= 3 ? lines["early"] : floor <= 6 ? lines["mid"] : lines["late"]
        return pool?.randomElement() ?? "The dungeon claims another."
    }

    func closingLine(dungeon: String, cls: String) -> String {
        (closingLines[dungeon] ?? closingLines["Crypt of Malachar"])?[cls]
            ?? "You descended. You survived. The dungeon remembers."
    }
}
