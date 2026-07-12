// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Steinregen",
    platforms: [
        // macOS 15+ fuer die Desktop-App; iOS 17+ fuer die iPhone-App (teilt Core+Render,
        // eigene Touch-App-Schicht ueber dasselbe SteinregenApp-Quellverzeichnis).
        .macOS(.v15),
        .iOS(.v17)
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
        ),
        // Tests der Render-/Spielloop-Schicht (Lock-Delay-Verhalten u.ae.). Braucht SpriteKit,
        // laeuft daher nur mit der Xcode-Toolchain (DEVELOPER_DIR=… xcrun swift test).
        .testTarget(
            name: "SteinregenRenderTests",
            dependencies: ["SteinregenRender", "SteinregenCore"]
        ),
        // Tests der App-Schicht: die persistente Bestenliste (Friedhof). Haengt am
        // ausfuehrbaren App-Target (@testable import); laeuft mit der Xcode-Toolchain.
        .testTarget(
            name: "SteinregenAppTests",
            dependencies: ["SteinregenApp"]
        )
    ]
)
