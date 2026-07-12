// MusicPlayer.swift
// Hintergrundmusik — bewusst GETRENNT von den Soundeffekten (SoundFX).
//
// Instrumentale Stücke laufen in zufälliger Reihenfolge: Jeder Durchlauf enthält jedes
// Stück genau einmal. Erst danach wird die nächste zufällige Reihenfolge gebaut; ihr
// erster Titel darf nicht derselbe wie der zuletzt gespielte sein. Die Stücke werden
// AUTOMATISCH entdeckt (gleiches Muster wie die
// Hintergrundbilder): alle lückenlos nummerierten `musik-N.mp3` im Bundle — ein weiteres
// Stück ins Bundle legen genügt, keine Code-Änderung nötig. Musik ist standardmäßig AN,
// lässt sich aber unabhängig von den Soundeffekten ausschalten — eigener
// UserDefaults-Schlüssel, im Spiel Taste M, in den Einstellungen.
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

    /// Aufgelöste Datei-URLs der vorhandenen Stücke, nach ihrem Namen sortiert
    /// (`musik-1`, `musik-2`, …). Die spätere Abspiel-Reihenfolge wird separat gemischt.
    private var tracks: [URL] = []
    /// Der aktuell laufende Player (genau ein Stück gleichzeitig) oder nil (Musik steht).
    private var player: AVAudioPlayer?
    /// Index des gerade laufenden Stücks in `tracks`.
    private var index = 0
    /// Zufällige Reihenfolge für den aktuellen Durchlauf. Sie enthält jeden Index genau einmal.
    private var playbackOrder: [Int] = []
    /// Position des laufenden Stücks innerhalb von `playbackOrder`.
    private var playbackPosition = 0
    /// true, solange eine Partie läuft (zwischen `gameStarted()` und `gameEnded()`). Verhindert,
    /// dass Musik im Menü spielt — auch wenn der Ein/Aus-Schalter dort umgelegt wird.
    private var inGame = false

    private override init() {
        super.init()
        // URLs einmalig aus dem Bundle auflösen.
        tracks = MusicPlayer.discoverTracks(in: Theme.resourceBundle)
    }

    /// Findet alle Musikstücke im Bundle: `musik-1.mp3`, `musik-2.mp3`, … in lückenlos
    /// aufsteigender Nummerierung (die erste Lücke beendet die Suche — gleiches Muster wie
    /// `Theme.backdropCount()`/`backdropImage(_:)`). So genügt es, ein weiteres Stück als `musik-N.mp3` ins
    /// Bundle zu legen. Statisch + parameterisiert, damit Tests sie direkt prüfen können.
    static func discoverTracks(in bundle: Bundle) -> [URL] {
        var urls: [URL] = []
        var n = 1
        while let url = bundle.url(forResource: "musik-\(n)", withExtension: "mp3") {
            urls.append(url)
            n += 1
            if n > 64 { break }   // Sicherheitsdeckel gegen eine versehentliche Endlosschleife
        }
        return urls
    }

    /// Baut einen zufälligen Durchlauf über alle Titel. Falls ein vorheriger Index bekannt ist,
    /// beginnt ein neuer Durchlauf nie mit genau diesem Titel — so entsteht an der Schleifen-
    /// grenze keine direkte Wiederholung. Die Methode ist statisch, damit ihre wichtige
    /// Vollständigkeitsregel ohne Audio-Ausgabe getestet werden kann.
    static func randomPlaybackOrder(trackCount: Int, avoiding previousIndex: Int? = nil) -> [Int] {
        guard trackCount > 0 else { return [] }

        var order = Array(0..<trackCount).shuffled()
        if trackCount > 1, let previousIndex, order.first == previousIndex {
            // Der zweite Eintrag ist bei einer echten Permutation zwangsläufig verschieden.
            order.swapAt(0, 1)
        }
        return order
    }

    /// Ist Musik gewünscht? Liest direkt aus UserDefaults, damit der Einstellungs-Schalter
    /// (per AppStorage) und dieser Spieler immer denselben Stand sehen.
    public static var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(!newValue, forKey: mutedKey) }
    }

    // MARK: - Steuerung durch die App-Schicht

    /// Levelbeginn: ab jetzt darf Musik laufen. Startet einen zufälligen vollständigen Durchlauf,
    /// falls Musik an ist und noch nichts spielt. Mehrfachaufruf (z.B. „nochmal mit gleichem Seed")
    /// lässt eine bereits laufende Musik unangetastet weiterlaufen — kein harter Neustart.
    public func gameStarted() {
        inGame = true
        guard Self.enabled, player == nil, !tracks.isEmpty else { return }
        beginRandomRun()
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
                beginRandomRun()
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

    /// Mischt alle vorhandenen Titel für einen vollständigen Durchlauf und übernimmt dessen
    /// ersten Eintrag als aktuellen Titel. Beim Neustart nach einem Durchlauf wird der zuletzt
    /// gespielte Titel übergeben, damit derselbe Song nicht zweimal hintereinander erklingt.
    private func beginRandomRun(avoiding previousIndex: Int? = nil) {
        playbackOrder = Self.randomPlaybackOrder(trackCount: tracks.count,
                                                  avoiding: previousIndex)
        playbackPosition = 0
        index = playbackOrder[playbackPosition]
    }

    /// Zum nächsten Titel im gemischten Durchlauf springen; danach beginnt ein neuer Durchlauf.
    private func advance() {
        guard inGame, Self.enabled, !tracks.isEmpty else { player = nil; return }
        playbackPosition += 1
        if playbackPosition == playbackOrder.count {
            beginRandomRun(avoiding: index)
        } else {
            index = playbackOrder[playbackPosition]
        }
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
