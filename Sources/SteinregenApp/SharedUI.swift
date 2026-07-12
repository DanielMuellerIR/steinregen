// SharedUI.swift
// Geteilte UI-Bausteine der App-Schicht: die Farb-/Dialog-Helfer sowie die mehrfach genutzten
// Steuerelemente (Karten-Hintergrund, Chevron-Stepper-Pfeil, Fertig-Knopf). Frueher lagen die
// Helfer als private Extensions in SteinregenApp.swift; seit die Views in eigene Dateien
// aufgeteilt sind, liegen sie hier modulweit sichtbar (kein `private` — gleiches Modul).

import SwiftUI
import SteinregenCore
import SteinregenRender

/// Bequemer Brueckenbau: dieselbe (r,g,b)-Palette wie die Render-Schicht als SwiftUI-`Color`.
extension Theme.RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

extension View {
    /// Dialog-Maße: auf macOS ein festes Sheet-Format, auf iOS bildschirmfüllend (das iPhone
    /// gibt die Größe vor). Hält die drei Dialoge (Einstellungen/Friedhof/Spielregeln) konsistent.
    @ViewBuilder func dialogFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    /// Karten-Hintergrund der Einstellungen: 12 pt Innenabstand, linksbündig über die volle
    /// Breite, gedämpfte Füllung mit abgerundeter Ecke. Fasst das mehrfach wortgleich
    /// wiederholte Karten-Layout zusammen — die Optik bleibt unverändert.
    func themeCard() -> some View {
        self.padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Großer Chevron-Pfeil für die ◀ Wert ▶-Stepper (Start-Tempo im Menü, Brettmaße in den
/// Einstellungen). Am Bereichsende gedämpft und deaktiviert; kein Fokusrahmen (die Bedienung
/// läuft per ← → bzw. Tap). SF-Symbol statt Schrift-Glyphe — die gotische Schrift hat keine
/// Pfeile. `size` unterscheidet die Verwendungsorte (Menü 38 pt, Einstellungen 26 pt).
struct StepperArrow: View {
    let symbol: String
    var size: CGFloat
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(enabled ? Theme.blood.color : Theme.boneDim.color.opacity(0.35))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
    }
}

/// „Fertig"/„Schließen"-Knopf der Dialoge (Einstellungen/Friedhof/Spielregeln): einheitliches
/// Maß, Ochsenblut-Tint, als Standard-Aktion per Return auslösbar. Fasst die drei zuvor
/// identischen Schließen-Knöpfe zusammen.
struct DoneButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(Theme.blackletterBoldPostScript, size: 18))
                .frame(width: 200, height: 42)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.oxblood.color)
        .keyboardShortcut(.defaultAction)
    }
}
