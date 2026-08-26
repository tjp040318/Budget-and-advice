import Foundation

/// A small, fast, fully deterministic PRNG (SplitMix64).
///
/// Every random decision in a battle goes through one of these. Two runs with
/// the same seed and the same inputs produce byte-identical event streams, which
/// is what makes replays, arena defence simulation and regression tests possible
/// — and what will let the server re-verify a battle when this goes online.
struct SeededRandom: RandomNumberGenerator, Codable, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform double in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// True with the given probability. Clamped, so a 1.2 chance always lands.
    mutating func chance(_ probability: Double) -> Bool {
        if probability >= 1.0 { return true }
        if probability <= 0.0 { return false }
        return unit() < probability
    }

    /// Uniform double in the closed range.
    mutating func double(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in the closed range.
    mutating func int(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    func pick<T>(_ elements: [T]) -> T? {
        var copy = self
        return copy.pickMutating(elements)
    }

    mutating func pickMutating<T>(_ elements: [T]) -> T? {
        guard !elements.isEmpty else { return nil }
        return elements[int(in: 0...(elements.count - 1))]
    }

    mutating func pick<T>(from elements: [T]) -> T? {
        pickMutating(elements)
    }

    /// Weighted pick. Weights need not sum to 1.
    mutating func pickWeighted<T>(_ elements: [(value: T, weight: Double)]) -> T? {
        let total = elements.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0 else { return elements.first?.value }
        var roll = unit() * total
        for element in elements {
            roll -= max(0, element.weight)
            if roll <= 0 { return element.value }
        }
        return elements.last?.value
    }

    mutating func shuffled<T>(_ elements: [T]) -> [T] {
        var result = elements
        guard result.count > 1 else { return result }
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            let j = int(in: 0...i)
            result.swapAt(i, j)
        }
        return result
    }

    /// A fresh seed derived from the current state, for spawning sub-streams
    /// without disturbing the parent sequence's meaning.
    mutating func derive() -> SeededRandom {
        SeededRandom(seed: next())
    }
}
