// SteinregenApp.swift
// SwiftUI-Shell von Steinregen: Startbildschirm (Titel, Start-Tempostufe, Seed),
// Spielansicht mit Tastatursteuerung und Game-Over-Overlay.
//
// Die Seed-Erzeugung passiert HIER in der App-Schicht (System-Zufall ist erlaubt) — der
// Core bleibt frei von globalem Zufall. Gleicher Seed ⇒ exakt gleicher Spielverlauf.

import SwiftUI
#if os(macOS)
import AppKit   // nur macOS: NSEvent-Tastatur, NSWindow-Konfiguration, NSApplication
#endif
#if os(iOS)
import UIKit    // nur iOS: UIDevice (eindeutige iPad-Erkennung fürs Touch-Layout)
import AVFoundation   // nur iOS: AVAudioSession (Stummschalter respektieren, mit anderer Audio mischen)
#endif
import SteinregenCore
import SteinregenRender

/// Bequemer Brueckenbau: dieselbe (r,g,b)-Palette wie die Render-Schicht als SwiftUI-`Color`.
private extension Theme.RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

private extension View {
    /// Dialog-Maße: auf macOS ein festes Sheet-Format, auf iOS bildschirmfüllend (das iPhone
    /// gibt die Größe vor). Hält die drei Dialoge (Einstellungen/Friedhof/Spielregeln) konsistent.
    @ViewBuilder func dialogFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

@main
struct SteinregenApp: App {
    init() {
        // Blackletter-Schrift einmalig registrieren, BEVOR die erste View gezeichnet wird.
        Theme.registerFonts()
        #if os(macOS)
        // macOS: App als regulaeres, fokussiertes Fenster nach vorn holen.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
        #if os(iOS)
        // iOS-Audio: .playback + .mixWithOthers. So spielen Musik UND Soundeffekte auch dann, wenn
        // der Stummschalter / Lautlos-Modus aktiv ist (mit .ambient blieb es auf einem lautlos
        // gestellten iPhone komplett still) — mischen sich aber höflich mit fremder Audio (kein
        // Abwürgen von z.B. Spotify). Abschalten geht in der App (Noten-Knopf / Einstellungen / M).
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // macOS: klassisches Titelleisten-Fenster mit festem Wunschmaß (Brett mittig, Seiten-Panels).
        WindowGroup("Steinregen") {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 670, height: 900)
        #else
        // iOS: bildschirmfüllende Szene, kein Fenster-Konzept.
        WindowGroup("Steinregen") {
            RootView()
        }
        #endif
    }
}

private enum Screen {
    case menu
    case playing
}

#if os(macOS)
/// Sperrt das Fenster auf ein festes Seitenverhältnis (nur proportional vergrößer-/verkleinerbar,
/// damit die Steine nie verzerren) und setzt eine Mindestgröße. Beim ersten Erscheinen wird die
/// Fenstergröße auf das Verhältnis eingerastet — falls macOS einen abweichenden Frame wiederherstellt.
private struct WindowConfigurator: NSViewRepresentable {
    let aspectW: CGFloat
    let aspectH: CGFloat
    let minWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window, snap: true) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, snap: false) }
    }
    private func configure(_ window: NSWindow?, snap: Bool) {
        guard let window else { return }
        window.contentAspectRatio = NSSize(width: aspectW, height: aspectH)
        window.contentMinSize = NSSize(width: minWidth, height: (minWidth * aspectH / aspectW).rounded())
        if snap, let content = window.contentView {
            let w = content.frame.width
            let targetH = (w * aspectH / aspectW).rounded()
            if abs(content.frame.height - targetH) > 1 {
                window.setContentSize(NSSize(width: w, height: targetH))
            }
        }
    }
}
#endif

/// Welches modale Sheet im Menue offen ist (Einstellungen oder Friedhof).
private enum ActiveSheet: Int, Identifiable {
    case settings, friedhof, rules
    var id: Int { rawValue }
}

struct RootView: View {
    @State private var model = GameModel()
    @State private var scene = GameScene(size: CGSize(width: 670, height: 880))
    @State private var screen: Screen = .menu
    @State private var startLevel: Int = 1          // 1-basiert (kein „Level 0")
    @State private var currentSeed: UInt64 = 1
    @State private var activeSheet: ActiveSheet?
    /// Gewaehlter Spielmodus (im Startbildschirm waehlbar).
    @State private var gameMode: GameMode = .saeulen
    /// Konstantes Tempo („Endlos"): Fallgeschwindigkeit bleibt auf der Start-Tempostufe, statt mit
    /// dem Level zu steigen. Persistiert.
    @AppStorage("steinregen.endless") private var endless = false
    // Sprache nur beobachten, damit ein Umschalten (in den Einstellungen) den ganzen Baum neu
    // zeichnet — der Wert selbst wird über `L10n` gelesen.
    @AppStorage(L10n.key) private var langRaw = ""

    var body: some View {
        ZStack {
            // Rabenschwarzer Hintergrund-Verlauf fuer alle Screens.
            LinearGradient(colors: [Color(red: 0.055, green: 0.055, blue: 0.066),
                                    Color(red: 0.012, green: 0.012, blue: 0.020)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            switch screen {
            case .menu:
                StartView(startLevel: $startLevel,
                          mode: $gameMode,
                          endless: $endless,
                          onSettings: { activeSheet = .settings },
                          onFriedhof: { activeSheet = .friedhof },
                          onRules: { activeSheet = .rules },
                          onStart: startGame)
            case .playing:
                GameplayView(scene: scene,
                             model: model,
                             onExit: goToMenu,
                             onRetrySameSeed: { startGame(seed: currentSeed) },
                             onRetryNewSeed: { startGame(seed: Self.randomSeed()) })
            }
        }
        #if os(macOS)
        // macOS: Mindestgröße + Seitenverhältnis-Sperre (verhindert verzerrte Steine).
        .frame(minWidth: 580, minHeight: 779)
        .background(WindowConfigurator(aspectW: 670, aspectH: 900, minWidth: 580))
        #endif
        .preferredColorScheme(.dark)   // immer finster — unabhaengig vom System-Modus
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings: SettingsView(mode: $gameMode, onClose: { activeSheet = nil })
            case .friedhof: FriedhofSheet(onClose: { activeSheet = nil })
            case .rules:    RulesSheet(onClose: { activeSheet = nil })
            }
        }
        .onAppear {
            scene.model = model
            // Automations-/Test-Naht: STEINREGEN_AUTOSTART startet sofort ein Spiel (fuer
            // automatische Screenshots / headless-Smoke-Test). STEINREGEN_LEVEL setzt das
            // Start-Tempo, STEINREGEN_SEED den Seed (sonst zufaellig), STEINREGEN_SET das
            // Steine-Set ("sigil"/"doom"/…); STEINREGEN_SETTINGS/STEINREGEN_FRIEDHOF oeffnen
            // direkt den jeweiligen Dialog.
            let env = ProcessInfo.processInfo.environment
            if let setID = env["STEINREGEN_SET"] { StoneSets.selectedID = setID }
            if let m = env["STEINREGEN_MODE"] {
                switch m {
                case "verschuettet": gameMode = .verschuettet
                case "klumpen":      gameMode = .klumpen
                default:             gameMode = .saeulen
                }
            }
            if env["STEINREGEN_ENDLESS"] != nil { endless = true }
            // Headless-Naht: STEINREGEN_MUSIC=0 schaltet die Musik aus (stiller Screenshot-Lauf),
            // =1 erzwingt sie an. Ohne die Variable bleibt der (persistierte) Default „an".
            if let mu = env["STEINREGEN_MUSIC"] { MusicPlayer.shared.setEnabled(mu != "0") }
            // STEINREGEN_LANG=de|en erzwingt die Sprache (sonst System-Sprache / gespeicherte Wahl).
            if let lng = env["STEINREGEN_LANG"], let l = L10n.Lang(rawValue: lng) { L10n.lang = l }
            if env["STEINREGEN_SETTINGS"] != nil { activeSheet = .settings }
            if env["STEINREGEN_FRIEDHOF"] != nil { activeSheet = .friedhof }
            if env["STEINREGEN_AUTOSTART"] != nil {
                if let lvl = env["STEINREGEN_LEVEL"], let n = Int(lvl) { startLevel = min(max(n, 1), 10) }
                if let s = env["STEINREGEN_SEED"], let seed = UInt64(s) {
                    startGame(seed: seed)
                } else {
                    startGame()
                }
            }
        }
    }

    /// Startet ein neues Spiel mit frischem Seed.
    private func startGame() { startGame(seed: Self.randomSeed()) }

    private func startGame(seed: UInt64) {
        currentSeed = seed
        scene.start(seed: seed, startLevel: startLevel, mode: gameMode,
                    width: BoardConfig.width(gameMode), height: BoardConfig.height(gameMode),
                    endless: endless)
        screen = .playing
        // Musik erst AB Levelbeginn (nicht im Menü). Läuft sie schon (z.B. „nochmal"), bleibt sie.
        MusicPlayer.shared.gameStarted()
    }

    /// Zurück ins Hauptmenü — dabei die Musik stoppen (im Menü ist es still).
    private func goToMenu() {
        MusicPlayer.shared.gameEnded()
        screen = .menu
    }

    private static func randomSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64.max)
    }
}

// MARK: - Startbildschirm

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

            // Spielmodus — drei Chips (Steinschlag / Eingemauert / Blutklumpen). Auf macOS
            // zusätzlich per ↑ ↓ wählbar (← → bleiben fürs Tempo), auf iOS per Tap.
            VStack(spacing: 10) {
                Text(L10n.t("Modus", "Mode"))
                    .font(.custom(Theme.blackletterBoldPostScript, size: 28)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(GameMode.allCases, id: \.self) { m in modeChip(m) }
                }
                .frame(maxWidth: 598)        // macOS: 3×190 + Abstände; schmales iPhone: Chips schrumpfen mit
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
                    arrowButton("chevron.left.circle.fill", enabled: startLevel > 1) {
                        if startLevel > 1 { startLevel -= 1 }
                    }
                    Text("Level \(startLevel)")
                        .font(.custom(Theme.blackletterBoldPostScript, size: 42))
                        .foregroundStyle(Theme.bone.color)
                        .frame(minWidth: 170)
                    arrowButton("chevron.right.circle.fill", enabled: startLevel < 10) {
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

    /// Großer, gut sichtbarer Pfeil-Knopf für die Tempo-Auswahl. Am Bereichsende (Level 1 bzw. 10)
    /// wird er gedämpft und deaktiviert. SF-Symbol statt Schrift-Glyphe — die gotische Schrift hat
    /// keine Pfeile.
    private func arrowButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 38))
                .foregroundStyle(enabled ? Theme.blood.color : Theme.boneDim.color.opacity(0.35))
        }
        .buttonStyle(.plain)
        .focusable(false)        // kein blauer Fokusrahmen — die Bedienung läuft über ← →
        .disabled(!enabled)
    }
}

// MARK: - Einstellungen (Steine-Set)

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
        }
    }
    private func setHeight(_ v: Int) {
        switch mode {
        case .saeulen:      saeulenH = v
        case .verschuettet: verschuettetH = v
        case .klumpen:      klumpenH = v
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
            dimArrow("chevron.left.circle.fill", enabled: value > range.lowerBound) {
                set(max(range.lowerBound, value - 1))
            }
            Text("\(value)")
                .font(.custom(Theme.blackletterBoldPostScript, size: 26))
                .foregroundStyle(Theme.bone.color)
                .frame(minWidth: 44)
            dimArrow("chevron.right.circle.fill", enabled: value < range.upperBound) {
                set(min(range.upperBound, value + 1))
            }
            Text("(\(range.lowerBound)–\(range.upperBound))")
                .font(.custom(Theme.blackletterFamily, size: 18)) // war 16, unter der 18pt-Untergrenze
                .foregroundStyle(Theme.boneDim.color.opacity(0.7))
        }
    }

    private func dimArrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 26))
                .foregroundStyle(enabled ? Theme.blood.color : Theme.boneDim.color.opacity(0.35))
        }
        .buttonStyle(.plain).focusable(false).disabled(!enabled)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Text(L10n.t("Steine-Set", "Stone set"))
                .font(.custom(Theme.blackletterFamily, size: 22))
                .foregroundStyle(Theme.bone.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            stoneSection

            Button(action: onClose) {
                Text(L10n.t("Fertig", "Done")).font(.custom(Theme.blackletterBoldPostScript, size: 18)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
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

// MARK: - Spielansicht

struct GameplayView: View {
    let scene: GameScene
    let model: GameModel
    let onExit: () -> Void
    let onRetrySameSeed: () -> Void
    let onRetryNewSeed: () -> Void

    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif
    #if os(iOS)
    // iPad bekommt ein angepasstes Touch-Layout (größeres Logo, zentrierte Knopfgruppe, Brett-Einzug);
    // iPhone bleibt unverändert. Idiom ist eindeutig (anders als die Size-Class in manchen Kontexten).
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    #endif

    var body: some View {
        ZStack {
            #if os(iOS)
            // iPad: Brett vertikal einrücken, damit über dem Schacht Platz fürs Logo und darunter
            // für die Steuerleiste bleibt (iPhone füllt wie gehabt — kein Einzug).
            GameBoardView(scene: scene)
                .padding(.top, isPad ? 290 : 0)
                .padding(.bottom, isPad ? 188 : 0)
            // Touch-Steuerung (Gesten über dem Brett + dezente Knopfleiste + Menü-Knopf), nur im Spiel.
            if !model.isGameOver {
                TouchControlsOverlay(scene: scene, onExit: onExit, isPad: isPad)
            }
            #else
            GameBoardView(scene: scene)
            #endif

            if model.isGameOver {
                GameOverOverlay(score: model.finalScore,
                                level: model.finalLevel,
                                onRetrySameSeed: onRetrySameSeed,
                                onRetryNewSeed: onRetryNewSeed,
                                onExit: onExit)
            }
        }
        #if os(macOS)
        // Tastatur fokus-unabhaengig: ein lokaler NSEvent-Monitor empfaengt Tasten, sobald das
        // Fenster aktiv ist — kein Warten auf SwiftUI-Fokus (das war die Ursache, dass die Steuerung
        // anfangs ein paar Sekunden tot war). Installiert solange diese Ansicht sichtbar ist.
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        #endif
    }

    #if os(macOS)
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            handle(event) ? nil : event   // verbrauchte Taste schlucken, Rest normal weiterreichen
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Verarbeitet eine Taste; `true` = verbraucht. Pfeiltasten UND W/A/S/D, Leertaste = Hard-Drop,
    /// Esc = Menue. Bewegen wiederholt bei gehaltener Taste; Drehen/Hard-Drop nur einmal pro Anschlag.
    private func handle(_ e: NSEvent) -> Bool {
        guard !model.isGameOver else { return false }   // im Game-Over die SwiftUI-Buttons handeln lassen
        let down = (e.type == .keyDown)
        let rep = e.isARepeat
        // Links/Rechts laufen über einen EIGENEN Auto-Repeat in der Szene (feste, snappy Rate,
        // unabhängig von der OS-Tastenwiederholung): Tastendruck startet, Loslassen stoppt;
        // die OS-Wiederholungen (`rep`) ignorieren wir bewusst.
        switch e.keyCode {
        case 123: if down { if !rep { scene.startMove(-1) } } else { scene.stopMove(-1) }; return true  // ←
        case 124: if down { if !rep { scene.startMove(1)  } } else { scene.stopMove(1)  }; return true  // →
        case 126: if down && !rep { scene.inputRotate() }; return true   // ↑
        case 125: scene.setSoftDrop(down); return true                   // ↓ (Druck = an, Loslassen = aus)
        case 49:  if down && !rep { scene.inputHardDrop() }; return true  // Leertaste
        case 53:  if down { onExit() }; return true                      // Esc
        default:  break
        }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "a": if down { if !rep { scene.startMove(-1) } } else { scene.stopMove(-1) }; return true
        case "d": if down { if !rep { scene.startMove(1)  } } else { scene.stopMove(1)  }; return true
        case "w": if down && !rep { scene.inputRotate() }; return true
        case "s": scene.setSoftDrop(down); return true
        case "t":   // Soundeffekte ein/aus (S geht nicht — belegt durch Softdrop)
            if down && !rep {
                SoundFX.muted.toggle()
                scene.flashHint(SoundFX.muted ? L10n.t("mundtot", "silenced") : L10n.t("Ton an", "Sound on"))
            }
            return true
        case "m":   // Musik ein/aus — getrennt von den Soundeffekten
            if down && !rep {
                let on = MusicPlayer.shared.toggle()
                scene.flashHint(on ? L10n.t("Musik an", "Music on") : L10n.t("Musik aus", "Music off"))
            }
            return true
        default:  return false
        }
    }
    #endif
}

// MARK: - Game-Over-Overlay

struct GameOverOverlay: View {
    let score: Int
    let level: Int
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
                    Text(L10n.t("Verreckt", "Perished"))
                        .font(.custom(Theme.blackletterBoldPostScript, size: 56))
                        .foregroundStyle(Theme.blood.color)
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

                // Grim-Zitat (Bethlehem) als Grabspruch — ganz unten, Schrift bewusst unverändert.
                Text(L10n.t("Am Ende fällt jeder Stein", "In the end, every stone falls"))
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

// MARK: - Friedhof (Bestenliste)

/// Zweizeilige Grabstein-Liste: Zeile 1 Name + Score, Zeile 2 in Rot „Verreckt in Level …"
/// (plus ein dezentes Sterbedatum rechts). Wird im Game-Over-Overlay (gekürzt) und im
/// Friedhof-Fenster (vollständig) verwendet.
struct FriedhofView: View {
    let entries: [GraveEntry]
    var highlightID: UUID? = nil
    var maxRows: Int? = nil
    /// Im Game-Over-Overlay OHNE Scrollbar (`scroll: false`) — es werden nur so viele Gräber
    /// gezeigt, wie hineinpassen. Das eigene Friedhof-Fenster bleibt scrollbar (alle Einträge).
    var scroll: Bool = true

    var body: some View {
        let shown = maxRows.map { Array(entries.prefix($0)) } ?? entries
        Group {
            if entries.isEmpty {
                Text(L10n.t("Noch frisch — kein Grab ausgehoben.", "Still fresh — no grave dug yet."))
                    .font(.custom(Theme.blackletterFamily, size: 18))
                    .foregroundStyle(Theme.boneDim.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if scroll {
                ScrollView { graveStack(shown) }
            } else {
                graveStack(shown)
            }
        }
    }

    /// Die gestapelten Grabstein-Zeilen — gemeinsam für die scrollbare und die feste Darstellung.
    private func graveStack(_ shown: [GraveEntry]) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, e in
                row(rank: idx + 1, e: e, highlight: e.id == highlightID)
            }
        }
        .padding(.horizontal, 2)
    }

    private func row(rank: Int, e: GraveEntry, highlight: Bool) -> some View {
        // Einzeilig, ohne Karte/Rahmen/Hintergrund — schlichte Liste direkt auf dem schwarzen Grund
        // (kontrastreich). Rang und Name in derselben Schrift/Größe; nur die Punktzahl im fetten
        // Schnitt abgesetzt. Der frisch eingetragene Eintrag (highlight) erscheint in Rot.
        let fg = highlight ? Theme.blood.color : Theme.bone.color
        return HStack(spacing: 12) {
            Text("\(rank).")
                .font(.custom(Theme.blackletterFamily, size: 22))
                .foregroundStyle(highlight ? Theme.blood.color : Theme.boneDim.color)
                .frame(width: 36, alignment: .trailing)
            Text(e.name.isEmpty ? L10n.t("Niemand", "Nobody") : e.name)
                .font(.custom(Theme.blackletterFamily, size: 22))
                .foregroundStyle(fg)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text("\(e.score)")
                .font(.custom(Theme.blackletterBoldPostScript, size: 22))
                .foregroundStyle(fg)
        }
        .padding(.vertical, 2)
    }
}

/// Der Friedhof als eigenes Fenster (Menü-Button „Friedhof").
struct FriedhofSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("Friedhof", "Graveyard"))
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)
            FriedhofView(entries: Friedhof.entries())
            Button(action: onClose) {
                Text(L10n.t("Schließen", "Close")).font(.custom(Theme.blackletterBoldPostScript, size: 18)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .dialogFrame(width: 480, height: 640)
        .background(Color(red: 0.02, green: 0.02, blue: 0.03))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Spielregeln

/// Eigenes Fenster (Menü-Button „Spielregeln"): erklärt Ziel, Treffer, Ketten, Steuerung,
/// den Magic-Stein und Tempo/Game-Over — damit Neulinge ohne Vorwissen loslegen können.
struct RulesSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.t("Spielregeln", "How to play"))
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(L10n.t("Ziel", "Goal"), L10n.t("""
                    Von oben schweben Säulen aus drei Steinen ein. Staple sie so, dass mindestens \
                    DREI gleiche Steine in einer Linie liegen — sie lösen sich dann auf.
                    """, """
                    Columns of three stones float in from the top. Stack them so that at least \
                    THREE alike line up — they then clear.
                    """))
                    section(L10n.t("Treffer", "Matches"), L10n.t("""
                    Eine Linie zählt waagerecht, senkrecht ODER diagonal (beide Richtungen). \
                    Sobald drei oder mehr gleiche Steine zusammenkommen, verschwinden sie.
                    """, """
                    A line counts horizontally, vertically OR diagonally (both directions). As soon \
                    as three or more alike meet, they vanish.
                    """))
                    section(L10n.t("Ketten (2× · 3× · 4× …)", "Chains (2× · 3× · 4× …)"), L10n.t("""
                    Nach einer Räumung rutschen die Steine darüber nach. Entsteht dabei eine neue \
                    Linie, geht es als Kettenreaktion weiter — jede Stufe gibt deutlich mehr Punkte. \
                    Lange Ketten sind der Schlüssel zu hohen Scores.
                    """, """
                    After a clear, the stones above fall in. If that forms a new line, it continues \
                    as a chain reaction — each step scores far more. Long chains are the key to high \
                    scores.
                    """))
                    section(L10n.t("Magischer Stein", "Magic stone"), L10n.t("""
                    Selten schwebt eine hell pulsierende Säule ein. Setzt sie auf, räumt sie \
                    BRETTWEIT alle Steine der Sorte weg, die direkt unter ihr liegt. Landet sie auf \
                    leerem Boden, verpufft sie wirkungslos. Es ist der einzige Spezialstein.
                    """, """
                    Rarely a brightly pulsing column floats in. Where it lands, it clears EVERY \
                    stone of the kind directly beneath it from the whole board. On empty ground it \
                    fizzles out. It is the only special stone.
                    """))
                    #if os(iOS)
                    section(L10n.t("Steuerung", "Controls"), L10n.t("""
                    Tippen dreht die Säule (die drei Steine tauschen durch). Nach links oder rechts \
                    wischen verschiebt sie um einen Schritt, nach unten wischen wirft sie sofort ganz \
                    nach unten. Unten liegt eine Knopfleiste: ◀ ▶ gehalten bewegen (mit Auto-\
                    Wiederholung), ↻ dreht, ▼ gehalten lässt schneller fallen, ⤓ wirft sofort ab. Ton \
                    und Musik schaltest du in den Einstellungen, der ✕-Knopf oben links führt ins Menü.
                    """, """
                    Tap rotates the column (cycling the three stones). Swipe left or right to move it \
                    one step; swipe down to drop it all the way instantly. A button bar sits at the \
                    bottom: hold ◀ ▶ to move (with auto-repeat), ↻ rotates, hold ▼ for a faster fall, \
                    ⤓ drops instantly. Toggle sound and music in Settings; the ✕ button top-left \
                    returns to the menu.
                    """))
                    #else
                    section(L10n.t("Steuerung", "Controls"), L10n.t("""
                    Steuern kannst du wahlweise mit den Cursortasten oder mit den Tasten W, A, S, D \
                    — beides ist gleichwertig. Im Einzelnen: links und rechts verschieben die Säule, \
                    hoch dreht sie (die drei Steine tauschen durch), runter lässt sie schneller \
                    fallen. Die Leertaste wirft sie sofort ganz nach unten, T schaltet die \
                    Soundeffekte an und aus, M die Musik, Esc führt zurück ins Menü.
                    """, """
                    Play with the arrow keys or with W, A, S, D — both work the same. In detail: \
                    left and right move the piece, up rotates it (cycling the three stones), down \
                    makes it fall faster. Space drops it all the way down, T toggles the sound \
                    effects, M the music, Esc returns to the menu.
                    """))
                    #endif
                    section(L10n.t("Tempo & Ende", "Speed & end"), L10n.t("""
                    Das Level steigt mit der Zahl geräumter Steine; je höher, desto schneller fällt \
                    die Säule. Die Partie endet, wenn die mittlere Einwurf-Spalte bis oben voll ist \
                    und keine neue Säule mehr Platz findet.
                    """, """
                    The level rises with the number of cleared stones; the higher it is, the faster \
                    pieces fall. The game ends when the central spawn column is full to the top and \
                    no new piece fits.
                    """))
                }
                .padding(.horizontal, 4)
            }

            Button(action: onClose) {
                Text(L10n.t("Fertig", "Done")).font(.custom(Theme.blackletterBoldPostScript, size: 18)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
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

// MARK: - iOS-Touch-Steuerung

#if os(iOS)
/// Touch-Steuerung fürs iPhone (es gibt keine Tastatur): Über dem Brett fängt eine durchsichtige
/// Fläche Gesten ab — Tippen dreht die Säule, Wischen schiebt sie (links/rechts je einen Schritt)
/// bzw. wirft sie ab (nach unten). Unten liegt eine dezente Knopfleiste, oben links ein Menü-Knopf.
/// Die Links/Rechts-Knöpfe nutzen `startMove`/`stopMove` → szeneneigener Auto-Repeat wie bei der
/// gehaltenen Taste am Mac.
private struct TouchControlsOverlay: View {
    let scene: GameScene
    let onExit: () -> Void
    var isPad: Bool = false   // iPad: größeres Logo, Steuerleiste auf Maximalbreite begrenzt

    // Spiegelt den Musik-an/aus-Zustand (UserDefaults, geteilt mit Einstellungen + M-Taste am Mac),
    // damit der Noten-Knopf oben rechts sofort die richtige Optik (Slash/gedimmt = aus) zeigt.
    @AppStorage(MusicPlayer.mutedKey) private var musicMuted = false

    // In-Game-Logo: auf kleinen iPhones (SE, ~667 pt) deutlich kleiner — sonst ragt es in die
    // Spielfläche, weil über dem Brett kaum freier Raum bleibt. Große iPhones + iPad: volles Maß.
    private var logoMaxWidth: CGFloat {
        if isPad { return 620 }
        return UIScreen.main.bounds.height < 700 ? 230 : 380
    }
    private var logoMaxHeight: CGFloat {
        if isPad { return 210 }
        return UIScreen.main.bounds.height < 700 ? 76 : 140
    }

    // Sicherheitsabfrage, damit ein versehentliches Tippen auf ✕ nicht sofort die Partie abbricht.
    @State private var showExitConfirm = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            gestureCatcher
            VStack(spacing: 0) {
                // Das Black-Metal-Logo füllt den freien Raum ÜBER dem Brett (groß; rein dekorativ →
                // allowsHitTesting(false), damit ein Tippen dort weiterhin das Brett dreht). Liegt
                // ganz oben, damit es nach unten nicht in den Schacht/Einwurf ragt.
                if let logo = Theme.logoImage() {
                    Image(decorative: logo, scale: 1)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: logoMaxWidth, maxHeight: logoMaxHeight)
                        .opacity(0.95)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                        .allowsHitTesting(false)
                        .padding(.top, isPad ? 48 : 6)
                }
                Spacer()
                controlBar
            }
            // Volle Breite/Höhe — sonst schrumpft die VStack auf ihr breitestes Kind und landet
            // (ZStack .topLeading) am linken Rand; so zentrieren sich Logo und Knopfgruppe.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Ecken-Knöpfe als OVERLAYS (über dem Gesture-Catcher) — so bekommen sie den Tap zuverlässig,
        // statt dass die Brett-Geste (Tippen = drehen) ihn abfängt. ✕ links = zurück ins Menü.
        .overlay(alignment: .topLeading) {
            // ✕ fragt erst nach (Sicherheitsabfrage), statt die Partie sofort abzubrechen.
            Button { showExitConfirm = true } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.bone.color.opacity(0.75))
                    .padding(12)
            }
            .buttonStyle(.plain)
        }
        // Musik-Knopf oben rechts (analog zum ✕): schaltet die Hintergrundmusik an/aus. Helle Note =
        // an, gedimmte Note mit Slash = aus.
        .overlay(alignment: .topTrailing) {
            Button { MusicPlayer.shared.toggle() } label: {
                Image(systemName: "music.note")
                    .symbolVariant(musicMuted ? .slash : .none)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.bone.color.opacity(musicMuted ? 0.4 : 0.85))
                    .padding(12)
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog(L10n.t("Partie abbrechen?", "Quit this game?"),
                            isPresented: $showExitConfirm, titleVisibility: .visible) {
            Button(L10n.t("Partie abbrechen", "Quit game"), role: .destructive) { onExit() }
            Button(L10n.t("Weiterspielen", "Keep playing"), role: .cancel) { }
        }
    }

    /// Durchsichtige Fläche über dem ganzen Brett: Tippen dreht, Wischen schiebt/wirft.
    private var gestureCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { scene.inputRotate() }
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        if abs(dx) > abs(dy) {
                            if dx < 0 { scene.inputLeft() } else { scene.inputRight() }
                        } else if dy > 0 {
                            scene.inputHardDrop()          // nach unten wischen = Hard-Drop
                        }
                        // nach oben wischen: bewusst ohne Wirkung (Tippen dreht bereits)
                    }
            )
    }

    private var controlBar: some View {
        let btn: CGFloat = isPad ? 78 : 64
        return Group {
            if isPad {
                // iPad: zentrierte Knopfgruppe mit festen, angenehmen Abständen — NICHT über die
                // ganze (breite) Fläche, sonst stehen die Knöpfe unerreichbar an den Rändern.
                HStack(spacing: 30) {
                    HoldButton(symbol: "arrowtriangle.left.fill", size: btn,
                               onPress: { scene.startMove(-1) }, onRelease: { scene.stopMove(-1) })
                    TapControlButton(symbol: "arrow.clockwise", size: btn) { scene.inputRotate() }
                    HoldButton(symbol: "arrowtriangle.down.fill", size: btn,
                               onPress: { scene.setSoftDrop(true) }, onRelease: { scene.setSoftDrop(false) })
                    TapControlButton(symbol: "arrow.down.to.line", size: btn) { scene.inputHardDrop() }
                    HoldButton(symbol: "arrowtriangle.right.fill", size: btn,
                               onPress: { scene.startMove(1) }, onRelease: { scene.stopMove(1) })
                }
            } else {
                // iPhone: volle Breite — ◀ ganz links, ▶ ganz rechts, Rest gleichmäßig dazwischen.
                HStack(spacing: 0) {
                    HoldButton(symbol: "arrowtriangle.left.fill", size: btn,
                               onPress: { scene.startMove(-1) }, onRelease: { scene.stopMove(-1) })
                    Spacer()
                    TapControlButton(symbol: "arrow.clockwise", size: btn) { scene.inputRotate() }
                    Spacer()
                    HoldButton(symbol: "arrowtriangle.down.fill", size: btn,
                               onPress: { scene.setSoftDrop(true) }, onRelease: { scene.setSoftDrop(false) })
                    Spacer()
                    TapControlButton(symbol: "arrow.down.to.line", size: btn) { scene.inputHardDrop() }
                    Spacer()
                    HoldButton(symbol: "arrowtriangle.right.fill", size: btn,
                               onPress: { scene.startMove(1) }, onRelease: { scene.stopMove(1) })
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, isPad ? 40 : 12)
    }
}

/// Knopf mit Halte-Verhalten: `onPress` beim ersten Berühren, `onRelease` beim Loslassen — so greift
/// der szeneneigene Auto-Repeat (DAS/ARR) wie bei einer gehaltenen Taste.
private struct HoldButton: View {
    let symbol: String
    var size: CGFloat = 64
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.47, weight: .bold))
            .foregroundStyle(Theme.bone.color)
            .frame(width: size, height: size)
            .background(Circle().fill(pressed ? Theme.oxblood.color.opacity(0.85)
                                              : Color.white.opacity(0.10)))
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true; onPress() } }
                    .onEnded { _ in pressed = false; onRelease() }
            )
    }
}

/// Einfacher Tipp-Knopf (Drehen, Hard-Drop) im selben dezenten Stil.
private struct TapControlButton: View {
    let symbol: String
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.47, weight: .bold))
                .foregroundStyle(Theme.bone.color)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
#endif
