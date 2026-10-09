// Turns a play into a casting plan.
//
// 1. Merge "together" roles into one group each (they are one actor).
// 2. Work out, for every pair of groups, whether one actor could play both
//    and how much spare time their tightest costume change would have.
// 3. Colour the clash graph with as few colours (actors) as possible.
// 4. Among plans with that many actors, find the safest: raise a threshold
//    of required spare time as far as it can go while the cast still fits.

import { largestClique, minimumColouring } from './colour.js';
import { PlayError } from './parse.js';
import { pairing, timeline } from './timeline.js';

/**
 * @typedef {import('./parse.js').Play} Play
 * @typedef {import('./timeline.js').Change} Change
 * @typedef {{ roles: string[], spare: number, tightest: Change | null }} Actor
 * @typedef {{
 *   tl: ReturnType<typeof timeline>, groups: string[][], minimum: number, minimumProven: boolean,
 *   clique: string[][], actors: number, feasible: boolean, plan: Actor[], safety: number, budgetHit: boolean
 * }} Casting
 */

/** @param {Play} play */
function groupRoles(play) {
  /** @type {Map<string, string>} */
  const parent = new Map(play.roles.map((r) => [r, r]));
  /** @param {string} r @returns {string} */
  const find = (r) => {
    let root = r;
    while (parent.get(root) !== root) root = /** @type {string} */ (parent.get(root));
    parent.set(r, root);
    return root;
  };
  for (const [a, b] of play.together) parent.set(find(a), find(b));
  /** @type {Map<string, string[]>} */
  const groups = new Map();
  for (const r of play.roles) {
    const root = find(r);
    if (!groups.has(root)) groups.set(root, []);
    groups.get(root)?.push(r);
  }
  return [...groups.values()];
}

/**
 * @param {Play} play
 * @param {{ actors?: number, budget?: number }} [options]
 * @returns {Casting}
 */
export function cast(play, options = {}) {
  const tl = timeline(play);
  const groups = groupRoles(play);
  const n = groups.length;
  let budgetHit = false;

  // Pair information between individual roles, reused below.
  /** @param {string} a @param {string} b */
  const pair = (a, b) => pairing(play, tl, a, b);

  // Roles meant to be together must really be playable by one actor.
  for (const group of groups)
    for (let i = 0; i < group.length; i++)
      for (let j = i + 1; j < group.length; j++) {
        const p = pair(group[i], group[j]);
        if (!p.possible) throw new PlayError(`'${group[i]}' and '${group[j]}' are both in scene ${p.sharedScene}, so they can't be together`);
        if (p.spare < 0)
          throw new PlayError(
            `'${group[i]}' and '${group[j]}' can't be together: the change before scene ${p.tightest?.toScene} is too quick`,
          );
      }

  const apart = new Set(play.apart.map(([a, b]) => `${a} ${b}`));
  /** spare[g][h]: tightest spare time if one actor plays groups g and h (-Infinity = never) */
  const spare = groups.map(() => new Array(n).fill(Infinity));
  /** @type {(Change | null)[][]} */
  const tightest = groups.map(() => new Array(n).fill(null));
  for (let g = 0; g < n; g++)
    for (let h = g + 1; h < n; h++) {
      let s = Infinity;
      /** @type {Change | null} */
      let t = null;
      for (const a of groups[g])
        for (const b of groups[h]) {
          if (apart.has(`${a} ${b}`) || apart.has(`${b} ${a}`)) s = -Infinity;
          const p = pair(a, b);
          if (!p.possible) s = -Infinity;
          else if (p.spare < s) {
            s = p.spare;
            t = p.tightest;
          }
        }
      spare[g][h] = spare[h][g] = s;
      tightest[g][h] = tightest[h][g] = t;
    }

  /** Clash graph when every change needs at least `threshold` seconds spare. @param {number} threshold */
  const graphAt = (threshold) => spare.map((row, g) => row.map((s, h) => g !== h && s < threshold));

  const base = graphAt(0);
  const clique = largestClique(base, options.budget);
  budgetHit ||= !clique.proven;
  const lowerBound = Math.max(1, clique.members.length);
  const smallest = minimumColouring(base, { lowerBound, budget: options.budget });
  budgetHit ||= !smallest.proven && smallest.count !== lowerBound;
  const minimum = smallest.count;
  const minimumProven = smallest.count === lowerBound || smallest.proven;

  const actors = options.actors ?? minimum;
  /** @param {number} threshold */
  const tryColour = (threshold) => {
    const result = minimumColouring(graphAt(threshold), { lowerBound: 1, maxColours: actors, budget: options.budget });
    if (!result.proven && !result.complete) budgetHit = true;
    return result.complete ? result : null;
  };

  let chosen = actors >= minimum ? tryColour(0) : null;
  let safety = 0;
  if (chosen) {
    // Binary search over the spare times that actually occur.
    // The last candidate, Infinity, means "no doubling at all beyond the planned ones".
    const candidates = [...new Set(spare.flat().filter((s) => Number.isFinite(s) && s > 0))].sort((a, b) => a - b);
    candidates.push(Infinity);
    let lo = 0;
    let hi = candidates.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const attempt = tryColour(candidates[mid]);
      if (attempt) {
        chosen = attempt;
        safety = candidates[mid];
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
  }

  /** @type {Actor[]} */
  const plan = [];
  if (chosen) {
    const colours = chosen.colours;
    for (let c = 0; c < chosen.count; c++) {
      const members = colours.map((col, g) => (col === c ? g : -1)).filter((g) => g >= 0);
      /** @type {Actor} */
      const actor = { roles: members.flatMap((g) => groups[g]), spare: Infinity, tightest: null };
      for (const g of members) {
        for (const h of members) if (g < h && spare[g][h] < actor.spare) {
          actor.spare = spare[g][h];
          actor.tightest = tightest[g][h];
        }
        // Changes inside a "together" group count too.
        for (let i = 0; i < groups[g].length; i++)
          for (let j = i + 1; j < groups[g].length; j++) {
            const p = pair(groups[g][i], groups[g][j]);
            if (p.possible && p.spare < actor.spare) {
              actor.spare = p.spare;
              actor.tightest = p.tightest;
            }
          }
      }
      plan.push(actor);
    }
    plan.sort((x, y) => y.roles.length - x.roles.length || x.spare - y.spare);
    safety = Math.min(...plan.map((a) => a.spare));
  }

  return {
    tl,
    groups,
    minimum,
    minimumProven,
    clique: clique.members.map((g) => groups[g]),
    actors,
    feasible: chosen !== null,
    plan,
    safety,
    budgetHit,
  };
}
