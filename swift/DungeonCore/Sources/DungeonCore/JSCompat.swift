import Foundation

// Small helpers that reproduce JavaScript's exact behavior, so numbers in the
// Swift version come out identical to the web version.

/// JavaScript `Math.round`: halves round toward +infinity (-2.5 → -2, 2.5 → 3).
@inline(__always)
public func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

/// JavaScript `parseInt(s)`: reads an optional sign and leading digits,
/// ignores anything after them ("12abc" → 12). Returns nil where JS gives NaN.
public func jsParseInt(_ s: String?) -> Int? {
    guard let s else { return nil }
    var chars = Substring(s).drop(while: { $0.isWhitespace })
    var sign = 1
    if let f = chars.first, f == "-" || f == "+" {
        if f == "-" { sign = -1 }
        chars = chars.dropFirst()
    }
    let digits = chars.prefix(while: { $0.isASCII && $0.isNumber })
    guard !digits.isEmpty, let n = Int(digits) else { return nil }
    return sign * n
}
