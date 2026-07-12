// GameOverOverlay.swift
// Game-Over-/Sieg-Overlay: Titel, Punktestand, Namenseingabe fuer den Friedhof und die drei
// Weiter-Knoepfe (auf macOS per Cursortasten waehlbar). Aus SteinregenApp.swift ausgegliedert.

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import SteinregenCore
import SteinregenRender

struct GameOverOverlay: View {
    let score: Int
    let level: Int
    /// true = die Partie wurde GEWONNEN (Kapsel-Modus: alle Flueche getilgt) — Titel/Farbe
    /// wechseln auf die Sieg-Variante, alles andere (Friedhof-Eintrag, Knoepfe) bleibt gleich.
    var victory: Bool = false
    let onRetrySameSeed: () -> Void
    let onRetryNewSeed: () -> Void
    let onExit: () -> Void

    private enum Step { case entry, list }
    @State private var step: Step = .entry
    @State private var name = ""
    @State private var highlightID: UUID? = nil
    @FocusState private var nameFocused: Bool
    /// Im Listen-Schritt per Cursortasten gewählter Knopf (0 = Nochmal, 1 = Neues Spiel, 2 = Menü).
    @State private var selectedButton = 0
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text(victory ? L10n.t("Ausgetrieben", "Exorcised")
                                 : L10n.t("Verreckt", "Perished"))
                        .font(.custom(Theme.blackletterBoldPostScript, size: 56))
                        .foregroundStyle(victory ? Theme.bone.color : Theme.blood.color)
                    Text(L10n.t("Level \(level) · \(score) Punkte", "Level \(level) · \(score) points"))
                        .font(.custom(Theme.blackletterBoldPostScript, size: 22))
                        .foregroundStyle(Theme.bone.color)
                }

                if step == .entry {
                    entryView
                } else {
                    // Ohne Scrollbar: zeigt bis zu 8 Gräber direkt, kompakt gestapelt.
                    FriedhofView(entries: Friedhof.entries(), highlightID: highlightID,
                                 maxRows: 8, scroll: false)
                }

                buttons

                // Grabspruch ganz unten — bei einem Sieg (Kapsel-Modus) die triumphale Variante.
                Text(victory ? L10n.t("Die Flüche sind gebannt", "The curses are banished")
                             : L10n.t("Am Ende fällt jeder Stein", "In the end, every stone falls"))
                    .font(.custom(Theme.blackletterFamily, size: 20))
                    .tracking(1)
                    .foregroundStyle(Theme.blood.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.06, green: 0.055, blue: 0.07))
                    .shadow(color: .black.opacity(0.7), radius: 18, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.oxblood.color.opacity(0.9), lineWidth: 2)
            )
        }
        .onAppear {
            name = Friedhof.lastName
            if Friedhof.qualifies(score: score) {
                step = .entry
                DispatchQueue.main.async { nameFocused = true }
            } else {
                step = .list
            }
            #if os(macOS)
            installKeyMonitor()
            #endif
        }
        #if os(macOS)
        .onDisappear { removeKeyMonitor() }
        #endif
    }

    #if os(macOS)
    // Im Listen-Schritt steuern die Cursortasten die Auswahl der drei Knöpfe, Return löst sie aus
    // (fokus-unabhängiges NSEvent-Muster wie im Menü). Im Eingabe-Schritt gehört die Tastatur dem
    // Namensfeld (Pfeile = Textcursor, Return = abschicken) — dann reicht der Monitor alles durch.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard step == .list else { return event }
            switch event.keyCode {
            case 125, 124: selectedButton = (selectedButton + 1) % 3; return nil   // ↓ / →
            case 126, 123: selectedButton = (selectedButton + 2) % 3; return nil   // ↑ / ←
            case 36, 76:   activateSelected(); return nil                          // Return / Enter
            default:       return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func activateSelected() {
        switch selectedButton {
        case 0:  onRetrySameSeed()
        case 1:  onRetryNewSeed()
        default: onExit()
        }
    }
    #endif

    private var entryView: some View {
        VStack(spacing: 10) {
            Text(L10n.t("Ein Grab auf dem Friedhof — trag dich ein:", "A grave in the graveyard — sign it:"))
                .font(.custom(Theme.blackletterFamily, size: 22))
                .foregroundStyle(Theme.boneDim.color)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.custom(Theme.blackletterFamily, size: 22))
                .frame(width: 280)
                .focused($nameFocused)
                .onChange(of: name) { _, v in if v.count > 16 { name = String(v.prefix(16)) } }
                .onSubmit(submit)
            Button(action: submit) {
                Text(L10n.t("Begraben", "Bury")).font(.custom(Theme.blackletterBoldPostScript, size: 19)).frame(width: 240, height: 40)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            navButton(0, L10n.t("Nochmal (gleicher Seed)", "Again (same seed)"), action: onRetrySameSeed)
            navButton(1, L10n.t("Neues Spiel", "New game"), action: onRetryNewSeed)
            navButton(2, L10n.t("Hauptmenü", "Main menu"), action: onExit)
        }
    }

    /// Ein per Cursortasten ansteuerbarer Knopf: KEIN Fokusrahmen, stattdessen wechselt bei Auswahl
    /// die Hintergrundfarbe (Ochsenblut). Mausklick funktioniert weiterhin und merkt die Auswahl vor.
    private func navButton(_ index: Int, _ title: String, action: @escaping () -> Void) -> some View {
        let isSel = (selectedButton == index)
        return Button {
            selectedButton = index
            action()
        } label: {
            Text(title)
                .font(.custom(Theme.blackletterFamily, size: 18))
                .foregroundStyle(Theme.bone.color)
                .frame(width: 280, height: 44)
                .background(isSel ? Theme.oxblood.color : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isSel ? Theme.blood.color : Color.white.opacity(0.14),
                                lineWidth: isSel ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        highlightID = Friedhof.add(name: trimmed.isEmpty ? L10n.t("Niemand", "Nobody") : trimmed, score: score, level: level)
        step = .list
    }
}
