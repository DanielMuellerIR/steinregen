// Friedhof.swift
// Persistente Bestenliste — thematisch „Friedhof": jeder Eintrag ist ein Grab mit Name, Score
// und dem Level, in dem man verreckt ist. Gespeichert als JSON in UserDefaults (App-Schicht-
// Zustand, kein Core-Zustand). Datum/UUID sind hier erlaubt (reine Praesentation, kein
// deterministischer Core).

import Foundation

/// Ein Grab auf dem Friedhof.
struct GraveEntry: Codable, Identifiable {
    let id: UUID
    var name: String
    var score: Int
    var level: Int          // Level, in dem der Lauf endete („verreckt in Level …")
    var date: Date
}

@MainActor
enum Friedhof {
    /// So viele Graeber werden behalten (die mit dem hoechsten Score).
    static let maxEntries = 16
    private static let key = "steinregen.friedhof"
    private static let nameKey = "steinregen.lastName"

    /// Alle Graeber, absteigend nach Score sortiert.
    static func entries() -> [GraveEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([GraveEntry].self, from: data) else { return [] }
        return list.sorted { $0.score > $1.score }
    }

    /// Reicht dieser Score auf den Friedhof (Liste noch nicht voll oder schlaegt das schlechteste Grab)?
    static func qualifies(score: Int) -> Bool {
        let list = entries()
        if list.count < maxEntries { return true }
        return score > (list.last?.score ?? Int.min)
    }

    /// Traegt ein Grab ein, sortiert + kuerzt auf `maxEntries`, merkt den Namen. Gibt die id zurueck
    /// (zum Hervorheben des frischen Grabs in der Liste).
    @discardableResult
    static func add(name: String, score: Int, level: Int) -> UUID {
        var list = entries()
        let entry = GraveEntry(id: UUID(), name: name, score: score, level: level, date: Date())
        list.append(entry)
        list.sort { $0.score > $1.score }
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
        lastName = name
        return entry.id
    }

    /// Zuletzt eingegebener Name (als Vorbelegung beim naechsten Eintrag).
    static var lastName: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }
}
