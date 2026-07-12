// RulesSheet.swift
// Der Spielregeln-Dialog: eine Sektion je Modus plus gemeinsame Steuerung und Tempo/Ende,
// zweisprachig. Aus SteinregenApp.swift ausgegliedert.

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import SteinregenCore
import SteinregenRender

/// Eigenes Fenster (Menü-Button „Spielregeln"): erklärt ALLE sechs Spielmodi einzeln plus die
/// gemeinsame Steuerung und Tempo/Spielende — damit Neulinge ohne Genre-Vorwissen loslegen
/// können (ab v0.27.1; bis dahin erklärte der Dialog nur den Steinschlag-Modus).
struct RulesSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("Spielregeln", "How to play"))
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(GameMode.saeulen.title, L10n.t("""
                    Der Klassiker: Eine Säule aus drei Steinen fällt; Drehen tauscht ihre Steine \
                    zyklisch durch. Liegen DREI gleiche in einer Linie — waagerecht, senkrecht \
                    oder diagonal — lösen sie sich auf. Nachrutschende Steine können Ketten \
                    auslösen (2× · 3× · 4× …), jede Stufe gibt deutlich mehr Punkte. Selten \
                    schwebt eine hell pulsierende Säule ein, der einzige Spezialstein: Beim \
                    Aufsetzen räumt er BRETTWEIT alle Steine der Sorte, auf der er landet.
                    """, """
                    The classic: a column of three stones falls; rotating cycles its stones. \
                    When THREE alike line up — horizontally, vertically or diagonally — they \
                    clear. Stones falling in can trigger chains (2× · 3× · 4× …), each step \
                    scoring far more. Rarely a brightly pulsing column floats in, the only \
                    special stone: where it lands, it clears EVERY stone of the kind beneath it \
                    from the whole board.
                    """))
                    section(GameMode.verschuettet.title, L10n.t("""
                    Vierer-Formen fallen, Drehen dreht die Form. Volle REIHEN verschwinden — die \
                    Steinsorten sind hier reine Zierde, es zählt allein die lückenlose Reihe. \
                    Mehrere Reihen auf einen Schlag geben deutlich mehr Punkte.
                    """, """
                    Four-block shapes fall; rotating turns the shape. Full ROWS clear — the stone \
                    kinds are pure decoration here, only the complete row counts. Clearing \
                    several rows at once scores far more.
                    """))
                    section(GameMode.klumpen.title, L10n.t("""
                    Ein Steinpaar fällt und dreht sich um seinen Dreh-Stein; beim Aufsetzen \
                    fallen die beiden Hälften einzeln weiter. VIER oder mehr gleiche, seitlich \
                    oder übereinander verbundene Steine verschwinden (Diagonalen verbinden \
                    nicht) — Nachrutscher lösen Ketten aus.
                    """, """
                    A pair of stones falls and rotates around its pivot stone; on landing the \
                    two halves drop independently. FOUR or more alike stones connected sideways \
                    or vertically vanish (diagonals do not connect) — stones falling in trigger \
                    chains.
                    """))
                    section(GameMode.fuenfling.title, L10n.t("""
                    Wie Eingemauert, nur brutal: Es fallen alle achtzehn Fünfer-Formen auf ein \
                    größeres Brett. Volle Reihen räumen; fünf auf einen Streich schafft nur die \
                    senkrechte Fünfer-Linie.
                    """, """
                    Like Entombed, but brutal: all eighteen five-block shapes fall onto a larger \
                    board. Full rows clear; only the upright five-line can take five rows in one \
                    blow.
                    """))
                    section(GameMode.kapseln.title, L10n.t("""
                    Das Brett beginnt mit eingemauerten FLÜCHEN — beringte Steine, die \
                    festkleben und nie nachrutschen. Kapsel-Paare fallen und drehen wie im \
                    Blutklumpen-Modus. VIER gleiche in einer Reihe oder Spalte räumen (keine \
                    Diagonalen); jeder getilgte Fluch gibt Bonuspunkte. Sind ALLE Flüche \
                    getilgt, ist die Partie GEWONNEN — der einzige Modus mit Sieg. Die \
                    Tempostufe bestimmt hier auch die Zahl der Flüche.
                    """, """
                    The board starts with immured CURSES — ringed stones that stay pinned and \
                    never slide down. Capsule pairs fall and rotate as in Blood Clots. Clear \
                    FOUR alike in a row or column (no diagonals); every purged curse scores a \
                    bonus. Purge ALL curses and the game is WON — the only mode with a victory. \
                    The speed level here also sets the number of curses.
                    """))
                    section(GameMode.schnitter.title, L10n.t("""
                    Ein 2×2-Block aus zwei Steinsorten fällt; Drehen lässt seine Farben im Kreis \
                    wandern, beim Aufsetzen fallen die beiden Spalten einzeln. Gleichfarbige \
                    2×2-QUADRATE leuchten auf — geräumt werden sie erst von der SENSE, der \
                    Linie, die stetig übers Brett zieht und leuchtende Gruppen im Vorbeiziehen \
                    erntet. Je mehr Zellen ein Schnitt erwischt, desto mehr Punkte.
                    """, """
                    A 2×2 block of two stone kinds falls; rotating cycles its colors, and on \
                    landing its two columns drop independently. Same-colored 2×2 SQUARES light \
                    up — they are only cleared by the SCYTHE, the line that steadily crosses \
                    the board and reaps glowing groups as it passes. The more cells one cut \
                    catches, the more points.
                    """))
                    #if os(iOS)
                    section(L10n.t("Steuerung", "Controls"), L10n.t("""
                    Tippen dreht den fallenden Stein (was Drehen bewirkt, steht beim jeweiligen \
                    Modus). Nach links oder rechts wischen verschiebt ihn um einen Schritt, nach \
                    unten wischen wirft ihn sofort ganz nach unten. Unten liegt eine Knopfleiste: \
                    ◀ ▶ gehalten bewegen (mit Auto-Wiederholung), ↻ dreht, ▼ gehalten lässt \
                    schneller fallen, ⤓ wirft sofort ab. Ton und Musik schaltest du in den \
                    Einstellungen, der ✕-Knopf oben links führt ins Menü.
                    """, """
                    Tap rotates the falling piece (what rotating does is explained per mode). \
                    Swipe left or right to move it one step; swipe down to drop it all the way \
                    instantly. A button bar sits at the bottom: hold ◀ ▶ to move (with \
                    auto-repeat), ↻ rotates, hold ▼ for a faster fall, ⤓ drops instantly. Toggle \
                    sound and music in Settings; the ✕ button top-left returns to the menu.
                    """))
                    #else
                    section(L10n.t("Steuerung", "Controls"), L10n.t("""
                    Steuern kannst du wahlweise mit den Cursortasten oder mit den Tasten W, A, S, D \
                    — beides ist gleichwertig. Im Einzelnen: links und rechts verschieben den \
                    fallenden Stein, hoch dreht ihn (was Drehen bewirkt, steht beim jeweiligen \
                    Modus), runter lässt ihn schneller fallen. Die Leertaste wirft ihn sofort ganz \
                    nach unten, T schaltet die Soundeffekte an und aus, M die Musik, Esc führt \
                    zurück ins Menü.
                    """, """
                    Play with the arrow keys or with W, A, S, D — both work the same. In detail: \
                    left and right move the falling piece, up rotates it (what rotating does is \
                    explained per mode), down makes it fall faster. Space drops it all the way \
                    down, T toggles the sound effects, M the music, Esc returns to the menu.
                    """))
                    #endif
                    section(L10n.t("Tempo & Ende", "Speed & end"), L10n.t("""
                    Das Level steigt mit dem Geräumten; je höher, desto schneller fällt der \
                    Stein (nur in der Austreibung bleibt es fest auf der Startstufe). Die Partie \
                    endet, wenn der Einwurf oben blockiert ist — allein die Austreibung lässt \
                    sich gewinnen.
                    """, """
                    The level rises as you clear; the higher it is, the faster pieces fall (only \
                    in Exorcism it stays fixed at the starting level). The game ends when the \
                    spawn area at the top is blocked — Exorcism alone can be won.
                    """))
                }
                .padding(.horizontal, 4)
            }

            DoneButton(title: L10n.t("Fertig", "Done"), action: onClose)
        }
        .padding(24)
        .dialogFrame(width: 520, height: 720)
        .background(Color(red: 0.02, green: 0.02, blue: 0.03))
        .preferredColorScheme(.dark)
    }

    /// Eine Regel-Sektion: gotische Überschrift + erklärender Fließtext.
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.custom(Theme.blackletterBoldPostScript, size: 22))
                .foregroundStyle(Theme.blood.color)
            Text(text)
                .font(.custom(Theme.blackletterFamily, size: 20))
                .foregroundStyle(Theme.bone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
