// SoundFX.swift
// Schmale Audio-Schicht für die Soundeffekte (FreeDoom-WAVs, BSD-3 — siehe
// Resources/FREEDOOM-LICENSE.txt). Reine Präsentation: KEIN Bezug zum deterministischen Core.
//
// Zuordnung (vom Nutzer gewählt):
//   • Drehen        → dstink
//   • Aufsetzen     → zyklisch dsgetpow → dsoof → dsswtchn (bei jedem Aufruf der nächste)
//   • Auflösen      → dspstop
//   • Game Over     → zufällig aus dspdiehi / dspldeth / dsdorcls
//   • Level geschafft → dswpnup
//
// „mundtot" = Ton aus (persistiert in UserDefaults, geteilt mit der Einstellungen-View und der
// T-Taste im Spiel). Pro Sound ein kleiner Player-Pool, damit schnelle Wiederholungen (Kaskaden)
// sich nicht gegenseitig abschneiden.

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

    public static func rotate()   { play("dstink", volume: 0.55) }
    public static func clear()    { play("dspstop", volume: 0.85) }
    public static func levelUp()  { play("dswpnup", volume: 0.9) }

    /// Aufsetzen: zyklisch durch die drei Klänge (der Reihe nach).
    public static func land() {
        let name = landCycle[landIndex % landCycle.count]
        landIndex += 1
        play(name, volume: 0.8)
    }

    /// Game Over: jedes Mal zufällig einer der drei (Render-Zufall, kein Core-Zufall).
    public static func gameOver() {
        play(gameOverPool.randomElement() ?? "dspldeth", volume: 0.95)
    }

    private static let landCycle = ["dsgetpow", "dsoof", "dsswtchn"]
    private static var landIndex = 0
    private static let gameOverPool = ["dspdiehi", "dspldeth", "dsdorcls"]

    // MARK: - Player-Pools

    private static let poolSize = 3
    private static var pools: [String: [AVAudioPlayer]] = [:]
    private static var ring: [String: Int] = [:]

    private static func play(_ name: String, volume: Float) {
        guard !muted else { return }
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
        if let url = Theme.resourceBundle.url(forResource: name, withExtension: "wav") {
            for _ in 0..<poolSize {
                if let p = try? AVAudioPlayer(contentsOf: url) { p.prepareToPlay(); players.append(p) }
            }
        }
        pools[name] = players
        return players
    }
}
