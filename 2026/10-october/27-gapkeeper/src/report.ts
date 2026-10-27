import type { DayReport } from './headways.js';
import type { Log } from './log.js';
import { ALPHAS, CAPS, type Replay } from './replay.js';

const min = (s: number) => (s / 60).toFixed(1);
const signedMin = (s: number) => `${s >= 0 ? '+' : '-'}${min(Math.abs(s))}`;

/** A one-line picture of the gaps at a stop: one mark per bus, spaced by time. */
export function strip(headways: number[], H: number, width = 48): string {
  const total = headways.reduce((a, b) => a + b, 0);
  if (!total) return '';
  const cells = Array<string>(width).fill('·');
  let t = 0;
  cells[0] = '■';
  for (const h of headways) {
    t += h;
    const at = Math.min(width - 1, Math.round((t / total) * (width - 1)));
    cells[at] = h < H / 4 ? '▲' : '■';
  }
  return cells.join('');
}

export function render(log: Log, none: Replay, rules: Replay[], best: Replay): string {
  const out: string[] = [];
  const day: DayReport = none.report;
  const H = log.headway;
  out.push(`GAPKEEPER  ${log.route}`);
  out.push(`${log.trips.length} trips past ${log.stops.length} stops, scheduled every ${min(H)} min (an even service means an average wait of ${min(H / 2)} min).`);
  out.push('');
  out.push(`What riders got: ${min(day.ewt)} min of excess waiting on average (EWT), ${day.bunched} bunched pairs, ${day.gaps} long gaps, ${day.overtakes} overtakes.`);
  out.push('');
  out.push(`  ${'Stop'.padEnd(18)} ${'Avg wait'.padStart(8)} ${'Excess'.padStart(7)}  Buses through the day (▲ = bunched)`);
  for (const s of day.stops) {
    out.push(`  ${s.stop.slice(0, 18).padEnd(18)} ${min(s.awt).padStart(8)} ${signedMin(s.ewt).padStart(7)}  ${strip(s.headways, H)}`);
  }
  out.push('');
  const worst = [...day.stops].sort((a, b) => b.ewt - a.ewt)[0]!;
  const first = day.stops[0]!;
  out.push(`Gaps grow along the route: excess wait ${signedMin(first.ewt)} min at ${first.stop}, ${signedMin(worst.ewt)} min at ${worst.stop}.`);
  out.push('');

  if (!log.control.length) {
    out.push("No control stop is set, so there is nothing to replay. Add 'control <stop>' to try holding buses there.");
    return out.join('\n') + '\n';
  }
  out.push(`Replaying the day with holding at ${log.control.map((i) => log.stops[i]).join(', ')}`);
  out.push(`(a bus waits until alpha x ${min(H)} min after the one in front left, but never longer than the cap):`);
  out.push('');
  out.push(`  ${'alpha'.padEnd(6)}${CAPS.map((c) => `cap ${c / 60} min`.padStart(14)).join('')}`);
  for (const alpha of ALPHAS) {
    const row = CAPS.map((cap) => {
      const r = rules.find((x) => x.rule.alpha === alpha && x.rule.cap === cap)!;
      const cell = `${min(r.report.ewt)} / ${signedMin(r.addedRide)}`;
      return (r === best ? `*${cell}` : cell).padStart(14);
    });
    out.push(`  ${alpha.toFixed(1).padEnd(6)}${row.join('')}`);
  }
  out.push('  (each cell: excess wait in min / extra ride time per trip in min; * = best)');
  out.push('');
  if (best === none) {
    out.push('Recommendation: no holding rule beats running as logged once the extra riding time is counted.');
  } else {
    const saved = none.report.ewt - best.report.ewt;
    out.push(`Recommendation: hold to ${best.rule.alpha.toFixed(1)} x headway, capped at ${best.rule.cap / 60} min.`);
    out.push(`  Excess waiting falls from ${min(none.report.ewt)} to ${min(best.report.ewt)} min (${Math.round((saved / Math.max(none.report.ewt, 1e-9)) * 100)}% less);`);
    out.push(`  bunched pairs ${none.report.bunched} -> ${best.report.bunched}; ${best.holds} of ${log.trips.length} trips held, ${min(best.meanHold)} min each on average;`);
    out.push(`  riders on board pay ${min(best.addedRide)} min more per trip (counted at ${log.rideValue} of a waiting minute).`);
  }
  out.push('');
  out.push('This is a replay of one logged day with a simple dwell model, not a forecast: try the rule, then log again.');
  return out.join('\n') + '\n';
}
