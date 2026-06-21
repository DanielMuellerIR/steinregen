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
        .defaultSize(width: 410, height: 920)   // hochkant, nahezu randlos um das 6×13-Brett
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
    case settings, friedhof
    var id: Int { rawValue }
}

struct RootView: View {
    @State private var model = GameModel()
    @State private var scene = GameScene(size: CGSize(width: 410, height: 880))
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
                          onStart: startGame)
            case .playing:
                GameplayView(scene: scene,
                             model: model,
                             onExit: { screen = .menu },
                             onRetrySameSeed: { startGame(seed: currentSeed) },
                             onRetryNewSeed: { startGame(seed: Self.randomSeed()) })
            }
        }
        .frame(minWidth: 360, minHeight: 808)   // Mindestgröße im Brett-Seitenverhältnis
        .background(WindowConfigurator(aspectW: 410, aspectH: 920, minWidth: 360))
        .preferredColorScheme(.dark)   // Fenster ist immer finster — unabhaengig vom System-Modus
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .settings: SettingsView(onClose: { activeSheet = nil })
            case .friedhof: FriedhofSheet(onClose: { activeSheet = nil })
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
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                // Logo-Grafik statt Schriftzug; Fallback auf den Blackletter-Text, falls die
                // Datei fehlt (z.B. in einem Build ohne logo.png im Bundle).
                if let logo = Theme.logoImage() {
                    Image(decorative: logo, scale: 1)
                        .resizable().interpolation(.high).scaledToFit()
                        .frame(maxWidth: 380, maxHeight: 150)
                        .shadow(color: .black.opacity(0.7), radius: 6, y: 2)
                } else {
                    Text("Steinregen")
                        .font(.custom(Theme.blackletterFamily, size: 60))
                        .foregroundStyle(Theme.bone.color)
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                }
                Text("Tod macht Fliegen aus uns allen")
                    .font(.custom(Theme.blackletterFamily, size: 16))
                    .tracking(2)
                    .foregroundStyle(Theme.oxblood.color)
            }

            // Start-Tempostufe.
            VStack(spacing: 8) {
                Text("Start-Tempo")
                    .font(.headline).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Stepper(value: $startLevel, in: 1...10) {
                        Text("Level \(startLevel)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 90, alignment: .leading)
                    }
                    .fixedSize()
                }
                Text(tempoHint)
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)

            Button(action: onStart) {
                Text("Spiel starten")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 220, height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 12) {
                Button(action: onSettings) {
                    Label("Einstellungen", systemImage: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 150, height: 38)
                }
                Button(action: onFriedhof) {
                    Label("Friedhof", systemImage: "list.number")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 150, height: 38)
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.boneDim.color)

            ControlsLegend()

            Spacer()
        }
        .padding(40)
    }

    private var tempoHint: String {
        switch startLevel {
        case 1...3: return "ruhig — gut zum Einsteigen"
        case 4...6: return "zügig"
        case 7...8: return "schnell"
        default:    return "sehr schnell — für Profis"
        }
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
        .font(.system(size: 13, design: .rounded))
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func legend(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: 108, alignment: .leading)
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
                .font(.custom(Theme.blackletterFamily, size: 32))
                .foregroundStyle(Theme.bone.color)

            // Ton (aus = „mundtot")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ton")
                        .font(.custom(Theme.blackletterFamily, size: 20))
                        .foregroundStyle(Theme.bone.color)
                    Spacer()
                    Toggle("", isOn: Binding(get: { !mundtot }, set: { mundtot = !$0 }))
                        .labelsHidden()
                        .tint(Theme.oxblood.color)
                }
                Text(mundtot ? "mundtot — keine Soundeffekte (im Spiel: Taste T)"
                             : "Soundeffekte an (im Spiel: Taste T)")
                    .font(.system(size: 12))
                    .foregroundStyle(mundtot ? Theme.oxblood.color : Theme.boneDim.color)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            Text("Steine-Set")
                .font(.custom(Theme.blackletterFamily, size: 20))
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
                Text("Fertig").font(.system(size: 16, weight: .bold)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 440, height: 820)
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
                            .font(.system(size: 12))
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
        switch e.keyCode {
        case 123: if down { scene.inputLeft() };  return true            // ←
        case 124: if down { scene.inputRight() }; return true            // →
        case 126: if down && !rep { scene.inputRotate() }; return true   // ↑
        case 125: scene.setSoftDrop(down); return true                   // ↓ (Druck = an, Loslassen = aus)
        case 49:  if down && !rep { scene.inputHardDrop() }; return true  // Leertaste
        case 53:  if down { onExit() }; return true                      // Esc
        default:  break
        }
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "a": if down { scene.inputLeft() };  return true
        case "d": if down { scene.inputRight() }; return true
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("verreckt")
                        .font(.custom(Theme.blackletterFamily, size: 46))
                        .foregroundStyle(Theme.oxblood.color)
                    Text("Level \(level) · \(score) Punkte")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.boneDim.color)
                }

                if step == .entry {
                    entryView
                } else {
                    FriedhofView(entries: Friedhof.entries(), highlightID: highlightID, maxRows: 6)
                        .frame(maxHeight: 250)
                }

                buttons
            }
            .padding(28)
            .frame(width: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .onAppear {
            name = Friedhof.lastName
            if Friedhof.qualifies(score: score) {
                step = .entry
                DispatchQueue.main.async { nameFocused = true }
            } else {
                step = .list
            }
        }
    }

    private var entryView: some View {
        VStack(spacing: 10) {
            Text("Ein Grab auf dem Friedhof — trag dich ein:")
                .font(.system(size: 13))
                .foregroundStyle(Theme.boneDim.color)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($nameFocused)
                .onChange(of: name) { _, v in if v.count > 16 { name = String(v.prefix(16)) } }
                .onSubmit(submit)
            Button(action: submit) {
                Text("Begraben").frame(width: 240, height: 40)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onRetrySameSeed) {
                Text("Nochmal (gleicher Seed)").frame(width: 240, height: 40)
            }
            .buttonStyle(.bordered)
            Button(action: onRetryNewSeed) {
                Text("Neues Spiel").frame(width: 240, height: 40)
            }
            .buttonStyle(.bordered)
            Button(action: onExit) {
                Text("Hauptmenü").frame(width: 240, height: 34)
            }
            .buttonStyle(.borderless)
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        highlightID = Friedhof.add(name: trimmed.isEmpty ? "Niemand" : trimmed, score: score, level: level)
        step = .list
    }
}

// MARK: - Friedhof (Bestenliste)

/// Zweizeilige Grabstein-Liste: Zeile 1 Name + Score, Zeile 2 in Rot „verreckt in Level …"
/// (plus ein dezentes Sterbedatum rechts). Wird im Game-Over-Overlay (gekürzt) und im
/// Friedhof-Fenster (vollständig) verwendet.
struct FriedhofView: View {
    let entries: [GraveEntry]
    var highlightID: UUID? = nil
    var maxRows: Int? = nil

    var body: some View {
        let shown = maxRows.map { Array(entries.prefix($0)) } ?? entries
        Group {
            if entries.isEmpty {
                Text("Noch frisch — kein Grab ausgehoben.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.boneDim.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { idx, e in
                            row(rank: idx + 1, e: e, highlight: e.id == highlightID)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func row(rank: Int, e: GraveEntry, highlight: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.boneDim.color)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.name.isEmpty ? "Niemand" : e.name)
                        .font(.custom(Theme.blackletterFamily, size: 18))
                        .foregroundStyle(Theme.bone.color)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(e.score)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.bone.color)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("verreckt in Level \(e.level)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.oxblood.color)
                    Spacer(minLength: 8)
                    Text(e.date, format: .dateTime.day().month().year())
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(highlight ? Theme.oxblood.color.opacity(0.18) : Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(highlight ? Theme.oxblood.color : Color.white.opacity(0.06),
                        lineWidth: highlight ? 1.5 : 0.5)
        )
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
                Text("Schließen").font(.system(size: 16, weight: .bold)).frame(width: 200, height: 42)
            }
            .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 440, height: 640)
        .background(Color(red: 0.02, green: 0.02, blue: 0.03))
        .preferredColorScheme(.dark)
    }
}
