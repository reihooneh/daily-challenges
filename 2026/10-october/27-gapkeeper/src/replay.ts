// Replays the logged day as if drivers had been held at the control stops to even out the gaps.
//
// Holding rule (headway-based): a bus may not leave a control stop until `target` seconds after
// the bus in front left it, where target = alpha x scheduled headway, and never waits longer than
// `cap`. Alpha below 1 leaves slack so the bus isn't held for a full headway behind a late leader.
//
// Why bunching feeds itself: a bus with a big gap in front finds more people waiting, so it dwells
// longer and falls further behind, while the bus behind it finds fewer and catches up. The replay
// models that with `dwell`: every extra second of gap in front of a bus at a stop adds `dwell`
// seconds to its time at the stop (and a smaller gap takes time off). Running times between stops
// otherwise come straight from the log.

import { analyse, type DayReport, type Timetable } from './headways.js';
import type { Log } from './log.js';

export interface Rule {
  alpha: number;
  cap: number; // seconds
}

export interface Replay {
  rule: Rule;
  table: Timetable;
  report: DayReport;
  holds: number; // trips held at least once
  meanHold: number; // seconds per trip
  addedRide: number; // mean extra end-to-end time per trip, seconds
  score: number; // EWT + rideValue x addedRide, seconds
}

/** Fills interior gaps by linear interpolation; times after a trip's last logged stop stay null. */
export function interpolate(times: (number | null)[]): (number | null)[] {
  const out = [...times];
  let lastKnown = 0;
  for (let s = 1; s < out.length; s++) {
    if (out[s] == null) continue;
    for (let k = lastKnown + 1; k < s; k++) {
      out[k] = out[lastKnown]! + ((out[s]! - out[lastKnown]!) * (k - lastKnown)) / (s - lastKnown);
    }
    lastKnown = s;
  }
  return out;
}

export function replay(log: Log, rule: Rule): Replay {
  const order = log.trips.map((_, i) => i).sort((a, b) => log.trips[a]!.times[0]! - log.trips[b]!.times[0]!);
  const base = log.trips.map((t) => interpolate(t.times));
  const target = rule.alpha * log.headway;
  const table: Timetable = log.trips.map(() => []);
  let holds = 0, held = 0, added = 0, finished = 0;

  order.forEach((k, pos) => {
    const obs = base[k]!;
    const prev = pos > 0 ? order[pos - 1]! : -1;
    const out: (number | null)[] = [obs[0]!];
    let wasHeld = false;
    for (let s = 0; s < obs.length; s++) {
      const here = out[s];
      if (here == null) break;
      // Dwell feedback: compare the gap in front now with the gap in front in the log.
      let depart = here;
      if (prev >= 0 && s > 0) {
        const gapNow = gapAt(table[prev]!, s, here);
        const gapThen = gapAt(base[prev]!, s, obs[s]!);
        if (gapNow !== null && gapThen !== null) depart += log.dwell * (gapNow - gapThen);
      }
      if (prev >= 0 && log.control.includes(s)) {
        const leader = table[prev]![s];
        if (leader != null) {
          const hold = Math.min(rule.cap, Math.max(0, leader + target - depart));
          if (hold > 0) {
            depart += hold;
            held += hold;
            wasHeld = true;
          }
        }
      }
      out[s] = depart;
      const next = obs[s + 1];
      if (s + 1 < obs.length && next != null) {
        // Running time to the next stop as logged; dwell changes can't make it negative.
        out[s + 1] = depart + Math.max(0, next - obs[s]!);
      }
    }
    table[k] = out;
    if (wasHeld) holds++;
    const lastIdx = lastKnownIndex(obs);
    const now = out[lastIdx];
    if (now != null) {
      added += now - obs[lastIdx]!;
      finished++;
    }
  });

  const report = analyse(log, table);
  const addedRide = finished ? added / finished : 0;
  return {
    rule,
    table,
    report,
    holds,
    meanHold: held / log.trips.length,
    addedRide,
    score: report.ewt + log.rideValue * addedRide,
  };
}

function gapAt(trip: (number | null)[], s: number, mine: number): number | null {
  const t = trip[s];
  return t == null ? null : mine - t;
}

function lastKnownIndex(times: (number | null)[]): number {
  for (let s = times.length - 1; s >= 0; s--) if (times[s] != null) return s;
  return 0;
}

export const ALPHAS = [0.5, 0.6, 0.7, 0.8, 0.9];
export const CAPS = [60, 120, 180, 300];

/** Tries every rule in the grid; the first entry is "no holding" for comparison. */
export function sweep(log: Log): { none: Replay; rules: Replay[]; best: Replay } {
  const none = replay(log, { alpha: 0, cap: 0 });
  const rules: Replay[] = [];
  if (log.control.length) {
    for (const alpha of ALPHAS) for (const cap of CAPS) rules.push(replay(log, { alpha, cap }));
  }
  let best = none;
  for (const r of rules) if (r.score < best.score - 1e-9) best = r;
  return { none, rules, best };
}
