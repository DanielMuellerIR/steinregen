// Tests fuer das Lock-Delay-Verhalten der Spielloop (GameScene).
// Ziel: Der Einrast-Zeitpunkt darf sich NICHT durch Dauer-Rotieren unendlich hinauszoegern lassen —
// nach dem Aufsetzen rastet der Stein nach ~lockDelay ein.
//
// Die GameScene wird headless getrieben: wir rufen update(_:) selbst mit synthetischen Zeitstempeln
// auf (kein SKView-Render-Loop noetig, die Lock-Entscheidung ist reine Logik) und lesen den Zustand
// ueber die oeffentliche Diagnose-Property `testActiveBottomRow` (tiefste Reihe des aktiven Steins;
// Boden = 0). Rastet ein Stein ein, laeuft die Aufloesung headless synchron durch und ein NEUER Stein
// erscheint oben → die tiefste Reihe springt sprunghaft nach oben. Genau das nutzen wir als
// „eingerastet"-Signal.

import XCTest
import SpriteKit
import SteinregenCore
@testable import SteinregenRender

@MainActor
final class LockDelayTests: XCTestCase {

    private let frame = 1.0 / 60.0   // ein Simulations-Frame

    private func makeScene() -> GameScene {
        let scene = GameScene(size: CGSize(width: 600, height: 800))
        scene.model = GameModel()
        scene.start(seed: 42, startLevel: 1, mode: .verschuettet)
        return scene
    }

    /// Kernfall (Daniels Bug): Stein per Hard-Drop aufsetzen, dann JEDEN Frame rotieren. Er MUSS
    /// trotzdem zeitnah einrasten — frueher setzte jede Rotation den Lock-Timer zurueck (endlos).
    func testDauerRotationRastetEin() {
        let scene = makeScene()
        var t = 0.0
        t += frame; scene.update(t)          // erster Frame (initialisiert nur lastUpdateTime)
        scene.inputHardDrop()                 // sofort bis zum Aufsetzen (bottom ~ 0)
        t += frame; scene.update(t)

        let groundRow = scene.testActiveBottomRow ?? 0   // ~0 (Boden)
        var elapsed = 0.0
        var locked = false
        for _ in 0..<600 {                    // bis zu 10 s Simulationszeit
            scene.inputRotate()               // Dauer-Rotation
            t += frame; scene.update(t)
            elapsed += frame
            // Neuer Stein oben → tiefste Reihe springt deutlich nach oben ⇒ vorheriger rastete ein.
            if let r = scene.testActiveBottomRow, r >= groundRow + 6 { locked = true; break }
        }
        XCTAssertTrue(locked, "Stein rastete trotz Dauer-Rotation nicht ein (Infinity-Spin-Bug)")
        XCTAssertLessThan(elapsed, 1.0, "Einrasten dauerte zu lange (\(elapsed)s) — Fenster wird verlaengert")
    }

    /// Haerterer Fall: von Anfang an JEDEN Frame rotieren, waehrend der Stein (per Softdrop schnell)
    /// faellt und aufsetzt. Rotation gibt einem Stein am/ueber dem Stapel kurz „Luft" (canFall true) —
    /// das darf den Lock-Timer NICHT dauerhaft nullen (Auf-ab-„Wippen"). Der Stein muss einrasten.
    func testDauerRotationImFallRastetEin() {
        let scene = makeScene()
        scene.setSoftDrop(true)               // schnelles Fallen → zuegig am Boden
        var t = 0.0
        t += frame; scene.update(t)

        var sawGround = false                 // war der Stein schon unten?
        var locked = false
        var elapsed = 0.0
        for _ in 0..<600 {                    // bis zu 10 s
            scene.inputRotate()
            t += frame; scene.update(t)
            elapsed += frame
            if let r = scene.testActiveBottomRow {
                if r <= 3 { sawGround = true }                 // unten angekommen
                if sawGround && r >= 10 { locked = true; break } // danach Sprung nach oben = eingerastet
            }
        }
        XCTAssertTrue(locked, "Stein rastete unter Dauer-Rotation im Fall nicht ein (Wippen-Exploit)")
        XCTAssertLessThan(elapsed, 3.0, "Einrasten dauerte zu lange (\(elapsed)s)")
    }

    /// Aktuellen Stein `abs(shift)` Schritte schieben, hart fallen lassen und vorspulen, bis der
    /// naechste Stein oben erscheint (tiefste Reihe springt hoch). Baut so deterministisch Stapel auf.
    private func placePiece(_ scene: GameScene, _ t: inout Double, shift: Int) {
        if shift < 0 { for _ in 0..<(-shift) { scene.inputLeft() } }
        if shift > 0 { for _ in 0..<shift  { scene.inputRight() } }
        scene.inputHardDrop()
        for _ in 0..<300 {
            t += frame; scene.update(t)
            if let r = scene.testActiveBottomRow, r >= 14 { return }   // neuer Stein oben
        }
    }

    /// Schaerfster Fall (Daniels echtes Szenario): erst einen UNEBENEN Stapel bauen, dann auf dem
    /// unebenen Kamm einen Stein per Dauer-Rotation „wippen". Auf unebener Auflage gibt eine Drehung
    /// dem Stein kurz Luft (canFall true) — das darf den Lock-Timer NICHT dauerhaft nullen. Der Stein
    /// MUSS trotzdem einrasten (auf flachem Boden greift dieser Pfad nicht, daher der Stapel).
    func testDauerRotationAufUnebenemStapelRastetEin() {
        let scene = makeScene()
        scene.setSoftDrop(true)               // schnell zum Stapel — misst die SETTLE-Zeit, nicht die Fallzeit
        var t = 0.0
        t += frame; scene.update(t)
        for s in [-5, 5, -4, 3, -5, 4, -3, 5, -4, 2, -5, 4] { placePiece(scene, &t, shift: s) }

        var descended = false
        var locked = false
        var elapsed = 0.0
        for _ in 0..<600 {                    // bis zu 10 s
            scene.inputRotate()
            t += frame; scene.update(t)
            elapsed += frame
            if let r = scene.testActiveBottomRow {
                if r < 12 { descended = true }                    // auf den Stapel gesunken
                if descended && r >= 14 { locked = true; break }  // neuer Stein oben = eingerastet
            }
        }
        XCTAssertTrue(locked, "Stein rastete beim Dauer-Rotieren auf unebenem Stapel nicht ein (Wippen-Exploit)")
        XCTAssertLessThan(elapsed, 2.0, "Einrasten dauerte zu lange (\(elapsed)s)")
    }

    /// Gegenprobe: OHNE Eingriff rastet der Stein nach dem Hard-Drop ebenfalls ein (reguläres
    /// Lock-Delay unbeschaedigt) — stellt sicher, dass der Fix das normale Einrasten nicht bricht.
    func testOhneEingriffRastetEin() {
        let scene = makeScene()
        var t = 0.0
        t += frame; scene.update(t)
        scene.inputHardDrop()
        t += frame; scene.update(t)

        let groundRow = scene.testActiveBottomRow ?? 0
        var locked = false
        for _ in 0..<120 {                    // bis zu 2 s
            t += frame; scene.update(t)
            if let r = scene.testActiveBottomRow, r >= groundRow + 6 { locked = true; break }
        }
        XCTAssertTrue(locked, "Stein rastete ohne Eingriff nicht ein — reguläres Lock-Delay kaputt")
    }
}
