// L10n.swift
// Winzige Lokalisierungs-Schicht für Deutsch/Englisch — bewusst OHNE SwiftPM-`.lproj`/
// `.xcstrings`-Maschinerie (die zickt mit dem eigenen, robusten Ressourcen-Loader und müsste
// für macOS-SwiftPM UND das iOS-xcodegen-Projekt getrennt eingerichtet werden).
//
// Stattdessen stehen beide Sprachvarianten DIREKT am Aufrufort:
//
//     Text(L10n.t("Einstellungen", "Settings"))
//
// `L10n.t(de, en)` liefert je nach aktueller Sprache den passenden String. Das ist für eine
// Zwei-Sprachen-App am wartungsärmsten (keine Schlüsseltabelle, keine fehlenden Keys) und gut
// lesbar — man sieht beide Fassungen nebeneinander.
//
// Sprachwahl: Standard ist die System-Sprache (Deutsch bei deutschem System, sonst Englisch);
// in den Einstellungen lässt sie sich fest umstellen (persistiert in UserDefaults). Reine
// Präsentationsschicht — kein Bezug zum deterministischen Core.

import Foundation

// Bewusst NICHT @MainActor: `L10n.t` wird auch aus nicht-isolierten Stellen aufgerufen
// (z.B. `GameMode.title`), und es liest nur den thread-sicheren `UserDefaults`/`Locale`.
public enum L10n {

    /// Die zwei unterstützten Sprachen.
    public enum Lang: String, CaseIterable, Sendable {
        case de   // Deutsch
        case en   // English
    }

    /// UserDefaults-Schlüssel des (optionalen) festen Sprach-Overrides. Ungesetzt ⇒ Auto.
    public static let key = "steinregen.sprache"

    /// Aktuelle Sprache. Ohne gespeicherten Override wird sie aus der bevorzugten System-Sprache
    /// abgeleitet: beginnt sie mit „de", ist es Deutsch, sonst Englisch.
    public static var lang: Lang {
        get {
            if let raw = UserDefaults.standard.string(forKey: key), let l = Lang(rawValue: raw) {
                return l
            }
            let pref = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return pref.hasPrefix("de") ? .de : .en
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Liefert je nach aktueller Sprache den deutschen (`de`) oder englischen (`en`) Text.
    public static func t(_ de: String, _ en: String) -> String {
        lang == .de ? de : en
    }
}
