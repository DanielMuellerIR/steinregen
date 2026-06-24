// MusicPlayer.swift
// Hintergrundmusik — bewusst GETRENNT von den Soundeffekten (SoundFX).
//
// Drei instrumentale Stücke (Downfall-of-Gaia-Stil, lokal mit ACE-Step erzeugt) laufen
// NACHEINANDER in Endlosschleife: beim Spielstart wird zufällig eines als Einstieg gewählt
// („zufälliger Anfang"), danach geht es der Reihe nach weiter (musik-1 → musik-2 → musik-3 →
// musik-1 …). Musik ist standardmäßig AN, lässt sich aber unabhängig von den Soundeffekten
// ausschalten — eigener UserDefaults-Schlüssel, im Spiel Taste M, in den Einstellungen.
//
// Wichtig: Musik spielt NUR im laufenden Spiel, NICHT im Hauptmenü. Die App-Schicht ruft
// `gameStarted()` beim Levelbeginn und `gameEnded()` bei der Rückkehr ins Menü.
//
// Reine Präsentationsschicht — KEIN Bezug zum deterministischen Core (der Zufall hier ist
// Render-Zufall, kein Core-Zufall). Ein einziger gemeinsamer Spieler (`shared`).

import AVFoundation
import Foundation

@MainActor
public final class MusicPlayer: NSObject {

    /// Der einzige, prozessweite Musik-Spieler. Die App-Schicht steuert ihn über die
    /// Start/Stopp- und Ein/Aus-Methoden weiter unten.
    public static let shared = MusicPlayer()

    /// UserDefaults-Schlüssel: true = Musik AUS. Default false ⇒ Musik AN. Bewusst ein
    /// EIGENER Schlüssel (getrennt von „steinregen.mundtot" für die Soundeffekte).
    public static let mutedKey = "steinregen.musik.aus"

    /// Lautstärke der Musik — bewusst unter den Soundeffekten, damit diese gut durchkommen.
    private let volume: Float = 0.5

    /// Dateinamen der Musikstücke (ohne Endung), in fester Abspiel-Reihenfolge. Die zugehörigen
    /// `.mp3` liegen im Ressourcen-Bundle (geteilt mit macOS und iOS).
    private let trackNames = ["musik-1", "musik-2", "musik-3"]

    /// Aufgelöste Datei-URLs der vorhandenen Stücke (fehlende werden still übersprungen).
    private var tracks: [URL] = []
    /// Der aktuell laufende Player (genau ein Stück gleichzeitig) oder nil (Musik steht).
    private var player: AVAudioPlayer?
    /// Index des gerade laufenden Stücks in `tracks`.
    private var index = 0
    /// true, solange eine Partie läuft (zwischen `gameStarted()` und `gameEnded()`). Verhindert,
    /// dass Musik im Menü spielt — auch wenn der Ein/Aus-Schalter dort umgelegt wird.
    private var inGame = false

    private override init() {
        super.init()
        // URLs einmalig aus dem Bundle auflösen.
        for name in trackNames {
            if let url = Theme.resourceBundle.url(forResource: name, withExtension: "mp3") {
                tracks.append(url)
            }
        }
    }

    /// Ist Musik gewünscht? Liest direkt aus UserDefaults, damit der Einstellungs-Schalter
    /// (per AppStorage) und dieser Spieler immer denselben Stand sehen.
    public static var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(!newValue, forKey: mutedKey) }
    }

    // MARK: - Steuerung durch die App-Schicht

    /// Levelbeginn: ab jetzt darf Musik laufen. Startet ein zufällig gewähltes Stück, falls
    /// Musik an ist und noch nichts spielt. Mehrfachaufruf (z.B. „nochmal mit gleichem Seed")
    /// lässt eine bereits laufende Musik unangetastet weiterlaufen — kein harter Neustart.
    public func gameStarted() {
        inGame = true
        guard Self.enabled, player == nil, !tracks.isEmpty else { return }
        index = Int.random(in: 0..<tracks.count)   // zufälliger Einstiegspunkt in die Reihe
        playCurrent()
    }

    /// Rückkehr ins Menü / Spielende: Musik stoppt (im Hauptmenü ist es still).
    public func gameEnded() {
        inGame = false
        stop()
    }

    /// Musik an/aus umschalten (Taste M). Liefert den NEUEN Zustand zurück (true = an), damit der
    /// Aufrufer einen kurzen Hinweis einblenden kann. Wirkt sofort: an + im Spiel ⇒ Musik beginnt;
    /// aus ⇒ Musik verstummt.
    @discardableResult
    public func toggle() -> Bool {
        setEnabled(!Self.enabled)
        return Self.enabled
    }

    /// Musik-Wunsch setzen (persistiert) und sofort anwenden.
    public func setEnabled(_ on: Bool) {
        Self.enabled = on
        if on {
            // Nur im laufenden Spiel sofort losspielen — im Menü bleibt es still bis zum Levelbeginn.
            if inGame, player == nil, !tracks.isEmpty {
                index = Int.random(in: 0..<tracks.count)
                playCurrent()
            }
        } else {
            stop()
        }
    }

    // MARK: - Intern

    private func playCurrent() {
        guard index < tracks.count else { return }
        guard let p = try? AVAudioPlayer(contentsOf: tracks[index]) else { return }
        p.delegate = self
        p.volume = volume
        p.numberOfLoops = 0            // ein Durchlauf; danach schaltet der Delegate aufs nächste Stück
        p.prepareToPlay()
        p.play()
        player = p
    }

    private func stop() {
        player?.stop()
        player = nil
    }

    /// Zum nächsten Stück springen (Reihe herum), solange noch gespielt werden soll.
    private func advance() {
        guard inGame, Self.enabled, !tracks.isEmpty else { player = nil; return }
        index = (index + 1) % tracks.count
        playCurrent()
    }
}

// Der AVAudioPlayerDelegate-Callback kommt außerhalb der MainActor-Isolation herein → wir
// hüpfen explizit auf den MainActor, um den Spieler-Zustand sicher anzufassen. `.stop()`
// löst diesen Callback NICHT aus (nur ein natürlich zu Ende gespieltes Stück), daher schaltet
// `advance()` ausschließlich nach echtem Stück-Ende weiter.
extension MusicPlayer: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.advance() }
    }
}
