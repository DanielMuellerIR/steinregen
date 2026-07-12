// StartView.swift
// Startbildschirm der App: Logo, Spielmodus-Wahl (2×2-Chips), Start-Tempostufe mit
// Endlos-Umschalter und die drei Menue-Knoepfe. Steuerung fokus-unabhaengig — macOS per
// NSEvent-Tastatur (← → Tempo, ↑ ↓ Modus), iOS per Tap. Aus SteinregenApp.swift ausgegliedert.

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import SteinregenCore
import SteinregenRender

struct StartView: View {
    @Binding var startLevel: Int
    @Binding var mode: GameMode
    @Binding var endless: Bool
    let onSettings: () -> Void
    let onFriedhof: () -> Void
    let onRules: () -> Void
    let onStart: () -> Void

    #if os(macOS)
    // Fokus-unabhängiger Tastatur-Monitor fürs Menü: ← → wählen das Start-Tempo (wie im Spiel,
    // bewährtes NSEvent-Muster). Return startet über den Standard-Knopf (`.defaultAction`).
    @State private var keyMonitor: Any?
    #endif

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #endif
    // Menü-Logo: auf iPad deutlich größer (dort ist reichlich Platz), sonst Standardmaß.
    private var menuLogoMaxWidth: CGFloat {
        #if os(iOS)
        isPad ? 660 : 480
        #else
        480
        #endif
    }
    private var menuLogoHeight: CGFloat {
        #if os(iOS)
        if isPad { return 320 }
        // Kleine iPhones (SE ~667 pt, mini ~812 pt) brauchen ein kleineres Logo, damit der ganze
        // Startbildschirm ohne Scrollen passt; große iPhones behalten das volle Maß.
        let h = UIScreen.main.bounds.height
        return h < 700 ? 132 : (h < 850 ? 180 : 210)
        #else
        return 210
        #endif
    }

    var body: some View {
        // Zentrierende ScrollView auf BEIDEN Plattformen: durch Modus- und Tempo-Verlauf-Wahl ist der
        // Menü-Inhalt höher geworden und kann ein knapp bemessenes Fenster / schmales iPhone
        // überlaufen. `minHeight = sichtbare Höhe` hält die bisherige vertikale Zentrierung (Spacer)
        // bei, wo der Platz reicht (großes Fenster / iPad), und macht den Rest scrollbar statt ihn
        // oben/unten abzuschneiden — alle Element-Maße bleiben unverändert.
        GeometryReader { geo in
            ScrollView { menuContent.frame(minHeight: geo.size.height) }
        }
    }

    private var menuContent: some View {
        VStack(spacing: 14) {
            #if os(macOS)
            // macOS: kleiner fester Abstand oben → Logo sitzt nah am oberen Rand (statt mittig
            // zentriert wie früher). Die flexiblen Spacer ZWISCHEN den Gruppen (unten) ziehen den
            // restlichen Inhalt auseinander; die Menü-Reihe landet so unten. iOS bleibt unberührt
            // (kein Spacer → Inhalt oben, passt ohne Scrollen aufs iPhone).
            Spacer().frame(height: 40)
            #endif
            VStack(spacing: 6) {
                // Logo-Grafik statt Schriftzug; Fallback auf den Blackletter-Text, falls die
                // Datei fehlt (z.B. in einem Build ohne logo.png im Bundle). FESTE Höhe, damit das
                // Logo nicht von größeren Nachbar-Elementen gequetscht wird (war der Grund, warum es
                // nach der Schrift-Vergrößerung winzig wurde).
                if let logo = Theme.logoImage() {
                    Image(decorative: logo, scale: 1)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: menuLogoMaxWidth)
                        .frame(height: menuLogoHeight)
                        .shadow(color: .black.opacity(0.7), radius: 6, y: 2)
                } else {
                    Text("Steinregen")
                        .font(.custom(Theme.blackletterFamily, size: 60))
                        .foregroundStyle(Theme.bone.color)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                }
            }

            #if os(iOS)
            Spacer()   // iOS: flexibler Abstand — Logo oben, Auswahl rückt zur Mitte (kollabiert auf kleinen iPhones)
            #endif
            #if os(macOS)
            Spacer()   // macOS: flexibler Abstand Logo → Modus (zieht die Gruppen auseinander)
            #endif

            // Spielmodus — vier Chips im 2×2-Raster (Steinschlag / Eingemauert / Blutklumpen /
            // Erdrückt): vier nebeneinander würden selbst auf macOS zu schmal. Auf macOS
            // zusätzlich per ↑ ↓ zyklisch wählbar (← → bleiben fürs Tempo), auf iOS per Tap.
            VStack(spacing: 10) {
                Text(L10n.t("Modus", "Mode"))
                    .font(.custom(Theme.blackletterBoldPostScript, size: 28)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(GameMode.allCases, id: \.self) { m in modeChip(m) }
                }
                .frame(maxWidth: 394)        // macOS: 2×190 je Zeile; schmales iPhone: Chips schrumpfen mit
                Text(mode.hint)
                    .font(.custom(Theme.blackletterFamily, size: 20)).foregroundStyle(.tertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)   // einzeilig halten — notfalls kleiner statt umbrechen
            }

            #if os(macOS)
            Spacer()   // macOS: flexibler Abstand Modus → Tempo
            #endif

            // Start-Tempostufe — eigene ◀ Level N ▶-Steuerung (statt des hässlichen System-Steppers).
            // Ohne Überschrift/Erklärung: dass „Level" das Tempo ist, versteht sich von selbst.
            VStack(spacing: 10) {
                HStack(spacing: 24) {
                    StepperArrow(symbol: "chevron.left.circle.fill", size: 38, enabled: startLevel > 1) {
                        if startLevel > 1 { startLevel -= 1 }
                    }
                    Text("Level \(startLevel)")
                        .font(.custom(Theme.blackletterBoldPostScript, size: 42))
                        .foregroundStyle(Theme.bone.color)
                        .frame(minWidth: 170)
                    StepperArrow(symbol: "chevron.right.circle.fill", size: 38, enabled: startLevel < 10) {
                        if startLevel < 10 { startLevel += 1 }
                    }
                }
                // Tempo-Verlauf: steigt es mit dem Level oder bleibt es konstant („Endlos")?
                HStack(spacing: 10) {
                    tempoPill(L10n.t("steigt mit Level", "rises with level"), selected: !endless) { endless = false }
                    tempoPill(L10n.t("konstant", "constant"), selected: endless) { endless = true }
                }
            }

            #if os(iOS)
            Spacer()   // iOS: flexibler Abstand vor dem Start-Knopf
            #endif
            #if os(macOS)
            Spacer()   // macOS: flexibler Abstand Tempo → Start-Knopf
            #endif

            Button(action: onStart) {
                Text(L10n.t("Spiel starten", "Start game"))
                    .font(.custom(Theme.blackletterBoldPostScript, size: 22))
                    .frame(width: 220, height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)

            #if os(iOS)
            Spacer()   // iOS: schiebt die drei Menü-Knöpfe relativ nach unten (kein fixer Abstand)
            #endif
            #if os(macOS)
            Spacer()   // macOS: flexibler Abstand Start → Menü-Reihe (drückt die Knöpfe nach unten)
            #endif

            // Die drei Menü-Knöpfe: auf macOS eine Zeile mit breiten Knöpfen, auf iPhone eine
            // kompakte Reihe aus Icon+Label, damit alles ohne Scrollen aufs Bild passt.
            #if os(macOS)
            HStack(spacing: 8) { menuButtons }
                .buttonStyle(.bordered)
                .tint(Theme.boneDim.color)
            #else
            HStack(spacing: 10) {
                compactMenuButton(L10n.t("Einstellungen", "Settings"), "gearshape", onSettings)
                compactMenuButton(L10n.t("Spielregeln", "How to play"), "book", onRules)
                compactMenuButton(L10n.t("Friedhof", "Graveyard"), "list.number", onFriedhof)
            }
            #endif

            #if os(macOS)
            Spacer().frame(height: 20)   // macOS: kleiner fester Abstand unten → Menü-Reihe nah am unteren Rand
            #endif
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 14)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // ← → ändern das Start-Tempo, ohne dass ein Knopf den Fokus braucht. Andere Tasten (u.a.
    // Return) reicht der Monitor unverändert weiter → der Start-Knopf fängt Return per defaultAction.
    // Nur macOS — auf iOS bedienen Taps die ◀ ▶-Knöpfe direkt.
    private func installKeyMonitor() {
        #if os(macOS)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.keyCode {
            case 123: if startLevel > 1  { startLevel -= 1 }; return nil   // ←
            case 124: if startLevel < 10 { startLevel += 1 }; return nil   // →
            case 126: cycleMode(-1); return nil                           // ↑
            case 125: cycleMode(+1); return nil                           // ↓
            default:  return event
            }
        }
        #endif
    }

    private func removeKeyMonitor() {
        #if os(macOS)
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        #endif
    }

    /// Die drei Menü-Knöpfe (Einstellungen/Spielregeln/Friedhof) — Inhalt für beide Plattform-Layouts.
    @ViewBuilder private var menuButtons: some View {
        Button(action: onSettings) {
            Label(L10n.t("Einstellungen", "Settings"), systemImage: "gearshape")
                .font(.custom(Theme.blackletterFamily, size: 22))
                .frame(width: 168, height: 48)
        }
        Button(action: onRules) {
            Label(L10n.t("Spielregeln", "How to play"), systemImage: "book")
                .font(.custom(Theme.blackletterFamily, size: 22))
                .frame(width: 168, height: 48)
        }
        Button(action: onFriedhof) {
            Label(L10n.t("Friedhof", "Graveyard"), systemImage: "list.number")
                .font(.custom(Theme.blackletterFamily, size: 22))
                .frame(width: 168, height: 48)
        }
    }

    #if os(iOS)
    /// Kompakter Menü-Knopf fürs iPhone: Icon über kleinem Label, drei nebeneinander in einer Reihe
    /// (spart Höhe gegenüber drei gestapelten Knöpfen — der Startbildschirm passt so ohne Scrollen).
    private func compactMenuButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(title).font(.custom(Theme.blackletterFamily, size: 14))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
        }
        .buttonStyle(.bordered)
        .tint(Theme.boneDim.color)
    }
    #endif

    /// Ein Modus-Chip; der gewaehlte Modus ist mit Ochsenblut hinterlegt (kein Fokusrahmen — die
    /// Bedienung laeuft per Tap bzw. auf macOS ueber ↑ ↓).
    private func modeChip(_ m: GameMode) -> some View {
        let selected = (m == mode)
        return Button { mode = m } label: {
            Text(m.title)
                .font(.custom(Theme.blackletterBoldPostScript, size: 26))
                .lineLimit(1).minimumScaleFactor(0.75)   // auf schmalem iPhone notfalls leicht kleiner
                .foregroundStyle(selected ? Theme.bone.color : Theme.boneDim.color)
                .frame(maxWidth: .infinity)               // beide Chips teilen sich die Breite gleichmäßig
                .frame(height: 54)
                .background(selected ? Theme.oxblood.color : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Theme.blood.color : Color.white.opacity(0.12),
                            lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    /// Kleine Kapsel zur Wahl des Tempo-Verlaufs (steigend vs. konstant); gewaehlte in Ochsenblut.
    private func tempoPill(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(Theme.blackletterFamily, size: 18))
                .foregroundStyle(selected ? Theme.bone.color : Theme.boneDim.color)
                .padding(.horizontal, 16).frame(height: 38)
                .background(selected ? Theme.oxblood.color : Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.blood.color : Color.white.opacity(0.12),
                                          lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain).focusable(false)
    }

    /// Schaltet den Modus zyklisch um (fuer die ↑ ↓-Tasten auf macOS).
    private func cycleMode(_ delta: Int) {
        let all = GameMode.allCases
        guard let i = all.firstIndex(of: mode) else { return }
        mode = all[(i + delta + all.count) % all.count]
    }

}
