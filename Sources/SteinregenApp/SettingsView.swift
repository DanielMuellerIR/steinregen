// SettingsView.swift
// Einstellungs-Dialog: Sprache, Ton/Klang-Set, Musik, Brettgroesse je Modus und die
// Steine-Set-Auswahl mit Live-Vorschau. Enthaelt StoneSetCard und den Theme-Schrift-
// Segmentschalter ThemeSegmented. Aus SteinregenApp.swift ausgegliedert.

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import SteinregenCore
import SteinregenRender

/// Auswahl-Dialog fuer das Steine-Set, mit Live-Vorschau. Die Auswahl wird per `@AppStorage`
/// im selben UserDefaults-Schluessel gemerkt, den die Render-Schicht (`StoneSets.selectedID`)
/// liest — beim naechsten Spielstart gilt das gewaehlte Set. Neue Sets erscheinen hier
/// automatisch, sobald sie in `StoneSets.all` stehen.
struct SettingsView: View {
    /// Modus, dessen Brettmaße hier eingestellt werden (im Menü gewählt, vom Aufrufer durchgereicht).
    /// Als Binding, NICHT als Wert-Kopie: Das Inhalts-Closure von `.sheet` kann einen veralteten
    /// View-Stand einfangen (beobachtet bei der env-Naht STEINREGEN_MODE + STEINREGEN_SETTINGS —
    /// die Karte zeigte den alten Modus); ein Binding liest dagegen IMMER live aus dem
    /// @State-Speicher des Aufrufers.
    @Binding var mode: GameMode
    @AppStorage(StoneSets.defaultsKey) private var selectedSet = "doom"   // Standard-Set
    @AppStorage(SoundFX.mutedKey) private var mundtot = false             // true = Soundeffekte aus
    @AppStorage(SoundFX.setKey) private var soundSetRaw = SoundFX.SoundSet.eigene.rawValue  // Klang-Set
    @AppStorage(MusicPlayer.mutedKey) private var musikAus = false        // true = Musik aus (separat!)
    @AppStorage(L10n.key) private var langRaw = ""                        // "" = Auto (System-Sprache)
    // Brettmaße je Modus (gleiche Schlüssel wie BoardConfig — dort liest der Spielstart sie). 0 =
    // ungesetzt; die Stepper-Bindings unten setzen beim ersten Antippen den Modus-Standard ein.
    @AppStorage(BoardConfig.saeulenWidthKey)       private var saeulenW = 0
    @AppStorage(BoardConfig.saeulenHeightKey)      private var saeulenH = 0
    @AppStorage(BoardConfig.verschuettetWidthKey)  private var verschuettetW = 0
    @AppStorage(BoardConfig.verschuettetHeightKey) private var verschuettetH = 0
    @AppStorage(BoardConfig.klumpenWidthKey)       private var klumpenW = 0
    @AppStorage(BoardConfig.klumpenHeightKey)      private var klumpenH = 0
    @AppStorage(BoardConfig.fuenflingWidthKey)     private var fuenflingW = 0
    @AppStorage(BoardConfig.fuenflingHeightKey)    private var fuenflingH = 0
    @AppStorage(BoardConfig.kapselnWidthKey)       private var kapselnW = 0
    @AppStorage(BoardConfig.kapselnHeightKey)      private var kapselnH = 0
    @AppStorage(BoardConfig.schnitterWidthKey)     private var schnitterW = 0
    @AppStorage(BoardConfig.schnitterHeightKey)    private var schnitterH = 0
    let onClose: () -> Void

    // Aktuelle (geklemmte) Maße des gewählten Modus + Schreib-Bindings, die den Modus-Standard
    // einsetzen, falls noch nichts gespeichert ist.
    private var curWidth: Int  { BoardConfig.width(mode) }
    private var curHeight: Int { BoardConfig.height(mode) }
    private func setWidth(_ v: Int) {
        switch mode {
        case .saeulen:      saeulenW = v
        case .verschuettet: verschuettetW = v
        case .klumpen:      klumpenW = v
        case .fuenfling:    fuenflingW = v
        case .kapseln:      kapselnW = v
        case .schnitter:    schnitterW = v
        }
    }
    private func setHeight(_ v: Int) {
        switch mode {
        case .saeulen:      saeulenH = v
        case .verschuettet: verschuettetH = v
        case .klumpen:      klumpenH = v
        case .fuenfling:    fuenflingH = v
        case .kapseln:      kapselnH = v
        case .schnitter:    schnitterH = v
        }
    }

    /// Steine-Set per Tastatur durchschalten (↑ ↓): verschiebt die Auswahl zyklisch
    /// durch `StoneSets.all`. Die Auswahl wirkt sofort (Live-Vorschau in den Karten).
    private func moveStone(_ direction: Int) {
        let all = StoneSets.all
        guard let i = all.firstIndex(where: { $0.id == selectedSet }) else {
            if let first = all.first { selectedSet = first.id }
            return
        }
        let n = all.count
        selectedSet = all[(i + direction + n) % n].id
    }

    /// Eine Stepper-Zeile für ein Brettmaß (Beschriftung · ◀ Wert ▶ · Spanne), auf `range` begrenzt.
    private func dimRow(_ label: String, value: Int, range: ClosedRange<Int>,
                        set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.custom(Theme.blackletterFamily, size: 20))
                .foregroundStyle(Theme.boneDim.color)
                .frame(width: 64, alignment: .leading)
            StepperArrow(symbol: "chevron.left.circle.fill", size: 26, enabled: value > range.lowerBound) {
                set(max(range.lowerBound, value - 1))
            }
            Text("\(value)")
                .font(.custom(Theme.blackletterBoldPostScript, size: 26))
                .foregroundStyle(Theme.bone.color)
                .frame(minWidth: 44)
            StepperArrow(symbol: "chevron.right.circle.fill", size: 26, enabled: value < range.upperBound) {
                set(min(range.upperBound, value + 1))
            }
            Text("(\(range.lowerBound)–\(range.upperBound))")
                .font(.custom(Theme.blackletterFamily, size: 18)) // war 16, unter der 18pt-Untergrenze
                .foregroundStyle(Theme.boneDim.color.opacity(0.7))
        }
    }

    var body: some View {
        content
            .dialogFrame(width: 480, height: 880)
            .background(Color(red: 0.02, green: 0.02, blue: 0.03))
            .preferredColorScheme(.dark)
    }

    // iOS: die ganze Seite ist scrollbar — sonst klemmt der Inhalt auf dem iPhone (mit der
    // Sprach-Karte wird er höher als der Schirm, und der Titel würde oben abgeschnitten).
    // macOS: feste Dialoghöhe wie gehabt, dort scrollt nur die Steine-Liste.
    @ViewBuilder private var content: some View {
        #if os(iOS)
        ScrollView { stack.padding(24) }
        #else
        stack.padding(24)
        #endif
    }

    private var stack: some View {
        VStack(spacing: 14) {
            Text(L10n.t("Einstellungen", "Settings"))
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)

            // Sprache — Deutsch/Englisch. Standard ist die System-Sprache; hier fest umstellbar.
            // Der Schreibweg (L10n.lang) setzt denselben UserDefaults-Schlüssel, den alle Views
            // über @AppStorage(L10n.key) beobachten → die Oberfläche zeichnet sich sofort neu.
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Sprache", "Language"))
                    .font(.custom(Theme.blackletterFamily, size: 22))
                    .foregroundStyle(Theme.bone.color)
                ThemeSegmented(
                    options: [("Deutsch", "de"), ("English", "en")],
                    selection: Binding(
                        get: { L10n.lang.rawValue },
                        set: { v in L10n.lang = L10n.Lang(rawValue: v) ?? .de }))
            }
            .themeCard()

            // Ton & Klang — eine Karte, drei sich gegenseitig ausschließende Optionen:
            // „Steinregen" (eigene Klänge, Ton an) · „Freedoom" (klassische Klänge, Ton an) ·
            // „Mundtot" (Ton aus). Bedienbar per Maus UND Tastatur (← → / Leertaste). Gleiche
            // Theme-Schrift wie der Rest (kein Stilbruch). Treibt SoundFX.muted + .soundSet.
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Ton", "Sound"))
                    .font(.custom(Theme.blackletterFamily, size: 22))
                    .foregroundStyle(Theme.bone.color)
                ThemeSegmented(
                    options: [("Steinregen", "eigene"),
                              ("Freedoom", "freedoom"),
                              (L10n.t("Mundtot", "Silenced"), "mundtot")],
                    selection: Binding(
                        get: { mundtot ? "mundtot" : soundSetRaw },
                        set: { v in
                            if v == "mundtot" { mundtot = true }
                            else { mundtot = false; soundSetRaw = v }
                        }))
                Text(mundtot
                     ? L10n.t("Mundtot — keine Soundeffekte (im Spiel: Taste T)",
                              "Silenced — no sound effects (in-game: T)")
                     : L10n.t("Soundeffekte an, Set \(soundSetRaw == "freedoom" ? "Freedoom" : "Steinregen") (im Spiel: Taste T)",
                              "Sound effects on, set \(soundSetRaw == "freedoom" ? "Freedoom" : "Steinregen") (in-game: T)"))
                    .font(.custom(Theme.blackletterFamily, size: 18))
                    .foregroundStyle(mundtot ? Theme.blood.color : Theme.boneDim.color)
            }
            .themeCard()

            // Musik — bewusst GETRENNT von den Soundeffekten (eigene Karte, eigener Schalter).
            // An/Aus über dieselbe Theme-Schrift-Segmentanzeige. Treibt MusicPlayer.setEnabled
            // (persistiert + wirkt sofort); die Musik läuft ohnehin erst ab Levelbeginn.
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Musik", "Music"))
                    .font(.custom(Theme.blackletterFamily, size: 22))
                    .foregroundStyle(Theme.bone.color)
                ThemeSegmented(
                    options: [(L10n.t("An", "On"), "an"), (L10n.t("Aus", "Off"), "aus")],
                    selection: Binding(
                        get: { musikAus ? "aus" : "an" },
                        set: { v in MusicPlayer.shared.setEnabled(v == "an") }))
                Text(musikAus
                     ? L10n.t("Musik aus (im Spiel: Taste M)", "Music off (in-game: M)")
                     : L10n.t("Musik an — startet erst im Spiel (im Spiel: Taste M)",
                              "Music on — starts only in-game (in-game: M)"))
                    .font(.custom(Theme.blackletterFamily, size: 18))
                    .foregroundStyle(musikAus ? Theme.blood.color : Theme.boneDim.color)
            }
            .themeCard()

            // Brettgröße des gewählten Modus — zwei Stepper (Breite/Höhe), auf die erlaubte Spanne
            // begrenzt. Wirkt ab der nächsten Partie (Maße werden beim Spielstart gelesen).
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Brettgröße — \(mode.title)", "Board size — \(mode.title)"))
                    .font(.custom(Theme.blackletterFamily, size: 22))
                    .foregroundStyle(Theme.bone.color)
                dimRow(L10n.t("Breite", "Width"), value: curWidth, range: mode.widthRange, set: setWidth)
                dimRow(L10n.t("Höhe", "Height"),  value: curHeight, range: mode.heightRange, set: setHeight)
                Text(L10n.t("Standard \(mode.defaultWidth)×\(mode.defaultHeight) · gilt ab der nächsten Partie",
                            "Default \(mode.defaultWidth)×\(mode.defaultHeight) · applies from the next game"))
                    .font(.custom(Theme.blackletterFamily, size: 18))
                    .foregroundStyle(Theme.boneDim.color)
            }
            .themeCard()

            Text(L10n.t("Steine-Set", "Stone set"))
                .font(.custom(Theme.blackletterFamily, size: 22))
                .foregroundStyle(Theme.bone.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            stoneSection

            DoneButton(title: L10n.t("Fertig", "Done"), action: onClose)
        }
    }

    // Die Steine-Karten. macOS: in einer eigenen, fokussierbaren ScrollView (↑ ↓ schalten durch
    // die Sets) — füllt im festen Dialog den Rest. iOS: nur die Kartenliste (die ganze Seite
    // scrollt bereits via `content`, ein zweiter Scroll in selber Richtung würde sich beißen).
    @ViewBuilder private var stoneSection: some View {
        let cards = VStack(spacing: 14) {
            ForEach(StoneSets.all) { set in
                StoneSetCard(set: set, selected: selectedSet == set.id) { selectedSet = set.id }
            }
        }
        .padding(.horizontal, 2)
        #if os(iOS)
        cards
        #else
        ScrollView { cards }
            .focusable()
            .onKeyPress(.upArrow)   { moveStone(-1); return .handled }
            .onKeyPress(.downArrow) { moveStone(1);  return .handled }
        #endif
    }
}

/// Eine anklickbare Karte je Set: Name, Kurzbeschreibung und eine Vorschau der sechs Steine.
struct StoneSetCard: View {
    let set: StoneSet
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(set.name)
                        .font(.custom(Theme.blackletterFamily, size: 22))
                        .foregroundStyle(Theme.bone.color)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(selected ? Theme.oxblood.color : Theme.boneDim.color)
                }
                // Live-Vorschau: die sechs Steine dieses Sets.
                HStack(spacing: 6) {
                    ForEach(Gem.colors, id: \.self) { gem in
                        Image(decorative: GemTextures.previewImage(gem, set: set.id), scale: 1)
                            .resizable().interpolation(.high)
                            .frame(width: 38, height: 38)
                    }
                }
            }
            .themeCard()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Theme.oxblood.color : Color.white.opacity(0.10),
                            lineWidth: selected ? 2 : 1)
            )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

/// Segmentierter Auswahl-Schalter in der Theme-Schrift (kein System-Picker → kein
/// Stilbruch). Bedienbar per Maus (Klick) UND Tastatur: fokussieren (Tab), dann
/// ← → bzw. Leertaste schalten die Auswahl. Generisch über String-Werte.
struct ThemeSegmented: View {
    let options: [(label: String, value: String)]
    @Binding var selection: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { opt in
                segment(opt)
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(focused ? Theme.bone.color.opacity(0.7) : Color.white.opacity(0.08),
                    lineWidth: focused ? 2 : 1))
        .focusable()
        .focused($focused)
        .onKeyPress(.leftArrow)  { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1);  return .handled }
        .onKeyPress(.space)      { move(1);  return .handled }
    }

    /// Ein Segment (typisierte Zwischen-Variablen, damit der Type-Checker schnell bleibt).
    @ViewBuilder
    private func segment(_ opt: (label: String, value: String)) -> some View {
        let isSel = opt.value == selection
        let fg: Color = isSel ? Theme.bone.color : Theme.boneDim.color
        let bg: Color = isSel ? Theme.oxblood.color.opacity(0.35) : Color.white.opacity(0.05)
        let ring: Color = isSel ? Theme.oxblood.color : Color.clear
        Text(opt.label)
            .font(.custom(Theme.blackletterFamily, size: 22))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(bg, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(ring, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture { selection = opt.value }
    }

    /// Auswahl zyklisch um `direction` verschieben.
    private func move(_ direction: Int) {
        guard let i = options.firstIndex(where: { $0.value == selection }) else {
            if let first = options.first { selection = first.value }
            return
        }
        let n = options.count
        selection = options[(i + direction + n) % n].value
    }
}
