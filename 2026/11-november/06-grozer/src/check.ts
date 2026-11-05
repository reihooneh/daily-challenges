// What makes a piece of glass uncuttable, and the search for the fewest lead lines that fix it.
//
// Glass is cut by scoring a line and snapping it, and the break runs on through the sheet, so:
//  - an inside corner can't be cut: the break carries on into the piece;
//  - an inside curve can be nibbled out with relief scores, but only if it is shallow;
//  - very sharp points and thin slivers snap off.
// A lead line through the trouble splits the piece into two that can each be cut.

import { dist, hull, inside, interior, lineDistance, rayHit, segmentsMeet, turn, vertex, width, type Pt } from "./geometry.js";
import type { Settings } from "./parse.js";

/** A piece's outline, with a flag on each vertex that is the end of a lead line Grozer added. */
export interface Shape {
  pts: Pt[];
  cut: boolean[];
}

export type Problem =
  | { kind: "corner"; at: number; turn: number } // an inside corner too sharp to cut
  | { kind: "curve"; chain: number[]; ratio: number; deepest: number }; // an inside curve too deep

export type Warning =
  | { kind: "point"; at: number; angle: number } // a point that may snap off
  | { kind: "narrow"; width: number }; // the whole piece is thin

/** The inside curves of a shape: each stretch of outline between two neighbouring hull corners. */
function curves(s: Shape): { chain: number[]; ratio: number; deepest: number }[] {
  const h = hull(s.pts);
  const n = s.pts.length;
  const out: { chain: number[]; ratio: number; deepest: number }[] = [];
  for (let k = 0; k < h.length; k++) {
    const a = h[k]!;
    const b = h[(k + 1) % h.length]!;
    const chain: number[] = [];
    for (let i = (a + 1) % n; i !== b; i = (i + 1) % n) chain.push(i);
    if (chain.length === 0) continue;
    const pa = s.pts[a]!;
    const pb = s.pts[b]!;
    let depth = 0;
    let deepest = chain[0]!;
    for (const i of chain) {
      const d = lineDistance(s.pts[i]!, pa, pb);
      if (d > depth) [depth, deepest] = [d, i];
    }
    out.push({ chain, ratio: depth / dist(pa, pb), deepest });
  }
  return out;
}

/** What stops this shape from being cut as it is: inside corners first, then deep curves. */
export function problems(s: Shape, set: Settings): Problem[] {
  const out: Problem[] = [];
  for (let i = 0; i < s.pts.length; i++) {
    const t = turn(s.pts, i);
    if (t < -set.sharpCorner) out.push({ kind: "corner", at: i, turn: -t });
  }
  // A curve that holds a sharp corner is already explained (and fixed) by the corner.
  const corners = new Set(out.map((p) => (p.kind === "corner" ? p.at : -1)));
  for (const c of curves(s)) {
    if (c.ratio > set.maxCurve && !c.chain.some((i) => corners.has(i))) out.push({ kind: "curve", ...c });
  }
  return out;
}

/** Things a glass cutter should know about, which a lead line can't fix. */
export function warnings(s: Shape, set: Settings): Warning[] {
  const out: Warning[] = [];
  for (let i = 0; i < s.pts.length; i++) {
    const a = interior(s.pts, i);
    if (a < set.minAngle) out.push({ kind: "point", at: i, angle: a });
  }
  const w = width(s.pts);
  if (w < set.minWidth) out.push({ kind: "narrow", width: w });
  return out;
}

export interface Line {
  a: Pt;
  b: Pt;
}

export interface Plan {
  lines: Line[];
  length: number; // mm of extra lead
}

/** Fewer lines first, then less lead. */
function better(p: Plan, q: Plan | null): boolean {
  return q === null || p.lines.length < q.lines.length || (p.lines.length === q.lines.length && p.length < q.length - 1e-9);
}

/** Splits a shape along the chord between vertices i and j (both ends become cut vertices). */
export function split(s: Shape, i: number, j: number): [Shape, Shape] {
  const n = s.pts.length;
  const take = (from: number, to: number): Shape => {
    const pts: Pt[] = [];
    const cut: boolean[] = [];
    for (let k = from; ; k = (k + 1) % n) {
      pts.push(s.pts[k]!);
      cut.push(k === i || k === j || s.cut[k]!);
      if (k === to) break;
    }
    return { pts, cut };
  };
  return [take(i, j), take(j, i)];
}

/** Puts a new vertex on edge k (between k and k+1), or reuses an end if the point is on it. */
function addPoint(s: Shape, k: number, q: Pt): { shape: Shape; index: number } {
  const n = s.pts.length;
  const a = vertex(s.pts, k);
  const b = vertex(s.pts, k + 1);
  if (dist(a, q) < 0.5) return { shape: s, index: k };
  if (dist(b, q) < 0.5) return { shape: s, index: (k + 1) % n };
  const pts = [...s.pts.slice(0, k + 1), q, ...s.pts.slice(k + 1)];
  const cut = [...s.cut.slice(0, k + 1), false, ...s.cut.slice(k + 1)];
  return { shape: { pts, cut }, index: k + 1 };
}

/** A chord from i to j runs inside the shape without touching its outline anywhere else. */
function chordInside(s: Shape, i: number, j: number): boolean {
  const n = s.pts.length;
  if (i === j || (i + 1) % n === j || (j + 1) % n === i) return false;
  const a = s.pts[i]!;
  const b = s.pts[j]!;
  for (let k = 0; k < n; k++) {
    const k1 = (k + 1) % n;
    if (k === i || k === j || k1 === i || k1 === j) continue;
    if (segmentsMeet(a, b, s.pts[k]!, s.pts[k1]!)) return false;
  }
  return inside(s.pts, { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });
}

/** A part made by a split is only worth keeping if the new line doesn't make a sliver or a point that snaps. */
function cuttablePart(s: Shape, set: Settings): boolean {
  for (let k = 0; k < s.pts.length; k++) {
    if (s.cut[k] && interior(s.pts, k) < set.minAngle) return false;
  }
  return width(s.pts) >= set.minWidth;
}

interface Candidate {
  parts: [Shape, Shape];
  line: Line;
}

/** Every lead line worth trying through a vertex: to each other vertex it can see, and straight on along each edge and the angle's bisector. */
function candidates(s: Shape, v: number, set: Settings): Candidate[] {
  const out: Candidate[] = [];
  const consider = (shape: Shape, i: number, j: number): void => {
    if (!chordInside(shape, i, j)) return;
    const parts = split(shape, i, j);
    if (!cuttablePart(parts[0], set) || !cuttablePart(parts[1], set)) return;
    out.push({ parts, line: { a: shape.pts[i]!, b: shape.pts[j]! } });
  };
  for (let w = 0; w < s.pts.length; w++) consider(s, v, w);
  const p = s.pts[v]!;
  const prev = vertex(s.pts, v - 1);
  const next = vertex(s.pts, v + 1);
  const u1 = { x: (p.x - prev.x) / dist(prev, p), y: (p.y - prev.y) / dist(prev, p) };
  const u2 = { x: (p.x - next.x) / dist(next, p), y: (p.y - next.y) / dist(next, p) };
  for (const [dx, dy] of [
    [u1.x, u1.y],
    [u2.x, u2.y],
    [u1.x + u2.x, u1.y + u2.y],
  ] as const) {
    const hit = rayHit(s.pts, v, dx, dy);
    if (hit === null) continue;
    const { shape, index } = addPoint(s, hit.edge, hit.point);
    // Inserting a point before v moves v along by one.
    consider(shape, shape !== s && index <= v ? v + 1 : v, index);
  }
  return out;
}

export const MAX_LINES = 8;
export const NODE_BUDGET = 60_000;

class OutOfBudget extends Error {}

/**
 * The fewest lead lines (then the least lead) that leave every part cuttable.
 *
 * Any fix must put a line through each problem corner (otherwise the corner is still there in one
 * of the parts), so only lines through the first problem are tried: the search stays complete for
 * corners while branching on one vertex at a time. Deep curves try lines through each of their
 * inside corners.
 */
export function fix(s: Shape, set: Settings): Plan | "impossible" | "too complex" {
  const memo = new Map<string, Plan | null>();
  let nodes = 0;
  const key = (sh: Shape, limit: number): string => `${limit}|${sh.pts.map((q) => `${q.x.toFixed(3)},${q.y.toFixed(3)}`).join(" ")}`;
  const solve = (sh: Shape, limit: number): Plan | null => {
    const k = key(sh, limit);
    const known = memo.get(k);
    if (known !== undefined) return known;
    if (++nodes > NODE_BUDGET) throw new OutOfBudget();
    const probs = problems(sh, set);
    let best: Plan | null = null;
    if (probs.length === 0) best = { lines: [], length: 0 };
    else if (limit > 0) {
      const first = probs[0]!;
      let through: number[];
      if (first.kind === "corner") through = [first.at];
      else {
        through = first.chain.filter((i) => turn(sh.pts, i) < 0);
        if (through.length === 0) through = [first.deepest];
      }
      for (const v of through) {
        for (const c of candidates(sh, v, set)) {
          const a = solve(c.parts[0], limit - 1);
          if (a === null) continue;
          const b = solve(c.parts[1], limit - 1 - a.lines.length);
          if (b === null) continue;
          const plan = { lines: [c.line, ...a.lines, ...b.lines], length: dist(c.line.a, c.line.b) + a.length + b.length };
          if (better(plan, best)) best = plan;
        }
      }
    }
    memo.set(k, best);
    return best;
  };
  try {
    // Iterative deepening: the first limit that works gives the fewest lines.
    for (let limit = 0; limit <= MAX_LINES; limit++) {
      const plan = solve(s, limit);
      if (plan !== null) return plan;
    }
    return "impossible";
  } catch (e) {
    if (e instanceof OutOfBudget) return "too complex";
    throw e;
  }
}
