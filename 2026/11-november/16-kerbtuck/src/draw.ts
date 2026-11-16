// The parking, drawn from above in text: the kerb at the bottom, the parked cars as #, the path
// of the middle of the rear axle as dots, and the car where it ends up as @.

import { Pose, corners } from './motion.js';
import { Scene, SIDE, OTHER } from './park.js';
import { Move } from './park.js';

const DX = 0.15; // m per column
const DY = 0.25; // m per row

function inside(poly: [number, number][], x: number, y: number): boolean {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i]!;
    const [xj, yj] = poly[j]!;
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
}

export function picture(s: Scene, poses: Pose[], end: Pose | null): string {
  const x0 = -1.5, x1 = s.gap + 1.5;
  const y1 = SIDE + OTHER.width + 2.6;
  const cols = Math.ceil((x1 - x0) / DX);
  const rows = Math.ceil(y1 / DY);
  const grid: string[][] = Array.from({ length: rows }, () => Array(cols).fill(' '));
  const body = end ? corners(s.car, end) : null;
  for (let r = 0; r < rows; r++) {
    const y = y1 - (r + 0.5) * DY;
    for (let c = 0; c < cols; c++) {
      const x = x0 + (c + 0.5) * DX;
      const inBox = (b: { x0: number; x1: number; y0: number; y1: number }) => x >= b.x0 && x <= b.x1 && y >= b.y0 && y <= b.y1;
      const parkedCar = (y >= SIDE && y <= SIDE + OTHER.width) && (x <= 0 || x >= s.gap);
      if (parkedCar && (inBox({ x0: -OTHER.length, x1: 0, y0: SIDE, y1: SIDE + OTHER.width }) || inBox({ x0: s.gap, x1: s.gap + OTHER.length, y0: SIDE, y1: SIDE + OTHER.width }))) grid[r]![c] = '#';
      if (body && inside(body, x, y)) grid[r]![c] = '@';
    }
  }
  for (const p of poses) {
    const c = Math.floor((p.x - x0) / DX);
    const r = Math.floor((y1 - p.y) / DY);
    if (r >= 0 && r < rows && c >= 0 && c < cols && grid[r]![c] === ' ') grid[r]![c] = '.';
  }
  const lines = grid.map((row) => '  ' + row.join('').replace(/\s+$/, ''));
  while (lines.length && lines[0]!.trim() === '') lines.shift();
  lines.push('  ' + '='.repeat(cols) + '  kerb');
  return lines.join('\n');
}

function lock(steer: number): string {
  return steer < 0 ? 'full right lock' : steer > 0 ? 'full left lock' : 'straight';
}

// Groups the moves into goes (one per gear) and describes each: "Go 1, reverse: 0.6 m
// straight, then 3.0 m on full right lock".
export function goes(moves: Move[]): string[] {
  const out: string[] = [];
  let i = 0;
  while (i < moves.length) {
    const rev = moves[i]!.reverse;
    const parts: string[] = [];
    let total = 0;
    while (i < moves.length && moves[i]!.reverse === rev) {
      const m = moves[i]!;
      parts.push(`${m.distance.toFixed(1)} m ${m.steer === 0 ? 'straight' : `on ${lock(m.steer)}`}`);
      total += m.distance;
      i++;
    }
    out.push(`Go ${out.length + 1}, ${rev ? 'reverse' : 'forward'} ${total.toFixed(1)} m: ${parts.join(', then ')}`);
  }
  return out;
}
