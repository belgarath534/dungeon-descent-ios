import Foundation

/// Source of randomness for the game. Real play uses the system generator;
/// tests use a seeded one so the same fight plays out the same way every time.
public protocol Dice {
    /// Random whole number from the range, both ends included (web version's `rnd(a, b)`).
    mutating func roll(_ range: ClosedRange<Int>) -> Int
    /// True with the given probability (web version's `Math.random() < p`).
    mutating func chance(_ p: Double) -> Bool
}

public struct SystemDice: Dice {
    private var rng = SystemRandomNumberGenerator()
    public init() {}
    public mutating func roll(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
    public mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }
}

/// Repeatable dice (SplitMix64). Same seed, same rolls.
public struct SeededDice: Dice {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    public mutating func roll(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(unit() * Double(range.count))
    }

    public mutating func chance(_ p: Double) -> Bool { unit() < p }
}

/// Dice that return fixed answers, for tests that need an exact outcome.
public struct LoadedDice: Dice {
    public var rolls: [Int]
    public var chances: [Bool]
    public init(rolls: [Int] = [], chances: [Bool] = []) {
        self.rolls = rolls
        self.chances = chances
    }
    public mutating func roll(_ range: ClosedRange<Int>) -> Int {
        let r = rolls.isEmpty ? range.lowerBound : rolls.removeFirst()
        return min(max(r, range.lowerBound), range.upperBound)
    }
    public mutating func chance(_ p: Double) -> Bool {
        if p >= 1 { return true }
        if p <= 0 { return false }
        return chances.isEmpty ? false : chances.removeFirst()
    }
}
