// Capsule.swift
// Ergebnis-Typen des fuenften Spielmodus „Austreibung" (Dr.-Mario-Stil): Es faellt ein
// Kapsel-PAAR aus zwei Steinen (dieselbe Paar-Geometrie wie im „Blutklumpen"-Modus — darum
// werden `PairPiece` und `PairOrientation` aus `Pair.swift` WIEDERVERWENDET, nicht dupliziert).
// Das Brett ist mit FLUECHEN vorbefuellt (festsitzende Zielsteine); geraeumt werden Laeufe aus
// mindestens vier gleichfarbigen Steinen in einer REIHE oder SPALTE (keine Diagonalen).
// Sind alle Flueche getilgt, ist die Partie GEWONNEN — der erste Modus mit Sieg-Bedingung.
// Bewusst markenfrei: „fallende Kapsel-Paare + Zielsteine" ist der Gattungsbegriff des Genres.
//
// Koordinaten wie im ganzen Spiel: Ursprung unten links, `row` waechst nach oben.

/// Ergebnis des Aufsetzens einer Kapsel. `boardBefore` ist das Brett direkt nach dem
/// Einschreiben BEIDER Steine an ihrer Aufsetz-Position — also VOR dem Nachrutschen (eine quer
/// liegende Haelfte kann darin noch ueber einem Loch schweben; die Render-Schicht animiert das
/// Herabfallen, siehe `postLockSettle` im PlayEngine-Protokoll). `steps` ist die komplette
/// Ketten-Kaskade (0..n Wellen) — Ketten entstehen, wenn nachrutschende Steine neue Laeufe bilden.
public struct CapsuleLock: Sendable, Equatable {
    public let landed: PairPiece
    public let boardBefore: Board
    public let steps: [ClearStep]
}

/// Ergebnis eines Schwerkraft-Ticks im „Austreibung"-Modus.
public enum CapsuleTick: Sendable, Equatable {
    case moved
    case locked(CapsuleLock)
}
