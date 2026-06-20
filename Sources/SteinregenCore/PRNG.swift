// PRNG.swift
// Deterministische Pseudo-Zufallsgeneratoren.
//
// WICHTIG (siehe CLAUDE.md §Determinismus): Der gesamte Core darf KEINEN globalen
// Zufall (Foundation `random`, `arc4random`, `SystemRandomNumberGenerator`) und KEINE
// Wanduhr verwenden. Jede Zufallsentscheidung laeuft ueber einen dieser injizierten,
// seed-bestimmten Generatoren — gleicher Seed ⇒ exakt gleicher Spielverlauf.

/// 64-Bit-Zustands-Generator (SplitMix64). Einfach und schnell; dient auch dazu,
/// den groesseren xoshiro-Generator mit einem Seed zu „verteilen".
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

/// 256-Bit-Zustands-Generator (xoshiro256** 1.0). Das ist der eigentliche Spiel-PRNG —
/// er bestimmt die Farbfolge der fallenden Steine und das Auftauchen des Magic Jewels.
public struct Xoshiro256StarStar: RandomNumberGenerator, Sendable {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    public init(seed: UInt64) {
        // Seed ueber SplitMix64 auf 256 Bit Zustand „aufblasen".
        var sm = SplitMix64(seed: seed)
        self.s0 = sm.next()
        self.s1 = sm.next()
        self.s2 = sm.next()
        self.s3 = sm.next()

        // Der Zustand darf nicht komplett 0 sein.
        if s0 == 0 && s1 == 0 && s2 == 0 && s3 == 0 {
            s0 = 1
        }
    }

    public mutating func next() -> UInt64 {
        let result = rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17

        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3

        s2 ^= t
        s3 = rotl(s3, 45)

        return result
    }

    @inline(__always)
    private func rotl(_ x: UInt64, _ k: Int) -> UInt64 {
        return (x << k) | (x >> (64 - k))
    }
}
