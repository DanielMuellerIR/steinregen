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
    private let backgroundLayer = SKNode()
    private let boardLayer = SKNode()
    private let pieceLayer = SKNode()
    private let hudLayer = SKNode()

    /// Brett-Knoten, indiziert [col][row]; nil = leere Zelle.
    private var gemNodes: [[SKSpriteNode?]] =
        Array(repeating: Array(repeating: nil, count: Board.height), count: Board.width)
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
    private let topBarHeight: CGFloat = 64
    private let outerPad: CGFloat = 18

    // MARK: Timing / Ablaufsteuerung
    private var lastUpdateTime: TimeInterval = 0
    private var fallAccumulator: TimeInterval = 0
    private var isResolving = false
    private var softDropActive = false

    // MARK: - Lebenszyklus

    public override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0, y: 0)
        backgroundColor = SKColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1)
        if backgroundLayer.parent == nil {
            addChild(backgroundLayer)
            addChild(boardLayer)
            addChild(pieceLayer)
            addChild(hudLayer)
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
        engine = Engine(seed: seed, startLevel: startLevel)
        isResolving = false
        fallAccumulator = 0
        lastUpdateTime = 0
        softDropActive = false
        model?.reset()
        if backgroundLayer.parent != nil {
            layout()
            renderBoardInstant(engine!.board)
            renderPiece()
            updateHUD()
        }
    }

    // MARK: - Layout

    private func layout() {
        let availW = size.width - outerPad * 2
        let availH = size.height - outerPad * 2 - topBarHeight
        guard availW > 0, availH > 0 else { return }
        tile = floor(min(availW / CGFloat(Board.width), availH / CGFloat(Board.height)))
        let boardW = tile * CGFloat(Board.width)
        let boardH = tile * CGFloat(Board.height)
        boardOriginX = (size.width - boardW) / 2
        boardOriginY = outerPad
        gemSize = CGSize(width: tile * 0.94, height: tile * 0.94)
        buildBackground(boardW: boardW, boardH: boardH)
        buildHUD(boardW: boardW, boardH: boardH)
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
        panel.fillColor = SKColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        panel.strokeColor = SKColor(red: 0.30, green: 0.34, blue: 0.50, alpha: 0.9)
        panel.lineWidth = 2
        backgroundLayer.addChild(panel)
        // Feines Raster.
        let grid = SKShapeNode()
        let path = CGMutablePath()
        for c in 0...Board.width {
            let x = boardOriginX + CGFloat(c) * tile
            path.move(to: CGPoint(x: x, y: boardOriginY))
            path.addLine(to: CGPoint(x: x, y: boardOriginY + boardH))
        }
        for r in 0...Board.height {
            let y = boardOriginY + CGFloat(r) * tile
            path.move(to: CGPoint(x: boardOriginX, y: y))
            path.addLine(to: CGPoint(x: boardOriginX + boardW, y: y))
        }
        grid.path = path
        grid.strokeColor = SKColor(white: 1, alpha: 0.05)
        grid.lineWidth = 1
        backgroundLayer.addChild(grid)
    }

    private func buildHUD(boardW: CGFloat, boardH: CGFloat) {
        hudLayer.removeAllChildren()
        previewNodes.removeAll()
        let barY = boardOriginY + boardH + topBarHeight / 2 + 4

        scoreLabel = makeLabel(size: 22, bold: true)
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: boardOriginX - 6, y: barY)
        hudLayer.addChild(scoreLabel)

        levelLabel = makeLabel(size: 16, bold: false)
        levelLabel.horizontalAlignmentMode = .left
        levelLabel.verticalAlignmentMode = .center
        levelLabel.fontColor = SKColor(white: 0.75, alpha: 1)
        levelLabel.position = CGPoint(x: boardOriginX - 6, y: barY - 24)
        hudLayer.addChild(levelLabel)

        nextLabel = makeLabel(size: 13, bold: true)
        nextLabel.text = "NÄCHSTE"
        nextLabel.fontColor = SKColor(white: 0.6, alpha: 1)
        nextLabel.horizontalAlignmentMode = .right
        nextLabel.verticalAlignmentMode = .center
        let rightX = boardOriginX + boardW + 6
        nextLabel.position = CGPoint(x: rightX, y: barY + 18)
        hudLayer.addChild(nextLabel)

        // Drei kleine Vorschau-Knoten unter dem Label.
        let pSize = min(topBarHeight * 0.42, tile * 0.7)
        for i in 0..<3 {
            let n = SKSpriteNode(color: .clear, size: CGSize(width: pSize, height: pSize))
            n.position = CGPoint(x: rightX - pSize * 0.5, y: barY - 8 - CGFloat(i) * 0 )
            previewNodes.append(n)
            hudLayer.addChild(n)
        }
        // Vorschau horizontal nebeneinander statt gestapelt.
        for (i, n) in previewNodes.enumerated() {
            n.position = CGPoint(x: rightX - CGFloat(2 - i) * (pSize + 4) - pSize * 0.5, y: barY - 12)
        }
    }

    private func makeLabel(size: CGFloat, bold: Bool) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: bold ? "AvenirNext-Bold" : "AvenirNext-Medium")
        label.fontSize = size
        label.fontColor = .white
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
        for col in 0..<Board.width {
            for row in 0..<Board.height {
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
        let visible = (engine.phase == .falling)
        for i in 0..<3 {
            let node = pieceNodes[i]
            node.isHidden = !visible
            node.size = gemSize
            let gem = engine.current.gems[i]
            if gem.isMagic {
                node.texture = GemTextures.colorTextures.first
                applyMagicAnimation(to: node)
            } else {
                node.removeAction(forKey: "magic")
                node.setScale(1)
                node.texture = GemTextures.texture(for: gem)
            }
            let target = cellCenter(col: engine.current.col, row: engine.current.row + i)
            if animated {
                node.run(SKAction.move(to: target, duration: 0.06))
            } else {
                node.position = target
            }
        }
    }

    /// Pulsierender Regenbogen fuer Magic-Steine: Texturen durchwechseln + sanftes Pulsieren.
    private func applyMagicAnimation(to node: SKSpriteNode) {
        guard node.action(forKey: "magic") == nil else { return }
        let cycle = SKAction.animate(with: GemTextures.colorTextures, timePerFrame: 0.09,
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
        fallAccumulator += dt
        let interval = softDropActive ? min(0.045, fallInterval(engine.level)) : fallInterval(engine.level)
        if fallAccumulator >= interval {
            fallAccumulator = 0
            stepGravity()
        }
    }

    /// Fallgeschwindigkeit je Level (Sekunden pro Reihe). Reines Zahlen-Mapping, keine Wanduhr.
    private func fallInterval(_ level: Int) -> TimeInterval {
        max(0.085, 0.80 - Double(level) * 0.06)
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

    public func inputLeft()  { guard canInput() else { return }; if engine!.moveLeft()  { renderPiece(animated: true) } }
    public func inputRight() { guard canInput() else { return }; if engine!.moveRight() { renderPiece(animated: true) } }
    public func inputRotate(){ guard canInput() else { return }; if engine!.rotate()    { renderPiece(); bumpPiece() } }

    /// Harter Fall: sofort bis zum Aufsetzen.
    public func inputHardDrop() {
        guard canInput() else { return }
        var locked: LockResult?
        loop: while true {
            switch engine!.gravityTick() {
            case .moved: continue
            case .locked(let r): locked = r; break loop
            }
        }
        if let locked { beginResolution(locked) }
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
        for col in 0..<Board.width {
            var writeRow = 0
            for row in 0..<Board.height {
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
            let node = SKSpriteNode(texture: GemTextures.colorTextures.first, size: gemSize)
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
        run(SKAction.wait(forDuration: 0.42)) { completion() }
    }

    private func endResolution() {
        guard let engine else { return }
        renderBoardInstant(engine.board)            // finaler, garantiert korrekter Stand
        if self.engine!.spawnNext() {
            renderPiece()
        } else {
            model?.finalScore = self.engine!.score
            model?.isGameOver = true
            showGameOverBanner()
        }
        updateHUD()
        isResolving = false
        fallAccumulator = 0
    }

    private func showGameOverBanner() {
        let label = makeLabel(size: 40, bold: true)
        label.text = "GAME OVER"
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.alpha = 0
        label.zPosition = 20
        hudLayer.addChild(label)
        label.run(SKAction.fadeIn(withDuration: 0.4))
    }

    // MARK: - HUD

    private func updateHUD() {
        guard let engine else { return }
        scoreLabel.text = "\(engine.score)"
        levelLabel.text = "Level \(engine.level)"
        model?.score = engine.score
        model?.level = engine.level

        let pSize = previewNodes.first?.size ?? gemSize
        let isMagicPreview = engine.nextGems.allSatisfy { $0.isMagic }
        for (i, node) in previewNodes.enumerated() {
            node.size = pSize
            let gem = engine.nextGems[i]
            if isMagicPreview {
                node.texture = GemTextures.colorTextures.first
                applyMagicAnimation(to: node)
            } else {
                node.removeAction(forKey: "magic")
                node.setScale(1)
                node.texture = GemTextures.texture(for: gem)
            }
        }
    }
}
