// GameScene.swift
// SpriteKit-Szene von Steinregen: zeichnet Brett, fallende Saeule, HUD und Vorschau,
// treibt im `update(_:)` die Fallgeschwindigkeit (Timing lebt hier, NICHT im Core) und
// animiert die Raeum-Kaskaden inklusive des pulsierenden Magic Jewels.

import SpriteKit
import SteinregenCore

@MainActor
public final class GameScene: SKScene {

    // MARK: Anbindung
    /// Beobachtbares Modell fuer SwiftUI (Game-Over-Overlay, Punktestand). Schwach, um Zyklus zu meiden.
    public weak var model: GameModel?

    // MARK: Spielzustand
    private var engine: Engine?

    // MARK: Layer + Knoten
    /// Ganz hinten: animierter, ziehender Nebel.
    private let fogLayer = SKNode()
    private let backgroundLayer = SKNode()
    private let boardLayer = SKNode()
    private let pieceLayer = SKNode()
    private let hudLayer = SKNode()
    /// Liegt ueber Brett/Saeule (aber unter dem HUD) und legt das raeudige Korn drueber.
    private let overlayLayer = SKNode()

    /// Brett-Knoten, indiziert [col][row]; nil = leere Zelle.
    private var gemNodes: [[SKSpriteNode?]] =
        Array(repeating: Array(repeating: nil, count: Board.defaultHeight), count: Board.defaultWidth)
    /// Die drei Knoten der aktiven Saeule.
    private var pieceNodes: [SKSpriteNode] = []

    private var scoreLabel = SKLabelNode()
    private var levelLabel = SKLabelNode()
    private var nextLabel = SKLabelNode()
    private var previewNodes: [SKSpriteNode] = []

    // MARK: Layout (in layout() berechnet)
    private var tile: CGFloat = 40
    private var boardOriginX: CGFloat = 0
    private var boardOriginY: CGFloat = 0
    private var gemSize: CGSize = .init(width: 36, height: 36)
    private let outerPad: CGFloat = 8

    // MARK: Timing / Ablaufsteuerung
    private var lastUpdateTime: TimeInterval = 0
    private var fallAccumulator: TimeInterval = 0
    private var isResolving = false
    private var softDropActive = false
    /// Zuletzt gesehenes Level — um beim Anstieg den „Level geschafft"-Sound auszulösen.
    private var lastLevel = 0
    /// Lock-Delay (Sega-Style): kurzes Korrektur-Fenster, in dem eine aufgesetzte Saeule noch
    /// geschoben/gedreht werden kann, bevor sie fixiert. Verschiebt man sie so, dass sie wieder
    /// fallen kann, geht es normal weiter. Wert in Sekunden — bewusst etwas laenger als die reine
    /// Reaktionszeit, damit das Fenster auch dann komfortabel zu treffen ist, wenn das Aufsetzen
    /// kaum sichtbar ist. Zusaetzlich frischt jede gelungene Korrektur das Fenster wieder auf
    /// (siehe `inputLeft`/`inputRight`/`inputRotate`).
    private let lockDelay: TimeInterval = 0.42
    /// Nach einem Hard-Drop (Leertaste) gilt bewusst nur das halbe Fenster: der Slam soll knackig
    /// bleiben, aber eine kurze Last-Minute-Korrektur ist noch moeglich (gewuenschter Kompromiss).
    private let hardDropLockDelay: TimeInterval = 0.21
    private var lockDelayAccumulator: TimeInterval = 0
    /// true, solange die aktuelle Saeule per Leertaste heruntergelassen wurde → kuerzeres Fenster.
    private var hardDropped = false

    /// Horizontaler Auto-Repeat: gehaltene Links/Rechts-Taste verschiebt die Saeule in fester,
    /// snappy Rate — bewusst UNABHAENGIG von der OS-Tastenwiederholung (sonst haengt das Tempo an
    /// den Systemeinstellungen). `moveDir` ist -1 (links), +1 (rechts) oder 0 (keine Taste).
    private var moveDir = 0
    private var moveRepeatAccumulator: TimeInterval = 0
    /// false bis der erste Auto-Repeat nach der Anfangsverzoegerung (DAS) ausgeloest hat.
    private var moveDASStarted = false
    /// DAS = Wartezeit zwischen dem ersten Schritt und dem Einsetzen des Auto-Repeats.
    private let moveDAS: TimeInterval = 0.17
    /// ARR = Intervall des Auto-Repeats danach (ca. 17 % schneller als der uebliche OS-Default).
    private let moveARR: TimeInterval = 0.05

    // MARK: - Lebenszyklus

    public override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        // Szene sofort an die View-Größe angleichen, sonst wird der erste Frame (Szene noch in
        // Ausgangsgröße) in den View gestreckt → verzerrte Steine bis zum ersten Resize.
        if view.bounds.size.width > 0, view.bounds.size.height > 0 { size = view.bounds.size }
        anchorPoint = CGPoint(x: 0, y: 0)
        Theme.registerFonts()
        backgroundColor = Theme.canvas.sk
        if backgroundLayer.parent == nil {
            addChild(fogLayer)
            addChild(backgroundLayer)
            addChild(boardLayer)
            addChild(pieceLayer)
            addChild(overlayLayer)
            addChild(hudLayer)
            // Zeichenreihenfolge: Nebel ganz hinten, Korn ueber den Steinen, HUD oben (bleibt scharf).
            fogLayer.zPosition = -1
            overlayLayer.zPosition = 50
            hudLayer.zPosition = 100
        }
        layout()
        if let engine { renderBoardInstant(engine.board); renderPiece(); updateHUD() }
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard backgroundLayer.parent != nil else { return }
        layout()
        if let engine { renderBoardInstant(engine.board); renderPiece(); updateHUD() }
    }

    // MARK: - Spielstart

    /// Startet (oder restartet) eine Partie mit gegebenem Seed und Start-Tempostufe.
    public func start(seed: UInt64, startLevel: Int) {
        // Gewaehltes Steine-Set aus den Einstellungen uebernehmen (gilt ab dieser Partie).
        GemTextures.activeSetID = StoneSets.selectedID
        engine = Engine(seed: seed, startLevel: startLevel)
        lastLevel = engine!.level          // kein „Level geschafft" beim Start
        isResolving = false
        fallAccumulator = 0
        lockDelayAccumulator = 0
        hardDropped = false
        lastUpdateTime = 0
        softDropActive = false
        moveDir = 0
        moveRepeatAccumulator = 0
        moveDASStarted = false
        model?.reset()
        if backgroundLayer.parent != nil {
            layout()
            renderBoardInstant(engine!.board)
            renderPiece()
            updateHUD()
        }
    }

    // MARK: - Layout

    /// So viele Kacheln Breite werden fuer die beiden Seiten-Panels reserviert (links Punkte/Level,
    /// rechts die senkrechte Vorschau) — der Rest ist das Brett. Haelt die Panels auch auf kleinen
    /// Fenstern lesbar breit.
    private let sideTilesTotal: CGFloat = 3.6

    private func layout() {
        let availW = size.width - outerPad * 2
        let availH = size.height - outerPad * 2
        guard availW > 0, availH > 0 else { return }
        // Brett fuellt die Hoehe; die Kachelgroesse wird zusaetzlich so gedeckelt, dass links und
        // rechts je ein Seiten-Panel frei bleibt (Punkte/Level bzw. Vorschau).
        tile = floor(min(availH / CGFloat(Board.defaultHeight),
                         availW / (CGFloat(Board.defaultWidth) + sideTilesTotal)))
        let boardW = tile * CGFloat(Board.defaultWidth)
        let boardH = tile * CGFloat(Board.defaultHeight)
        boardOriginX = (size.width - boardW) / 2          // mittig → gleicher Rand links/rechts
        boardOriginY = (size.height - boardH) / 2          // senkrecht zentriert
        gemSize = CGSize(width: tile * 0.94, height: tile * 0.94)
        buildFog()
        buildBackground(boardW: boardW, boardH: boardH)
        buildHUD(boardW: boardW, boardH: boardH)
        buildGrain()
    }

    /// Baut zwei gegenlaeufig driftende, leicht pulsierende Nebelschichten — der animierte Hintergrund.
    private func buildFog() {
        fogLayer.removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }
        let tex = GemTextures.fog()

        func makeFog(scale: CGFloat, alpha: CGFloat, dx: CGFloat, dy: CGFloat, dur: TimeInterval, offset: CGPoint) {
            let node = SKSpriteNode(texture: tex)
            // Deutlich groesser als die Szene, damit beim Driften nie ein Rand sichtbar wird.
            node.size = CGSize(width: size.width * 1.7, height: size.height * 1.5)
            node.setScale(scale)
            node.position = CGPoint(x: size.width / 2 + offset.x, y: size.height / 2 + offset.y)
            node.alpha = alpha
            fogLayer.addChild(node)
            let move = SKAction.sequence([SKAction.moveBy(x: dx, y: dy, duration: dur),
                                          SKAction.moveBy(x: -dx, y: -dy, duration: dur)])
            move.timingMode = .easeInEaseOut
            let pulse = SKAction.sequence([SKAction.scale(to: scale * 1.08, duration: dur * 0.85),
                                           SKAction.scale(to: scale, duration: dur * 0.85)])
            node.run(SKAction.repeatForever(SKAction.group([move, pulse])))
        }
        makeFog(scale: 1.00, alpha: 0.28, dx:  46, dy:  14, dur: 17, offset: CGPoint(x: -20, y: 0))
        makeFog(scale: 1.35, alpha: 0.18, dx: -60, dy: -10, dur: 23, offset: CGPoint(x:  30, y: 20))
    }

    /// Legt das statische Korn als ganzflaechigen Schleier ueber die Szene (raeudiger Lo-Fi-Look).
    private func buildGrain() {
        overlayLayer.removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }
        let grain = SKSpriteNode(texture: GemTextures.grain(), size: size)
        grain.position = CGPoint(x: size.width / 2, y: size.height / 2)
        grain.alpha = 0.32
        overlayLayer.addChild(grain)
    }

    private func cellCenter(col: Int, row: Int) -> CGPoint {
        CGPoint(x: boardOriginX + (CGFloat(col) + 0.5) * tile,
                y: boardOriginY + (CGFloat(row) + 0.5) * tile)
    }

    private func buildBackground(boardW: CGFloat, boardH: CGFloat) {
        backgroundLayer.removeAllChildren()
        // Brett-Panel.
        let panel = SKShapeNode(rect: CGRect(x: boardOriginX - 6, y: boardOriginY - 6,
                                             width: boardW + 12, height: boardH + 12),
                                cornerRadius: 12)
        // Halbtransparent, damit der Nebel auch hinter dem Schacht durchzieht.
        panel.fillColor = Theme.panel.sk(0.6)
        panel.strokeColor = Theme.oxbloodDark.sk
        panel.lineWidth = 2
        backgroundLayer.addChild(panel)
        // Feines Raster.
        let grid = SKShapeNode()
        let path = CGMutablePath()
        for c in 0...Board.defaultWidth {
            let x = boardOriginX + CGFloat(c) * tile
            path.move(to: CGPoint(x: x, y: boardOriginY))
            path.addLine(to: CGPoint(x: x, y: boardOriginY + boardH))
        }
        for r in 0...Board.defaultHeight {
            let y = boardOriginY + CGFloat(r) * tile
            path.move(to: CGPoint(x: boardOriginX, y: y))
            path.addLine(to: CGPoint(x: boardOriginX + boardW, y: y))
        }
        grid.path = path
        grid.strokeColor = Theme.bone.sk(0.045)
        grid.lineWidth = 1
        backgroundLayer.addChild(grid)
    }

    private func buildHUD(boardW: CGFloat, boardH: CGFloat) {
        hudLayer.removeAllChildren()
        previewNodes.removeAll()

        let topY = boardOriginY + boardH                      // Oberkante des Bretts
        let leftCenterX  = (outerPad + boardOriginX) / 2      // Mitte des linken Seiten-Panels
        let rightCenterX = (boardOriginX + boardW + size.width - outerPad) / 2  // Mitte des rechten Panels

        // --- Linkes Panel: Punkte (groß) + Level ---
        let punkteCap = makeLabel(size: 18, bold: false)
        punkteCap.text = "Punkte"
        punkteCap.fontColor = Theme.boneDim.sk
        punkteCap.horizontalAlignmentMode = .center
        punkteCap.verticalAlignmentMode = .center
        punkteCap.position = CGPoint(x: leftCenterX, y: topY - 24)
        hudLayer.addChild(punkteCap)

        scoreLabel = makeLabel(size: 28, bold: true)
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: leftCenterX, y: topY - 56)
        hudLayer.addChild(scoreLabel)

        levelLabel = makeLabel(size: 20, bold: false)
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.fontColor = Theme.boneDim.sk
        levelLabel.position = CGPoint(x: leftCenterX, y: topY - 92)
        hudLayer.addChild(levelLabel)

        // --- Rechtes Panel: „als Nächstes" + SENKRECHTE Vorschau (wie die fallende Säule) ---
        nextLabel = makeLabel(size: 18, bold: true)
        nextLabel.text = "als Nächstes"
        nextLabel.fontColor = Theme.boneDim.sk
        nextLabel.horizontalAlignmentMode = .center
        nextLabel.verticalAlignmentMode = .center
        nextLabel.position = CGPoint(x: rightCenterX, y: topY - 24)
        hudLayer.addChild(nextLabel)

        // Drei Steine senkrecht gestapelt: Index 0 = unterster Stein der Säule → unten, Index 2 → oben.
        let pSize = min(tile * 0.86, (size.width - (boardOriginX + boardW) - outerPad) * 0.78)
        let gap: CGFloat = 6
        let firstY = topY - 56 - pSize / 2          // Mitte des obersten Vorschau-Steins
        for i in 0..<3 {
            let n = SKSpriteNode(color: .clear, size: CGSize(width: pSize, height: pSize))
            n.position = CGPoint(x: rightCenterX, y: firstY - CGFloat(2 - i) * (pSize + gap))
            previewNodes.append(n)
            hudLayer.addChild(n)
        }
    }

    /// Alle HUD-Texte in der gotischen Schrift (Grenze Gotisch). `bold` waehlt jetzt den fetten
    /// Schnitt — fuer kraeftigere, besser lesbare Titel/Score; sonst der Regular-Schnitt.
    private func makeLabel(size: CGFloat, bold: Bool) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: bold ? Theme.blackletterBoldPostScript : Theme.blackletterPostScript)
        label.fontSize = size
        label.fontColor = Theme.bone.sk
        return label
    }

    // MARK: - Rendering Brett + Saeule

    private func makeGemNode(_ gem: Gem) -> SKSpriteNode {
        let node = SKSpriteNode(texture: GemTextures.texture(for: gem), size: gemSize)
        if gem.isMagic { applyMagicAnimation(to: node) }
        return node
    }

    /// Setzt das ganze Brett ohne Animation neu (initial + Resync nach Kaskade).
    private func renderBoardInstant(_ board: Board) {
        boardLayer.removeAllChildren()
        for col in 0..<Board.defaultWidth {
            for row in 0..<Board.defaultHeight {
                gemNodes[col][row] = nil
                if let gem = board[col, row] {
                    let node = makeGemNode(gem)
                    node.position = cellCenter(col: col, row: row)
                    boardLayer.addChild(node)
                    gemNodes[col][row] = node
                }
            }
        }
    }

    /// Positioniert/texturiert die drei Knoten der aktiven Saeule.
    private func renderPiece(animated: Bool = false) {
        guard let engine else { return }
        while pieceNodes.count < 3 {
            let n = SKSpriteNode(); pieceLayer.addChild(n); pieceNodes.append(n)
        }
        let falling = (engine.phase == .falling)
        for i in 0..<3 {
            let node = pieceNodes[i]
            node.size = gemSize
            // Die Saeule schwebt von oben ein: Segmente oberhalb der obersten Brettreihe sind noch
            // nicht im Spielfeld und bleiben unsichtbar, bis sie eine Reihe tiefer rutschen.
            let row = engine.current.row + i
            let onBoard = row < Board.defaultHeight
            node.isHidden = !falling || !onBoard
            let gem = engine.current.gems[i]
            if gem.isMagic {
                node.texture = GemTextures.magicTextures.first
                applyMagicAnimation(to: node)
            } else {
                node.removeAction(forKey: "magic")
                node.setScale(1)
                node.texture = GemTextures.texture(for: gem)
            }
            let target = cellCenter(col: engine.current.col, row: row)
            // Nur im Brett animieren; ein noch unsichtbares Segment wird direkt an seine Position
            // ueber dem Brett geparkt — taucht es eine Reihe tiefer auf, gleitet es von dort herein.
            if animated && onBoard {
                node.run(SKAction.move(to: target, duration: 0.06))
            } else {
                node.position = target
            }
        }
    }

    /// Pulsierender Regenbogen fuer Magic-Steine: Texturen durchwechseln + sanftes Pulsieren.
    private func applyMagicAnimation(to node: SKSpriteNode) {
        guard node.action(forKey: "magic") == nil else { return }
        let cycle = SKAction.animate(with: GemTextures.magicTextures, timePerFrame: 0.09,
                                     resize: false, restore: false)
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 0.35),
            SKAction.scale(to: 0.96, duration: 0.35)
        ])
        node.run(SKAction.repeatForever(SKAction.group([cycle, pulse])), withKey: "magic")
    }

    // MARK: - Spielloop

    public override func update(_ currentTime: TimeInterval) {
        guard let engine, !isResolving, engine.phase == .falling else {
            lastUpdateTime = currentTime
            return
        }
        if lastUpdateTime == 0 { lastUpdateTime = currentTime; return }
        let dt = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        // Horizontaler Auto-Repeat: erster Schritt kam schon beim Tastendruck (startMove); hier
        // folgt nach der Anfangsverzoegerung (DAS) die schnelle Wiederholung (ARR), solange gehalten.
        if moveDir != 0 {
            moveRepeatAccumulator += dt
            let threshold = moveDASStarted ? moveARR : moveDAS
            if moveRepeatAccumulator >= threshold {
                moveRepeatAccumulator = 0
                moveDASStarted = true
                if moveDir < 0 { inputLeft() } else { inputRight() }
            }
        }

        if engine.canFall() {
            // Normales Fallen. (Hat die Saeule durch Schieben wieder Luft, läuft das Lock-Delay nicht.)
            lockDelayAccumulator = 0
            fallAccumulator += dt
            let interval = softDropActive ? min(0.045, fallInterval(engine.level)) : fallInterval(engine.level)
            if fallAccumulator >= interval {
                fallAccumulator = 0
                stepGravity()
            }
        } else {
            // Aufgesetzt → kurzes Korrektur-Fenster (Lock-Delay); erst danach wird fixiert.
            fallAccumulator = 0
            lockDelayAccumulator += dt
            // Per Leertaste aufgesetzt → halbes Fenster; normales Aufsetzen → volles Fenster.
            let limit = hardDropped ? hardDropLockDelay : lockDelay
            if lockDelayAccumulator >= limit {
                lockDelayAccumulator = 0
                stepGravity()          // canFall() ist false → gravityTick() setzt jetzt auf
            }
        }
    }

    /// Fallgeschwindigkeit je Level (Sekunden pro Reihe). Reines Zahlen-Mapping, keine Wanduhr.
    /// Level ist 1-basiert: Level 1 = ruhigster Start.
    private func fallInterval(_ level: Int) -> TimeInterval {
        max(0.085, 0.80 - Double(level - 1) * 0.06)
    }

    private func stepGravity() {
        guard engine != nil else { return }
        switch engine!.gravityTick() {
        case .moved:
            renderPiece(animated: true)
        case .locked(let result):
            beginResolution(result)
        }
    }

    // MARK: - Eingaben (von SwiftUI weitergereicht)

    // Jede gelungene Korrektur (Schieben/Drehen) setzt den Lock-Delay-Akku auf 0 zurueck und frischt
    // so das Korrektur-Fenster auf: liegt die Saeule schon auf, bekommt der Spieler nach jedem Zug
    // erneut die volle Zeit, statt dass das Fenster ab dem ersten Aufsetzen unaufhaltsam ablaeuft.
    // Im freien Fall ist der Akku ohnehin 0 — dort ist das Zuruecksetzen wirkungslos (harmlos).
    public func inputLeft()  { guard canInput() else { return }; if engine!.moveLeft()  { renderPiece(animated: true); lockDelayAccumulator = 0 } }
    public func inputRight() { guard canInput() else { return }; if engine!.moveRight() { renderPiece(animated: true); lockDelayAccumulator = 0 } }
    public func inputRotate(){ guard canInput() else { return }; if engine!.rotate()    { renderPiece(); bumpPiece(); SoundFX.rotate(); lockDelayAccumulator = 0 } }

    /// Beginnt das horizontale Halten in `dir` (-1 links, +1 rechts): ein sofortiger erster Schritt,
    /// danach uebernimmt der Auto-Repeat im `update(_:)` (siehe moveDAS/moveARR).
    public func startMove(_ dir: Int) {
        moveDir = dir
        moveRepeatAccumulator = 0
        moveDASStarted = false
        if dir < 0 { inputLeft() } else if dir > 0 { inputRight() }
    }

    /// Beendet das Halten in `dir` (nur wenn genau diese Richtung aktiv war — so stoppt das
    /// Loslassen der einen Taste nicht versehentlich eine noch gehaltene Gegenrichtung).
    public func stopMove(_ dir: Int) {
        if moveDir == dir { moveDir = 0 }
    }

    /// Harter Fall: zieht die Saeule sofort bis zum Aufsetzen herunter — fixiert dann aber NICHT
    /// sofort, sondern oeffnet das halbe Korrektur-Fenster (`hardDropLockDelay`), in dem noch
    /// geschoben/gedreht werden kann. Wer gar nichts mehr tut, rastet nach 0,21 s ein.
    public func inputHardDrop() {
        guard canInput() else { return }
        // Nur fallen lassen, solange Luft ist (jeder Tick liefert .moved). Den lock-ausloesenden
        // Tick (canFall == false) bewusst NICHT ausfuehren — das uebernimmt erst das Lock-Delay.
        while engine!.canFall() { _ = engine!.gravityTick() }
        hardDropped = true
        lockDelayAccumulator = 0
        renderPiece()          // sofort an die Aufsetz-Position (knackiger Slam)
    }

    public func setSoftDrop(_ active: Bool) { softDropActive = active }

    private func canInput() -> Bool { engine != nil && !isResolving && engine!.phase == .falling }

    /// Kleiner Skalier-Impuls als Feedback beim Drehen.
    private func bumpPiece() {
        for node in pieceNodes where !node.isHidden && node.action(forKey: "magic") == nil {
            node.run(SKAction.sequence([SKAction.scale(to: 1.12, duration: 0.05),
                                        SKAction.scale(to: 1.0, duration: 0.08)]))
        }
    }

    // MARK: - Kaskaden-Animation

    private func beginResolution(_ result: LockResult) {
        isResolving = true
        SoundFX.land()                 // Säule ist aufgesetzt (Stein berührt Stein/Boden)
        for node in pieceNodes { node.isHidden = true }
        animateLock(result) { [weak self] in self?.endResolution() }
    }

    private func animateLock(_ result: LockResult, completion: @escaping () -> Void) {
        renderBoardInstant(result.boardBefore)

        func runSteps(_ index: Int) {
            guard index < result.steps.count else {
                updateHUD()            // Punktestand nach der Welle nachziehen
                completion()
                return
            }
            let step = result.steps[index]
            showCombo(chain: step.chain, count: step.cells.count)
            flashAndRemove(step.cells) { [weak self] in
                self?.compactColumnsAnimated {
                    self?.updateHUD()
                    runSteps(index + 1)
                }
            }
        }

        if result.wasMagic {
            showMagicLanding(result.landed) { runSteps(0) }
        } else {
            runSteps(0)
        }
    }

    /// Laesst die getroffenen Zellen aufblitzen und verschwinden.
    private func flashAndRemove(_ cells: [Cell], completion: @escaping () -> Void) {
        SoundFX.clear()                // eine Räum-Welle (Steine lösen sich auf)
        let flash = SKAction.group([
            SKAction.scale(to: 1.35, duration: 0.14),
            SKAction.fadeOut(withDuration: 0.16)
        ])
        for cell in cells {
            if let node = gemNodes[cell.col][cell.row] {
                node.zPosition = 5
                node.run(SKAction.sequence([flash, SKAction.removeFromParent()]))
                gemNodes[cell.col][cell.row] = nil
            }
        }
        run(SKAction.wait(forDuration: 0.18)) { completion() }
    }

    /// Laesst die uebrigen Steine spaltenweise nach unten nachrutschen (analog zu `settle`).
    private func compactColumnsAnimated(completion: @escaping () -> Void) {
        var maxDuration: TimeInterval = 0
        for col in 0..<Board.defaultWidth {
            var writeRow = 0
            for row in 0..<Board.defaultHeight {
                if let node = gemNodes[col][row] {
                    if writeRow != row {
                        gemNodes[col][writeRow] = node
                        gemNodes[col][row] = nil
                        let distance = row - writeRow
                        let dur = min(0.05 + 0.03 * Double(distance), 0.3)
                        maxDuration = max(maxDuration, dur)
                        let move = SKAction.move(to: cellCenter(col: col, row: writeRow), duration: dur)
                        move.timingMode = .easeIn
                        node.run(move)
                    }
                    writeRow += 1
                }
            }
        }
        if maxDuration == 0 {
            completion()
        } else {
            run(SKAction.wait(forDuration: maxDuration)) { completion() }
        }
    }

    /// Zeigt die aufsetzende Magic-Saeule kurz an ihrer Landeposition und laesst sie aufploppen.
    private func showMagicLanding(_ landed: Piece, completion: @escaping () -> Void) {
        var nodes: [SKSpriteNode] = []
        for i in 0..<3 {
            let node = SKSpriteNode(texture: GemTextures.magicTextures.first, size: gemSize)
            node.position = cellCenter(col: landed.col, row: landed.row + i)
            node.zPosition = 6
            applyMagicAnimation(to: node)
            boardLayer.addChild(node)
            nodes.append(node)
        }
        let poof = SKAction.sequence([
            SKAction.wait(forDuration: 0.22),
            SKAction.group([SKAction.scale(to: 1.6, duration: 0.18), SKAction.fadeOut(withDuration: 0.2)]),
            SKAction.removeFromParent()
        ])
        for node in nodes { node.run(poof) }

        // Dezenter Erklärungstext (bewusst leiser als das Combo-Feedback): erklärt, was gerade
        // passiert, ohne aufdringlich zu sein.
        let info = makeLabel(size: 17, bold: false)
        info.text = "Magischer Stein — räumt eine ganze Sorte"
        info.fontColor = Theme.boneDim.sk
        info.horizontalAlignmentMode = .center
        info.verticalAlignmentMode = .center
        info.position = CGPoint(x: size.width / 2, y: size.height * 0.66)
        info.zPosition = 60
        info.alpha = 0
        hudLayer.addChild(info)
        info.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.15),
            SKAction.wait(forDuration: 0.9),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))

        run(SKAction.wait(forDuration: 0.42)) { completion() }
    }

    private func endResolution() {
        guard let engine else { return }
        renderBoardInstant(engine.board)            // finaler, garantiert korrekter Stand
        if self.engine!.spawnNext() {
            renderPiece()
        } else {
            model?.finalScore = self.engine!.score
            model?.finalLevel = self.engine!.level
            model?.isGameOver = true
            SoundFX.gameOver()
            showGameOverBanner()
        }
        updateHUD()
        isResolving = false
        fallAccumulator = 0
        hardDropped = false        // frische Saeule → wieder volles Korrektur-Fenster
    }

    private func showGameOverBanner() {
        let label = makeLabel(size: 46, bold: true)
        label.text = "Verreckt"
        label.fontColor = Theme.blood.sk
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.alpha = 0
        label.zPosition = 20
        hudLayer.addChild(label)
        label.run(SKAction.fadeIn(withDuration: 0.4))
    }

    /// Positives Erfolgs-Feedback: blendet bei Kettenreaktionen eine groß werdende „N×"-Anzeige ein
    /// (ab Kette 3 in kräftigem Rot). Auch eine große Einzel-Räumung (viele Steine auf einmal)
    /// bekommt einen dezenten Hinweis. Eine ruhige erste Welle mit wenigen Steinen bleibt still.
    private func showCombo(chain: Int, count: Int) {
        let text: String
        let color: Theme.RGB
        if chain >= 2 {
            text = "\(chain)×"
            color = chain >= 3 ? Theme.blood : Theme.bone
        } else if count >= 6 {
            text = "\(count)!"
            color = Theme.bone
        } else {
            return
        }
        let label = makeLabel(size: 40, bold: true)
        label.text = text
        label.fontColor = color.sk
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.56)
        label.zPosition = 60
        label.alpha = 0
        label.setScale(0.4)
        hudLayer.addChild(label)
        // Höhere Ketten erscheinen größer und ploppen kräftiger.
        let peak = min(2.8, 1.3 + CGFloat(max(chain, 2)) * 0.32)
        let appear = SKAction.group([SKAction.fadeIn(withDuration: 0.10),
                                     SKAction.scale(to: peak, duration: 0.22)])
        appear.timingMode = .easeOut
        label.run(SKAction.sequence([
            appear,
            SKAction.wait(forDuration: 0.32),
            SKAction.group([SKAction.fadeOut(withDuration: 0.30),
                            SKAction.scale(to: peak * 1.25, duration: 0.30)]),
            SKAction.removeFromParent()
        ]))
    }

    /// Kurzer, einblendender Hinweis (z.B. „mundtot" / „Ton an" beim Umschalten mit T).
    public func flashHint(_ text: String) {
        hudLayer.childNode(withName: "hint")?.removeFromParent()
        let label = makeLabel(size: 22, bold: true)
        label.name = "hint"
        label.text = text
        label.fontColor = Theme.bone.sk
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.6)
        label.alpha = 0
        label.zPosition = 30
        hudLayer.addChild(label)
        label.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.08),
            SKAction.wait(forDuration: 0.7),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - HUD

    private func updateHUD() {
        guard let engine else { return }
        scoreLabel.text = "\(engine.score)"
        levelLabel.text = "Level \(engine.level)"
        model?.score = engine.score
        model?.level = engine.level
        if engine.level > lastLevel { SoundFX.levelUp() }   // Level gestiegen
        lastLevel = engine.level

        let pSize = previewNodes.first?.size ?? gemSize
        let isMagicPreview = engine.nextGems.allSatisfy { $0.isMagic }
        for (i, node) in previewNodes.enumerated() {
            node.size = pSize
            let gem = engine.nextGems[i]
            if isMagicPreview {
                node.texture = GemTextures.magicTextures.first
                applyMagicAnimation(to: node)
            } else {
                node.removeAction(forKey: "magic")
                node.setScale(1)
                node.texture = GemTextures.texture(for: gem)
            }
        }
    }
}
