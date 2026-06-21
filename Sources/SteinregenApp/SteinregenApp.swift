// SteinregenApp.swift
// SwiftUI-Shell von Steinregen: Startbildschirm (Titel, Start-Tempostufe, Seed),
// Spielansicht mit Tastatursteuerung und Game-Over-Overlay.
//
// Die Seed-Erzeugung passiert HIER in der App-Schicht (System-Zufall ist erlaubt) — der
// Core bleibt frei von globalem Zufall. Gleicher Seed ⇒ exakt gleicher Spielverlauf.

import SwiftUI
import SpriteKit
import AppKit
import SteinregenCore
import SteinregenRender

/// Bequemer Brueckenbau: dieselbe (r,g,b)-Palette wie die Render-Schicht als SwiftUI-`Color`.
private extension Theme.RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

@main
struct SteinregenApp: App {
    init() {
        // Blackletter-Schrift einmalig registrieren, BEVOR die erste View gezeichnet wird.
        Theme.registerFonts()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Steinregen") {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 670, height: 900)   // breiter: Brett mittig, Seiten-Panels für HUD/Vorschau
    }
}

private enum Screen {
    case menu
    case playing
}

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
                          onSettings: { activeSheet = .settings },
                          onFriedhof: { activeSheet = .friedhof },
                          onRules: { activeSheet = .rules },
                          onStart: startGame)
            case .playing:
                GameplayView(scene: scene,
                             model: model,
                             onExit: { screen = .menu },
                             onRetrySameSeed: { startGame(seed: currentSeed) },
                             onRetryNewSeed: { startGame(seed: Self.randomSeed()) })
            }
        }
        .frame(minWidth: 580, minHeight: 779)   // Mindestgröße im neuen Seitenverhältnis
        .background(WindowConfigurator(aspectW: 670, aspectH: 900, minWidth: 580))
        .preferredColorScheme(.dark)   // Fenster ist immer finster — unabhaengig vom System-Modus
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings: SettingsView(onClose: { activeSheet = nil })
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
        scene.start(seed: seed, startLevel: startLevel)
        screen = .playing
    }

    private static func randomSeed() -> UInt64 {
        UInt64.random(in: 1...UInt64.max)
    }
}

// MARK: - Startbildschirm

struct StartView: View {
    @Binding var startLevel: Int
    let onSettings: () -> Void
    let onFriedhof: () -> Void
    let onRules: () -> Void
    let onStart: () -> Void

    // Fokus-unabhängiger Tastatur-Monitor fürs Menü: ← → wählen das Start-Tempo (wie im Spiel,
    // bewährtes NSEvent-Muster). Return startet über den Standard-Knopf (`.defaultAction`).
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 6) {
                // Logo-Grafik statt Schriftzug; Fallback auf den Blackletter-Text, falls die
                // Datei fehlt (z.B. in einem Build ohne logo.png im Bundle). FESTE Höhe, damit das
                // Logo nicht von größeren Nachbar-Elementen gequetscht wird (war der Grund, warum es
                // nach der Schrift-Vergrößerung winzig wurde).
                if let logo = Theme.logoImage() {
                    Image(decorative: logo, scale: 1)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: 480)
                        .frame(height: 210)
                        .shadow(color: .black.opacity(0.7), radius: 6, y: 2)
                } else {
                    Text("Steinregen")
                        .font(.custom(Theme.blackletterFamily, size: 60))
                        .foregroundStyle(Theme.bone.color)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                }
            }

            // Start-Tempostufe — eigene ◀ Level N ▶-Steuerung (statt des hässlichen System-Steppers).
            VStack(spacing: 12) {
                Text("Start-Tempo")
                    .font(.custom(Theme.blackletterBoldPostScript, size: 28)).foregroundStyle(.secondary)
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
                Text(tempoHint)
                    .font(.custom(Theme.blackletterFamily, size: 24)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)

            Button(action: onStart) {
                Text("Spiel starten")
                    .font(.custom(Theme.blackletterBoldPostScript, size: 22))
                    .frame(width: 220, height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 8) {
                Button(action: onSettings) {
                    Label("Einstellungen", systemImage: "gearshape")
                        .font(.custom(Theme.blackletterFamily, size: 22))
                        .frame(width: 168, height: 48)
                }
                Button(action: onRules) {
                    Label("Spielregeln", systemImage: "book")
                        .font(.custom(Theme.blackletterFamily, size: 22))
                        .frame(width: 168, height: 48)
                }
                Button(action: onFriedhof) {
                    Label("Friedhof", systemImage: "list.number")
                        .font(.custom(Theme.blackletterFamily, size: 22))
                        .frame(width: 168, height: 48)
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.boneDim.color)

            ControlsLegend()

            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // ← → ändern das Start-Tempo, ohne dass ein Knopf den Fokus braucht. Andere Tasten (u.a.
    // Return) reicht der Monitor unverändert weiter → der Start-Knopf fängt Return per defaultAction.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.keyCode {
            case 123: if startLevel > 1  { startLevel -= 1 }; return nil   // ←
            case 124: if startLevel < 10 { startLevel += 1 }; return nil   // →
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private var tempoHint: String {
        switch startLevel {
        case 1...3: return "ruhig — gut zum Einsteigen"
        case 4...6: return "zügig"
        case 7...8: return "schnell"
        default:    return "sehr schnell — für Profis"
        }
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

/// Kurze Steuerungs-Legende.
struct ControlsLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            legend("← →  ·  A D", "Säule bewegen")
            legend("↑  ·  W", "Säule drehen (Steine durchtauschen)")
            legend("↓  ·  S", "schneller fallen lassen")
            legend("Leertaste", "sofort fallen lassen")
        }
        .font(.custom(Theme.blackletterFamily, size: 19))
        .padding(18)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func legend(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            // Bewusste Ausnahme: die Tasten-/Pfeil-Spalte bleibt in der klaren Mono-Schrift —
            // Grenze Gotisch hat keine Pfeil-Glyphen (←↑→↓) und wuerde sie als Kaestchen zeigen.
            Text(key)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .frame(width: 132, alignment: .leading)
                .foregroundStyle(.primary)
            Text(desc).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Einstellungen (Steine-Set)

/// Auswahl-Dialog fuer das Steine-Set, mit Live-Vorschau. Die Auswahl wird per `@AppStorage`
/// im selben UserDefaults-Schluessel gemerkt, den die Render-Schicht (`StoneSets.selectedID`)
/// liest — beim naechsten Spielstart gilt das gewaehlte Set. Neue Sets erscheinen hier
/// automatisch, sobald sie in `StoneSets.all` stehen.
struct SettingsView: View {
    @AppStorage(StoneSets.defaultsKey) private var selectedSet = "doom"   // Standard-Set
    @AppStorage(SoundFX.mutedKey) private var mundtot = false             // true = Ton aus
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Einstellungen")
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)

            // Ton (aus = „mundtot")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ton")
                        .font(.custom(Theme.blackletterFamily, size: 22))
                        .foregroundStyle(Theme.bone.color)
                    Spacer()
                    Toggle("", isOn: Binding(get: { !mundtot }, set: { mundtot = !$0 }))
                        .labelsHidden()
                        .tint(Theme.oxblood.color)
                }
                Text(mundtot ? "mundtot — keine Soundeffekte (im Spiel: Taste T)"
                             : "Soundeffekte an (im Spiel: Taste T)")
                    .font(.custom(Theme.blackletterFamily, size: 18))
                    .foregroundStyle(mundtot ? Theme.blood.color : Theme.boneDim.color)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Text("Steine-Set")
                .font(.custom(Theme.blackletterFamily, size: 22))
                .foregroundStyle(Theme.bone.color)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(StoneSets.all) { set in
                        StoneSetCard(set: set, selected: selectedSet == set.id) {
                            selectedSet = set.id
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Button(action: onClose) {
                Text("Fertig").font(.custom(Theme.blackletterBoldPostScript, size: 18)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 480, height: 820)
        .background(Color(red: 0.02, green: 0.02, blue: 0.03))
        .preferredColorScheme(.dark)
    }
}

/// Eine anklickbare Karte je Set: Name, Kurzbeschreibung und eine Vorschau der sechs Steine.
struct StoneSetCard: View {
    let set: StoneSet
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.name)
                            .font(.custom(Theme.blackletterFamily, size: 22))
                            .foregroundStyle(Theme.bone.color)
                        Text(set.subtitle)
                            .font(.custom(Theme.blackletterFamily, size: 18))
                            .foregroundStyle(Theme.boneDim.color)
                    }
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
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Spielansicht

struct GameplayView: View {
    let scene: GameScene
    let model: GameModel
    let onExit: () -> Void
    let onRetrySameSeed: () -> Void
    let onRetryNewSeed: () -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            GameBoardView(scene: scene)

            if model.isGameOver {
                GameOverOverlay(score: model.finalScore,
                                level: model.finalLevel,
                                onRetrySameSeed: onRetrySameSeed,
                                onRetryNewSeed: onRetryNewSeed,
                                onExit: onExit)
            }
        }
        // Tastatur fokus-unabhaengig: ein lokaler NSEvent-Monitor empfaengt Tasten, sobald das
        // Fenster aktiv ist — kein Warten auf SwiftUI-Fokus (das war die Ursache, dass die Steuerung
        // anfangs ein paar Sekunden tot war). Installiert solange diese Ansicht sichtbar ist.
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

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
        case "t":   // Ton ein/aus (S geht nicht — belegt durch Softdrop)
            if down && !rep {
                SoundFX.muted.toggle()
                scene.flashHint(SoundFX.muted ? "mundtot" : "Ton an")
            }
            return true
        // "m" ist für späteres Musik-Ein/Aus reserviert (Musik gibt es noch nicht).
        default:  return false
        }
    }
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
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 12) {
                VStack(spacing: 6) {
                    Text("Verreckt")
                        .font(.custom(Theme.blackletterBoldPostScript, size: 56))
                        .foregroundStyle(Theme.blood.color)
                    Text("Level \(level) · \(score) Punkte")
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
                Text("Tod macht Fliegen aus uns allen")
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
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
    }

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

    private var entryView: some View {
        VStack(spacing: 10) {
            Text("Ein Grab auf dem Friedhof — trag dich ein:")
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
                Text("Begraben").font(.custom(Theme.blackletterBoldPostScript, size: 19)).frame(width: 240, height: 40)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            navButton(0, "Nochmal (gleicher Seed)", action: onRetrySameSeed)
            navButton(1, "Neues Spiel", action: onRetryNewSeed)
            navButton(2, "Hauptmenü", action: onExit)
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
        highlightID = Friedhof.add(name: trimmed.isEmpty ? "Niemand" : trimmed, score: score, level: level)
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
                Text("Noch frisch — kein Grab ausgehoben.")
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
            Text(e.name.isEmpty ? "Niemand" : e.name)
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
            Text("Friedhof")
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)
            FriedhofView(entries: Friedhof.entries())
            Button(action: onClose) {
                Text("Schließen").font(.custom(Theme.blackletterBoldPostScript, size: 18)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 480, height: 640)
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
            Text("Spielregeln")
                .font(.custom(Theme.blackletterFamily, size: 34))
                .foregroundStyle(Theme.bone.color)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Ziel", """
                    Von oben schweben Säulen aus drei Steinen ein. Staple sie so, dass mindestens \
                    DREI gleiche Steine in einer Linie liegen — sie lösen sich dann auf.
                    """)
                    section("Treffer", """
                    Eine Linie zählt waagerecht, senkrecht ODER diagonal (beide Richtungen). \
                    Sobald drei oder mehr gleiche Steine zusammenkommen, verschwinden sie.
                    """)
                    section("Ketten (2× · 3× · 4× …)", """
                    Nach einer Räumung rutschen die Steine darüber nach. Entsteht dabei eine neue \
                    Linie, geht es als Kettenreaktion weiter — jede Stufe gibt deutlich mehr Punkte. \
                    Lange Ketten sind der Schlüssel zu hohen Scores.
                    """)
                    section("Magischer Stein", """
                    Selten schwebt eine hell pulsierende Säule ein. Setzt sie auf, räumt sie \
                    BRETTWEIT alle Steine der Sorte weg, die direkt unter ihr liegt. Landet sie auf \
                    leerem Boden, verpufft sie wirkungslos. Es ist der einzige Spezialstein.
                    """)
                    section("Steuerung", """
                    Steuern kannst du wahlweise mit den Cursortasten oder mit den Tasten W, A, S, D \
                    — beides ist gleichwertig. Im Einzelnen: links und rechts verschieben die Säule, \
                    hoch dreht sie (die drei Steine tauschen durch), runter lässt sie schneller \
                    fallen. Die Leertaste wirft sie sofort ganz nach unten, T schaltet den Ton an \
                    und aus, Esc führt zurück ins Menü.
                    """)
                    section("Tempo & Ende", """
                    Das Level steigt mit der Zahl geräumter Steine; je höher, desto schneller fällt \
                    die Säule. Die Partie endet, wenn die mittlere Einwurf-Spalte bis oben voll ist \
                    und keine neue Säule mehr Platz findet.
                    """)
                }
                .padding(.horizontal, 4)
            }

            Button(action: onClose) {
                Text("Fertig").font(.custom(Theme.blackletterBoldPostScript, size: 18)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 520, height: 720)
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
