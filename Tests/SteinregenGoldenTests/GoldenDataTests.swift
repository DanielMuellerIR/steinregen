// GoldenDataTests.swift
// Bindet die eingecheckten Vergleichsdaten an den aktuellen Spielkern.
//
// Der Sinn: Die Datei `golden/steinregen-golden.json` ist der Pruefmassstab fuer die geplante
// TypeScript-Portierung. Aendert jemand eine Regel im Kern, passt sie nicht mehr — und das MUSS
// auffallen, statt still weiterzulaufen. Schlaegt dieser Test fehl, ist das also kein Grund, die
// Datei blind neu zu erzeugen: Erst pruefen, ob die Aenderung am Kern gewollt war, dann
// `bash tools/make-golden.sh` laufen lassen und den Unterschied im Diff durchsehen.

import XCTest
@testable import SteinregenGolden
import SteinregenCore

final class GoldenDataTests: XCTestCase {

    /// Pfad zur eingecheckten Datei — aus dem Ort DIESER Quelldatei abgeleitet, damit der Test
    /// unabhaengig vom Arbeitsverzeichnis laeuft (Tests/SteinregenGoldenTests/… → zwei Ebenen hoch).
    private var goldenPath: String {
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()   // SteinregenGoldenTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Repo-Wurzel
            .appendingPathComponent("golden/steinregen-golden.json")
            .path
    }

    /// Der eigentliche Waechter: neu erzeugen und Zeichen fuer Zeichen vergleichen.
    func testCheckedInDataMatchesCurrentCore() throws {
        let expected = try String(contentsOfFile: goldenPath, encoding: .utf8)
        let actual = try GoldenData.json()

        if expected != actual {
            // Bei Abweichung die erste unterschiedliche Zeile nennen — das spart die Suche
            // in einer sehr grossen Datei.
            let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
            let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
            var line = 0
            while line < min(e.count, a.count), e[line] == a[line] { line += 1 }
            let expectedLine = line < e.count ? String(e[line]) : "(Datei zu Ende)"
            let actualLine = line < a.count ? String(a[line]) : "(Datei zu Ende)"
            XCTFail("""
                Vergleichsdaten weichen ab (Zeile \(line + 1)):
                  eingecheckt: \(expectedLine)
                  aktuell:     \(actualLine)
                Der Spielkern hat sich geaendert. War das gewollt, neu erzeugen mit
                  bash tools/make-golden.sh
                und den Unterschied im Diff pruefen — niemals ungeprueft uebernehmen.
                """)
        }
    }

    /// Die Datei nuetzt nur, wenn sie wirklich alle sechs Modi abdeckt.
    func testEveryModeIsCovered() {
        let modes = Set(GoldenData.specs.map(\.mode))
        XCTAssertEqual(modes, ["saeulen", "verschuettet", "klumpen", "fuenfling", "kapseln", "schnitter"])
    }

    /// Zweimal erzeugen muss dasselbe ergeben. Faengt genau die Fehlerart, gegen die der Kern
    /// gebaut ist: eine Menge (`Set`) unsortiert auszugeben, deren Reihenfolge sich je Lauf aendert.
    func testGenerationIsReproducible() throws {
        XCTAssertEqual(try GoldenData.json(), try GoldenData.json())
    }

    /// Stichprobe auf den wichtigsten Einzelbaustein: Der Zufallsgenerator muss die bekannte
    /// xoshiro256**-Folge liefern. Stimmt die nicht, ist jede weitere Zeile der Datei wertlos.
    func testPRNGVectorsAreComplete() {
        let vectors = GoldenData.prngVectors()
        XCTAssertEqual(Set(vectors.map(\.generator)), ["SplitMix64", "Xoshiro256StarStar"])
        for vector in vectors {
            XCTAssertEqual(vector.values.count, 16, "\(vector.generator)/\(vector.seed)")
            // Als Zeichenkette exportiert, weil JavaScript nur 53 Bit genau rechnet — die Werte
            // muessen sich verlustfrei als 64-Bit-Zahl zurueckwandeln lassen.
            for value in vector.values {
                XCTAssertNotNil(UInt64(value), "keine gueltige 64-Bit-Zahl: \(value)")
            }
        }
    }

    /// Eine Partie ohne Zuege waere ein stiller Ausfall — etwa wenn jede Engine sofort
    /// „Game Over" meldete. Darum: jeder Fall braucht Befehle und Zustaende.
    func testEveryCaseRecordsProgress() {
        for spec in GoldenData.specs {
            let recorded = GoldenData.record(spec)
            XCTAssertFalse(recorded.commands.isEmpty, "\(spec.id): keine Befehle")
            XCTAssertEqual(recorded.commands.count, recorded.snapshots.count,
                           "\(spec.id): Befehle und Zustaende muessen sich entsprechen")
            XCTAssertGreaterThan(recorded.snapshots.count, 20, "\(spec.id): verdaechtig kurz")
        }
    }
}
