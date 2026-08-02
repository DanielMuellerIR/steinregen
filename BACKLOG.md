# Backlog-Kandidaten Steinregen

Vor Übernahme gegen aktuellen Code, CHANGELOG und bestehende Todos prüfen.

- Klax-artiger Fangmodus: eigenes Input-/Renderparadigma; nicht in FallingPieceEngine zwingen.
- Panel-de-Pon-artiger Cursor-/Wachstumsmodus nur als eigener großer Architekturtrack.
- Vor erstem öffentlichen Push entscheiden, ob alte Developer-ID/Team-ID aus History entfernt
  werden soll; destruktiver Rewrite nur mit ausdrücklicher Freigabe.
- Marken-/Lizenzbewertung vor breiter oder kommerzieller Veröffentlichung aktualisieren.
- Weitere StoneSets/Musik nur mit vollständiger Lizenzkette und bestehenden Registries.
- Notar-Profilprüfung liegt dreifach vor (`notarize-lib.sh`, `tools/make-dmg.sh`,
  `tools/make-notarized.sh`). Über `install.sh`/`release.sh` läuft die Schleife mit fünf
  Versuchen dadurch zweimal hintereinander, und die Kopien können auseinanderlaufen. Die
  unteren Werkzeuge sollen den gemeinsamen Helfer genau einmal nutzen, die Einstiegspunkte nur
  noch Profilnamen ermitteln und delegieren. Abnahme braucht einen echten Notarisierungslauf.
- `install.sh`: Austausch in `/Applications` rücksetzbar machen — Backup-Name beim
  `replaceItemAt` und Rückrollen, falls die Prüfungen nach dem Austausch scheitern. Die
  Gatekeeper-Bewertung läuft seit 2026-08-03 schon vor dem Austausch; für die Nachprüfungen
  gibt es weiterhin keinen Rückweg.
- Deployment-Target 15 → 14 absenken? Technisch kostenlos (echte API-Untergrenze ist
  macOS 14: @Observable + neue onChange-Signatur; Audit 2026-07-16, alle Schwester-Apps
  wurden entsprechend abgesenkt). Kippt aber die dokumentierte Scope-Entscheidung
  „macOS 15+ auf Apple Silicon" (CHANGELOG v0.27.11) — braucht ausdrückliche Freigabe.
