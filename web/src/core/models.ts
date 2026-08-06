// models.ts
// Datentypen des Spiels — Portierung von `Sources/SteinregenCore/Models.swift`.
//
// Zwei Unterschiede zu Swift muss man beim Lesen im Kopf behalten, sonst wird die Portierung
// still falsch:
//
// 1. In Swift ist `Board` ein Werttyp (struct). `let vorher = board` legt dort eine KOPIE an;
//    spätere Änderungen am Original lassen `vorher` unberührt. In JavaScript sind Objekte
//    Verweise — dieselbe Zeile würde beide Namen auf dasselbe Brett zeigen lassen. Überall, wo
//    Swift sich auf das Kopierverhalten verlässt, steht hier deshalb ein ausdrückliches
//    `clone()`. Das ist der häufigste Fehler bei dieser Art Portierung.
//
// 2. Swift kann `Cell` in ein `Set` legen, weil Werte dort nach Inhalt verglichen werden.
//    JavaScript vergleicht Objekte nach Identität — zwei `{col: 1, row: 2}` sind für ein `Set`
//    verschieden. Dafür gibt es unten `CellSet`.

// MARK: - Stein

/**
 * Die Steinsorten. Die Kürzel sind dieselben, die auch die Vergleichsdaten benutzen
 * (siehe golden/README.md) — dadurch ist ein Brett direkt lesbar und die Kodierung braucht
 * keine Übersetzungstabelle.
 *
 * Bewusst ein Objekt statt eines `enum`: Node führt die TypeScript-Dateien aus, indem es die
 * Typangaben wegstreicht. Ein `enum` erzeugt aber echten Laufzeit-Code und ließe sich nicht
 * wegstreichen — `tsconfig.json` verbietet solche Konstrukte deshalb über `erasableSyntaxOnly`.
 */
export const Gem = {
  ruby: "r",
  topaz: "t",
  emerald: "e",
  diamond: "d",
  sapphire: "s",
  amethyst: "a",
  /** Sonder-Stein (Magic Jewel) — liegt nie dauerhaft im Brett. */
  magic: "m",
} as const;

export type Gem = (typeof Gem)[keyof typeof Gem];

/** Die sechs normalen Spielfarben (ohne Magic Jewel) — Reihenfolge ist die Zieh-Reihenfolge. */
export const gemColors: readonly Gem[] = [
  Gem.ruby,
  Gem.topaz,
  Gem.emerald,
  Gem.diamond,
  Gem.sapphire,
  Gem.amethyst,
];

export const isMagic = (gem: Gem): boolean => gem === Gem.magic;

/** Das Zeichen für eine leere Zelle in der Brett-Zeichenkette. */
export const emptyCell = ".";

/** Prüft, ob ein Zeichen eine bekannte Steinsorte ist (beim Einlesen fremder Daten). */
export function isGem(value: string): value is Gem {
  return value === "r" || value === "t" || value === "e" || value === "d" ||
    value === "s" || value === "a" || value === "m";
}

// MARK: - Koordinate

/**
 * Eine Zelle im Spielfeld. Ursprung unten links: `row` 0 ist die unterste Reihe, `row` wächst
 * nach oben; `col` 0 ist die linke Spalte.
 */
export interface Cell {
  readonly col: number;
  readonly row: number;
}

export const cell = (col: number, row: number): Cell => ({ col, row });

/**
 * Feste Brett-Reihenfolge: erst Reihe, dann Spalte.
 *
 * Wichtig für den Determinismus: Die Treffer-Suche sammelt ihre Funde in einer Menge, und die
 * Reihenfolge einer Menge ist nicht die Reihenfolge des Bretts. Vor jeder Rückgabe wird deshalb
 * sortiert, damit die geräumten Zellen bei gleichem Seed immer gleich aussehen. In Swift macht
 * das `Cell: Comparable`, hier diese Funktion.
 */
export function compareCells(a: Cell, b: Cell): number {
  return a.row !== b.row ? a.row - b.row : a.col - b.col;
}

/** Zellen in Brett-Reihenfolge — liefert immer eine neue Liste. */
export const sortCells = (cells: Iterable<Cell>): Cell[] => [...cells].sort(compareCells);

/**
 * Eine Menge von Zellen.
 *
 * JavaScript vergleicht Objekte nach Identität, nicht nach Inhalt — `new Set([cell(1,2)])`
 * würde `cell(1,2)` nicht wiederfinden. Diese Klasse legt deshalb intern Zeichenketten ab und
 * gibt ihre Zellen ausschließlich sortiert heraus, damit aus der Mengen-Reihenfolge nie ein
 * Unterschied zur Swift-Fassung entstehen kann.
 */
export class CellSet {
  readonly #keys = new Set<string>();

  constructor(cells: Iterable<Cell> = []) {
    for (const c of cells) this.add(c);
  }

  static #key(c: Cell): string {
    return `${c.col},${c.row}`;
  }

  get size(): number {
    return this.#keys.size;
  }

  get isEmpty(): boolean {
    return this.#keys.size === 0;
  }

  add(c: Cell): void {
    this.#keys.add(CellSet.#key(c));
  }

  delete(c: Cell): void {
    this.#keys.delete(CellSet.#key(c));
  }

  has(c: Cell): boolean {
    return this.#keys.has(CellSet.#key(c));
  }

  /** Alle Zellen in Brett-Reihenfolge (erst Reihe, dann Spalte). */
  sorted(): Cell[] {
    const cells: Cell[] = [];
    for (const key of this.#keys) {
      const comma = key.indexOf(",");
      cells.push(cell(Number(key.slice(0, comma)), Number(key.slice(comma + 1))));
    }
    return cells.sort(compareCells);
  }

  /** Die Zellen, die auch in `other` vorkommen. */
  intersection(other: Iterable<Cell>): Cell[] {
    return sortCells([...other].filter((c) => this.has(c)));
  }

  /** Entfernt alle übergebenen Zellen. */
  subtract(cells: Iterable<Cell>): void {
    for (const c of cells) this.delete(c);
  }

  clone(): CellSet {
    const copy = new CellSet();
    for (const key of this.#keys) copy.#keys.add(key);
    return copy;
  }
}

// MARK: - Spielfeld

/**
 * Das Spielraster. Die Maße sind pro Partie und Modus frei wählbar; `null` = leere Zelle.
 * Magic-Steine landen NIE hier — das Brett enthält ausschließlich normale Farben.
 */
export class Board {
  /** Standard-Brettmaße (Columns-/„Säulen“-Klassik). */
  static readonly defaultWidth = 6;
  static readonly defaultHeight = 13;

  readonly width: number;
  readonly height: number;

  // Speicher zeilenweise: index = row * width + col.
  #cells: (Gem | null)[];

  constructor(width: number = Board.defaultWidth, height: number = Board.defaultHeight) {
    this.width = width;
    this.height = height;
    this.#cells = new Array<Gem | null>(width * height).fill(null);
  }

  /** Liegt (col, row) innerhalb DIESES Bretts? */
  inBounds(col: number, row: number): boolean {
    return col >= 0 && col < this.width && row >= 0 && row < this.height;
  }

  /** Inhalt einer Zelle; `null`, wenn leer. Nur innerhalb des Bretts aufrufen. */
  get(col: number, row: number): Gem | null {
    return this.#cells[row * this.width + col] ?? null;
  }

  set(col: number, row: number, gem: Gem | null): void {
    this.#cells[row * this.width + col] = gem;
  }

  /**
   * Eine unabhängige Kopie.
   *
   * Steht überall dort, wo Swift sich auf das Kopierverhalten seiner Werttypen verlässt —
   * etwa beim Festhalten des Bretts vor einer Räum-Welle. Ohne diese Kopie zeigten beide
   * Namen auf dasselbe Brett, und der „Vorher“-Stand würde stillschweigend mitverändert.
   */
  clone(): Board {
    const copy = new Board(this.width, this.height);
    copy.#cells = [...this.#cells];
    return copy;
  }

  /** Alle Zellen einer bestimmten Farbe (für den Magic-Jewel-Effekt). */
  cellsOf(gem: Gem): Cell[] {
    const result: Cell[] = [];
    for (let row = 0; row < this.height; row += 1) {
      for (let col = 0; col < this.width; col += 1) {
        if (this.get(col, row) === gem) result.push(cell(col, row));
      }
    }
    return result;
  }

  /** Anzahl belegter Zellen. */
  get filledCount(): number {
    return this.#cells.reduce<number>((n, g) => (g === null ? n : n + 1), 0);
  }

  /**
   * Passt ein Stein mit diesen Zellen an seine Position? Alle Zellen müssen seitlich im Feld
   * liegen, nicht unter dem Boden sein und (falls im Brett) leer — Zellen OBERHALB des Bretts
   * gelten als frei (Steine schweben von oben ein; Drehen darf kurz über den Rand hinaus).
   */
  fits(cells: readonly { readonly cell: Cell }[]): boolean {
    for (const { cell: c } of cells) {
      if (c.col < 0 || c.col >= this.width || c.row < 0) return false;
      if (c.row < this.height && this.get(c.col, c.row) !== null) return false;
    }
    return true;
  }

  /**
   * Das Brett als eine Zeichenkette: oberste Reihe zuerst, Reihen durch `/` getrennt.
   * Genau das Format der Vergleichsdaten (golden/README.md).
   */
  encode(): string {
    const rows: string[] = [];
    for (let row = this.height - 1; row >= 0; row -= 1) {
      let line = "";
      for (let col = 0; col < this.width; col += 1) {
        line += this.get(col, row) ?? emptyCell;
      }
      rows.push(line);
    }
    return rows.join("/");
  }

  /** Liest ein Brett aus der Zeichenketten-Darstellung zurück. */
  static decode(text: string): Board {
    const rows = text.split("/");
    const height = rows.length;
    const width = rows[0]?.length ?? 0;
    if (height === 0 || width === 0) {
      throw new Error(`Leere Brett-Zeichenkette: ${JSON.stringify(text)}`);
    }
    const board = new Board(width, height);
    rows.forEach((line, index) => {
      if (line.length !== width) {
        throw new Error(
          `Ungleich lange Reihen in der Brett-Zeichenkette: ${line.length} statt ${width}`,
        );
      }
      // Zeile 0 der Zeichenkette ist die OBERSTE Reihe des Bretts.
      const row = height - 1 - index;
      [...line].forEach((char, col) => {
        if (char === emptyCell) return;
        if (!isGem(char)) throw new Error(`Unbekanntes Stein-Zeichen: ${JSON.stringify(char)}`);
        board.set(col, row, char);
      });
    });
    return board;
  }
}

// MARK: - Ergebnis-Typen der Auflösung

/** Art einer Räum-Welle: normaler Treffer oder Magic-Jewel-Farbräumung. */
export type ClearKind = "match" | "magic";

/** Eine einzelne Räum-Welle der Kaskade. */
export interface ClearStep {
  /** In diesem Schritt verschwindende Zellen — immer in Brett-Reihenfolge. */
  readonly cells: readonly Cell[];
  readonly kind: ClearKind;
  /** Bei `magic`: die getroffene Farbe; sonst `null`. */
  readonly color: Gem | null;
  /** Kettenstufe (1 = erste Welle nach dem Aufsetzen). */
  readonly chain: number;
  readonly points: number;
  /** Brett-Zustand NACH Entfernen und Nachrutschen — eine eigenständige Kopie. */
  readonly boardAfter: Board;
}

/** Spielphase. Steuert, welche Eingaben erlaubt sind. */
export type Phase = "falling" | "resolving" | "gameOver" | "won";
