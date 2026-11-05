// Plane geometry for glass pieces: simple polygons in millimetres, kept counter-clockwise.

export interface Pt {
  readonly x: number;
  readonly y: number;
}

const EPS = 1e-9;

/** The i-th vertex, wrapping round. */
export function vertex(p: readonly Pt[], i: number): Pt {
  const n = p.length;
  return p[((i % n) + n) % n]!;
}

export function dist(a: Pt, b: Pt): number {
  return Math.hypot(b.x - a.x, b.y - a.y);
}

/** Twice the signed area of triangle o-a-b: positive when o, a, b turn left. */
export function cross(o: Pt, a: Pt, b: Pt): number {
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

/** Signed area: positive for a counter-clockwise polygon. */
export function area(p: readonly Pt[]): number {
  let s = 0;
  for (let i = 0; i < p.length; i++) {
    const a = vertex(p, i);
    const b = vertex(p, i + 1);
    s += a.x * b.y - b.x * a.y;
  }
  return s / 2;
}

/**
 * How far the outline turns at vertex i, in degrees: positive for a left turn (a convex corner of a
 * counter-clockwise polygon), negative for a right turn (an inside corner).
 */
export function turn(p: readonly Pt[], i: number): number {
  const a = vertex(p, i - 1);
  const b = vertex(p, i);
  const c = vertex(p, i + 1);
  const ux = b.x - a.x;
  const uy = b.y - a.y;
  const vx = c.x - b.x;
  const vy = c.y - b.y;
  return (Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy) * 180) / Math.PI;
}

/** The angle inside the piece at vertex i, in degrees (over 180 at an inside corner). */
export function interior(p: readonly Pt[], i: number): number {
  return 180 - turn(p, i);
}

function onSegment(a: Pt, b: Pt, q: Pt): boolean {
  return (
    Math.min(a.x, b.x) - EPS <= q.x &&
    q.x <= Math.max(a.x, b.x) + EPS &&
    Math.min(a.y, b.y) - EPS <= q.y &&
    q.y <= Math.max(a.y, b.y) + EPS
  );
}

/** Whether segments ab and cd meet at all, touching included. */
export function segmentsMeet(a: Pt, b: Pt, c: Pt, d: Pt): boolean {
  const d1 = cross(c, d, a);
  const d2 = cross(c, d, b);
  const d3 = cross(a, b, c);
  const d4 = cross(a, b, d);
  if (((d1 > EPS && d2 < -EPS) || (d1 < -EPS && d2 > EPS)) && ((d3 > EPS && d4 < -EPS) || (d3 < -EPS && d4 > EPS))) return true;
  return (
    (Math.abs(d1) <= EPS && onSegment(c, d, a)) ||
    (Math.abs(d2) <= EPS && onSegment(c, d, b)) ||
    (Math.abs(d3) <= EPS && onSegment(a, b, c)) ||
    (Math.abs(d4) <= EPS && onSegment(a, b, d))
  );
}

/** No two edges meet except neighbours at their shared vertex, and no edge has zero length. */
export function isSimple(p: readonly Pt[]): boolean {
  const n = p.length;
  for (let i = 0; i < n; i++) {
    if (dist(vertex(p, i), vertex(p, i + 1)) < 1e-6) return false;
  }
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      if (j === i + 1 || (i === 0 && j === n - 1)) continue;
      if (segmentsMeet(vertex(p, i), vertex(p, i + 1), vertex(p, j), vertex(p, j + 1))) return false;
    }
  }
  return true;
}

/** Whether a point is strictly inside the polygon (even-odd rule). */
export function inside(p: readonly Pt[], q: Pt): boolean {
  let c = false;
  for (let i = 0, j = p.length - 1; i < p.length; j = i++) {
    const a = p[i]!;
    const b = p[j]!;
    if (a.y > q.y !== b.y > q.y && q.x < ((b.x - a.x) * (q.y - a.y)) / (b.y - a.y) + a.x) c = !c;
  }
  return c;
}

/** Indices of the convex hull's corners, counter-clockwise (Andrew's monotone chain). */
export function hull(p: readonly Pt[]): number[] {
  const idx = p.map((_, i) => i).sort((a, b) => p[a]!.x - p[b]!.x || p[a]!.y - p[b]!.y);
  const build = (order: number[]): number[] => {
    const h: number[] = [];
    for (const i of order) {
      while (h.length >= 2 && cross(p[h[h.length - 2]!]!, p[h[h.length - 1]!]!, p[i]!) <= EPS) h.pop();
      h.push(i);
    }
    h.pop();
    return h;
  };
  return [...build(idx), ...build([...idx].reverse())];
}

/** Distance from q to the line through a and b. */
export function lineDistance(q: Pt, a: Pt, b: Pt): number {
  return Math.abs(cross(a, b, q)) / dist(a, b);
}

/**
 * The narrowest the piece is in any direction: for a convex outline the narrowest direction is
 * square to one of its hull edges, so it is enough to try each one.
 */
export function width(p: readonly Pt[]): number {
  const h = hull(p);
  let best = Infinity;
  for (let k = 0; k < h.length; k++) {
    const a = p[h[k]!]!;
    const b = p[h[(k + 1) % h.length]!]!;
    let far = 0;
    for (const i of h) far = Math.max(far, lineDistance(p[i]!, a, b));
    best = Math.min(best, far);
  }
  return best;
}

export interface Hit {
  edge: number; // the ray meets edge edge → edge+1
  point: Pt;
  t: number; // distance along the ray
}

/** Where a ray from vertex i in direction (dx, dy) first meets the outline (not at i itself). */
export function rayHit(p: readonly Pt[], i: number, dx: number, dy: number): Hit | null {
  const o = vertex(p, i);
  const len = Math.hypot(dx, dy);
  if (len < EPS) return null;
  const ux = dx / len;
  const uy = dy / len;
  let best: Hit | null = null;
  for (let k = 0; k < p.length; k++) {
    if (k === ((i % p.length) + p.length) % p.length || (k + 1) % p.length === ((i % p.length) + p.length) % p.length) continue;
    const a = vertex(p, k);
    const b = vertex(p, k + 1);
    const ex = b.x - a.x;
    const ey = b.y - a.y;
    const den = ux * ey - uy * ex;
    if (Math.abs(den) < EPS) continue;
    const t = ((a.x - o.x) * ey - (a.y - o.y) * ex) / den;
    const u = ((a.x - o.x) * uy - (a.y - o.y) * ux) / den;
    if (t > 1e-6 && u >= -EPS && u <= 1 + EPS && (best === null || t < best.t)) {
      best = { edge: k, point: { x: o.x + t * ux, y: o.y + t * uy }, t };
    }
  }
  return best;
}
