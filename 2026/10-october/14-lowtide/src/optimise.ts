// Choosing new due days for the movable bills: first, keep the balance above the buffer
// (or as close to it as possible), moving as few bills as possible; then, among those,
// the highest low tide and the smallest moves.
//
// Branch and bound: bills are decided one at a time. At any point, the best low tide
// still possible is at most min over days of (balance so far − the least each undecided
// bill could have taken out by that day), so branches that can't beat the best plan
// found so far are skipped.
import { flows, occurrences } from './ledger.js';
import type { Item, Plan } from './plan.js';

export const CHOICES = 28; // days 1-28 exist in every month, so billers allow them
export const NODE_LIMIT = 2_000_000;

export interface Move {
  item: Item;
  from: number; // day of the month
  to: number;
}

export interface Result {
  moves: Move[]; // only the bills that change day
  days: number[]; // chosen day for every movable bill, in plan order
  lowTide: number;
  lowDay: number;
  exhaustive: boolean; // false if the search stopped at NODE_LIMIT
  nodes: number;
}

// Cumulative cents a bill has taken out by the end of each day, if due on `dom`.
function cumulative(item: Item, dom: number, plan: Plan): Float64Array {
  const out = new Float64Array(plan.days);
  for (const d of occurrences({ every: 'month', on: dom }, plan.start, plan.days)) out[d]! += item.cents;
  for (let d = 1; d < plan.days; d++) out[d]! += out[d - 1]!;
  return out;
}

export function optimise(plan: Plan): Result {
  const movable = plan.items.filter((it) => it.movable);
  const fixed = plan.items.filter((it) => !it.movable);
  const T = plan.days;

  // The lowest balance each day from everything that can't move.
  const f = flows(fixed, plan);
  const base = new Float64Array(T);
  let bal = plan.balance;
  for (let d = 0; d < T; d++) {
    bal -= f.out[d]!;
    base[d] = bal;
    bal += f.in[d]!;
  }

  // For each movable bill (biggest first: they matter most), every choice of day.
  const order = movable.map((_, i) => i).sort((a, b) => movable[b]!.cents - movable[a]!.cents);
  const original = movable.map((it) => (it.schedule as { on: number }).on);
  const cum = movable.map((it) => Array.from({ length: CHOICES }, (_, k) => cumulative(it, k + 1, plan)));
  // The least each bill can have taken out by each day, whatever day it's moved to;
  // rest[i] sums that over the bills decided after position i.
  // (A bill now due on the 29th-31st may also stay there, so that counts as a choice too.)
  const least = cum.map((options, k) => {
    const m = new Float64Array(T).fill(Infinity);
    const all = original[k]! > CHOICES ? [...options, cumulative(movable[k]!, original[k]!, plan)] : options;
    for (const c of all) for (let d = 0; d < T; d++) m[d] = Math.min(m[d]!, c[d]!);
    return m;
  });
  const rest: Float64Array[] = Array.from({ length: order.length + 1 }, () => new Float64Array(T));
  for (let i = order.length - 1; i >= 0; i--) {
    for (let d = 0; d < T; d++) rest[i]![d] = rest[i + 1]![d]! + least[order[i]!]![d]!;
  }

  let best = { low: -Infinity, moved: Infinity, shift: Infinity, days: original.slice() };
  const chosen = original.slice();
  let nodes = 0;
  let exhaustive = true;

  // What makes one plan better than another, in order: staying above the buffer (how far
  // below it, if not), then moving fewer bills, then a higher low tide, then smaller moves.
  // Every part of a branch's bound is optimistic, so comparing the bound is a safe prune.
  const capped = (low: number) => Math.min(low, plan.buffer);
  const better = (low: number, moved: number, shift: number) => {
    if (capped(low) !== capped(best.low)) return capped(low) > capped(best.low);
    if (moved !== best.moved) return moved < best.moved;
    if (low !== best.low) return low > best.low;
    return shift < best.shift;
  };

  const search = (i: number, current: Float64Array, moved: number, shift: number): void => {
    if (++nodes > NODE_LIMIT) {
      exhaustive = false;
      return;
    }
    let bound = Infinity;
    for (let d = 0; d < T; d++) bound = Math.min(bound, current[d]! - rest[i]![d]!);
    if (!better(bound, moved, shift)) return; // nothing down this branch can win
    if (i === order.length) {
      best = { low: bound, moved, shift, days: chosen.slice() };
      return;
    }
    const b = order[i]!;
    const home = original[b]!;
    // Try the bill's own day first, then the days nearest to it, so good plans are found early.
    const others = Array.from({ length: CHOICES }, (_, k) => k + 1)
      .filter((d) => d !== home)
      .sort((x, y) => Math.abs(x - home) - Math.abs(y - home) || x - y);
    for (const day of [home, ...others]) {
      // A bill left on the 29th-31st isn't in the table of choices, so work it out.
      const c = day > CHOICES ? cumulative(movable[b]!, day, plan) : cum[b]![day - 1]!;
      const next = new Float64Array(T);
      for (let d = 0; d < T; d++) next[d] = current[d]! - c[d]!;
      chosen[b] = day;
      search(i + 1, next, moved + (day === home ? 0 : 1), shift + Math.abs(day - home));
      if (!exhaustive) break;
    }
    chosen[b] = home;
  };
  search(0, base, 0, 0);

  // Recompute the result from scratch with the chosen days, as an independent check.
  const items = plan.items.map((it) => {
    const k = movable.indexOf(it);
    return k < 0 ? it : { ...it, schedule: { every: 'month' as const, on: best.days[k]! } };
  });
  const g = flows(items, plan);
  let balance = plan.balance;
  let lowTide = Infinity;
  let lowDay = 0;
  for (let d = 0; d < T; d++) {
    balance -= g.out[d]!;
    if (balance < lowTide) {
      lowTide = balance;
      lowDay = d;
    }
    balance += g.in[d]!;
  }
  const moves = movable
    .map((item, k) => ({ item, from: original[k]!, to: best.days[k]! }))
    .filter((m) => m.from !== m.to);
  return { moves, days: best.days, lowTide, lowDay, exhaustive, nodes };
}
