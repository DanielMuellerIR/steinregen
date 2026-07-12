// TouchControls.swift
// iOS-Touch-Steuerung: TouchControlsOverlay (Gesten ueber dem Brett + Knopfleiste + Menue-/
// Musik-Knopf) samt der Bausteine HoldButton (Halte-Verhalten) und TapControlButton. Die
// ganze Datei ist iOS-only. Aus SteinregenApp.swift ausgegliedert.

import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif
import SteinregenCore
import SteinregenRender

#if os(iOS)
/// Touch-Steuerung fürs iPhone (es gibt keine Tastatur): Über dem Brett fängt eine durchsichtige
/// Fläche Gesten ab — Tippen dreht die Säule, Wischen schiebt sie (links/rechts je einen Schritt)
/// bzw. wirft sie ab (nach unten). Unten liegt eine dezente Knopfleiste, oben links ein Menü-Knopf.
/// Die Links/Rechts-Knöpfe nutzen `startMove`/`stopMove` → szeneneigener Auto-Repeat wie bei der
/// gehaltenen Taste am Mac.
// Nicht `private`: GameplayView (eigene Datei) verwendet dieses Overlay — im selben Modul
// genügt internal. HoldButton/TapControlButton bleiben `private` (nur hier gebraucht).
struct TouchControlsOverlay: View {
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
