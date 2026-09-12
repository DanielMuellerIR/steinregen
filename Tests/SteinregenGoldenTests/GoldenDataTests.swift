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

    /// Die sechs Modus-Kennungen — an EINER Stelle. Stand die Menge doppelt im Test, wurde bei
    /// einem siebten Modus erfahrungsgemaess nur die Stelle nachgezogen, die zuerst rot wird;
    /// die andere prueft dann still eine veraltete Erwartung.
    private static let allModes: Set<String> = [
        "saeulen", "verschuettet", "klumpen", "fuenfling", "kapseln", "schnitter",
    ]

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
        XCTAssertEqual(modes, Self.allModes)
    }

    /// Zweimal erzeugen muss dasselbe ergeben. Faengt genau die Fehlerart, gegen die der Kern
    /// gebaut ist: eine Menge (`Set`) unsortiert auszugeben, deren Reihenfolge sich je Lauf aendert.
    func testGenerationIsReproducible() throws {
        XCTAssertEqual(try GoldenData.json(), try GoldenData.json())
    }

    /// Stichprobe auf den wichtigsten Einzelbaustein: Der Zufallsgenerator muss die bekannte
    /// Folge liefern. Stimmt die nicht, ist jede weitere Zeile der Datei wertlos.
    ///
    /// Frueher stand hier nur `UInt64(value) != nil`. Das konnte gar nicht fehlschlagen, denn
    /// die Werte entstehen als `String(rng.next())` — die Pruefung sagte also nichts ueber den
    /// Generator aus. Jetzt stehen feste Vergleichszahlen im Test: die veroeffentlichte
    /// Referenzfolge von SplitMix64 ab Zustand 0 und der erste xoshiro256**-Wert fuer Seed 1,
    /// den auch `golden/README.md` nennt. Diese Zahlen haengen nicht an der eingecheckten Datei.
    func testPRNGVectorsMatchKnownReference() {
        let vectors = GoldenData.prngVectors()

        // Beide Generatoren mit genau denselben fuenf Seeds — inklusive der Randfaelle 0 und
        // groesster 64-Bit-Wert. Faellt ein Seed weg, faellt hier auf.
        let seeds = ["0", "1", "42", "20260806", "18446744073709551615"]
        for generator in ["SplitMix64", "Xoshiro256StarStar"] {
            let own = vectors.filter { $0.generator == generator }
            XCTAssertEqual(own.map(\.seed), seeds, "\(generator): andere Seed-Menge")
            for vector in own {
                XCTAssertEqual(vector.values.count, 16, "\(generator)/\(vector.seed)")
            }
        }
        XCTAssertEqual(vectors.count, 2 * seeds.count, "unerwartete Zahl an Vektoren")

        /// Die Werte eines einzelnen Vektors herausgreifen.
        func values(_ generator: String, seed: String) -> [String] {
            vectors.first { $0.generator == generator && $0.seed == seed }?.values ?? []
        }
        XCTAssertEqual(Array(values("SplitMix64", seed: "0").prefix(3)),
                       ["16294208416658607535", "7960286522194355700", "487617019471545679"],
                       "SplitMix64 weicht von der veroeffentlichten Referenzfolge ab")
        XCTAssertEqual(values("Xoshiro256StarStar", seed: "1").first, "12966619160104079557",
                       "xoshiro256** weicht vom dokumentierten ersten Wert ab")
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

    /// Mindestabdeckung des Spielendes: Zu JEDEM Modus muss mindestens eine Partie wirklich zu
    /// Ende gespielt sein. Bricht eine Aufzeichnung nur wegen der Stein-Obergrenze ab, endet sie
    /// mitten im Fallen — dann kommt der blockierte Einwurf dieses Modus in keinem Replay vor,
    /// und eine Portierung duerfte dort abweichen, ohne dass es auffaellt.
    func testEveryModeReachesTheEndOfAGame() {
        var reached: Set<String> = []
        for spec in GoldenData.specs {
            // `continue` statt `return`: Sonst braeche schon der erste leere Fall die ganze
            // Testfunktion ab — die uebrigen Faelle blieben ungeprueft und der Vergleich unten
            // liefe nie. Der Bericht zeigte dann nur das erste Symptom statt der Lage.
            guard let last = GoldenData.record(spec).snapshots.last else {
                XCTFail("\(spec.id): keine Zustaende aufgezeichnet")
                continue
            }
            if last.phase == "gameOver" || last.phase == "won" { reached.insert(spec.mode) }
        }
        XCTAssertEqual(reached, Self.allModes,
                       "diese Modi enden in keinem Fall mit einer Endphase")
    }

    /// Die Reihen-Level-Regel (`TetrominoEngine.linesPerLevel`, Stufe je 10 geraeumte Reihen)
    /// muss in den Daten wirklich zuschlagen. Frueher behauptete der Kommentar an `specs` das,
    /// obwohl kein einziger Reihen-Fall die Stufe aenderte: Der hoechste raeumte 3 Reihen. Eine
    /// Portierung durfte `linesPerLevel` beliebig falsch umsetzen, ohne dass es auffiel.
    func testRowModeLevelRuleIsCovered() {
        let rowModes: Set<String> = ["verschuettet", "fuenfling"]
        var raised = false
        for spec in GoldenData.specs where rowModes.contains(spec.mode) {
            let recorded = GoldenData.record(spec)
            let levels = Set(recorded.snapshots.map(\.level))
            if levels.count > 1 { raised = true }
        }
        XCTAssertTrue(raised, """
            Kein Reihen-Fall aendert seine Stufe. Damit stehen weder `linesPerLevel` noch der \
            Faktor `max(1, level)` aus `linePoints` im Pruefmassstab der Portierung.
            """)
    }

    /// Der Deckel der Fluch-Vorbefuellung muss wenigstens einmal binden. `curseCount` ist
    /// `min(4 * level, (Breite * curseRows) / 2)`; solange nur der erste Zweig gewinnt, steht
    /// der zweite nirgends in den Daten.
    func testCurseCountCapIsCovered() {
        guard let spec = GoldenData.specs.first(where: {
            $0.mode == "kapseln" && $0.id == "kapseln-klein"
        }) else {
            return XCTFail("Vergleichsfall kapseln-klein fehlt")
        }
        XCTAssertEqual(GoldenData.record(spec).curseCountAtStart, 18,
                       "kapseln-klein muss den Kapazitaetsdeckel exakt belegen")
    }

    /// Die Kommandozeile darf ueberzaehlige Argumente nicht stillschweigend schlucken.
    /// `--list --check DATEI` meldete frueher Erfolg (0), ohne den verlangten Vergleich
    /// auszufuehren — ein Tippfehler in einer Automation waere so unbemerkt geblieben.
    func testCommandLineRejectsExtraArguments() {
        XCTAssertEqual(goldenMain(["--help"]), 0)
        XCTAssertEqual(goldenMain(["--help", "zuviel"]), 1)
        XCTAssertEqual(goldenMain(["-h", "zuviel"]), 1)
        XCTAssertEqual(goldenMain(["--list", "--check", "datei.json"]), 1)
        XCTAssertEqual(goldenMain(["--out"]), 1, "--out ohne Datei")
        XCTAssertEqual(goldenMain(["--out", "a.json", "b.json"]), 1, "--out mit zwei Dateien")
        XCTAssertEqual(goldenMain(["--unbekannt"]), 1)
        // Der schreibende Zweig zaehlte frueher nur die Argumente: `--out --check` legte eine
        // 1,4-MB-Datei namens „--check" an und meldete Erfolg, waehrend der verlangte Vergleich
        // nie lief. Ein Dateiname faengt nicht mit `--` an.
        XCTAssertEqual(goldenMain(["--out", "--check"]), 1, "--out darf keine Option beschreiben")
        XCTAssertEqual(goldenMain(["--check", "--out"]), 1, "--check darf keine Option lesen")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "--check"),
                       "es darf keine Datei namens --check entstanden sein")
    }
}
