// Headless-Test des „Blutklumpen"-Modus durch die ECHTE GameScene (wie LockDelayTests):
// update(_:) wird mit synthetischen Zeitstempeln gepumpt, der Fortschritt ueber die
// Diagnose-Properties (`testActiveBottomRow`, `testEngineScore`) gelesen.
//
// Grenze der Harness: SKActions laufen nur in einer praesentierenden SKView — headless bleibt
// die Raeum-ANIMATION daher stehen (betrifft alle Modi, nicht nur diesen). Der Test prueft
// deshalb (a) den Lock→Spawn-Zyklus ohne Treffer und (b) dass ein Treffer den ENGINE-Score
// setzt (der ist sofort nach dem Aufsetzen final). Die Animation selbst wird in der echten
// App visuell verifiziert (Seed 12 raeumt ohne Eingaben nach vier Paaren).

import XCTest
import SpriteKit
import SteinregenCore
@testable import SteinregenRender

@MainActor
final class PairModeSceneTests: XCTestCase {

    private let frame = 1.0 / 60.0   // ein Simulations-Frame

    /// Aktuelles Paar `shift` Schritte schieben, hart fallen lassen und vorspulen, bis der
    /// naechste Stein oben erscheint (tiefste Reihe springt hoch) oder nichts mehr passiert.
    private func placePair(_ scene: GameScene, _ t: inout Double, shift: Int) {
        if shift < 0 { for _ in 0..<(-shift) { scene.inputLeft() } }
        if shift > 0 { for _ in 0..<shift  { scene.inputRight() } }
        scene.inputHardDrop()
        for _ in 0..<60 {
            t += frame; scene.update(t)
            if let r = scene.testActiveBottomRow, r >= 11 { return }   // neues Paar oben
        }
    }

    /// Paare ohne Treffer verteilen: der Lock→Spawn-Zyklus (inkl. postLockSettle-Pfad mit
    /// bereits gestuetzten Steinen) muss headless durchlaufen — nach jedem Aufsetzen erscheint
    /// zeitnah ein neues aktives Paar.
    func testLockSpawnZyklusLaeuft() {
        let scene = GameScene(size: CGSize(width: 600, height: 800))
        // Seed 42 raeumt in den ersten Paaren nichts (unten geprueft) — der Zyklus bleibt
        // ohne Raeum-Animation und damit headless-tauglich.
        scene.start(seed: 42, startLevel: 1, mode: .klumpen)
        var t = 0.0
        t += frame; scene.update(t)

        let shifts = [-3, 3, -1, 1]
        for (i, s) in shifts.enumerated() {
            placePair(scene, &t, shift: s)
            XCTAssertNotNil(scene.testActiveBottomRow, "nach Paar \(i + 1) erschien kein neues Paar — Aufloesung haengt")
            XCTAssertEqual(scene.testEngineScore, 0, "Seed 42 sollte in den ersten Paaren nichts raeumen (Test-Annahme)")
        }
    }

    /// Treffer-Fall: Seed 12 raeumt (ohne jede Eingabe) nach vier Paaren eine Vierergruppe —
    /// der Engine-Score muss dann gesetzt sein. Dass danach die Animation haengt, ist eine
    /// Harness-Grenze (siehe Kopfkommentar), kein App-Fehler.
    func testGruppeRaeumtSetztEngineScore() {
        let scene = GameScene(size: CGSize(width: 600, height: 800))
        scene.start(seed: 12, startLevel: 1, mode: .klumpen)
        var t = 0.0
        t += frame; scene.update(t)

        for _ in 0..<4 { placePair(scene, &t, shift: 0) }
        XCTAssertEqual(scene.testEngineScore, 40, "Seed 12 raeumt nach vier Paaren eine Vierergruppe (4 × 10 × Kette 1)")
    }
}
