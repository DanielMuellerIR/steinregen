// freedoom-contact.swift — Kontaktbogen-Werkzeug für die FreeDoom-Steine-Auswahl.
//
// Lädt alle PNGs aus einem Ordner, quetscht jedes nach der GLEICHEN Logik wie das Spiel-Set
// in ein spielgroßes Segment (Sprite FÜLLT das Tile = „cover" + leichter Überscan, also lieber
// angeschnitten als Leerraum; Nearest-Neighbor = harte Pixelkanten) und legt alles als
// beschriftetes Raster in ein Übersichts-PNG. So sieht man vorab, ob das Quetschen taugt.
//
// Nutzung:  swift tools/freedoom-contact.swift <eingabe-ordner> <ausgabe.png> [tileGröße] [spalten]
//   z.B.    swift tools/freedoom-contact.swift /tmp/fdtest /tmp/fd-contact.png 96 6

import AppKit
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write("Aufruf: <in-ordner> <out.png> [tile] [spalten]\n".data(using: .utf8)!); exit(2) }
let inDir = args[1]
let outPath = args[2]
// Modus: "squeeze" = Spiel-Look (Sprite füllt das Tile, leicht angeschnitten);
//        "raw"     = ganzes Sprite ungequetscht (aspect-fit), mit Maßangabe — zum Durchschauen.
let mode = args.count > 3 ? args[3] : "squeeze"
let defaultTile: CGFloat = (mode == "raw") ? 150 : 96
let tile = CGFloat(args.count > 4 ? (Int(args[4]).map { CGFloat($0) } ?? defaultTile) : defaultTile)
let cols = args.count > 5 ? Int(args[5]) ?? 6 : 6

// Alle PNGs im Ordner, alphabetisch.
let fm = FileManager.default
let files = (try? fm.contentsOfDirectory(atPath: inDir))?
    .filter { $0.lowercased().hasSuffix(".png") }
    .sorted() ?? []
guard !files.isEmpty else { FileHandle.standardError.write("Keine PNGs in \(inDir)\n".data(using: .utf8)!); exit(1) }

// Optionale Pro-Bild-Feinjustage aus <in-ordner>/crop.tsv: Zeilen „basisname  zoom  ybias".
//   zoom  > 1  = stärker ranzoomen (mehr Anschnitt rundum)
//   ybias 0    = oben bündig (unten anschneiden, Köpfe/Gesichter bleiben)
//   ybias 0.5  = mittig · ybias 1 = unten bündig (oben anschneiden, z.B. Haare weg)
var cropCfg: [String: (CGFloat, CGFloat)] = [:]
if let txt = try? String(contentsOfFile: inDir + "/crop.tsv", encoding: .utf8) {
    for line in txt.split(separator: "\n") {
        let p = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
        if p.count >= 3, let z = Double(p[1]), let y = Double(p[2]) { cropCfg[p[0]] = (CGFloat(z), CGFloat(y)) }
    }
}

// Optionale Empfehlungs-Markierung aus <in-ordner>/recommend.txt (ein Basisname je Zeile) → ★.
var recommendSet = Set<String>()
if let txt = try? String(contentsOfFile: inDir + "/recommend.txt", encoding: .utf8) {
    for line in txt.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        let n = line.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { recommendSet.insert(n) }
    }
}

func loadCG(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

// Bounding-Box der nicht (fast) durchsichtigen Pixel — zum Wegschneiden der „Luft" ums Sprite.
// Rückgabe in CGImage-Koordinaten (Ursprung oben links), passend für CGImage.cropping(to:).
func opaqueBounds(_ img: CGImage, alphaMin: UInt8 = 12) -> CGRect? {
    let w = img.width, h = img.height
    guard w > 0, h > 0 else { return nil }
    let bpr = w * 4
    var data = [UInt8](repeating: 0, count: bpr * h)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let c = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))   // bottom-up: data-Zeile 0 = unten
    var minX = w, minY = h, maxX = -1, maxY = -1
    for yy in 0..<h {
        for xx in 0..<w where data[yy * bpr + xx * 4 + 3] > alphaMin {
            if xx < minX { minX = xx }; if xx > maxX { maxX = xx }
            if yy < minY { minY = yy }; if yy > maxY { maxY = yy }
        }
    }
    if maxX < 0 { return nil }
    // yy ist bottom-up → in Top-Left-Koordinaten umrechnen.
    return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

// Layout: pro Zelle ein Tile + eine Beschriftungszeile darunter.
let labelH: CGFloat = 16
let pad: CGFloat = 8
let cellW = tile + pad
let cellH = tile + labelH + pad
let rows = (files.count + cols - 1) / cols
let W = Int(CGFloat(cols) * cellW + pad)
let H = Int(CGFloat(rows) * cellH + pad)

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Seiten-Hintergrund: rabenschwarz (wie im Spiel).
ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)

func drawTile(_ img: CGImage, at origin: CGPoint, label: String, swatch: (CGFloat, CGFloat, CGFloat)? = nil, marked: Bool = false) {
    let inset: CGFloat = 3
    let body = CGRect(x: origin.x + inset, y: origin.y + inset, width: tile - 2*inset, height: tile - 2*inset)
    let corner = body.width * 0.13
    let path = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Neutrales dunkles Tile (im Spiel später farbig getönt — hier soll man nur das Sprite beurteilen).
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: cs,
                       colors: [CGColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),
                                CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: body.midX, y: body.midY + body.height*0.1), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: body.width*0.7,
                           options: [.drawsAfterEndLocation])

    // „Luft" entfernen: auf die undurchsichtige Bounding-Box zuschneiden (brutal quetschen).
    let cropped = opaqueBounds(img).flatMap { img.cropping(to: $0) } ?? img
    let sw = CGFloat(cropped.width), sh = CGFloat(cropped.height)
    let dr: CGRect
    if mode == "raw" {
        // RAW: ganzes (zugeschnittenes) Sprite, aspect-fit, mittig — nichts angeschnitten.
        let scale = min(body.width / sw, body.height / sh)
        let dw = sw * scale, dh = sh * scale
        dr = CGRect(x: body.midX - dw / 2, y: body.midY - dh / 2, width: dw, height: dh)
    } else {
        // SQUEEZE: cover (füllt das Tile, kein Leerraum) + optionale Pro-Bild-Justage (zoom, ybias).
        // ybias 0 = oben bündig (unten anschneiden) … 1 = unten bündig (oben anschneiden).
        let (zoom, ybias) = cropCfg[label] ?? (1.0, 0.0)
        let scale = max(body.width / sw, body.height / sh) * zoom
        let dw = sw * scale, dh = sh * scale
        let overflowV = max(0, dh - body.height)
        let topY = body.maxY + ybias * overflowV
        dr = CGRect(x: body.midX - dw / 2, y: topY - dh, width: dw, height: dh)
    }
    ctx.interpolationQuality = .none
    ctx.draw(cropped, in: dr)
    ctx.restoreGState()

    // Rahmen: im color-Modus DICK in der gemessenen Durchschnittsfarbe, sonst dünn knochenfarben.
    ctx.addPath(path)
    if let s = swatch {
        ctx.setStrokeColor(CGColor(red: s.0, green: s.1, blue: s.2, alpha: 1)); ctx.setLineWidth(8)
    } else {
        ctx.setStrokeColor(CGColor(red: 0.85, green: 0.83, blue: 0.78, alpha: 0.5)); ctx.setLineWidth(2)
    }
    ctx.strokePath()

    // Empfehlungs-Markierung: goldener ★ auf dunklem Kreis, oben rechts in der Kachel.
    if marked {
        let cx = origin.x + tile - inset - 15, cy = origin.y + tile - inset - 15
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        ctx.fillEllipse(in: CGRect(x: cx - 14, y: cy - 14, width: 28, height: 28))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsctx
        let star = NSAttributedString(string: "★", attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: NSColor(red: 1, green: 0.84, blue: 0.25, alpha: 1)])
        let ss = star.size()
        star.draw(at: NSPoint(x: cx - ss.width/2, y: cy - ss.height/2))
        NSGraphicsContext.restoreGraphicsState()
    }

    // Beschriftung.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsctx
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor(white: 0.85, alpha: 1)
    ]
    // Im RAW-Modus zusätzlich die echte Pixelgröße anzeigen (Original, ungequetscht).
    var text = (mode == "raw") ? "\(label)  \(img.width)×\(img.height)" : label
    if let sw = swatch { text = String(format: "%@ #%02X%02X%02X", label, Int(sw.0*255), Int(sw.1*255), Int(sw.2*255)) }
    let s = NSAttributedString(string: text, attributes: attr)
    let ts = s.size()
    s.draw(at: NSPoint(x: origin.x + (tile - ts.width)/2, y: origin.y + tile + 2))
    NSGraphicsContext.restoreGraphicsState()
}

// --- „color"-Modus: alpha-gewichtete Durchschnittsfarbe (= Grenzwert eines starken Gauß) je Bild,
//     Kacheln nach Farbton (Hue) sortiert; Rahmen zeigt die Durchschnittsfarbe, Label den Hex-Wert. ---
func avgColor(_ path: String) -> (CGFloat, CGFloat, CGFloat)? {
    guard let img = loadCG(path) else { return nil }
    let crop = opaqueBounds(img).flatMap { img.cropping(to: $0) } ?? img
    let w = crop.width, h = crop.height
    let bpr = w * 4
    var data = [UInt8](repeating: 0, count: bpr * h)
    let cs2 = CGColorSpaceCreateDeviceRGB()
    guard let c = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                            space: cs2, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
    var sR = 0.0, sG = 0.0, sB = 0.0, sA = 0.0
    var i = 0
    while i < data.count {
        sR += Double(data[i]); sG += Double(data[i+1]); sB += Double(data[i+2]); sA += Double(data[i+3])
        i += 4
    }
    guard sA > 0 else { return nil }   // premultiplied → Kanalsumme / Alphasumme = Durchschnitt 0…1
    return (CGFloat(sR / sA), CGFloat(sG / sA), CGFloat(sB / sA))
}
var avgOf: [String: (CGFloat, CGFloat, CGFloat)] = [:]
for f in files { avgOf[f] = avgColor(inDir + "/" + f) ?? (0.5, 0.5, 0.5) }
func hueOf(_ f: String) -> CGFloat {
    let c = avgOf[f] ?? (0.5, 0.5, 0.5)
    return NSColor(deviceRed: c.0, green: c.1, blue: c.2, alpha: 1).hueComponent
}
let ordered = (mode == "color") ? files.sorted { hueOf($0) < hueOf($1) } : files
if mode == "color" {
    for f in ordered {
        let c = avgOf[f]!
        print(String(format: "%@  #%02X%02X%02X  hue %.0f", (f as NSString).deletingPathExtension,
                     Int(c.0*255), Int(c.1*255), Int(c.2*255), Double(hueOf(f) * 360)))
    }
}

for (i, file) in ordered.enumerated() {
    guard let img = loadCG(inDir + "/" + file) else { continue }
    let r = i / cols, c = i % cols
    let x = pad + CGFloat(c) * cellW
    // von oben nach unten füllen (CG-Ursprung ist unten links → Zeile invertieren)
    let y = CGFloat(H) - cellH - pad - CGFloat(r) * cellH + (cellH - tile - labelH)
    let label = (file as NSString).deletingPathExtension
    drawTile(img, at: CGPoint(x: x, y: y), label: label, swatch: (mode == "color") ? avgOf[file] : nil,
             marked: recommendSet.contains(label))
}

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, "public.png" as CFString, 1, nil) else {
    FileHandle.standardError.write("Konnte Ausgabe nicht erzeugen\n".data(using: .utf8)!); exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
CGImageDestinationFinalize(dest)
print("Geschrieben: \(outPath)  (\(files.count) Sprites, \(W)x\(H))")
