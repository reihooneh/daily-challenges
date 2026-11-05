// The report: each piece's verdict, the lead lines to add, and an optional SVG drawing.

import { fix, problems, warnings, type Plan, type Problem, type Shape, type Warning } from "./check.js";
import { dist, type Pt } from "./geometry.js";
import { COLOURS, type Design, type Piece } from "./parse.js";

export interface PieceResult {
  piece: Piece;
  problems: Problem[];
  warnings: Warning[];
  fix: Plan | "impossible" | "too complex" | null; // null when it can be cut as drawn
}

export function analyse(d: Design): PieceResult[] {
  return d.pieces.map((piece) => {
    const shape: Shape = { pts: piece.points, cut: piece.points.map(() => false) };
    const probs = problems(shape, d.settings);
    return {
      piece,
      problems: probs,
      warnings: warnings(shape, d.settings),
      fix: probs.length === 0 ? null : fix(shape, d.settings),
    };
  });
}

/** 12.5 or 60 (no trailing .0), so coordinates read like the design file. */
function num(v: number): string {
  return String(Math.round(v * 10) / 10);
}

function at(p: Pt): string {
  return `(${num(p.x)}, ${num(p.y)})`;
}

/** The problems in words, grouped: corners first, then curves. */
function describe(r: PieceResult): string {
  const pts = r.piece.points;
  const parts: string[] = [];
  const corners = r.problems.flatMap((p) => (p.kind === "corner" ? [p] : []));
  const curves = r.problems.flatMap((p) => (p.kind === "curve" ? [p] : []));
  if (corners.length === 1) parts.push(`an inside corner at ${at(pts[corners[0]!.at]!)} turns ${num(corners[0]!.turn)}°, too sharp to cut`);
  else if (corners.length > 1) parts.push(`${corners.length} inside corners too sharp to cut, at ${corners.map((p) => at(pts[p.at]!)).join(", ")}`);
  if (curves.length === 1) {
    const c = curves[0]!;
    parts.push(`an inside curve near ${at(pts[c.deepest]!)} is ${num(c.ratio * 100)} % as deep as it is wide, too deep to nibble out`);
  } else if (curves.length > 1) {
    parts.push(`${curves.length} inside curves too deep to nibble out, near ${curves.map((p) => at(pts[p.deepest]!)).join(", ")}`);
  }
  return parts.join("; ");
}

function note(r: PieceResult, w: Warning): string {
  if (w.kind === "point") return `the ${num(w.angle)}° point at ${at(r.piece.points[w.at]!)} may snap off`;
  return `it is only ${num(w.width)} mm wide at its narrowest and may break`;
}

export function render(d: Design, results: PieceResult[]): string {
  const s = d.settings;
  const out: string[] = [];
  out.push(`GROZER  ${d.title}`);
  out.push(
    `${d.pieces.length} piece${d.pieces.length === 1 ? "" : "s"}. Can't be cut: inside corners turning more than ${s.sharpCorner}°, ` +
      `inside curves deeper than ${s.maxCurve} of their width. May snap: points under ${s.minAngle}°, parts under ${s.minWidth} mm wide.`,
  );
  out.push("");
  const pad = Math.max(...results.map((r) => r.piece.name.length));
  let asDrawn = 0;
  let split = 0;
  let stuck = 0;
  let lines = 0;
  let lead = 0;
  for (const r of results) {
    const label = `${r.piece.name.padEnd(pad)}  (${r.piece.colour}, ${r.piece.points.length} sides)`;
    if (r.fix === null) {
      asDrawn++;
      out.push(`  OK      ${label}`);
    } else {
      const verdict = typeof r.fix === "string" ? "NO FIX" : "SPLIT";
      out.push(`  ${verdict.padEnd(6)}  ${label}: ${describe(r)}.`);
      if (typeof r.fix === "string") {
        stuck++;
        out.push(
          r.fix === "too complex"
            ? "          Too many possibilities to search: split this piece by hand into simpler shapes."
            : "          No set of up to 8 lead lines avoids making a sliver or a sharp point: redraw this piece.",
        );
      } else {
        split++;
        lines += r.fix.lines.length;
        lead += r.fix.length;
        const n = r.fix.lines.length;
        out.push(`          Add ${n} lead line${n === 1 ? "" : "s"} (${num(r.fix.length)} mm):`);
        for (const l of r.fix.lines) out.push(`            ${at(l.a)} to ${at(l.b)}, ${num(dist(l.a, l.b))} mm`);
      }
    }
    for (const w of r.warnings) out.push(`          Note: ${note(r, w)}.`);
  }
  out.push("");
  out.push(
    `In all: ${asDrawn} cut as drawn, ${split} need lead lines` +
      (split > 0 ? ` (${lines} line${lines === 1 ? "" : "s"}, ${num(lead)} mm of extra lead)` : "") +
      `, ${stuck} can't be fixed automatically.`,
  );
  return out.join("\n") + "\n";
}

/** Escapes text for SVG. Names are already restricted, but the drawing never trusts that. */
export function escapeXml(s: string): string {
  return s.replace(/[<>&"']/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&#39;" })[c]!);
}

/** A drawing of the panel: glass in its colours, lead in dark grey, suggested lines dashed, problems ringed. */
export function svg(d: Design, results: PieceResult[]): string {
  const all = d.pieces.flatMap((p) => p.points);
  const minX = Math.min(...all.map((p) => p.x));
  const maxX = Math.max(...all.map((p) => p.x));
  const minY = Math.min(...all.map((p) => p.y));
  const maxY = Math.max(...all.map((p) => p.y));
  const m = 10;
  // The design's y runs up, SVG's runs down.
  const X = (p: Pt): string => num(p.x - minX + m);
  const Y = (p: Pt): string => num(maxY - p.y + m);
  const w = num(maxX - minX + 2 * m);
  const h = num(maxY - minY + 2 * m);
  const out: string[] = [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}mm" height="${h}mm">`,
    `<title>${escapeXml(d.title)}</title>`,
  ];
  for (const r of results) {
    const pts = r.piece.points.map((p) => `${X(p)},${Y(p)}`).join(" ");
    out.push(
      `<polygon points="${pts}" fill="${COLOURS[r.piece.colour] ?? "#cccccc"}" stroke="#2b2b2b" stroke-width="3" stroke-linejoin="round"><title>${escapeXml(r.piece.name)}</title></polygon>`,
    );
  }
  for (const r of results) {
    if (r.fix !== null && typeof r.fix !== "string") {
      for (const l of r.fix.lines) {
        out.push(`<line x1="${X(l.a)}" y1="${Y(l.a)}" x2="${X(l.b)}" y2="${Y(l.b)}" stroke="#2b2b2b" stroke-width="3" stroke-dasharray="6 4"/>`);
      }
    }
    for (const p of r.problems) {
      const q = r.piece.points[p.kind === "corner" ? p.at : p.deepest]!;
      out.push(`<circle cx="${X(q)}" cy="${Y(q)}" r="6" fill="none" stroke="#d11f1f" stroke-width="2"/>`);
    }
  }
  out.push("</svg>");
  return out.join("\n") + "\n";
}
