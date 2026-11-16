// The parking problem: a kerb, a car parked behind the gap and one in front, and our car
// alongside the front one. How small a gap can it reverse into in one go, and how few
// back-and-forth shuffles does a smaller gap take?

import { Car, derive } from './car.js';
import { Box, Pose, corners, drive, hits } from './motion.js';

export const SIDE = 0.15;       // m between the kerb and the parked cars
export const OTHER = { length: 4.5, width: 1.8 }; // the parked cars
export const START_GAP = 0.5;   // m beside the front car when we start
export const CLEARANCE = 0.05;  // m we keep from the other cars
export const KERB_MAX = 0.4;    // m: parked counts as within this of the kerb
export const MAX_EXPANSIONS = 400000;

export interface Scene {
  car: Car;
  gap: number;   // m between the rear car's front bumper (x = 0) and the front car's rear bumper
  rear: Box;
  front: Box;
}

export function scene(car: Car, gap: number): Scene {
  const c = CLEARANCE;
  return {
    car,
    gap,
    rear: { x0: -OTHER.length - c, y0: SIDE - c, x1: c, y1: SIDE + OTHER.width + c },
    front: { x0: gap - c, y0: SIDE - c, x1: gap + OTHER.length + c, y1: SIDE + OTHER.width + c },
  };
}

// The smallest gap the car can reverse into in one movement. In the last part of the move the
// car turns about a point beside its rear axle, on the road side; its front kerb-side corner
// swings in on a circle round that point and must pass behind the front car's road-side
// corner. That gives gap = rear overhang + √(r² − (centre's distance out from that corner)²).
export function oneMoveGap(car: Car, kerbOffset = SIDE): number {
  const d = derive(car);
  const front = car.wheelbase + car.frontOverhang;
  const corner = Math.hypot(front, d.radius + car.width / 2);
  const centreY = kerbOffset + car.width / 2 + d.radius;
  const rise = centreY - (SIDE + OTHER.width);
  return d.rearOverhang + Math.sqrt(corner * corner - rise * rise);
}

export function clear(s: Scene, p: Pose): boolean {
  const poly = corners(s.car, p);
  for (const [, y] of poly) if (y < 0.02) return false; // over the kerb
  return !hits(poly, s.rear) && !hits(poly, s.front);
}

export function parked(s: Scene, p: Pose): boolean {
  if (Math.abs(p.heading) > (2.5 * Math.PI) / 180) return false;
  const poly = corners(s.car, p);
  const kerbSide = Math.min(...poly.map(([, y]) => y));
  const xs = poly.map(([x]) => x);
  return kerbSide <= KERB_MAX && Math.min(...xs) >= -CLEARANCE && Math.max(...xs) <= s.gap + CLEARANCE && clear(s, p);
}

export function startPose(s: Scene): Pose {
  const q = derive(s.car).rearOverhang;
  return { x: s.gap + q, y: SIDE + OTHER.width + START_GAP + s.car.width / 2, heading: 0 };
}

export interface Move {
  reverse: boolean;
  steer: number;    // −1 full right lock … 1 full left lock
  distance: number; // m
}

export interface Plan {
  found: boolean;
  moves: Move[];      // merged into continuous movements
  changes: number;    // gear changes between forward and reverse
  distance: number;   // m driven
  poses: Pose[];      // every 0.3 m, for drawing
  expansions: number;
  gave_up: boolean;   // hit the search limit
}

const STEP = 0.3;
const STEERS = [-1, 0, 1]; // full right lock, straight, full left lock: what drivers actually do
const CELL = 0.1;
const ANGLE = (3 * Math.PI) / 180;

// A binary heap of [cost, index].
class Heap {
  private a: [number, number][] = [];
  get size(): number { return this.a.length; }
  push(v: [number, number]): void {
    const a = this.a;
    a.push(v);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (a[p]![0] <= a[i]![0]) break;
      [a[p], a[i]] = [a[i]!, a[p]!];
      i = p;
    }
  }
  pop(): [number, number] {
    const a = this.a;
    const top = a[0]!;
    const last = a.pop()!;
    if (a.length) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < a.length && a[l]![0] < a[m]![0]) m = l;
        if (r < a.length && a[r]![0] < a[m]![0]) m = r;
        if (m === i) break;
        [a[m], a[i]] = [a[i]!, a[m]!];
        i = m;
      }
    }
    return top;
  }
}

// Plans the parking with the fewest gear changes (then the shortest drive): a search over
// short arcs at five steering positions, forwards and backwards, on a grid of positions and
// headings (a hybrid A* without the heuristic, i.e. Dijkstra).
export function plan(s: Scene, maxExpansions = MAX_EXPANSIONS): Plan {
  const k = derive(s.car).curvature;
  const start = startPose(s);
  // Stay near the gap: a little way past the front car, and no further out than where we started.
  const xMin = -0.5, xMax = s.gap + 5.5, yMax = start.y + 0.3;
  interface Node { pose: Pose; parent: number; move: Move | null; dir: number; steer: number; changes: number; turns: number; dist: number }
  const nodes: Node[] = [{ pose: start, parent: -1, move: null, dir: 0, steer: 0, changes: 0, turns: 0, dist: 0 }];
  const best = new Map<string, number>();
  const key = (p: Pose, dir: number) => `${Math.round(p.x / CELL)},${Math.round(p.y / CELL)},${Math.round(p.heading / ANGLE)},${dir}`;
  const heap = new Heap();
  heap.push([0, 0]);
  let expansions = 0;
  // Fewest gear changes first, then the fewest turns of the wheel, then the shortest drive.
  const cost = (n: Node) => n.changes * 1000 + n.turns * 0.5 + n.dist;
  while (heap.size && expansions < maxExpansions) {
    const [c, i] = heap.pop();
    const n = nodes[i]!;
    if (c > cost(n) + 1e-9) continue;
    expansions++;
    if (n.move && parked(s, n.pose)) return finish(nodes, i, expansions, false);
    for (const dir of [-1, 1]) {
      for (const steer of STEERS) {
        let p = n.pose;
        let ok = true;
        for (let sub = 1; sub <= 6 && ok; sub++) {
          p = drive(n.pose, steer * k, (dir * STEP * sub) / 6);
          ok = clear(s, p);
        }
        if (!ok || p.x < xMin || p.x > xMax || p.y > yMax || Math.abs(p.heading) > (55 * Math.PI) / 180) continue;
        const changes = n.changes + (n.dir !== 0 && n.dir !== dir ? 1 : 0);
        const turns = n.turns + (n.move && n.steer !== steer ? 1 : 0);
        const next: Node = { pose: p, parent: i, move: { reverse: dir < 0, steer, distance: STEP }, dir, steer, changes, turns, dist: n.dist + STEP };
        const kk = key(p, dir);
        const prev = best.get(kk);
        if (prev !== undefined && prev <= cost(next) + 1e-9) continue;
        best.set(kk, cost(next));
        nodes.push(next);
        heap.push([cost(next), nodes.length - 1]);
      }
    }
  }
  return { found: false, moves: [], changes: 0, distance: 0, poses: [start], expansions, gave_up: expansions >= maxExpansions };

  function finish(all: Node[], end: number, exp: number, gaveUp: boolean): Plan {
    const chain: Node[] = [];
    for (let j = end; j >= 0; j = all[j]!.parent) chain.push(all[j]!);
    chain.reverse();
    const moves: Move[] = [];
    for (const nd of chain) {
      if (!nd.move) continue;
      const last = moves[moves.length - 1];
      if (last && last.reverse === nd.move.reverse && last.steer === nd.move.steer) last.distance += nd.move.distance;
      else moves.push({ ...nd.move });
    }
    let changes = 0;
    for (let j = 1; j < moves.length; j++) if (moves[j]!.reverse !== moves[j - 1]!.reverse) changes++;
    return {
      found: true, moves, changes, distance: chain[chain.length - 1]!.dist,
      poses: chain.map((nd) => nd.pose), expansions: exp, gave_up: gaveUp,
    };
  }
}

// Replays a plan's moves from the start and checks every 5 cm for bumps; returns the end pose.
export function replay(s: Scene, moves: Move[]): { ok: boolean; end: Pose } {
  const k = derive(s.car).curvature;
  let p = startPose(s);
  for (const m of moves) {
    const steps = Math.max(1, Math.round(m.distance / 0.05));
    const from = p;
    for (let i = 1; i <= steps; i++) {
      p = drive(from, m.steer * k, ((m.reverse ? -1 : 1) * m.distance * i) / steps);
      if (!clear(s, p)) return { ok: false, end: p };
    }
  }
  return { ok: true, end: p };
}
