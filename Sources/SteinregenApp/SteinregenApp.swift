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

@main
struct SteinregenApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Steinregen") {
            RootView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 540, height: 860)
    }
}

private enum Screen {
    case menu
    case playing
}

struct RootView: View {
    @State private var model = GameModel()
    @State private var scene = GameScene(size: CGSize(width: 540, height: 780))
    @State private var screen: Screen = .menu
    @State private var startLevel: Int = 0
    @State private var currentSeed: UInt64 = 1

    var body: some View {
        ZStack {
            // Hintergrund-Verlauf fuer alle Screens.
            LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.18),
                                    Color(red: 0.04, green: 0.05, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            switch screen {
            case .menu:
                StartView(startLevel: $startLevel, onStart: startGame)
            case .playing:
                GameplayView(scene: scene,
                             model: model,
                             onExit: { screen = .menu },
                             onRetrySameSeed: { startGame(seed: currentSeed) },
                             onRetryNewSeed: { startGame(seed: Self.randomSeed()) })
            }
        }
        .frame(minWidth: 440, minHeight: 680)
        .onAppear {
            scene.model = model
            // Automations-/Test-Naht: STEINREGEN_AUTOSTART startet sofort ein Spiel (fuer
            // automatische Screenshots / headless-Smoke-Test). STEINREGEN_LEVEL setzt das
            // Start-Tempo, STEINREGEN_SEED den Seed (sonst zufaellig).
            let env = ProcessInfo.processInfo.environment
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
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                Text("STEINREGEN")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple],
                                       startPoint: .leading, endPoint: .trailing))
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                Text("Ein Columns-Klon · nativ macOS")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
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
            .tint(.indigo)
            .keyboardShortcut(.defaultAction)

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
            legend("←  →", "Säule bewegen")
            legend("↑", "Säule drehen (Farben durchtauschen)")
            legend("↓", "schneller fallen lassen")
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
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(.primary)
            Text(desc).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Spielansicht

struct GameplayView: View {
    let scene: GameScene
    let model: GameModel
    let onExit: () -> Void
    let onRetrySameSeed: () -> Void
    let onRetryNewSeed: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            GameBoardView(scene: scene)
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                // Bewegung/Drehen/Hartfall: Tastendruck + Auto-Wiederholung.
                .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
                // Softdrop-Ende: Pfeil-runter losgelassen.
                .onKeyPress(phases: [.up]) { press in
                    if press.key == .downArrow { scene.setSoftDrop(false) }
                    return .handled
                }
                .onAppear { focused = true }

            if model.isGameOver {
                GameOverOverlay(score: model.finalScore,
                                onRetrySameSeed: { onRetrySameSeed(); focused = true },
                                onRetryNewSeed: { onRetryNewSeed(); focused = true },
                                onExit: onExit)
            }
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow:
            scene.inputLeft(); return .handled
        case .rightArrow:
            scene.inputRight(); return .handled
        case .upArrow:
            if press.phase == .down { scene.inputRotate() }   // nur einmal pro Druck, kein Dauer-Drehen
            return .handled
        case .downArrow:
            scene.setSoftDrop(true); return .handled
        case .space:
            if press.phase == .down { scene.inputHardDrop() }
            return .handled
        case .escape:
            if press.phase == .down { onExit() }
            return .handled
        default:
            return .ignored
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
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Game Over")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                VStack(spacing: 2) {
                    Text("Punkte").font(.headline).foregroundStyle(.secondary)
                    Text("\(score)")
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                }
                VStack(spacing: 12) {
                    Button(action: onRetrySameSeed) {
                        Text("Nochmal (gleicher Seed)").frame(width: 240, height: 42)
                    }
                    .buttonStyle(.borderedProminent).tint(.indigo)
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
