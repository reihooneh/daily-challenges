// The design file. Every line has a fixed shape and every number a range; errors give the line
// number and what was expected, never the text of the line.

import { area, isSimple, type Pt } from "./geometry.js";

export const MAX_INPUT = 64 * 1024;
export const MAX_LINE = 200;
export const MAX_PIECES = 200;
export const MAX_POINTS = 80;
export const MAX_COORD = 5000;

/** Glass colours, each with the colour drawn for it (a fixed list, so nothing from the file reaches an SVG attribute). */
export const COLOURS: Readonly<Record<string, string>> = {
  clear: "#e8eef0",
  opal: "#f3efe4",
  white: "#fbfbf7",
  amber: "#d9902b",
  gold: "#e3b63c",
  yellow: "#f1d54a",
  orange: "#e3742a",
  red: "#c0352b",
  ruby: "#8f1d2c",
  pink: "#e59ab0",
  purple: "#6d3b8e",
  violet: "#8a6bc4",
  blue: "#2f5fa8",
  cobalt: "#1d3c8f",
  sky: "#8cc3e8",
  green: "#3f8f4a",
  emerald: "#17734f",
  brown: "#7a4f2a",
  grey: "#8d9399",
  black: "#26282b",
};

export interface Piece {
  name: string;
  colour: string;
  points: Pt[]; // counter-clockwise
  line: number;
}

export interface Settings {
  minWidth: number; // mm: narrower parts snap
  minAngle: number; // degrees: sharper points snap off
  sharpCorner: number; // degrees of turn that make an inside corner uncuttable
  maxCurve: number; // depth ÷ mouth beyond which an inside curve is too deep to cut
}

export interface Design {
  title: string;
  settings: Settings;
  pieces: Piece[];
}

export class InputError extends Error {
  constructor(
    readonly line: number,
    message: string,
  ) {
    super(line > 0 ? `line ${line}: ${message}` : message);
  }
}

const NAME = /^[a-z][a-z0-9-]{0,23}$/;
const NUMBER = /^\d{1,4}(\.\d{1,2})?$/;
const POINT = /^(\d{1,4}(?:\.\d{1,2})?),(\d{1,4}(?:\.\d{1,2})?)$/;
const TITLE = /^[A-Za-z0-9][A-Za-z0-9 '.,&()!-]{0,59}$/;
// Control characters, and invisible formatting characters (zero-width spaces and joiners,
// bidirectional marks and overrides, the byte-order mark), which can disguise text.
const HIDDEN = /[\u0000-\u0008\u000a-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]/;

function number(s: string, line: number, what: string, lo: number, hi: number): number {
  if (!NUMBER.test(s)) throw new InputError(line, `${what} must be a number like 12 or 0.3`);
  const v = Number(s);
  if (v < lo || v > hi) throw new InputError(line, `${what} must be from ${lo} to ${hi}`);
  return v;
}

function finishPiece(piece: Piece | null): void {
  if (piece === null) return;
  if (piece.points.length < 3) throw new InputError(piece.line, "a piece needs at least 3 points");
  const a = area(piece.points);
  if (Math.abs(a) < 1) throw new InputError(piece.line, "the piece has no area");
  if (!isSimple(piece.points)) throw new InputError(piece.line, "the piece's outline crosses or touches itself, or repeats a point");
  if (a < 0) piece.points.reverse();
}

export function parse(input: string): Design {
  if (input.length > MAX_INPUT) throw new InputError(0, "the design file is larger than 64 KB");
  const text = input.startsWith("\ufeff") ? input.slice(1) : input;
  const design: Design = {
    title: "A stained-glass panel",
    settings: { minWidth: 10, minAngle: 30, sharpCorner: 15, maxCurve: 0.3 },
    pieces: [],
  };
  const seen = new Set<string>();
  const names = new Set<string>();
  let current: Piece | null = null;
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const n = i + 1;
    const raw = lines[i]!.replace(/\r$/, "");
    if (raw.length > MAX_LINE) throw new InputError(n, `is longer than ${MAX_LINE} characters`);
    if (HIDDEN.test(raw)) throw new InputError(n, "contains a control or invisible formatting character");
    const line = raw.split("#")[0]!;
    const w = line.trim().split(/\s+/).filter((x) => x !== "");
    if (w.length === 0) continue;
    const head = w[0]!;
    if (POINT.test(head)) {
      if (current === null) throw new InputError(n, "points come after a piece line");
      for (const word of w) {
        const m = POINT.exec(word);
        if (m === null) throw new InputError(n, "points are written x,y in millimetres, like 120,45.5");
        const x = Number(m[1]);
        const y = Number(m[2]);
        if (x > MAX_COORD || y > MAX_COORD) throw new InputError(n, `points must be within ${MAX_COORD} mm`);
        if (current.points.length >= MAX_POINTS) throw new InputError(n, `a piece has at most ${MAX_POINTS} points`);
        current.points.push({ x, y });
      }
      continue;
    }
    if (["window", "min-width", "min-angle", "sharp-corner", "max-curve"].includes(head)) {
      if (seen.has(head)) throw new InputError(n, `'${head}' may only appear once`);
      if (design.pieces.length > 0) throw new InputError(n, "settings come before the first piece");
      seen.add(head);
    }
    const s = design.settings;
    if (head === "window") {
      const title = line.trim().slice("window".length).trim();
      if (!TITLE.test(title)) throw new InputError(n, "the window's name: letters, digits, spaces and ' . , & ( ) ! - (up to 60)");
      design.title = title;
    } else if (head === "min-width" && w.length === 2) {
      s.minWidth = number(w[1]!, n, "the narrowest part", 1, 100);
    } else if (head === "min-angle" && w.length === 2) {
      s.minAngle = number(w[1]!, n, "the sharpest point", 5, 90);
    } else if (head === "sharp-corner" && w.length === 2) {
      s.sharpCorner = number(w[1]!, n, "the sharpest inside corner", 1, 90);
    } else if (head === "max-curve" && w.length === 2) {
      s.maxCurve = number(w[1]!, n, "the deepest inside curve", 0.05, 2);
    } else if (head === "piece" && w.length === 3) {
      finishPiece(current);
      if (!NAME.test(w[1]!)) throw new InputError(n, "a piece name is lower-case letters, digits and -, up to 24, starting with a letter");
      if (names.has(w[1]!)) throw new InputError(n, "each piece name must be different");
      if (!Object.hasOwn(COLOURS, w[2]!)) throw new InputError(n, `colours are ${Object.keys(COLOURS).join(", ")}`);
      if (design.pieces.length >= MAX_PIECES) throw new InputError(n, `at most ${MAX_PIECES} pieces`);
      names.add(w[1]!);
      current = { name: w[1]!, colour: w[2]!, points: [], line: n };
      design.pieces.push(current);
    } else {
      throw new InputError(n, "lines are window, min-width, min-angle, sharp-corner, max-curve, piece NAME COLOUR, or points like 0,0 120,0");
    }
  }
  finishPiece(current);
  if (design.pieces.length === 0) throw new InputError(0, "the design has no pieces");
  return design;
}
