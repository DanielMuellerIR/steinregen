// SoundFX.swift
// Schmale Audio-Schicht für die Soundeffekte. Seit 2026-06-22 eigene, lokal mit
// Stable Audio 3 erzeugte Klänge (mono AAC/.m4a, passend zur Black-Metal-Ästhetik)
// statt der früheren Freedoom-WAVs. Reine Präsentation: KEIN Bezug zum
// deterministischen Core (der Zufall hier ist Render-Zufall, kein Core-Zufall).
//
// Zuordnung (Event → Resource-Name, jeweils .m4a im Render-Bundle):
//   • Drehen          → "drehen"
//   • Auflösen        → "aufloesen"
//   • Level geschafft → "level"
//   • Aufsetzen       → zufällig aus "aufsetzen-1…6" (wird sehr oft gehört →
//                        etwas leiser + nie direkt dieselbe Variante wie zuletzt,
//                        damit es nicht monoton wirkt)
//   • Game Over       → zufällig aus "gameover-1…7"
//
// „mundtot" = Ton aus (persistiert in UserDefaults, geteilt mit der Einstellungen-View
// und der T-Taste im Spiel). Pro Sound ein kleiner Player-Pool, damit schnelle
// Wiederholungen (Kaskaden) sich nicht gegenseitig abschneiden.

import AVFoundation
import Foundation

@MainActor
public enum SoundFX {

    /// UserDefaults-Schlüssel: true = „mundtot" (Ton aus). Default false (Ton an).
    public static let mutedKey = "steinregen.mundtot"

    public static var muted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    // MARK: - Spiel-Events

    public static func rotate()   { play("drehen", volume: 0.55) }
    public static func clear()    { play("aufloesen", volume: 0.85) }
    public static func levelUp()  { play("level", volume: 0.9) }

    /// Aufsetzen: oft gehörter Klang → zufällig aus dem Pool, aber nie direkt
    /// dieselbe Variante wie zuletzt; etwas leiser, weil bewusst dezent gewählt.
    public static func land() {
        play(pick(landPool, avoiding: &lastLand), volume: 0.7)
    }

    /// Game Over: jedes Mal zufällig einer aus dem Pool (seltenes Event).
    public static func gameOver() {
        play(pick(gameOverPool, avoiding: &lastGameOver), volume: 0.95)
    }

    // Varianten-Pools (Dateinamen ohne Endung; siehe Resources/<name>.m4a).
    // Bei geänderter Anzahl exportierter Varianten hier die Bereiche anpassen.
    private static let landPool     = (1...1).map { "aufsetzen-\($0)" }
    private static let gameOverPool = (1...7).map { "gameover-\($0)" }
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
