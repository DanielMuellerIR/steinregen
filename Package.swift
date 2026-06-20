// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Steinregen",
    platforms: [
        // macOS 15+ (iOS-Port bewusst spaeter; Core ist plattformneutral gehalten)
        .macOS(.v15)
    ],
    products: [
        .library(name: "SteinregenCore", targets: ["SteinregenCore"]),
        .library(name: "SteinregenRender", targets: ["SteinregenRender"]),
        // Das ausfuehrbare Produkt heisst schlicht "Steinregen" (= Fenster-/App-Titel).
        .executable(name: "Steinregen", targets: ["SteinregenApp"])
    ],
    dependencies: [],
    targets: [
        // Reine, deterministische Spiellogik: KEIN globaler Zufall, KEINE Wanduhr.
        .target(
            name: "SteinregenCore",
            dependencies: []
        ),
        // SpriteKit-Darstellung + Spielloop (Schwerkraft-Timing lebt hier, nicht im Core).
        .target(
            name: "SteinregenRender",
            dependencies: ["SteinregenCore"],
            resources: [.process("Resources")]
        ),
        // SwiftUI-Anwendungs-Shell.
        .executableTarget(
            name: "SteinregenApp",
            dependencies: ["SteinregenCore", "SteinregenRender"]
        ),
        .testTarget(
            name: "SteinregenCoreTests",
            dependencies: ["SteinregenCore"]
        )
    ]
)
