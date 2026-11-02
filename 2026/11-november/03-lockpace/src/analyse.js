// What a room asks of a team: which puzzles matter, where it can strand players, how long each
// team size takes, where players stand about, and when a game master should give a hint.
// All times are integer tenths of a minute, so no rounding decides between two plans.

/** @typedef {import('./parse.js').Room} Room @typedef {import('./parse.js').Puzzle} Puzzle */

/**
 * @typedef {{ puzzle: number, start: number, end: number, players: number[] }} Segment
 * @typedef {{ players: number, finish: number | null, stuck: string | null, segments: Segment[],
 *             work: number, idle: number, wait: { length: number, puzzle: number } }} Run
 */

/** Items the room starts with, as counts. @param {Room} room */
function startCounts(room) {
  /** @type {Map<string, number>} */
  const counts = new Map();
  for (const it of room.start) counts.set(it, 1);
  return counts;
}

/** Puzzles that can ever be solved, ignoring how many of each item there are. @param {Room} room */
export function reachable(room) {
  const have = new Set(room.start);
  const done = new Set();
  for (let changed = true; changed; ) {
    changed = false;
    room.puzzles.forEach((p, i) => {
      if (done.has(i) || ![...p.needs, ...p.uses].every((it) => have.has(it))) return;
      done.add(i);
      for (const it of p.gives) have.add(it);
      changed = true;
    });
  }
  return { puzzles: done, items: have };
}

/** Puzzles on some route to the goal: those giving it, and those giving what they need. @param {Room} room */
export function required(room) {
  const need = [room.goal];
  const seenItems = new Set(need);
  const out = new Set();
  while (need.length) {
    const it = /** @type {string} */ (need.pop());
    room.puzzles.forEach((p, i) => {
      if (!p.gives.includes(it) || out.has(i)) return;
      out.add(i);
      for (const x of [...p.needs, ...p.uses]) if (!seenItems.has(x)) seenItems.add(x), need.push(x);
    });
  }
  return out;
}

/**
 * Longest chain of puzzle time from each puzzle to the goal ("tail"), over the puzzles in `among`.
 * A puzzle's successors are the puzzles that need or use something it gives.
 * @param {Room} room @param {Set<number>} among
 */
export function tails(room, among) {
  /** @type {Map<number, number>} */
  const memo = new Map();
  const onStack = new Set();
  /** @param {number} i @returns {number} */
  const tail = (i) => {
    const cached = memo.get(i);
    if (cached !== undefined) return cached;
    onStack.add(i);
    const p = room.puzzles[i];
    let after = 0;
    for (const j of among) {
      if (onStack.has(j)) continue; // a loop of items: ignore the back edge
      const q = room.puzzles[j];
      if ([...q.needs, ...q.uses].some((it) => p.gives.includes(it))) after = Math.max(after, tail(j));
    }
    onStack.delete(i);
    const t = p.time + (p.gives.includes(room.goal) ? 0 : after);
    memo.set(i, t);
    return t;
  };
  for (const i of among) tail(i);
  return memo;
}

/** Problems a designer should know about. @param {Room} room */
export function warnings(room) {
  const out = [];
  const reach = reachable(room);
  const req = required(room);
  if (!reach.items.has(room.goal)) out.push(`The goal (${room.goal}) can never be reached: no chain of puzzles leads to it.`);
  room.puzzles.forEach((p, i) => {
    if (!reach.puzzles.has(i)) {
      const missing = [...p.needs, ...p.uses].filter((it) => !reach.items.has(it));
      out.push(`${p.name} can never be solved: nothing gives ${missing.join(', ')}.`);
    } else if (!req.has(i)) {
      out.push(`${p.name} isn't needed to escape (nothing on the way to the goal uses what it gives).`);
    }
  });
  // Items that get used up: if more puzzles use one than there are of it, solving the wrong
  // puzzle first strands the team.
  const supply = startCounts(room);
  for (const p of room.puzzles) for (const it of p.gives) supply.set(it, (supply.get(it) ?? 0) + 1);
  /** @type {Map<string, string[]>} */
  const users = new Map();
  for (const p of room.puzzles) for (const it of p.uses) users.set(it, [...(users.get(it) ?? []), p.name]);
  for (const [it, who] of users) {
    const have = supply.get(it) ?? 0;
    if (have > 0 && who.length > have) {
      out.push(`Dead end: ${who.join(' and ')} each use up the ${it}, but only ${have} exist${have === 1 ? 's' : ''}; using it in the wrong place first strands the team.`);
    }
  }
  const wanted = new Set([room.goal]);
  for (const p of room.puzzles) for (const it of [...p.needs, ...p.uses]) wanted.add(it);
  const herrings = new Set();
  for (const p of room.puzzles) for (const it of p.gives) if (!wanted.has(it)) herrings.add(it);
  if (herrings.size) out.push(`Never used anywhere (red herrings?): ${[...herrings].join(', ')}.`);
  return out;
}

/**
 * Plays the room with `k` players. Whenever players are free, they start the waiting puzzle
 * with the longest chain still to go after it (critical-path list scheduling).
 * @param {Room} room @param {number} k players (Infinity for "as many as it takes")
 * @returns {Run}
 */
export function play(room, k) {
  const req = required(room);
  const tail = tails(room, req);
  const order = [...req].sort((a, b) => /** @type {number} */ (tail.get(b)) - /** @type {number} */ (tail.get(a)) || a - b);
  const counts = startCounts(room);
  const free = Number.isFinite(k) ? Array.from({ length: k }, (_, i) => i) : [];
  let freeCount = Number.isFinite(k) ? k : Infinity;
  /** @type {Segment[]} */
  const segments = [];
  /** @type {Segment[]} */
  let running = [];
  const started = new Set();
  let time = 0;
  let work = 0;
  let wait = { length: 0, puzzle: -1 };
  for (;;) {
    for (const i of order) {
      const p = room.puzzles[i];
      if (started.has(i) || p.crew > freeCount) continue;
      if (![...p.needs, ...p.uses].every((it) => (counts.get(it) ?? 0) > 0)) continue;
      for (const it of p.uses) counts.set(it, /** @type {number} */ (counts.get(it)) - 1);
      started.add(i);
      const players = Number.isFinite(k) ? free.splice(0, p.crew) : [];
      freeCount -= p.crew;
      /** @type {Segment} */
      const seg = { puzzle: i, start: time, end: time + p.time, players };
      segments.push(seg);
      running.push(seg);
      work += p.time * p.crew;
    }
    if (!running.length) {
      const stuckOn = order.filter((i) => !started.has(i)).map((i) => room.puzzles[i]);
      const tooBig = stuckOn.find((p) => p.crew > k);
      const stuck = tooBig ? `${tooBig.name} needs ${tooBig.crew} people` : 'the team runs out of puzzles it can start';
      return { players: k, finish: null, stuck, segments, work, idle: 0, wait };
    }
    const next = Math.min(...running.map((s) => s.end));
    // A whole team waiting on a single puzzle is the moment players get bored.
    if (running.length === 1 && Number.isFinite(k) && k > running[0].players.length && next - time > wait.length) {
      wait = { length: next - time, puzzle: running[0].puzzle };
    }
    time = next;
    const finished = running.filter((s) => s.end === time);
    running = running.filter((s) => s.end !== time);
    for (const s of finished) {
      freeCount += room.puzzles[s.puzzle].crew;
      free.push(...s.players);
      free.sort((a, b) => a - b);
      for (const it of room.puzzles[s.puzzle].gives) counts.set(it, (counts.get(it) ?? 0) + 1);
    }
    if ((counts.get(room.goal) ?? 0) > 0) {
      const idle = Number.isFinite(k) ? k * time - work : 0;
      return { players: k, finish: time, stuck: null, segments, work, idle, wait };
    }
  }
}

/** Every team size in the room's range, plus the unlimited case that bounds them all. @param {Room} room */
export function analyse(room) {
  const unlimited = play(room, Infinity);
  const runs = [];
  for (let k = room.minPlayers; k <= room.maxPlayers; k++) {
    const run = play(room, k);
    const bound = unlimited.finish === null ? null : Math.max(unlimited.finish, Math.ceil(unlimited.work / k));
    runs.push({ run, bound });
  }
  // Latest start for each needed puzzle that can still beat the clock, even with unlimited players.
  const req = required(room);
  const tail = tails(room, req);
  const limit = room.limit * 10;
  const deadlines = [...req]
    .map((i) => ({ puzzle: i, latest: limit - /** @type {number} */ (tail.get(i)) }))
    .sort((a, b) => a.latest - b.latest || a.puzzle - b.puzzle);
  return { unlimited, runs, deadlines, warnings: warnings(room) };
}
