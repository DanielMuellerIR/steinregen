// ConfigTests.swift
// Deckt die reinen Konfigurations-/Präsentations-Helfer der Render-Schicht ab, die zuvor
// ungetestet waren: die Brettgrößen-Klemmung (BoardConfig), die Sprach-Auflösung (L10n.lang)
// und die Konsistenz der GameMode-Metadaten (Default liegt in der erlaubten Spanne).

import XCTest
@testable import SteinregenRender
import SteinregenCore

@MainActor
final class BoardConfigTests: XCTestCase {

    // Die von den einzelnen Tests angefassten UserDefaults-Schlüssel — vor jedem Test gesichert
    // und danach wiederhergestellt, damit die echten Einstellungen des Nutzers unberührt bleiben.
    // XCTest ruft `tearDown()` nicht auf dem Main Actor auf. Der Zustand gehört trotzdem nur zu
    // genau dieser seriell verwendeten Testinstanz; deshalb darf nur diese Variable die Isolation
    // bewusst überbrücken. Produktionscode und die getestete Spiellogik bleiben davon unberührt.
    nonisolated(unsafe) private var saved: [String: Any?] = [:]

    private func snapshot(_ keys: [String]) {
        for k in keys { saved[k] = UserDefaults.standard.object(forKey: k) }
    }

    override func tearDown() {
        for (k, v) in saved {
            if let v { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
        saved = [:]
        super.tearDown()
    }

    /// Ungesetzt (UserDefaults liefert 0) ⇒ der Modus-Standard.
    func testUnsetFallsBackToDefault() {
        let m = GameMode.saeulen
        snapshot([BoardConfig.widthKey(m), BoardConfig.heightKey(m)])
        UserDefaults.standard.removeObject(forKey: BoardConfig.widthKey(m))
        UserDefaults.standard.removeObject(forKey: BoardConfig.heightKey(m))
        XCTAssertEqual(BoardConfig.width(m), m.defaultWidth)
        XCTAssertEqual(BoardConfig.height(m), m.defaultHeight)
    }

    /// Ein Wert innerhalb der Spanne wird unverändert durchgereicht.
    func testInRangeValuePreserved() {
        let m = GameMode.saeulen
        snapshot([BoardConfig.widthKey(m), BoardConfig.heightKey(m)])
        UserDefaults.standard.set(9, forKey: BoardConfig.widthKey(m))   // Spanne 5…12
        UserDefaults.standard.set(20, forKey: BoardConfig.heightKey(m)) // Spanne 10…24
        XCTAssertEqual(BoardConfig.width(m), 9)
        XCTAssertEqual(BoardConfig.height(m), 20)
    }

    /// Werte außerhalb der Spanne (zu groß / zu klein) werden auf die Grenzen geklemmt —
    /// robust gegen alte oder kaputte gespeicherte Werte.
    func testOutOfRangeValueClamped() {
        let m = GameMode.saeulen   // Breite 5…12, Höhe 10…24
        snapshot([BoardConfig.widthKey(m), BoardConfig.heightKey(m)])
        UserDefaults.standard.set(999, forKey: BoardConfig.widthKey(m))
        UserDefaults.standard.set(3, forKey: BoardConfig.heightKey(m))
        XCTAssertEqual(BoardConfig.width(m), m.widthRange.upperBound)
        XCTAssertEqual(BoardConfig.height(m), m.heightRange.lowerBound)
    }

    /// Jeder Modus liest/schreibt seinen EIGENEN Schlüssel — kein Übersprechen zwischen Modi.
    func testPerModeKeysAreDistinct() {
        let a = GameMode.saeulen, b = GameMode.schnitter
        XCTAssertNotEqual(BoardConfig.widthKey(a), BoardConfig.widthKey(b))
        XCTAssertNotEqual(BoardConfig.heightKey(a), BoardConfig.heightKey(b))
    }
}

final class L10nLangTests: XCTestCase {

    private var savedRaw: Any??

    override func setUp() {
        super.setUp()
        savedRaw = .some(UserDefaults.standard.object(forKey: L10n.key))
    }

    override func tearDown() {
        if case let .some(v) = savedRaw {
            if let v { UserDefaults.standard.set(v, forKey: L10n.key) }
            else { UserDefaults.standard.removeObject(forKey: L10n.key) }
        }
        super.tearDown()
    }

    /// Ein gesetzter Override gewinnt — unabhängig von der System-Sprache.
    func testOverrideWins() {
        L10n.lang = .de
        XCTAssertEqual(L10n.lang, .de)
        XCTAssertEqual(L10n.t("deutsch", "english"), "deutsch")

        L10n.lang = .en
        XCTAssertEqual(L10n.lang, .en)
        XCTAssertEqual(L10n.t("deutsch", "english"), "english")
    }

    /// Ein ungültiger gespeicherter Rohwert fällt auf die System-Ableitung zurück (liefert also
    /// eine der beiden gültigen Sprachen, nicht crash/leer).
    func testInvalidRawFallsBackToSystem() {
        UserDefaults.standard.set("klingon", forKey: L10n.key)
        XCTAssertTrue([.de, .en].contains(L10n.lang))
    }
}

final class GameModeMetadataTests: XCTestCase {

    private var savedRaw: Any??

    override func setUp() {
        super.setUp()
        savedRaw = .some(UserDefaults.standard.object(forKey: L10n.key))
    }

    override func tearDown() {
        if case let .some(v) = savedRaw {
            if let v { UserDefaults.standard.set(v, forKey: L10n.key) }
            else { UserDefaults.standard.removeObject(forKey: L10n.key) }
        }
        super.tearDown()
    }

    /// Für JEDEN Modus muss das Standard-Brettmaß in der erlaubten Spanne liegen — ein billiger
    /// Wächter, dass ein neu hinzugefügter Modus konsistente Spannen/Defaults mitbringt.
    func testDefaultsWithinRanges() {
        for m in GameMode.allCases {
            XCTAssertTrue(m.widthRange.contains(m.defaultWidth),
                          "\(m): defaultWidth \(m.defaultWidth) ∉ \(m.widthRange)")
            XCTAssertTrue(m.heightRange.contains(m.defaultHeight),
                          "\(m): defaultHeight \(m.defaultHeight) ∉ \(m.heightRange)")
        }
    }

    /// Titel und Hinweis sind für jeden Modus nicht-leer (in beiden Sprachen). Die persistierte
    /// Sprache wird in tearDown wiederhergestellt (setUp/tearDown oben).
    func testTitlesAndHintsNonEmpty() {
        for lang in L10n.Lang.allCases {
            L10n.lang = lang
            for m in GameMode.allCases {
                XCTAssertFalse(m.title.isEmpty, "\(m): leerer Titel (\(lang))")
                XCTAssertFalse(m.hint.isEmpty, "\(m): leerer Hinweis (\(lang))")
            }
        }
    }
}
