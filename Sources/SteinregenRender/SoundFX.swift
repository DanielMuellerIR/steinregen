// SoundFX.swift
// Schmale Audio-Schicht für die Soundeffekte. Reine Präsentation: KEIN Bezug zum
// deterministischen Core (der Zufall hier ist Render-Zufall, kein Core-Zufall).
//
// Es gibt ZWEI in den Einstellungen wählbare Klang-Sets (alle Dateien sind mono
// AAC/.m4a — klein):
//   • „Eigene"   — lokal mit Stable Audio 3 erzeugt (Black-Metal-Ästhetik):
//                  drehen / aufloesen / level (je 1), aufsetzen-1 (kurz, scharfer
//                  Attack), gameover-1…7 (Zufalls-Pool).
//   • „FreeDoom" — die früheren Freedoom-Klänge (BSD-3, siehe FREEDOOM-LICENSE.txt),
//                  jetzt ebenfalls als AAC: dstink / dspstop / dswpnup, Land-Pool
//                  dsgetpow/dsoof/dsswtchn, Game-Over-Pool dspdiehi/dspldeth/dsdorcls.
//
// Land + Game-Over wählen zufällig aus ihrem Pool, aber nie direkt dieselbe Variante
// wie zuletzt. „mundtot" = Ton aus (UserDefaults, geteilt mit Einstellungen + T-Taste).
// Pro Sound ein kleiner Player-Pool, damit schnelle Wiederholungen (Kaskaden) sich
// nicht gegenseitig abschneiden.

import AVFoundation
import Foundation

@MainActor
public enum SoundFX {

    /// UserDefaults-Schlüssel: true = „mundtot" (Ton aus). Default false (Ton an).
    public static let mutedKey = "steinregen.mundtot"
    /// UserDefaults-Schlüssel: gewähltes Klang-Set (Default „eigene").
    public static let setKey = "steinregen.soundset"

    public static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    // MARK: - Klang-Set

    /// Die wählbaren Klang-Sets (in den Einstellungen umschaltbar).
    public enum SoundSet: String, CaseIterable, Identifiable, Sendable {
        case eigene
        case freedoom
        public var id: String { rawValue }
        public var label: String { self == .eigene ? "Steinregen" : "Freedoom" }
    }

    /// Aktuell gewähltes Set (persistiert). Wirkt sofort: jeder Sound liest beim
    /// Abspielen das aktuelle Set.
    public static var soundSet: SoundSet {
        get { SoundSet(rawValue: UserDefaults.standard.string(forKey: setKey) ?? "") ?? .eigene }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: setKey) }
    }

    /// Event→Dateiname-Zuordnung eines Sets (Namen ohne Endung; Dateien als .m4a).
    private struct Mapping {
        let rotate: String, clear: String, levelUp: String
        let land: [String], gameOver: [String]
    }

    private static func mapping(_ set: SoundSet) -> Mapping {
        switch set {
        case .eigene:
            return Mapping(rotate: "drehen", clear: "aufloesen", levelUp: "level",
                           land: ["aufsetzen-1"],
                           gameOver: (1...7).map { "gameover-\($0)" })
        case .freedoom:
            return Mapping(rotate: "dstink", clear: "dspstop", levelUp: "dswpnup",
                           land: ["dsgetpow", "dsoof", "dsswtchn"],
                           gameOver: ["dspdiehi", "dspldeth", "dsdorcls"])
        }
    }

    // MARK: - Spiel-Events

    public static func rotate()   { play(mapping(soundSet).rotate, volume: 0.55) }
    public static func clear()    { play(mapping(soundSet).clear, volume: 0.85) }
    public static func levelUp()  { play(mapping(soundSet).levelUp, volume: 0.9) }

    /// Aufsetzen: oft gehörter Klang → zufällig aus dem Pool (nie direkt dieselbe
    /// Variante wie zuletzt), etwas leiser.
    public static func land() {
        play(pick(mapping(soundSet).land, avoiding: &lastLand), volume: 0.7)
    }

    /// Game Over: zufällig aus dem Pool des aktuellen Sets.
    public static func gameOver() {
        play(pick(mapping(soundSet).gameOver, avoiding: &lastGameOver), volume: 0.95)
    }

    private static var lastLand = ""
    private static var lastGameOver = ""

    /// Liefert ein zufälliges Element, das (bei Pool-Größe > 1) nicht gleich dem
    /// zuletzt gewählten ist — verhindert unmittelbare Wiederholungen.
    private static func pick(_ pool: [String], avoiding last: inout String) -> String {
        guard pool.count > 1 else { return pool.first ?? "" }
        var name = pool.randomElement()!
        var guardCount = 0
        while name == last && guardCount < 8 {
            name = pool.randomElement()!
            guardCount += 1
        }
        last = name
        return name
    }

    // MARK: - Player-Pools

    private static let poolSize = 3
    private static var pools: [String: [AVAudioPlayer]] = [:]
    private static var ring: [String: Int] = [:]

    private static func play(_ name: String, volume: Float) {
        guard !muted, !name.isEmpty else { return }
        let pool = pool(for: name)
        guard !pool.isEmpty else { return }
        let i = (ring[name] ?? 0) % pool.count
        ring[name] = i + 1
        let player = pool[i]
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private static func pool(for name: String) -> [AVAudioPlayer] {
        if let existing = pools[name] { return existing }
        var players: [AVAudioPlayer] = []
        if let url = Theme.resourceBundle.url(forResource: name, withExtension: "m4a") {
            for _ in 0..<poolSize {
                if let p = try? AVAudioPlayer(contentsOf: url) { p.prepareToPlay(); players.append(p) }
            }
        }
        pools[name] = players
        return players
    }
}
