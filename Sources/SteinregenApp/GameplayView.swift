// GameplayView.swift
// Spielansicht: das SpriteKit-Brett plus Game-Over-Overlay; auf iOS zusaetzlich die
// Touch-Steuerung. macOS-Tastatur laeuft ueber einen fokus-unabhaengigen NSEvent-Monitor.
// Aus SteinregenApp.swift ausgegliedert.

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import SteinregenCore
import SteinregenRender

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
                                victory: model.isVictory,
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
