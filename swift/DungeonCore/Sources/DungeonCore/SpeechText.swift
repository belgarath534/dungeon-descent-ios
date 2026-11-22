import Foundation

/// Text for the Lewis Voice Pack, before it's turned into sounds. Its
/// pronunciation engine read numbers badly: "Floor 21" came out as "floor one"
/// and 3,082 as "three eighty-two" (a player thought they had 382 gold). So
/// every number is written out in words first, in English, the way a person
/// would say it.
public enum SpeechText {
    /// "Floor 21, 3,082 gold, 40% off, the 2nd floor, -5 HP, 1.5x"
    /// → "Floor twenty one, three thousand eighty two gold, forty percent off,
    /// the second floor, minus five HP, one point five x"
    public static func spellNumbers(_ raw: String) -> String {
        // A range between numbers ("20-35 damage") is "twenty to thirty five".
        let text = raw.replacingOccurrences(of: #"(\d)\s*[-–]\s*(\d)"#, with: "$1 to $2", options: .regularExpression)
        let pattern = #"(?<![\d.,])(-)?(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?(%|st|nd|rd|th)?"#
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            func part(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            let digits = (part(2) ?? "").replacingOccurrences(of: ",", with: "")
            var words = say(Int(digits) ?? 0)
            if let suffix = part(4), suffix != "%" { words = ordinal(words) }
            if let frac = part(3) {
                words += " point " + frac.dropFirst().map { say(Int(String($0)) ?? 0) }.joined(separator: " ")
            }
            // A minus sign, not a dash between words ("HP -5", but "2-3 turns").
            if part(1) != nil {
                let before = m.range.location > 0 ? ns.substring(with: NSRange(location: m.range.location - 1, length: 1)) : " "
                words = (before == " " || before == "(" ? "minus " : "") + words
            }
            if part(4) == "%" { words += " percent" }
            // Glued to letters ("x1.5", "Lv5", "3x"): a space either side.
            let start = m.range.location, end = m.range.location + m.range.length
            if start > 0, let c = Character(ns.substring(with: NSRange(location: start - 1, length: 1))) as Character?, c.isLetter { words = " " + words }
            if end < ns.length, let c = Character(ns.substring(with: NSRange(location: end, length: 1))) as Character?, c.isLetter { words += " " }
            out += words
            last = end
        }
        out += ns.substring(from: last)
        return out
    }

    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                               "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    /// A whole number in words ("three thousand eighty two"). Hyphens are left
    /// out: the pronunciation engine reads separate words more reliably.
    public static func say(_ n: Int) -> String {
        if n < 0 { return "minus " + say(-n) }
        if n < 20 { return ones[n] }
        if n < 100 { return tens[n / 10] + (n % 10 > 0 ? " " + ones[n % 10] : "") }
        if n < 1000 { return ones[n / 100] + " hundred" + (n % 100 > 0 ? " " + say(n % 100) : "") }
        for (size, name) in [(1_000_000_000_000, "trillion"), (1_000_000_000, "billion"), (1_000_000, "million"), (1000, "thousand")] where n >= size {
            return say(n / size) + " " + name + (n % size > 0 ? " " + say(n % size) : "")
        }
        return String(n)
    }

    /// "twenty one" → "twenty first".
    static func ordinal(_ words: String) -> String {
        var w = words.split(separator: " ").map(String.init)
        guard let lastWord = w.popLast() else { return words }
        let special = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth",
                       "nine": "ninth", "twelve": "twelfth"]
        let o = special[lastWord] ?? (lastWord.hasSuffix("y") ? String(lastWord.dropLast()) + "ieth" : lastWord + "th")
        return (w + [o]).joined(separator: " ")
    }
}
