// Graph colouring: roles are vertices, an edge means "can't be the same
// actor", and each colour is one actor. The fewest colours is the smallest
// cast. Both searches below are exact but carry a step budget, so a hostile
// input can never make them run for ever.

export const DEFAULT_BUDGET = 1_000_000;

/**
 * @typedef {boolean[][]} Graph adjacency matrix: graph[u][v] is true if u and v clash
 * @typedef {{ colours: number[], count: number, complete: boolean }} Colouring
 */

/**
 * Smallest colouring, by DSatur branch and bound: always colour next the
 * vertex whose neighbours already use the most different colours, because
 * it has the fewest options left and fails soonest.
 *
 * @param {Graph} graph
 * @param {{ lowerBound?: number, maxColours?: number, budget?: number }} [options]
 *   maxColours: give up on colourings that need more than this.
 * @returns {Colouring & { proven: boolean }}
 *   proven: the count is the true minimum (or no colouring within maxColours exists if count is 0).
 */
export function minimumColouring(graph, options = {}) {
  const n = graph.length;
  const lowerBound = options.lowerBound ?? 1;
  const maxColours = options.maxColours ?? n;
  let budget = options.budget ?? DEFAULT_BUDGET;
  const degree = graph.map((row) => row.filter(Boolean).length);

  const colour = new Array(n).fill(-1);
  /** neighbourCount[v][c]: how many neighbours of v have colour c */
  const neighbourCount = graph.map(() => new Array(n + 1).fill(0));
  const saturation = new Array(n).fill(0);

  let best = maxColours + 1; // colourings must use fewer than this
  /** @type {number[]} */
  let bestColours = [];
  let exhausted = false;

  /** @param {number} v @param {number} c @param {number} delta */
  const paint = (v, c, delta) => {
    colour[v] = delta > 0 ? c : -1;
    for (let u = 0; u < n; u++) {
      if (!graph[v][u]) continue;
      const before = neighbourCount[u][c];
      neighbourCount[u][c] += delta;
      if (before === 0 && delta > 0) saturation[u]++;
      if (before === 1 && delta < 0) saturation[u]--;
    }
  };

  /** @param {number} done @param {number} used */
  const search = (done, used) => {
    if (--budget < 0) {
      exhausted = true;
      return;
    }
    if (done === n) {
      best = used;
      bestColours = colour.slice();
      return;
    }
    let v = -1;
    for (let u = 0; u < n; u++)
      if (colour[u] < 0 && (v < 0 || saturation[u] > saturation[v] || (saturation[u] === saturation[v] && degree[u] > degree[v])))
        v = u;
    // Existing colours first, then (only if it could still beat the best) one new colour.
    for (let c = 0; c <= used && c < best - 1; c++) {
      if (neighbourCount[v][c] > 0) continue;
      paint(v, c, +1);
      search(done + 1, Math.max(used, c + 1));
      paint(v, c, -1);
      if (exhausted || best <= lowerBound) return;
    }
  };

  if (n === 0) return { colours: [], count: 0, complete: true, proven: true };
  search(0, 0);
  const found = bestColours.length === n;
  return {
    colours: found ? bestColours : [],
    count: found ? best : 0,
    complete: found,
    proven: !exhausted,
  };
}

/**
 * Largest group of vertices that all clash with each other (a clique).
 * Every one of them needs a different actor, so its size is a lower bound
 * on the cast, and it is the clearest way to explain that bound.
 *
 * @param {Graph} graph
 * @param {number} [budget]
 * @returns {{ members: number[], proven: boolean }}
 */
export function largestClique(graph, budget = DEFAULT_BUDGET) {
  const n = graph.length;
  /** @type {number[]} */
  let best = [];
  let steps = budget;
  let exhausted = false;

  /** @param {number[]} chosen @param {number[]} candidates */
  const grow = (chosen, candidates) => {
    if (--steps < 0) {
      exhausted = true;
      return;
    }
    if (candidates.length === 0) {
      if (chosen.length > best.length) best = chosen.slice();
      return;
    }
    for (let i = 0; i < candidates.length; i++) {
      if (chosen.length + candidates.length - i <= best.length) return; // can't beat the best any more
      const v = candidates[i];
      chosen.push(v);
      grow(chosen, candidates.slice(i + 1).filter((u) => graph[v][u]));
      chosen.pop();
      if (exhausted) return;
    }
  };

  // Highest-degree vertices first finds big cliques early, which prunes more.
  const order = [...Array(n).keys()].sort((a, b) => graph[b].filter(Boolean).length - graph[a].filter(Boolean).length);
  grow([], order);
  return { members: best, proven: !exhausted };
}
