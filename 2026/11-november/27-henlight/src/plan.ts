// Planning the timer.
//
// Each day of the season has a window of acceptable total light, [lo, hi] minutes: while the hens
// are being brought up to the target, lo rises by the ramp each week and hi is one more week's
// step above it; after that it is [target, most]. A timer setting is either "lights off" or a pair
// of pins (on, off) on the clock. The lamp must come on before sunrise and stay on until sunrise,
// so the morning has no dark gap and the evening ends at natural dusk (hens settle to roost as the
// light fades; a lamp switching off after dark leaves them on the floor).
//
// Whether a setting works on a day depends only on that day. So a setting that works on days s..e
// works on any days inside them, and the classic greedy is optimal for the fewest timer changes:
// from the first unplanned day, take the setting that works for the most days in a row.
import { Day } from './sun.js';

export interface Options {
  /** Minutes of total light to reach. */
  target: number;
  /** Most total light allowed (minutes). */
  most: number;
  /** How much total light may grow in a week while ramping up (minutes). */
  ramp: number;
  /** The timer's pin spacing (minutes). */
  step: number;
}

export type Setting = { off: true } | { off: false; on: number; until: number };

export interface Segment {
  from: number; // index into days
  to: number; // inclusive
  setting: Setting;
  lampMinutes: number; // total lamp time over the segment
}

export interface Window {
  lo: number;
  hi: number;
}

/** The acceptable total light for each day of the season. */
export function windows(days: Day[], o: Options): Window[] {
  if (days.length === 0) return [];
  const start = days[0]!.set - days[0]!.rise;
  return days.map((d, i) => {
    const natural = d.set - d.rise;
    const ramped = start + (o.ramp * i) / 7;
    const lo = Math.min(o.target, ramped);
    let hi = lo < o.target ? Math.min(o.most, lo + o.ramp) : o.most;
    hi = Math.max(hi, natural); // nobody can take daylight away
    return { lo, hi };
  });
}

/** Total light on a day with a setting, or NaN if the setting breaks the morning rule. */
export function totalLight(d: Day, s: Setting): number {
  if (s.off) return d.set - d.rise;
  if (!(s.on < d.rise && s.until >= d.rise && s.until < d.set)) return NaN;
  return d.set - s.on;
}

export function works(d: Day, w: Window, s: Setting): boolean {
  const t = totalLight(d, s);
  return t >= w.lo - 1e-9 && t <= w.hi + 1e-9;
}

/** Every setting the timer can hold, lights-off first. */
export function settings(step: number): Setting[] {
  const out: Setting[] = [{ off: true }];
  for (let on = 0; on < 1440; on += step) for (let until = on + step; until < 1440; until += step) out.push({ off: false, on, until });
  return out;
}

const lamp = (s: Setting): number => (s.off ? 0 : s.until - s.on);

export class NoSettingError extends Error {
  constructor(readonly day: number) {
    super('no timer setting works on this day');
  }
}

/** Fewest timer changes over the season (greedy furthest reach); among settings that reach as
 * far, the least lamp time. Throws NoSettingError if some day can't be lit within its window. */
export function plan(days: Day[], o: Options): Segment[] {
  const win = windows(days, o);
  const all = settings(o.step);
  const out: Segment[] = [];
  let s = 0;
  while (s < days.length) {
    let best: Setting | null = null;
    let bestEnd = s - 1;
    let bestLamp = Infinity;
    for (const set of all) {
      let e = s;
      while (e < days.length && works(days[e]!, win[e]!, set)) e++;
      e--;
      const l = lamp(set) * (e - s + 1);
      if (e > bestEnd || (e === bestEnd && e >= s && l < bestLamp)) {
        best = set;
        bestEnd = e;
        bestLamp = l;
      }
    }
    if (!best || bestEnd < s) throw new NoSettingError(s);
    out.push({ from: s, to: bestEnd, setting: best, lampMinutes: bestLamp });
    s = bestEnd + 1;
  }
  return out;
}

/** The fewest changes by dynamic programming over every split, for testing the greedy. */
export function fewestChanges(days: Day[], o: Options): number {
  const win = windows(days, o);
  const all = settings(o.step);
  const n = days.length;
  // ok[s][e]: one setting covers s..e.
  const reach = new Array<number>(n).fill(-1);
  for (let s = 0; s < n; s++) {
    for (const set of all) {
      let e = s;
      while (e < n && works(days[e]!, win[e]!, set)) e++;
      reach[s] = Math.max(reach[s]!, e - 1);
    }
  }
  const best = new Array<number>(n + 1).fill(Infinity);
  best[0] = 0;
  for (let s = 0; s < n; s++) {
    if (best[s] === Infinity) continue;
    for (let e = s; e <= reach[s]!; e++) best[e + 1] = Math.min(best[e + 1]!, best[s]! + 1);
  }
  return best[n]!;
}
