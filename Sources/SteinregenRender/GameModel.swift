// GameModel.swift
// Schmale Beobachtungs-Bruecke zwischen SpriteKit-Szene und SwiftUI. Die Szene rendert HUD,
// Brett und Steine selbst; SwiftUI braucht nur das Spielende (fuer das Overlay) und den
// Endpunktestand. Bewusst minimal gehalten.

import SwiftUI

@MainActor
@Observable
public final class GameModel {
    /// Wird true, sobald der Einwurf blockiert ist (Spiel vorbei).
    public var isGameOver: Bool = false
    /// Punktestand bei Spielende (fuer das Game-Over-Overlay / den Friedhof-Eintrag).
    public var finalScore: Int = 0
    /// Level bei Spielende („Verreckt in Level …").
    public var finalLevel: Int = 0
    /// Live-Punktestand (optional fuer SwiftUI; die Szene zeigt ihn ohnehin selbst).
    public var score: Int = 0
    /// Aktuelles Level (live).
    public var level: Int = 0

    public init() {}

    public func reset() {
        isGameOver = false
        finalScore = 0
        finalLevel = 0
        score = 0
        level = 0
    }
}
