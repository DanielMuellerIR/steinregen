import XCTest
@testable import SteinregenRender

/// Tests der Musik-Stück-Entdeckung (ab v0.27.2 automatisch statt fester Namensliste):
/// `discoverTracks` findet alle lückenlos nummerierten `musik-N.mp3` im Ressourcen-Bundle.
final class MusicPlayerTests: XCTestCase {

    @MainActor
    func testDiscoversAllBundledTracksInOrder() {
        let tracks = MusicPlayer.discoverTracks(in: Theme.resourceBundle)
        // Aktuell liegen drei Stücke im Bundle; ein spaeter ergaenztes musik-4.mp3 usw. wird
        // automatisch mitgefunden — darum >= 3 statt == 3 (der Test soll dann NICHT brechen).
        XCTAssertGreaterThanOrEqual(tracks.count, 3, "die drei ausgelieferten Stücke müssen gefunden werden")
        for (i, url) in tracks.enumerated() {
            XCTAssertEqual(url.lastPathComponent, "musik-\(i + 1).mp3",
                           "Stücke kommen in lückenlos aufsteigender Reihenfolge")
        }
    }

    @MainActor
    func testDiscoveryStopsAtFirstGap() throws {
        // Kunst-Bundle in einem Temp-Verzeichnis: musik-1..3 vorhanden, musik-4 FEHLT,
        // musik-5 vorhanden → die Entdeckung muss bei der Lücke stoppen (genau 3 Stücke).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("steinregen-musictest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for n in [1, 2, 3, 5] {
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent("musik-\(n).mp3").path, contents: Data())
        }
        let bundle = try XCTUnwrap(Bundle(url: dir))
        let tracks = MusicPlayer.discoverTracks(in: bundle)
        XCTAssertEqual(tracks.map(\.lastPathComponent),
                       ["musik-1.mp3", "musik-2.mp3", "musik-3.mp3"],
                       "die Lücke bei musik-4 beendet die Suche — musik-5 bleibt unberücksichtigt")
    }
}
