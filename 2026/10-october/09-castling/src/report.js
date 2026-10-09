// Prints the casting plan. Every name in it passed the parser's allow-list.

import { formatTime } from './parse.js';

/**
 * @typedef {import('./parse.js').Play} Play
 * @typedef {import('./plan.js').Casting} Casting
 */

/** @param {number} seconds */
const spareText = (seconds) => (Number.isFinite(seconds) ? `${formatTime(seconds)} spare` : 'no changes');

/**
 * @param {Play} play
 * @param {Casting} result
 * @param {{ warn: number }} options  changes with less spare time than this are flagged
 * @returns {{ text: string, problems: number }}
 */
export function report(play, result, options) {
  const out = [];
  const problems = [];
  const { tl } = result;

  out.push(`CASTLING  ${play.title}`);
  out.push(
    `${tl.scenes.length} scenes, ${play.roles.length} roles, running time ${formatTime(tl.runningTime)}` +
      (tl.intervals ? ` including ${tl.intervals} interval${tl.intervals > 1 ? 's' : ''}` : ''),
  );
  out.push('');

  const why = result.clique.map((g) => g.join('+')).join(', ');
  out.push(
    `Smallest cast: ${result.minimum} actor${result.minimum === 1 ? '' : 's'}` +
      (result.minimumProven ? ' (proven minimum)' : ' (best found; the search hit its limit)'),
  );
  out.push(`  These ${result.clique.length} all clash with each other, so each needs their own actor:`);
  out.push(`  ${why}`);
  out.push('');

  if (!result.feasible) {
    out.push(`A cast of ${result.actors} is not enough: at least ${result.minimum} are needed.`);
    problems.push(`${result.actors} actors can't cover every role. Cut or merge a role among: ${why}.`);
  } else {
    const safety = result.safety;
    out.push(
      (result.plan.length === result.actors
        ? `Plan for ${result.actors} actors`
        : `Plan using ${result.plan.length} of your ${result.actors} actors`) +
        (Number.isFinite(safety) ? ` (the safest: every costume change has at least ${formatTime(safety)} to spare)` : ''),
    );
    const width = Math.max(...result.plan.map((a) => a.roles.join(' + ').length), 10);
    result.plan.forEach((actor, i) => {
      const roles = actor.roles.join(' + ').padEnd(width);
      let line = `  Actor ${String(i + 1).padStart(2)}  ${roles}  ${spareText(actor.spare)}`;
      const t = actor.tightest;
      if (t) line += `  (${t.from} ${t.fromScene} -> ${t.to} ${t.toScene})`;
      out.push(line);
    });
    const tight = result.plan.filter((a) => a.spare < options.warn && a.tightest);
    if (tight.length) {
      out.push('');
      out.push(`Quick changes (under ${formatTime(options.warn)} spare): plan a dresser and a rehearsed change`);
      for (const actor of tight) {
        const t = actor.tightest;
        if (!t) continue;
        out.push(
          `  ${t.from} -> ${t.to} before scene ${t.toScene}: ${formatTime(t.gap)} offstage for a ${formatTime(t.needed)} change`,
        );
        problems.push(`Quick change from ${t.from} to ${t.to} before scene ${t.toScene} has only ${formatTime(actor.spare)} spare.`);
      }
    }
  }

  if (result.budgetHit) out.push('', 'Note: the search hit its step limit, so a better plan may exist.');

  out.push('');
  if (problems.length) {
    out.push(`${problems.length} problem${problems.length === 1 ? '' : 's'}:`);
    for (const p of problems) out.push(`  - ${p}`);
  } else {
    out.push('No problems found.');
  }
  return { text: out.join('\n') + '\n', problems: problems.length };
}
