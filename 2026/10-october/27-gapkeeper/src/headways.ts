// What passengers actually experienced: the gaps between buses at each stop, and how much
// longer people waited because the gaps were uneven.

import type { Log } from './log.js';

/** Departure times at each stop, trip by trip (null where unknown). */
export type Timetable = (number | null)[][];

export interface StopReport {
  stop: string;
  headways: number[]; // seconds, in time order
  awt: number; // average wait, seconds
  ewt: number; // excess over the scheduled wait, seconds
  bunched: number; // gaps under a quarter of the headway
  gaps: number; // gaps over 1.75 times the headway
}

export interface DayReport {
  stops: StopReport[];
  /** Demand-weighted excess waiting time across the route, seconds. */
  ewt: number;
  bunched: number;
  gaps: number;
  overtakes: number;
}

/**
 * Average wait for someone arriving at random: each gap h is landed in with probability
 * proportional to h, and then they wait h/2 on average, so AWT = sum(h^2) / (2 sum(h)).
 * Even gaps give the scheduled H/2; uneven gaps always give more.
 */
export function averageWait(headways: number[]): number {
  let sum = 0, squares = 0;
  for (const h of headways) {
    sum += h;
    squares += h * h;
  }
  return sum > 0 ? squares / (2 * sum) : 0;
}

export function analyse(log: Log, table: Timetable): DayReport {
  const H = log.headway;
  const stops: StopReport[] = [];
  let weighted = 0, weight = 0, bunched = 0, gaps = 0;
  for (let s = 0; s < log.stops.length; s++) {
    const times = table.map((trip) => trip[s]).filter((t): t is number => t !== null && t !== undefined).sort((a, b) => a - b);
    const headways = times.slice(1).map((t, i) => t - times[i]!);
    const awt = averageWait(headways);
    const report: StopReport = {
      stop: log.stops[s]!,
      headways,
      awt,
      ewt: headways.length >= 2 ? awt - H / 2 : 0,
      bunched: headways.filter((h) => h < H / 4).length,
      gaps: headways.filter((h) => h > 1.75 * H).length,
    };
    stops.push(report);
    bunched += report.bunched;
    gaps += report.gaps;
    if (headways.length >= 2) {
      weighted += report.ewt * log.demand[s]!;
      weight += log.demand[s]!;
    }
  }
  return { stops, ewt: weight > 0 ? weighted / weight : 0, bunched, gaps, overtakes: overtakes(table) };
}

/** Times one bus passed another between consecutive stops (the order of two trips flipped). */
export function overtakes(table: Timetable): number {
  let count = 0;
  for (let a = 0; a < table.length; a++) {
    for (let b = a + 1; b < table.length; b++) {
      let sign = 0;
      for (let s = 0; s < (table[a]?.length ?? 0); s++) {
        const ta = table[a]![s], tb = table[b]![s];
        if (ta == null || tb == null || ta === tb) continue;
        const now = Math.sign(tb - ta);
        if (sign !== 0 && now !== sign) count++;
        sign = now;
      }
    }
  }
  return count;
}

/** The observed log as a timetable. */
export function observed(log: Log): Timetable {
  return log.trips.map((t) => [...t.times]);
}
