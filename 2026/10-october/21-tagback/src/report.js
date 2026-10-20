// Turning a parsed survey into estimates, checks and a printable report.

import { tally } from './survey.js';
import { chapman, schnabel, schumacher, planSample, chaoLowerBound } from './estimate.js';
import { captureFrequencies } from './checks.js';

/**
 * Everything the report needs, as plain data (this is also what --json prints).
 * @param {import('./survey.js').Survey} survey
 * @param {number[]} precisions targets for the planner, e.g. [0.2, 0.1]
 */
export function analyse(survey, precisions = [0.2, 0.1]) {
  const { rows, everMarked } = tally(survey);
  const first = rows[1];
  const two = chapman(rows[0].C - rows[0].kept, first.C, first.R);
  const sch = schnabel(rows);
  const se = schumacher(rows);
  /** @type {{level: 'ok'|'warn', text: string}[]} */
  const checks = [];

  if (first.R < 7) {
    checks.push({ level: 'warn', text: `Only ${first.R} recaptures in session 2: the two-session estimate is rough (7 or more is the usual minimum).` });
  }
  if (sch.recaptures === 0) {
    checks.push({ level: 'warn', text: 'No marked animal was ever caught again, so there is no upper limit on the population yet. Catch more.' });
  } else if (sch.recaptures < 7) {
    checks.push({ level: 'warn', text: `Only ${sch.recaptures} recaptures in total: treat the estimates as a first guess.` });
  } else {
    checks.push({ level: 'ok', text: `${sch.recaptures} recaptures in total: enough for the estimates to settle.` });
  }

  if (se && rows.length >= 3) {
    if (se.fit < 0.8) {
      checks.push({
        level: 'warn',
        text: `The share of marked animals doesn't rise steadily (fit ${se.fit.toFixed(2)}). Animals may be arriving, leaving or dying, or marks may be lost.`,
      });
    } else {
      checks.push({ level: 'ok', text: `The share of marked animals rises steadily with the number marked (fit ${se.fit.toFixed(2)}).` });
    }
  }

  let frequencies = null;
  let chao = null;
  if (rows.length >= 3 && sch.recaptures > 0 && Number.isFinite(sch.N) && sch.N > 0) {
    frequencies = captureFrequencies(survey.sessions, Math.max(sch.N, everMarked));
    if (frequencies.heterogeneous) {
      checks.push({
        level: 'warn',
        text: 'Some animals are caught far more often than chance allows (trap-happy) and others hardly at all. The estimates above are probably too LOW; see Chao.',
      });
      chao = chaoLowerBound(frequencies.animals, frequencies.f1, frequencies.f2);
    } else {
      checks.push({ level: 'ok', text: 'How often each animal was caught matches equal catchability.' });
    }
  }

  const base = Number.isFinite(sch.N) && sch.recaptures > 0 ? sch.N : null;
  const plans = base ? precisions.map((p) => ({ precision: p, ...planSample(Math.round(base), p) })) : [];

  return {
    study: survey.study,
    sessions: rows,
    seen: everMarked,
    chapman: { ...two, low: Math.max(two.low, everMarkedAfter(rows, 2)) },
    schnabel: { ...sch, low: Math.max(sch.low, everMarked) },
    schumacher: se,
    chao,
    frequencies,
    checks,
    plans,
  };
}

/** Distinct animals seen in the first k sessions (a floor for any estimate from them). */
function everMarkedAfter(/** @type {{U:number}[]} */ rows, /** @type {number} */ k) {
  return rows.slice(0, k).reduce((a, r) => a + r.U, 0);
}

const fmt = (/** @type {number} */ x) => (Number.isFinite(x) ? String(Math.round(x)) : 'no limit');

/** The human-readable report. @param {ReturnType<typeof analyse>} a */
export function render(a) {
  const out = [];
  out.push(`TAGBACK  ${a.study}  (${a.sessions.length} sessions, ${a.seen} animals marked)`);
  out.push('');
  const w = Math.max(7, ...a.sessions.map((r) => r.label.length));
  out.push(`${'Session'.padEnd(w)}  Caught  Already marked  Marked at large  Newly marked  Kept`);
  for (const r of a.sessions) {
    out.push(
      `${r.label.padEnd(w)}  ${String(r.C).padStart(6)}  ${String(r.R).padStart(14)}  ${String(r.M).padStart(15)}  ${String(r.U).padStart(12)}  ${String(r.kept).padStart(4)}`,
    );
  }
  out.push('');
  out.push('Population estimates (95% interval)');
  const line = (/** @type {string} */ name, /** @type {number} */ n, /** @type {number} */ lo, /** @type {number} */ hi, extra = '') =>
    `  ${name.padEnd(34)} ${fmt(n).padStart(6)}   (${fmt(lo)} to ${fmt(hi)})${extra}`;
  out.push(line('Chapman, first two sessions', a.chapman.N, a.chapman.low, a.chapman.high));
  out.push(line('Schnabel, all sessions', a.schnabel.N, a.schnabel.low, a.schnabel.high));
  if (a.schumacher) {
    out.push(`  ${'Schumacher-Eschmeyer, all sessions'.padEnd(34)} ${fmt(a.schumacher.N).padStart(6)}   (straight-line fit ${a.schumacher.fit.toFixed(2)})`);
  }
  if (a.chao !== null) {
    out.push(`  ${'Chao, uneven catchability'.padEnd(34)} ${fmt(a.chao).padStart(6)}   (at least this many)`);
  }
  out.push('');
  out.push('Checks');
  for (const c of a.checks) out.push(`  ${c.level === 'ok' ? 'ok  ' : 'WARN'}  ${c.text}`);
  if (a.frequencies) {
    const [o, e] = [a.frequencies.observed, a.frequencies.expected];
    out.push(`        caught once / twice / 3+ times: ${o.join(' / ')}  (expected ${e.map((x) => x.toFixed(1)).join(' / ')})`);
  }
  if (a.plans.length) {
    out.push('');
    out.push(`Planning a fresh two-session survey (if the population is about ${fmt(a.schnabel.N)})`);
    for (const p of a.plans) {
      out.push(
        `  within +/-${Math.round(p.precision * 100)}%: mark ${p.mark}, then catch ${p.mark} (about ${Math.round(p.recaptures)} recaptures expected)`,
      );
    }
  }
  return out.join('\n') + '\n';
}

/** JSON-safe copy (Infinity becomes null). @param {ReturnType<typeof analyse>} a */
export function toJSON(a) {
  return JSON.stringify(a, (_k, v) => (typeof v === 'number' && !Number.isFinite(v) ? null : v), 2) + '\n';
}
