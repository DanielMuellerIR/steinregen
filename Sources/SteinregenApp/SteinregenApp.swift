// SteinregenApp.swift
// App-Geruest von Steinregen: der @main-Einstieg, die Fenster-Konfiguration (macOS) und die
// RootView, die zwischen Menue (StartView) und Spiel (GameplayView) umschaltet und die drei
// Dialoge (Einstellungen/Friedhof/Spielregeln) als Sheets fuehrt. Die einzelnen Views liegen
// in eigenen Dateien (StartView.swift, SettingsView.swift, …), die geteilten UI-Helfer in
// SharedUI.swift.
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
                case "fuenfling":    gameMode = .fuenfling
                case "kapseln":      gameMode = .kapseln
                case "schnitter":    gameMode = .schnitter
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
            if env["STEINREGEN_RULES"] != nil { activeSheet = .rules }
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
