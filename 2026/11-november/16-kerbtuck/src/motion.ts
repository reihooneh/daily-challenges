// How a car moves at low speed: the middle of the rear axle follows arcs (a car can't slide
// sideways), and the body is a rectangle around it. Plus the geometry to check for bumps.

import { Car, derive } from './car.js';

// Where the car is: the middle of its rear axle, and which way it points (radians, 0 = along
// the kerb towards the front of the gap).
export interface Pose {
  x: number;
  y: number;
  heading: number;
}

export type Point = [number, number];

// Drives `distance` metres (negative = reversing) with curvature `k` (1/m, positive turns
// left, towards the road).
export function drive(p: Pose, k: number, distance: number): Pose {
  const h = p.heading + k * distance;
  if (Math.abs(k) < 1e-12) {
    return { x: p.x + Math.cos(p.heading) * distance, y: p.y + Math.sin(p.heading) * distance, heading: h };
  }
  return {
    x: p.x + (Math.sin(h) - Math.sin(p.heading)) / k,
    y: p.y - (Math.cos(h) - Math.cos(p.heading)) / k,
    heading: h,
  };
}

// The four corners of the body: rear-right, front-right, front-left, rear-left (right is the
// kerb side when the car points along the kerb).
export function corners(car: Car, p: Pose): Point[] {
  const q = derive(car).rearOverhang;
  const front = car.wheelbase + car.frontOverhang;
  const w = car.width / 2;
  const c = Math.cos(p.heading), s = Math.sin(p.heading);
  return ([[-q, -w], [front, -w], [front, w], [-q, w]] as Point[]).map(([a, b]) => [p.x + a * c - b * s, p.y + a * s + b * c]);
}

export interface Box {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

// Separating-axis test between the car's rectangle and an axis-aligned box.
export function hits(poly: Point[], b: Box): boolean {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const [x, y] of poly) {
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  }
  if (maxX <= b.x0 || minX >= b.x1 || maxY <= b.y0 || minY >= b.y1) return false;
  // The rectangle's own two axes.
  const boxPts: Point[] = [[b.x0, b.y0], [b.x1, b.y0], [b.x1, b.y1], [b.x0, b.y1]];
  for (let i = 0; i < 2; i++) {
    const [ax, ay] = poly[i]!;
    const [bx, by] = poly[i + 1]!;
    const nx = -(by - ay), ny = bx - ax;
    let pMin = Infinity, pMax = -Infinity, qMin = Infinity, qMax = -Infinity;
    for (const [x, y] of poly) { const d = x * nx + y * ny; pMin = Math.min(pMin, d); pMax = Math.max(pMax, d); }
    for (const [x, y] of boxPts) { const d = x * nx + y * ny; qMin = Math.min(qMin, d); qMax = Math.max(qMax, d); }
    if (pMax <= qMin || qMax <= pMin) return false;
  }
  return true;
}
