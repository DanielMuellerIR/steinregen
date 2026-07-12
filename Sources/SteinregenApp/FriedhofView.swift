// FriedhofView.swift
// Die Bestenliste („Friedhof"): FriedhofView zeichnet die Grabstein-Zeilen (im Game-Over
// gekuerzt, im eigenen Fenster vollstaendig), FriedhofSheet ist das eigene Menue-Fenster.
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
            DoneButton(title: L10n.t("Schließen", "Close"), action: onClose)
        }
        .padding(24)
        .dialogFrame(width: 480, height: 640)
        .background(Color(red: 0.02, green: 0.02, blue: 0.03))
        .preferredColorScheme(.dark)
    }
}
