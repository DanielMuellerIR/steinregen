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

struct RootView: View {
    @State private var model = GameModel()
    @State private var scene = GameScene(size: CGSize(width: 410, height: 880))
    @State private var screen: Screen = .menu
    @State private var startLevel: Int = 0
    @State private var currentSeed: UInt64 = 1
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Rabenschwarzer Hintergrund-Verlauf fuer alle Screens.
            LinearGradient(colors: [Color(red: 0.055, green: 0.055, blue: 0.066),
                                    Color(red: 0.012, green: 0.012, blue: 0.020)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            switch screen {
            case .menu:
                StartView(startLevel: $startLevel, showSettings: $showSettings, onStart: startGame)
            case .playing:
                GameplayView(scene: scene,
                             model: model,
                             onExit: { screen = .menu },
                             onRetrySameSeed: { startGame(seed: currentSeed) },
                             onRetryNewSeed: { startGame(seed: Self.randomSeed()) })
            }
        }
        .frame(minWidth: 360, minHeight: 560)
        .preferredColorScheme(.dark)   // Fenster ist immer finster — unabhaengig vom System-Modus
        .sheet(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false })
        }
        .onAppear {
            scene.model = model
            // Automations-/Test-Naht: STEINREGEN_AUTOSTART startet sofort ein Spiel (fuer
            // automatische Screenshots / headless-Smoke-Test). STEINREGEN_LEVEL setzt das
            // Start-Tempo, STEINREGEN_SEED den Seed (sonst zufaellig), STEINREGEN_SET das
            // Steine-Set ("sigil"/"doom"/…).
            let env = ProcessInfo.processInfo.environment
            if let setID = env["STEINREGEN_SET"] { StoneSets.selectedID = setID }
            if env["STEINREGEN_SETTINGS"] != nil { showSettings = true }   // Dialog direkt oeffnen
            if env["STEINREGEN_AUTOSTART"] != nil {
                if let lvl = env["STEINREGEN_LEVEL"], let n = Int(lvl) { startLevel = min(max(n, 0), 9) }
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
    @Binding var showSettings: Bool
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
                    Stepper(value: $startLevel, in: 0...9) {
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

            Button { showSettings = true } label: {
                Label("Steine-Set wählen", systemImage: "square.grid.2x2")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 220, height: 38)
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
        case 0...2: return "ruhig — gut zum Einsteigen"
        case 3...5: return "zügig"
        case 6...7: return "schnell"
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
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Steine-Set")
                .font(.custom(Theme.blackletterFamily, size: 32))
                .foregroundStyle(Theme.bone.color)

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
        .frame(width: 440, height: 760)
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
        default:  return false
        }
    }
}

// MARK: - Game-Over-Overlay

struct GameOverOverlay: View {
    let score: Int
    let onRetrySameSeed: () -> Void
    let onRetryNewSeed: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 22) {
                VStack(spacing: 2) {
                    Text("verreckt")
                        .font(.custom(Theme.blackletterFamily, size: 48))
                        .foregroundStyle(Theme.oxblood.color)
                    Text("der schacht ist verstopft")
                        .font(.custom(Theme.blackletterFamily, size: 14))
                        .tracking(1.5)
                        .foregroundStyle(Theme.boneDim.color)
                }
                VStack(spacing: 2) {
                    Text("Punkte").font(.headline).foregroundStyle(.secondary)
                    Text("\(score)")
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.bone.color)
                }
                VStack(spacing: 12) {
                    Button(action: onRetrySameSeed) {
                        Text("Nochmal (gleicher Seed)").frame(width: 240, height: 42)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.oxblood.color)
                    .keyboardShortcut(.defaultAction)

                    Button(action: onRetryNewSeed) {
                        Text("Neues Spiel").frame(width: 240, height: 42)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onExit) {
                        Text("Hauptmenü").frame(width: 240, height: 36)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
