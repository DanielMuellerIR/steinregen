// FriedhofTests.swift
// Deckt die persistente Bestenliste ab (der einzige dauerhafte Spieler-Zustand): Sortierung
// nach Score, Kürzen auf maxEntries, „schlägt das schlechteste Grab", JSON-Round-Trip und
// den zuletzt gemerkten Namen. Friedhof liest/schreibt UserDefaults.standard — die Tests
// sichern die betroffenen Schlüssel vorher und stellen sie danach wieder her.

import XCTest
@testable import SteinregenApp

@MainActor
final class FriedhofTests: XCTestCase {

    private let key = "steinregen.friedhof"
    private let nameKey = "steinregen.lastName"
    // XCTest führt `setUp()` und `tearDown()` auf GitHubs Runner außerhalb des Main Actors aus.
    // Beide Werte gehören nur dieser seriell verwendeten Testinstanz und überbrücken deshalb
    // bewusst die Isolation; die eigentliche Bestenlisten-Implementierung bleibt Main-Actor-sicher.
    nonisolated(unsafe) private var savedList: Any?
    nonisolated(unsafe) private var savedName: Any?

    override func setUp() {
        super.setUp()
        savedList = UserDefaults.standard.object(forKey: key)
        savedName = UserDefaults.standard.object(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    override func tearDown() {
        if let v = savedList { UserDefaults.standard.set(v, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        if let v = savedName { UserDefaults.standard.set(v, forKey: nameKey) }
        else { UserDefaults.standard.removeObject(forKey: nameKey) }
        super.tearDown()
    }

    /// Leerer Start: keine Einträge, jeder Score qualifiziert, kein letzter Name.
    func testEmptyStart() {
        XCTAssertTrue(Friedhof.entries().isEmpty)
        XCTAssertTrue(Friedhof.qualifies(score: 0))
        XCTAssertEqual(Friedhof.lastName, "")
    }

    /// Einträge werden absteigend nach Score sortiert zurückgegeben (JSON-Round-Trip inklusive).
    func testEntriesSortedByScoreDescending() {
        Friedhof.add(name: "A", score: 100, level: 3)
        Friedhof.add(name: "B", score: 500, level: 5)
        Friedhof.add(name: "C", score: 300, level: 4)
        let scores = Friedhof.entries().map(\.score)
        XCTAssertEqual(scores, [500, 300, 100])
        XCTAssertEqual(Friedhof.entries().first?.name, "B")
    }

    /// `add` merkt den zuletzt eingetragenen Namen als Vorbelegung.
    func testAddRemembersLastName() {
        Friedhof.add(name: "Lucifer", score: 42, level: 2)
        XCTAssertEqual(Friedhof.lastName, "Lucifer")
    }

    /// Die Liste wird auf maxEntries gekürzt — und behält die HÖCHSTEN Scores.
    func testCapsAtMaxEntriesKeepingHighest() {
        // maxEntries+5 Gräber mit aufsteigenden Scores eintragen.
        let n = Friedhof.maxEntries + 5
        for i in 0..<n { Friedhof.add(name: "G\(i)", score: i * 10, level: 1) }
        let entries = Friedhof.entries()
        XCTAssertEqual(entries.count, Friedhof.maxEntries)
        // Höchster Score ist (n-1)*10, niedrigster behaltener ist (n-maxEntries)*10.
        XCTAssertEqual(entries.first?.score, (n - 1) * 10)
        XCTAssertEqual(entries.last?.score, (n - Friedhof.maxEntries) * 10)
    }

    /// Ist die Liste voll, qualifiziert nur ein Score ÜBER dem schlechtesten Grab.
    func testQualifiesWhenListFull() {
        for i in 0..<Friedhof.maxEntries { Friedhof.add(name: "G\(i)", score: 100 + i, level: 1) }
        let worst = Friedhof.entries().last!.score
        XCTAssertFalse(Friedhof.qualifies(score: worst - 1), "unter dem schlechtesten Grab: kein Platz")
        XCTAssertFalse(Friedhof.qualifies(score: worst), "gleich dem schlechtesten Grab: kein Platz")
        XCTAssertTrue(Friedhof.qualifies(score: worst + 1), "über dem schlechtesten Grab: Platz")
    }
}
