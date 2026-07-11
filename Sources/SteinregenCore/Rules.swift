// Rules.swift
// Modusuebergreifende Spielregel-Bausteine: Punktwertung, Level-Takt und die Zufalls-Ziehung
// der Steinfarben. Frueher lagen `points`/`gemsPerLevel` als Statics in der Saeulen-`Engine`
// und jede Engine hatte eine eigene, fast identische Zieh-Funktion — damit war die
// Saeulen-Engine der heimliche Konstanten-Speicher ALLER Modi (ein Umbau dort haette die
// anderen Engines gebrochen). Jetzt liegen die geteilten Regeln hier, sichtbar modusneutral.

/// Punktwertung + Level-Takt, geteilt von Saeulen, Klumpen, Austreibung und Schnitter.
/// (Eingemauert/Erdrueckt werten stattdessen volle Reihen ueber `TetrominoEngine.linePoints`;
/// die Magic-Chance der Saeulen bleibt als `Engine.magicOdds` beim einzigen Nutzer.)
public enum Scoring {
    /// So viele geraeumte Steine heben das Level um eins.
    public static let gemsPerLevel = 30

    /// Punkte einer Raeum-Welle: je Stein 10 Punkte, multipliziert mit der Kettenstufe
    /// (Kettenreaktionen werden also stark belohnt).
    static func points(cleared: Int, chain: Int) -> Int {
        cleared * 10 * chain
    }
}

/// Zieht `count` Steinfarben aus `palette` — deterministisch aus dem injizierten PRNG.
/// Gemeinsamer Baustein der Zieh-Funktionen aller Engines (Saeule 3 aus 6, Klumpen 2 aus 4,
/// Kapsel 2 aus 3, Block 4 aus 2). Magic kommt hier nie vor — die Magic-Chance wuerfelt
/// allein `Engine.drawColumn`.
func draw(_ count: Int, from palette: [Gem], using rng: inout Xoshiro256StarStar) -> [Gem] {
    (0..<count).map { _ in palette[Int(rng.next() % UInt64(palette.count))] }
}
