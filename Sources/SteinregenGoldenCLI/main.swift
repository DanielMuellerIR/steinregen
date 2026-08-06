// main.swift
// Das ausfuehrbare Werkzeug `steinregen-golden`. Es enthaelt absichtlich keine Logik: Alles
// steckt in der Bibliothek `SteinregenGolden`, damit der Regressionstest dieselbe Funktion
// aufrufen kann. Hier bleibt nur der Startpunkt und die Weitergabe des Exit-Codes.

import Foundation
import SteinregenGolden

exit(goldenMain())
