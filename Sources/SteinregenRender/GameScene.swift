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
    /// Die aktive Engine — modusneutral hinter `PlayEngine` (Saeulen oder Verschuettet).
    private var engine: (any PlayEngine)?
    /// Brettmaße der laufenden Partie. Werden in `start()` aus der Engine uebernommen; alle Layout-
    /// und Render-Schleifen laufen ueber DIESE Werte (nicht ueber die Board-Defaults), damit
    /// beliebige Brettgroessen (Verschuettet, frei eingestellte Maße) sauber gezeichnet werden.
    private var boardWidth = Board.defaultWidth
    private var boardHeight = Board.defaultHeight

    // MARK: Layer + Knoten
    /// Ganz hinten: das statische Hintergrundbild (Nebel bei Nacht). Früher prozeduraler Nebel.
    private let backdropLayer = SKNode()
    /// Index des für die LAUFENDE Partie gewählten Hintergrundbildes in `Theme.backdropImages()`.
    /// Wird in `start()` festgelegt und bleibt über alle Layout-Durchläufe (z.B. Fenster-Resize)
    /// stabil — sonst wechselte das Bild bei jeder Größenänderung. Default 0 ⇒ sicher renderbar,
    /// auch bevor die erste Partie gestartet wurde.
    private var backdropIndex = 0
    /// Zuletzt gezeigtes Hintergrundbild — damit `start()` pro Partie ein NEUES wählt (nie direkt
    /// dasselbe zweimal hintereinander). −1 = noch keines gezeigt (erste Wahl ohne Einschränkung).
    private var lastBackdropIndex = -1
    private let backgroundLayer = SKNode()
    private let boardLayer = SKNode()
    private let pieceLayer = SKNode()
    private let hudLayer = SKNode()

    /// Brett-Knoten, indiziert [col][row]; nil = leere Zelle.
    private var gemNodes: [[SKSpriteNode?]] =
        Array(repeating: Array(repeating: nil, count: Board.defaultHeight), count: Board.defaultWidth)
    /// Festgenagelte Zellen (Kapsel-Modus: die Flueche) im AKTUELL GEZEIGTEN Brett-Zwischenstand.
    /// Die Engine kennt nur den End-Stand nach der ganzen Kaskade — waehrend die Szene die Wellen
    /// nacheinander animiert, pflegt sie diese Menge selbst mit: `start()` uebernimmt den
    /// Anfangsbestand, `flashAndRemove` streicht geraeumte Zellen, `endResolution` gleicht mit der
    /// Engine ab. (Flueche wandern nie — sie koennen nur verschwinden.) Bei den anderen Modi leer.
    private var scenePinned: Set<Cell> = []
    /// Die drei Knoten der aktiven Saeule.
    private var pieceNodes: [SKSpriteNode] = []

    private var scoreLabel = SKLabelNode()
    private var levelLabel = SKLabelNode()
    private var nextLabel = SKLabelNode()
    private var previewNodes: [SKSpriteNode] = []
    /// Die Sense des Schnitter-Modus: eine senkrechte, gluehende Linie an der zuletzt
    /// ueberstrichenen Spalte. Bei Modi ohne Sense (sweepColumn == nil) nicht vorhanden.
    private var sweepNode: SKShapeNode?
    /// Geometrie des Vorschau-Bereichs im rechten Panel (in `buildHUD` gesetzt) — der
    /// Verschuettet-Vorschau-Pfad in `updateHUD` baut die Vierling-Form anhand dieser Werte auf.
    private var previewCenterX: CGFloat = 0
    private var previewAreaTopY: CGFloat = 0
    private var previewPanelWidth: CGFloat = 0

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
    /// Konstantes Tempo („Endlos"): bleibt true, hält die Fallgeschwindigkeit auf der Start-Tempostufe
    /// fest, statt sie mit dem Level zu beschleunigen. Der Punkte-/Level-Zähler steigt weiter normal.
    private var constantTempo = false
    /// Start-Tempostufe der laufenden Partie — bei konstantem Tempo bestimmt sie die Fallgeschwindigkeit.
    private var startTempoLevel = 1
    /// Lock-Delay: kurzes Korrektur-Fenster ab der ersten Beruehrung, in dem der aufgesetzte Stein
    /// noch geschoben ODER gedreht werden kann, bevor er fixiert. Verschiebt man ihn so, dass er
    /// wieder fallen kann, faellt er normal weiter. Wert in Sekunden — bewusst spuerbar lang, damit
    /// eine schnelle Last-Minute-Korrektur (ein Stueck zur Seite ziehen) komfortabel moeglich ist.
    /// Das Fenster wird NICHT aufgefrischt (siehe `settleTimer`), laeuft also ab der Beruehrung fest ab.
    private let lockDelay: TimeInterval = 0.6
    /// Nach einem Hard-Drop (Leertaste) gilt bewusst nur das halbe Fenster.
    private let hardDropLockDelay: TimeInterval = 0.21
    /// Lock-Delay als EINFACHE Regel (Wunsch Daniel): Sobald der Stein zum ersten Mal nicht mehr
    /// fallen kann (Beruehrung), startet `settleTimer`. Er laeuft in Echtzeit weiter und wird von
    /// NICHTS zurueckgesetzt — nicht durch Drehen, Schieben oder das kurze Anheben beim Rotieren.
    /// Nach `lockDelay` (bzw. `hardDropLockDelay` nach Instant-Fall) rastet der Stein ein. Drehen
    /// bremst das Fallen nicht (Schwerkraft laeuft unabhaengig). Kein „neue tiefste Reihe"-Reset,
    /// keine Obergrenze — der Zeitpunkt ist ab der ersten Beruehrung fix.
    private var settling = false
    private var settleTimer: TimeInterval = 0
    /// true, solange die aktuelle Saeule per Leertaste heruntergelassen wurde → kuerzeres Fenster.
    private var hardDropped = false

    /// Sense-Takt (Schnitter-Modus): so lange dauert EIN kompletter Durchlauf der Sweep-Linie
    /// uebers Brett — unabhaengig von der Brettbreite (das Intervall je Spalte ergibt sich
    /// daraus). Reines Render-Timing; der deterministische Schritt lebt im Core (`sweepTick`).
    private let sweepDuration: TimeInterval = 2.4
    private var sweepAccumulator: TimeInterval = 0

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
            addChild(backdropLayer)
            addChild(backgroundLayer)
            addChild(boardLayer)
            addChild(pieceLayer)
            addChild(hudLayer)
            // Zeichenreihenfolge: Hintergrundbild ganz hinten, HUD oben (bleibt scharf).
            backdropLayer.zPosition = -1
            hudLayer.zPosition = 100
        }
        layout()
        if let engine { renderBoardInstant(engine.board); renderPiece(); updateSweepNode(); updateHUD() }
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard backgroundLayer.parent != nil else { return }
        layout()
        if let engine { renderBoardInstant(engine.board); renderPiece(); updateSweepNode(); updateHUD() }
    }

    // MARK: - Spielstart

    /// Startet (oder restartet) eine Partie mit gegebenem Seed, Start-Tempostufe und Modus.
    /// `width`/`height` setzen die Brettmaße; nil ⇒ der Modus-Standard (Saeulen 6×13,
    /// Verschuettet 10×18). Default-Modus ist „Saeulen", damit bestehende Aufrufer unveraendert
    /// den Columns-Modus bekommen.
    public func start(seed: UInt64, startLevel: Int, mode: GameMode = .saeulen,
                      width: Int? = nil, height: Int? = nil, endless: Bool = false) {
        // Gewaehltes Steine-Set aus den Einstellungen uebernehmen (gilt ab dieser Partie).
        GemTextures.activeSetID = StoneSets.selectedID
        constantTempo = endless
        startTempoLevel = max(1, startLevel)
        // Pro Partie ein NEUES Hintergrundbild wählen — zufällig, aber nie direkt dasselbe wie in
        // der vorigen Partie (so wechselt das Motiv bei jedem Spielstart sichtbar, ganz ohne App-
        // Neustart). Bei nur einem Bild bleibt es zwangsläufig dabei.
        let backdropCount = Theme.backdropImages().count
        if backdropCount > 0 {
            var next = Int.random(in: 0..<backdropCount)
            var guardCount = 0
            while backdropCount > 1 && next == lastBackdropIndex && guardCount < 8 {
                next = Int.random(in: 0..<backdropCount)
                guardCount += 1
            }
            backdropIndex = next
            lastBackdropIndex = next
        }
        switch mode {
        case .saeulen:
            engine = Engine(seed: seed, startLevel: startLevel,
                            width: width ?? Board.defaultWidth,
                            height: height ?? Board.defaultHeight)
        case .verschuettet:
            engine = TetrominoEngine(seed: seed, startLevel: startLevel,
                                     width: width ?? TetrominoEngine.defaultWidth,
                                     height: height ?? TetrominoEngine.defaultHeight)
        case .klumpen:
            engine = PairEngine(seed: seed, startLevel: startLevel,
                                width: width ?? Board.defaultWidth,
                                height: height ?? Board.defaultHeight)
        case .fuenfling:
            // Gleiche Engine wie „Verschuettet", nur mit dem Fuenfling-Formen-Satz gefuettert.
            engine = TetrominoEngine(seed: seed, startLevel: startLevel,
                                     width: width ?? TetrominoEngine.pentominoDefaultWidth,
                                     height: height ?? TetrominoEngine.pentominoDefaultHeight,
                                     types: TetrominoType.pentominoes)
        case .kapseln:
            engine = CapsuleEngine(seed: seed, startLevel: startLevel,
                                   width: width ?? CapsuleEngine.defaultWidth,
                                   height: height ?? CapsuleEngine.defaultHeight)
        case .schnitter:
            engine = SquareEngine(seed: seed, startLevel: startLevel,
                                  width: width ?? SquareEngine.defaultWidth,
                                  height: height ?? SquareEngine.defaultHeight)
        }
        // Brettmaße + Knoten-Raster an die tatsaechliche Brettgroesse anpassen.
        boardWidth = engine!.board.width
        boardHeight = engine!.board.height
        scenePinned = engine!.pinnedCells      // Anfangsbestand der Flueche (andere Modi: leer)
        gemNodes = Array(repeating: Array(repeating: nil, count: boardHeight), count: boardWidth)
        pieceLayer.removeAllChildren()     // alte Saeulen-/Vierling-Knoten (evtl. andere Anzahl) verwerfen
        pieceNodes.removeAll()
        lastLevel = engine!.level          // kein „Level geschafft" beim Start
        isResolving = false
        fallAccumulator = 0
        settling = false
        settleTimer = 0
        hardDropped = false
        lastUpdateTime = 0
        softDropActive = false
        moveDir = 0
        moveRepeatAccumulator = 0
        moveDASStarted = false
        sweepAccumulator = 0
        model?.reset()
        if backgroundLayer.parent != nil {
            layout()
            renderBoardInstant(engine!.board)
            renderPiece()
            updateSweepNode()
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
        tile = floor(min(availH / CGFloat(boardHeight),
                         availW / (CGFloat(boardWidth) + sideTilesTotal)))
        let boardW = tile * CGFloat(boardWidth)
        let boardH = tile * CGFloat(boardHeight)
        boardOriginX = (size.width - boardW) / 2          // mittig → gleicher Rand links/rechts
        boardOriginY = (size.height - boardH) / 2          // senkrecht zentriert
        gemSize = CGSize(width: tile * 0.94, height: tile * 0.94)
        buildBackdrop()
        buildBackground(boardW: boardW, boardH: boardH)
        buildHUD(boardW: boardW, boardH: boardH)
    }

    /// Legt das statische Hintergrundbild (Nebel bei Nacht) ganz nach hinten und skaliert es
    /// formatfuellend (Cover): Es deckt die Szene immer komplett, ueberstehende Raender werden
    /// beschnitten — egal ob hohes iPhone-Hochformat oder breiteres macOS-Fenster.
    private func buildBackdrop() {
        backdropLayer.removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }
        // Das für diese Partie gewaehlte Bild aus dem Pool holen; ist keines vorhanden, bleibt
        // nur die schwarze Grundflaeche (Theme.canvas). `backdropIndex` wird in `start()` gesetzt;
        // der min() schuetzt, falls die Pool-Groesse mal kleiner als der Index sein sollte.
        let backdrops = Theme.backdropImages()
        guard !backdrops.isEmpty else { return }
        let cg = backdrops[min(backdropIndex, backdrops.count - 1)]
        let tex = SKTexture(cgImage: cg)
        let texSize = tex.size()
        guard texSize.width > 0, texSize.height > 0 else { return }
        let node = SKSpriteNode(texture: tex)
        // Cover-Skalierung: die groessere der beiden Achsen-Skalen fuellt die Szene vollstaendig.
        let scale = max(size.width / texSize.width, size.height / texSize.height)
        node.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        backdropLayer.addChild(node)
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
        panel.fillColor = Theme.panel.sk(0.75)
        panel.strokeColor = Theme.oxbloodDark.sk
        panel.lineWidth = 2
        backgroundLayer.addChild(panel)
        // Feines Raster.
        let grid = SKShapeNode()
        let path = CGMutablePath()
        for c in 0...boardWidth {
            let x = boardOriginX + CGFloat(c) * tile
            path.move(to: CGPoint(x: x, y: boardOriginY))
            path.addLine(to: CGPoint(x: x, y: boardOriginY + boardH))
        }
        for r in 0...boardHeight {
            let y = boardOriginY + CGFloat(r) * tile
            path.move(to: CGPoint(x: boardOriginX, y: y))
            path.addLine(to: CGPoint(x: boardOriginX + boardW, y: y))
        }
        grid.path = path
        grid.strokeColor = Theme.bone.sk(0.08)
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
        punkteCap.text = L10n.t("Punkte", "Score")
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
        nextLabel.text = L10n.t("als Nächstes", "Next")
        nextLabel.fontColor = Theme.boneDim.sk
        nextLabel.horizontalAlignmentMode = .center
        nextLabel.verticalAlignmentMode = .center
        nextLabel.position = CGPoint(x: rightCenterX, y: topY - 24)
        hudLayer.addChild(nextLabel)

        // Geometrie des Vorschau-Bereichs merken (beide Modi nutzen sie; Verschuettet baut seine
        // Form daraus in updateHUD auf).
        previewCenterX = rightCenterX
        previewAreaTopY = topY - 56
        previewPanelWidth = size.width - (boardOriginX + boardW) - outerPad

        // Saeulen-Vorschau: drei feste Knoten senkrecht (Index 0 = unten). Pixelgleich zu frueher,
        // damit der Saeulen-Modus optisch unveraendert bleibt. Verschuettet/Schnitter bauen ihre
        // Form dagegen pro Stein frisch in updateHUD auf (Form/Farben wechseln) → hier keine
        // festen Knoten anlegen.
        switch engine?.preview {
        case .tetromino, .grid: return
        default: break
        }

        // Drei Steine senkrecht gestapelt: Index 0 = unterster Stein der Säule → unten, Index 2 → oben.
        let pSize = min(tile * 0.86, previewPanelWidth * 0.78)
        let gap: CGFloat = 6
        let firstY = previewAreaTopY - pSize / 2     // Mitte des obersten Vorschau-Steins
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
        // Hervorhebungen (Schnitter: wartende Quadrat-Zellen) immer frisch aus der Engine —
        // sie aendern sich mit jedem Aufsetzen/Ernten. Waehrend einer Aufsetz-Animation kann
        // der Schimmer dem gezeigten Zwischenstand minimal vorauseilen (der Engine-Stand ist
        // schon final) — akzeptierter Kompromiss, der finale Resync stimmt immer.
        let highlighted = engine?.highlightedCells ?? []
        for col in 0..<boardWidth {
            for row in 0..<boardHeight {
                gemNodes[col][row] = nil
                if let gem = board[col, row] {
                    let node = makeGemNode(gem)
                    node.position = cellCenter(col: col, row: row)
                    // Flueche (Kapsel-Modus) sichtbar markieren — sie sind das Ziel des Modus.
                    if scenePinned.contains(Cell(col: col, row: row)) { decorateCurse(node) }
                    if highlighted.contains(Cell(col: col, row: row)) { decorateHighlight(node) }
                    boardLayer.addChild(node)
                    gemNodes[col][row] = node
                }
            }
        }
    }

    /// Fluch-Markierung (Kapsel-Modus): ein kraeftiger, leicht gluehender knochenweisser Ring um
    /// den Stein, der langsam pulsiert — deutlich vom normalen Stein unterscheidbar, ohne die
    /// Sigille zu verdecken. Als KIND des Stein-Knotens wandert er bei allen Animationen
    /// (Blitzen, Rutschen) mit.
    private func decorateCurse(_ node: SKSpriteNode) {
        let ring = SKShapeNode(circleOfRadius: gemSize.width * 0.46)
        ring.strokeColor = Theme.bone.sk(0.95)
        ring.lineWidth = 3
        ring.glowWidth = 2
        ring.fillColor = .clear
        ring.zPosition = 1
        node.addChild(ring)
        ring.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.7),
            SKAction.fadeAlpha(to: 1.0, duration: 0.7)
        ])))
    }

    /// Hervorhebung wartender Quadrat-Zellen (Schnitter-Modus): ein additiver, pulsierender
    /// Schimmer UEBER dem Stein — „glueht", bis die Sense erntet. Bewusst anders als der
    /// Fluch-Ring des Kapsel-Modus (Ring = Ziel, Schimmer = gleich geerntet).
    private func decorateHighlight(_ node: SKSpriteNode) {
        let glow = SKSpriteNode(color: Theme.bone.sk, size: node.size)
        glow.blendMode = .add
        glow.alpha = 0.28
        glow.zPosition = 1
        node.addChild(glow)
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.12, duration: 0.45),
            SKAction.fadeAlpha(to: 0.34, duration: 0.45)
        ])))
    }

    /// Positioniert/texturiert die Knoten des aktiven Steins (Saeule = 3 Zellen, Vierling = 4).
    private func renderPiece(animated: Bool = false) {
        guard let engine else { return }
        let cells = engine.activeCells
        while pieceNodes.count < cells.count {
            let n = SKSpriteNode(); pieceLayer.addChild(n); pieceNodes.append(n)
        }
        // Ueberzaehlige Knoten (z.B. nach Modus-/Brettwechsel von 4 auf 3 Zellen) ausblenden.
        for i in cells.count..<pieceNodes.count { pieceNodes[i].isHidden = true }

        let falling = (engine.phase == .falling)
        for i in 0..<cells.count {
            let node = pieceNodes[i]
            node.size = gemSize
            let (cell, gem) = cells[i]
            // Steine schweben von oben ein: Zellen oberhalb der obersten Brettreihe sind noch nicht
            // im Spielfeld und bleiben unsichtbar, bis sie eine Reihe tiefer rutschen.
            let onBoard = cell.row < boardHeight
            node.isHidden = !falling || !onBoard
            if gem.isMagic {
                node.texture = GemTextures.magicTextures.first
                applyMagicAnimation(to: node)
            } else {
                node.removeAction(forKey: "magic")
                node.setScale(1)
                node.texture = GemTextures.texture(for: gem)
            }
            let target = cellCenter(col: cell.col, row: cell.row)
            // Nur im Brett animieren; eine noch unsichtbare Zelle wird direkt an ihre Position ueber
            // dem Brett geparkt — taucht sie eine Reihe tiefer auf, gleitet sie von dort herein.
            // Die Gleit-Aktion bekommt den Key "move", damit ein direktes Setzen (Rotieren/Hard-Drop,
            // else-Zweig) einen noch LAUFENDEN Gleit-Effekt abbricht. Sonst ueberschrieb die anonyme
            // move-Aktion die frisch gesetzte Position weiter Richtung altem Ziel — die Rotation wirkte
            // dann verzoegert ("schnappt zurueck"), man drueckte nach und drehte eine Stufe zu weit.
            if animated && onBoard {
                node.run(SKAction.move(to: target, duration: 0.06), withKey: "move")
            } else {
                node.removeAction(forKey: "move")   // laufenden Gleit-Effekt abbrechen → sitzt sofort
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

        // Sense-Takt (nur Schnitter-Modus, sweepColumn != nil): die Sweep-Linie wandert in
        // festem Rhythmus Spalte fuer Spalte weiter — unabhaengig vom Fall-Takt. Liefert ein
        // Schritt eine Ernte, animiert `stepSweep` sie (kurze Aufloese-Pause wie beim Aufsetzen).
        if engine.sweepColumn != nil {
            sweepAccumulator += dt
            let interval = sweepDuration / Double(max(1, boardWidth))
            if sweepAccumulator >= interval {
                sweepAccumulator = 0
                stepSweep()
                // Die Ernte kann isResolving setzen — dann diesen Frame nicht weiter ticken.
                if isResolving { return }
            }
        }

        // Lock-Delay als einfache Regel: Ab der ERSTEN Beruehrung (Stein kann nicht mehr fallen)
        // laeuft `settleTimer`; er wird von nichts zurueckgesetzt. Drehen/Schieben aendern ihn nicht.
        if !engine.canFall() && !settling { settling = true; settleTimer = 0 }
        if settling { settleTimer += dt }

        // Schwerkraft laeuft UNABHAENGIG weiter — Drehen bremst das Fallen nicht. Hat der Stein (wieder)
        // Luft, faellt er im Level-Takt (bzw. schnell bei Softdrop). Der settleTimer laeuft parallel.
        if engine.canFall() {
            // Stein hat Luft → NORMAL weiterfallen. Bewusst NICHT fixieren, auch wenn settleTimer schon
            // abgelaufen ist: zieht man ihn neben einen Stein, soll er dort normal weiterschweben statt
            // instant zu droppen. Fixiert wird erst, wenn er wieder wirklich aufliegt (else-Zweig).
            fallAccumulator += dt
            // Bei konstantem Tempo („Endlos") zaehlt die Start-Tempostufe, nicht das gestiegene Level.
            let speedLevel = constantTempo ? startTempoLevel : engine.level
            let interval = softDropActive ? min(0.045, fallInterval(speedLevel)) : fallInterval(speedLevel)
            if fallAccumulator >= interval {
                fallAccumulator = 0
                stepGravity()
            }
        } else {
            // Aufgesetzt → nach Ablauf des Fensters fixieren. Instant-Fall → halbes Fenster, sonst volles.
            fallAccumulator = 0
            if settling {
                let limit = hardDropped ? hardDropLockDelay : lockDelay
                if settleTimer >= limit {
                    stepGravity()          // canFall == false → step() fixiert
                }
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
        switch engine!.step() {
        case .moved:
            renderPiece(animated: true)
        case .locked(let before, let steps, let magicLanding):
            beginResolution(before: before, steps: steps, magicLanding: magicLanding)
        }
    }

    /// Ein Sense-Schritt (Schnitter-Modus): bewegt die Sweep-Linie im Core eine Spalte weiter
    /// und animiert eine gelieferte Ernte (Aufblitzen → Nachrutschen → Resync). Waehrend der
    /// kurzen Ernte-Animation ist `isResolving` gesetzt — Fall und Eingaben pausieren wie bei
    /// einer Aufsetz-Kaskade (bewusst einfach gehalten; die Pause ist ~0,3 s).
    private func stepSweep() {
        guard engine != nil else { return }
        let step = engine!.sweepTick()
        updateSweepNode()
        guard let step else { return }
        isResolving = true
        showCombo(chain: step.chain, count: step.cells.count)
        flashAndRemove(step.cells) { [weak self] in
            self?.compactColumnsAnimated {
                guard let self else { return }
                if let engine = self.engine {
                    // Voller Resync: raeumt auch die Markierungs-Schimmer der geernteten
                    // Zellen ab und zeigt frisch entstandene Markierungen sofort.
                    self.renderBoardInstant(engine.board)
                }
                self.updateHUD()
                self.isResolving = false
            }
        }
    }

    /// Zeichnet/verschiebt die Sense (senkrechte, gluehende Linie an der rechten Kante der
    /// zuletzt ueberstrichenen Spalte). Bei Modi ohne Sense wird der Knoten entfernt.
    private func updateSweepNode() {
        guard let engine, let col = engine.sweepColumn else {
            sweepNode?.removeFromParent()
            sweepNode = nil
            return
        }
        if sweepNode == nil {
            let n = SKShapeNode()
            n.zPosition = 12                       // ueber Brett-Steinen, unter dem HUD
            n.strokeColor = Theme.bone.sk(0.7)
            n.lineWidth = 2
            n.glowWidth = 4
            pieceLayer.addChild(n)
            sweepNode = n
        }
        let x = boardOriginX + CGFloat(col + 1) * tile
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: boardOriginY))
        path.addLine(to: CGPoint(x: x, y: boardOriginY + CGFloat(boardHeight) * tile))
        sweepNode!.path = path
    }

    // MARK: - Eingaben (von SwiftUI weitergereicht)

    // Wichtig: Schieben/Drehen fasst den Lock-Delay-Timer GAR NICHT an (kein Reset, keine
    // Fenster-Umschaltung). Der Einrast-Zeitpunkt steht ab der ersten Beruehrung fest (siehe
    // `settleTimer` in `update`). So kann Dauer-Rotieren das Einrasten nicht hinauszoegern, und
    // ein per Instant-Fall gesetzter Stein behaelt sein kurzes 0,21-s-Fenster auch beim Drehen.
    // Drehen bremst das Fallen nicht: die Schwerkraft laeuft im `update` unabhaengig weiter.
    public func inputLeft()  { guard canInput() else { return }; if engine!.moveLeft()  { renderPiece(animated: true) } }
    public func inputRight() { guard canInput() else { return }; if engine!.moveRight() { renderPiece(animated: true) } }
    public func inputRotate(){ guard canInput() else { return }; if engine!.rotate()    { renderPiece(); bumpPiece(); SoundFX.rotate() } }

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
        // Nur fallen lassen, solange Luft ist (jeder Schritt liefert .moved). Den lock-ausloesenden
        // Schritt (canFall == false) bewusst NICHT ausfuehren — das uebernimmt erst das Lock-Delay.
        while engine!.canFall() { _ = engine!.step() }
        hardDropped = true
        // Kuerzeres 0,21-s-Fenster ab dem Slam. Lief der Timer schon (Stein lag bereits auf und wird
        // jetzt per Leertaste „bestaetigt"), NICHT zuruecksetzen — sonst liesse sich per Leertaste-
        // Spam verlaengern; das gegen `hardDropLockDelay` laufende Fenster rastet dann eben frueher.
        if !settling { settling = true; settleTimer = 0 }
        renderPiece()          // sofort an die Aufsetz-Position (knackiger Slam)
    }

    public func setSoftDrop(_ active: Bool) { softDropActive = active }

    private func canInput() -> Bool { engine != nil && !isResolving && engine!.phase == .falling }

    /// Nur fuer Headless-Tests/Diagnose: der Punktestand direkt aus der Engine. Anders als
    /// `model.score` (wird erst nach der Raeum-ANIMATION nachgezogen) ist er sofort nach dem
    /// Aufsetzen final — headless laufen SKActions nicht, das HUD-Update kaeme dort nie an.
    public var testEngineScore: Int? { engine?.score }

    /// Nur fuer Headless-Tests/Diagnose: tiefste belegte Reihe des aktiven Steins (kleinster
    /// row-Index; Boden = 0) bzw. nil, wenn gerade kein aktiver Stein faellt (z.B. waehrend einer
    /// Aufloesung). Erlaubt Tests, das Einrasten zu erkennen (neuer Stein → Reihe springt nach oben).
    public var testActiveBottomRow: Int? {
        guard let engine, engine.phase == .falling, !isResolving else { return nil }
        return engine.activeCells.map { $0.cell.row }.min()
    }

    /// Kleiner Skalier-Impuls als Feedback beim Drehen.
    private func bumpPiece() {
        for node in pieceNodes where !node.isHidden && node.action(forKey: "magic") == nil {
            node.run(SKAction.sequence([SKAction.scale(to: 1.12, duration: 0.05),
                                        SKAction.scale(to: 1.0, duration: 0.08)]))
        }
    }

    // MARK: - Kaskaden-Animation

    private func beginResolution(before: Board, steps: [ClearStep], magicLanding: (col: Int, row: Int)?) {
        isResolving = true
        SoundFX.land()                 // Stein ist aufgesetzt (berührt Stein/Boden)
        for node in pieceNodes { node.isHidden = true }
        animateLock(before: before, steps: steps, magicLanding: magicLanding) { [weak self] in
            self?.endResolution()
        }
    }

    private func animateLock(before: Board, steps: [ClearStep], magicLanding: (col: Int, row: Int)?,
                             completion: @escaping () -> Void) {
        renderBoardInstant(before)

        func runSteps(_ index: Int) {
            guard index < steps.count else {
                updateHUD()            // Punktestand nach der Welle nachziehen
                completion()
                return
            }
            let step = steps[index]
            showCombo(chain: step.chain, count: step.cells.count)
            flashAndRemove(step.cells) { [weak self] in
                self?.compactColumnsAnimated {
                    self?.updateHUD()
                    runSteps(index + 1)
                }
            }
        }

        if let landing = magicLanding {
            showMagicLanding(col: landing.col, row: landing.row) { runSteps(0) }
        } else if engine?.postLockSettle == true {
            // Klumpen-Modus: `before` zeigt das Paar an seiner Aufsetz-Position — eine quer
            // liegende Haelfte kann dort noch ueber einem Loch schweben. Zuerst dieses
            // Nachfallen animieren, dann die Raeum-Wellen. (Bei bereits gestuetzten Steinen
            // findet compactColumnsAnimated nichts und ruft sofort weiter.)
            compactColumnsAnimated { runSteps(0) }
        } else {
            runSteps(0)
        }
    }

    /// Laesst die getroffenen Zellen aufblitzen und verschwinden.
    private func flashAndRemove(_ cells: [Cell], completion: @escaping () -> Void) {
        SoundFX.clear()                // eine Räum-Welle (Steine lösen sich auf)
        scenePinned.subtract(cells)    // geraeumte Flueche sind keine Barriere mehr (Kapsel-Modus)
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
    /// Festgenagelte Zellen (`scenePinned`, Kapsel-Flueche) bleiben stehen und wirken als
    /// Barriere — exakt die Regel von `settle(pinned:)` im Core, nur auf den Knoten. Bei den
    /// anderen Modi ist die Menge leer und das Verhalten unveraendert.
    private func compactColumnsAnimated(completion: @escaping () -> Void) {
        var maxDuration: TimeInterval = 0
        for col in 0..<boardWidth {
            var writeRow = 0
            for row in 0..<boardHeight {
                if scenePinned.contains(Cell(col: col, row: row)) {
                    // Fluch klebt: alles Weitere in dieser Spalte landet OBERHALB von ihm.
                    writeRow = row + 1
                    continue
                }
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

    /// Zeigt die aufsetzende Magic-Saeule kurz an ihrer Landeposition (Spalte/Reihe) und laesst sie
    /// aufploppen. Nur Saeulen-Modus (Verschuettet hat keine Magic-Steine).
    private func showMagicLanding(col: Int, row: Int, completion: @escaping () -> Void) {
        var nodes: [SKSpriteNode] = []
        for i in 0..<3 {
            let node = SKSpriteNode(texture: GemTextures.magicTextures.first, size: gemSize)
            node.position = cellCenter(col: col, row: row + i)
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
        info.text = L10n.t("Magischer Stein — räumt eine ganze Sorte",
                            "Magic stone — clears a whole kind")
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
        scenePinned = engine.pinnedCells            // Abgleich mit dem finalen Engine-Stand
        renderBoardInstant(engine.board)            // finaler, garantiert korrekter Stand
        if self.engine!.spawnNext() {
            renderPiece()
        } else if self.engine!.phase == .won {
            // Sieg (nur Kapsel-Modus): alle Flueche getilgt — statt „Verreckt" ein Sieg-Banner,
            // das Overlay uebernimmt den Rest (Friedhof-Eintrag wie beim Game Over).
            model?.finalScore = self.engine!.score
            model?.finalLevel = self.engine!.level
            model?.isVictory = true
            model?.isGameOver = true
            SoundFX.levelUp()
            showVictoryBanner()
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
        settling = false            // frische Saeule → Beruehrungs-Timer neu
        settleTimer = 0
        hardDropped = false        // frische Saeule → wieder volles Korrektur-Fenster
    }

    private func showGameOverBanner() {
        let label = makeLabel(size: 46, bold: true)
        label.text = L10n.t("Verreckt", "Perished")
        label.fontColor = Theme.blood.sk
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.alpha = 0
        label.zPosition = 20
        hudLayer.addChild(label)
        label.run(SKAction.fadeIn(withDuration: 0.4))
    }

    /// Sieg-Banner des Kapsel-Modus (analog zum Game-Over-Banner, aber knochenweiss statt blutrot).
    private func showVictoryBanner() {
        let label = makeLabel(size: 46, bold: true)
        label.text = L10n.t("Ausgetrieben", "Exorcised")
        label.fontColor = Theme.bone.sk
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

        switch engine.preview {
        case .columns(let gems):       renderColumnsPreview(gems)
        case .tetromino(let cells, let gem): renderTetrominoPreview(cells: cells, gem: gem)
        case .grid(let cells):         renderGridPreview(cells)
        }
    }

    /// Stapel-Vorschau: die drei festen Knoten (aus buildHUD) texturieren — Index 0 = unten.
    /// Saeulen liefern drei Steine (unveraendert zu frueher, Magic-Saeule pulsiert); der
    /// Klumpen-Modus liefert zwei — ueberzaehlige Knoten werden ausgeblendet.
    private func renderColumnsPreview(_ gems: [Gem]) {
        let pSize = previewNodes.first?.size ?? gemSize
        let isMagicPreview = gems.allSatisfy { $0.isMagic }
        for (i, node) in previewNodes.enumerated() {
            node.isHidden = i >= gems.count
            guard i < gems.count else { continue }
            node.size = pSize
            let gem = gems[i]
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

    /// Verschuettet-Vorschau: die naechste Vierling-Form in einer kleinen Box zeichnen — alle
    /// Zellen tragen dieselbe Sorte; das Zeichnen uebernimmt der generische Raster-Pfad unten.
    private func renderTetrominoPreview(cells: [Cell], gem: Gem) {
        renderGridPreview(cells.map { (cell: $0, gem: gem) })
    }

    /// Generische Raster-Vorschau: Zellen mit INDIVIDUELLER Farbe (Schnitter-2×2 mit zwei
    /// Sorten; auch der Vierling-Pfad laeuft hierueber). Die Knoten werden pro Stein frisch
    /// aufgebaut (Zellen in Brett-Koordinaten: row 0 = unten), zentriert im rechten Panel
    /// unter dem „als Naechstes"-Label.
    private func renderGridPreview(_ cells: [(cell: Cell, gem: Gem)]) {
        for n in previewNodes { n.removeFromParent() }
        previewNodes.removeAll()
        guard !cells.isEmpty else { return }

        let cols = (cells.map(\.cell.col).max() ?? 0) + 1
        let rows = (cells.map(\.cell.row).max() ?? 0) + 1
        // Kachel so, dass die breiteste Form bequem ins Panel passt (Vierlinge bis 4 Zellen,
        // der Fuenfling I5 ist 5 breit — der max() laesst die Vierling-Vorschau unveraendert;
        // der 2×2-Block des Schnitters wird dadurch einfach kompakt klein gezeichnet).
        let t = min(tile * 0.72, previewPanelWidth * 0.9 / CGFloat(max(4, cols)))
        let totalW = CGFloat(cols) * t
        let leftCenterX = previewCenterX - totalW / 2 + t / 2     // Mitte der linken Zellspalte
        let topCenterY = previewAreaTopY - t / 2                  // Mitte der obersten Zellreihe
        let node0 = CGSize(width: t * 0.94, height: t * 0.94)
        for (cell, gem) in cells {
            let n = SKSpriteNode(texture: GemTextures.texture(for: gem), size: node0)
            // row waechst nach oben → groesste row liegt ganz oben.
            n.position = CGPoint(x: leftCenterX + CGFloat(cell.col) * t,
                                 y: topCenterY - CGFloat(rows - 1 - cell.row) * t)
            previewNodes.append(n)
            hudLayer.addChild(n)
        }
    }
}
