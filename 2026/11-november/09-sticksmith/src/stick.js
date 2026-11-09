// Chooses a hand for every note: the cheapest sticking that two real hands can play in time.
//
// A dynamic programme over the notes. After note i, the state is: which hand played it and on
// which drum, where the other hand is and when it last played (forgotten once it is long enough
// ago to make no difference), and whether either hand has just played the fast second stroke of
// a double. Every constraint is a minimum time between strokes, so the search is exact.

import { TEMPO } from './parse.js';

/** @typedef {import('./parse.js').Piece} Piece */
/** @typedef {import('./parse.js').Note} Note */
/** @typedef {'R' | 'L'} Hand */
/** For each note, the hand that plays each of its drums, in the note's drum order. */
/** @typedef {Hand[][]} Sticking */
/** @typedef {{ double: boolean, crossover: boolean, weakBeat: boolean, move: number }} Tags */

/** Speeds of a player's hands, in seconds. */
export const PLAYERS = Object.freeze({
  beginner: { single: 0.17, double: 0.09, move: 0.08, perMetre: 0.18 },
  average: { single: 0.12, double: 0.065, move: 0.05, perMetre: 0.12 },
  fast: { single: 0.095, double: 0.05, move: 0.04, perMetre: 0.09 },
});

/** What each awkward thing costs, in "metres of hand movement". */
export const COSTS = Object.freeze({ perMetre: 1, rush: 1.5, double: 0.8, crossover: 2, weak: 0.25, weakBeat: 1, reach: 2 });
/** The weaker hand plays freely up to this far (metres) past the middle of the kit towards the lead side. */
const REACH_FREE = 0.3;
/** A crossover costs in full when the hands must pass within this many seconds, less up to twice that. */
const CROSS_WINDOW = 0.4;

/** Past this many seconds, a hand's last stroke can no longer limit anything. */
const HORIZON = 1.5;
/** Safety bound on the size of the search at one note. */
export const MAX_STATES = 60000;

/** @typedef {{ drum: string | null, last: number, fast: boolean }} HandState */

/**
 * Can a hand at `h` play `drum` at time `t`, and at what cost?
 * @param {HandState} h @param {string} drum @param {number} t
 * @param {(d: string) => number} xOf @param {typeof PLAYERS.average} speed @param {number[]} times
 * @returns {{ ok: false, why: string } | { ok: true, cost: number, fast: boolean, move: number }}
 */
function stroke(h, drum, t, xOf, speed, times) {
  const move = h.drum === null ? 0 : Math.abs(xOf(drum) - xOf(h.drum));
  if (h.last < 0) return { ok: true, cost: 0, fast: false, move };
  const gap = t - /** @type {number} */ (times[h.last]);
  // Moving is work when it's quick; a hand with plenty of time gets there for free.
  const cost = COSTS.perMetre * move * Math.min(1, ((2 * speed.single) / gap) ** 2);
  if (h.drum !== drum && gap + 1e-9 < speed.move + speed.perMetre * move) return { ok: false, why: 'move' };
  // A hand is comfortable at up to 55% of its top single-stroke speed; faster is work.
  const rush = COSTS.rush * Math.max(0, (1.8 * speed.single - gap) / speed.single);
  if (gap + 1e-9 >= speed.single) return { ok: true, cost: cost + rush, fast: false, move };
  if (h.drum === drum && !h.fast && gap + 1e-9 >= speed.double) return { ok: true, cost: cost + COSTS.double, fast: true, move };
  return { ok: false, why: h.drum === drum ? 'speed' : 'move' };
}

/**
 * The cost of the whole note beyond its strokes: hands passing each other, the weaker hand
 * playing (a little), reaching far to the lead side (more) or taking a beat on its own (most).
 * Staying crossed is free: a right hand over the left on the hi-hat is how most people play.
 * @param {-1 | 0 | 1 | null} before @param {-1 | 0 | 1 | null} after @param {number} gap seconds since the previous note
 * @param {Note} note @param {Hand[]} who @param {Hand} lead @param {(d: string) => number} xOf @param {number} centre
 */
function noteCost(before, after, gap, note, who, lead, xOf, centre) {
  let cost = 0;
  const side = lead === 'R' ? 1 : -1;
  who.forEach((hand, k) => {
    if (hand !== lead) cost += COSTS.weak + COSTS.reach * Math.max(0, side * (xOf(/** @type {string} */ (note.drums[k])) - centre) - REACH_FREE);
  });
  // The hands pass each other only when they swap sides outright.
  const crossover = before !== null && after !== null && before * after === -1;
  if (crossover) cost += COSTS.crossover * Math.min(1, Math.max(0, (2 * CROSS_WINDOW - gap) / CROSS_WINDOW));
  const weakBeat = note.onBeat && who.length === 1 && who[0] !== lead;
  if (weakBeat) cost += COSTS.weakBeat;
  return { cost, crossover, weakBeat };
}

/**
 * Which way round are the hands? 1 if the right hand is to the left of the left hand (crossed),
 * -1 if it is to the right (open), 0 if they share a drum's position, null if either hand
 * hasn't played yet.
 * @param {string | null} r @param {string | null} l @param {(d: string) => number} xOf
 * @returns {-1 | 0 | 1 | null}
 */
function crossed(r, l, xOf) {
  if (r === null || l === null) return null;
  const d = xOf(l) - xOf(r);
  return d > 1e-9 ? 1 : d < -1e-9 ? -1 : 0;
}

/**
 * Plays a fixed sticking and adds up its cost exactly as the search does.
 * @param {Piece} piece @param {Sticking} sticking @param {{ tempo?: number, player?: keyof typeof PLAYERS }} [opts]
 * @returns {{ ok: true, cost: number, tags: Tags[] } | { ok: false, at: number, why: string }}
 */
export function evaluate(piece, sticking, opts = {}) {
  const { times, xOf, speed, centre } = setup(piece, opts);
  /** @type {Record<Hand, HandState>} */
  const hands = { R: { drum: null, last: -1, fast: false }, L: { drum: null, last: -1, fast: false } };
  let cost = 0;
  /** @type {Tags[]} */
  const tags = [];
  for (const note of piece.notes) {
    const i = note.index;
    const who = sticking[i];
    if (!who || who.length !== note.drums.length || (who.length === 2 && who[0] === who[1])) return { ok: false, at: i, why: 'hands' };
    for (const hand of /** @type {Hand[]} */ (['R', 'L'])) {
      const h = hands[hand];
      if (h.last >= 0 && /** @type {number} */ (times[i]) - /** @type {number} */ (times[h.last]) > HORIZON) hands[hand] = { drum: h.drum, last: -1, fast: false };
    }
    const before = crossed(hands.R.drum, hands.L.drum, xOf);
    let double = false;
    let move = 0;
    for (let k = 0; k < who.length; k++) {
      const hand = /** @type {Hand} */ (who[k]);
      const drum = /** @type {string} */ (note.drums[k]);
      const s = stroke(hands[hand], drum, /** @type {number} */ (times[i]), xOf, speed, times);
      if (!s.ok) return { ok: false, at: i, why: s.why };
      cost += s.cost;
      double ||= s.fast;
      move += s.move;
      hands[hand] = { drum, last: i, fast: s.fast };
    }
    const after = crossed(hands.R.drum, hands.L.drum, xOf);
    const gap = i === 0 ? Infinity : /** @type {number} */ (times[i]) - /** @type {number} */ (times[i - 1]);
    const extra = noteCost(before, after, gap, note, who, piece.lead, xOf, centre);
    cost += extra.cost;
    tags.push({ double, crossover: extra.crossover, weakBeat: extra.weakBeat, move });
  }
  return { ok: true, cost, tags };
}

/** @param {Piece} piece @param {{ tempo?: number, player?: keyof typeof PLAYERS }} opts */
function setup(piece, opts) {
  const tempo = opts.tempo ?? piece.tempo;
  if (!(tempo >= TEMPO.min && tempo <= TEMPO.max)) throw new RangeError(`tempo must be between ${TEMPO.min} and ${TEMPO.max}`);
  const speed = PLAYERS[opts.player ?? 'average'];
  if (!speed) throw new RangeError('unknown player');
  const times = piece.notes.map((n) => (n.beat * 60) / tempo);
  /** @param {string} d */
  const xOf = (d) => /** @type {import('./parse.js').Drum} */ (piece.kit.get(d)).x;
  // The middle of the kit: the median position of the drums the hands play.
  const xs = [...piece.kit.values()].filter((d) => !d.foot).map((d) => d.x).sort((a, b) => a - b);
  const centre = xs.length % 2 ? /** @type {number} */ (xs[(xs.length - 1) / 2]) : (/** @type {number} */ (xs[xs.length / 2 - 1]) + /** @type {number} */ (xs[xs.length / 2])) / 2;
  return { times, xOf, speed, centre };
}

/**
 * The search state after a note: `h` played it on `hd`; the other hand is on `od` and last played
 * note `ol` (-1 if long ago or never); `hf`/`of` mark a just-played fast double stroke.
 * @typedef {{ h: Hand, hd: string, od: string | null, ol: number, hf: boolean, of: boolean }} State
 */

/** @param {State} s */
const keyOf = (s) => `${s.h}|${s.hd}|${s.od}|${s.ol}|${s.hf ? 1 : 0}|${s.of ? 1 : 0}`;

/**
 * Finds the cheapest playable sticking.
 * @param {Piece} piece @param {{ tempo?: number, player?: keyof typeof PLAYERS }} [opts]
 * @returns {{ ok: true, cost: number, sticking: Sticking } | { ok: false, at: number }}
 */
export function solve(piece, opts = {}) {
  const { times, xOf, speed, centre } = setup(piece, opts);
  const notes = piece.notes;
  /** @typedef {{ state: State, cost: number, prev: string | null, who: Hand[] }} Entry */
  /** @type {Map<string, Entry>[]} */
  const layers = [];
  /** @type {Map<string, Entry>} */
  let current = new Map();
  const other = (/** @type {Hand} */ h) => (h === 'R' ? 'L' : 'R');

  for (const note of notes) {
    const i = note.index;
    const t = /** @type {number} */ (times[i]);
    /** @type {Map<string, Entry>} */
    const next = new Map();
    /** @param {State} state @param {number} cost @param {string | null} prev @param {Hand[]} who */
    const offer = (state, cost, prev, who) => {
      const k = keyOf(state);
      const old = next.get(k);
      if (!old || cost < old.cost - 1e-12) next.set(k, { state, cost, prev, who });
    };
    /** @type {[string | null, Entry | null][]} */
    const sources = i === 0 ? [[null, null]] : [...current.entries()];
    for (const [prevKey, entry] of sources) {
      // Rebuild both hands from the compact state.
      /** @type {Record<Hand, HandState>} */
      const hands = { R: { drum: null, last: -1, fast: false }, L: { drum: null, last: -1, fast: false } };
      if (entry) {
        const s = entry.state;
        hands[s.h] = { drum: s.hd, last: i - 1, fast: s.hf };
        hands[other(s.h)] = { drum: s.od, last: s.ol, fast: s.of };
      }
      for (const hand of /** @type {Hand[]} */ (['R', 'L'])) {
        const h = hands[hand];
        if (h.last >= 0 && t - /** @type {number} */ (times[h.last]) > HORIZON) hands[hand] = { drum: h.drum, last: -1, fast: false };
      }
      const before = crossed(hands.R.drum, hands.L.drum, xOf);
      const gap = i === 0 ? Infinity : t - /** @type {number} */ (times[i - 1]);
      const base = entry ? entry.cost : 0;
      /** @type {Hand[][]} */
      const choices = note.drums.length === 1 ? [['R'], ['L']] : [['R', 'L'], ['L', 'R']];
      for (const who of choices) {
        let cost = base;
        /** @type {Record<Hand, HandState>} */
        const after = { R: { ...hands.R }, L: { ...hands.L } };
        let ok = true;
        for (let k = 0; k < who.length && ok; k++) {
          const hand = /** @type {Hand} */ (who[k]);
          const drum = /** @type {string} */ (note.drums[k]);
          const s = stroke(hands[hand], drum, t, xOf, speed, times);
          if (!s.ok) ok = false;
          else { cost += s.cost; after[hand] = { drum, last: i, fast: s.fast }; }
        }
        if (!ok) continue;
        cost += noteCost(before, crossed(after.R.drum, after.L.drum, xOf), gap, note, who, piece.lead, xOf, centre).cost;
        const h = who.length === 1 ? /** @type {Hand} */ (who[0]) : 'R';
        const o = other(h);
        offer(
          { h, hd: /** @type {string} */ (after[h].drum), od: after[o].drum, ol: after[o].last, hf: after[h].fast, of: after[o].fast },
          cost,
          prevKey,
          who,
        );
      }
    }
    if (next.size === 0) return { ok: false, at: i };
    if (next.size > MAX_STATES) throw new RangeError('this passage is too complex to search');
    layers.push(next);
    current = next;
  }

  let bestKey = '';
  let best = Infinity;
  for (const [k, e] of current) if (e.cost < best) { best = e.cost; bestKey = k; }
  /** @type {Sticking} */
  const sticking = new Array(notes.length);
  /** @type {string | null} */
  let k = bestKey;
  for (let i = notes.length - 1; i >= 0; i--) {
    const e = /** @type {Entry} */ (/** @type {Map<string, Entry>} */ (layers[i]).get(/** @type {string} */ (k)));
    sticking[i] = e.who;
    k = e.prev;
  }
  return { ok: true, cost: best, sticking };
}

/**
 * Plain alternating sticking, starting with the lead hand; a two-hand note resets it.
 * @param {Piece} piece @returns {Sticking}
 */
export function alternating(piece) {
  /** @type {Hand} */
  let next = piece.lead;
  return piece.notes.map((n) => {
    if (n.drums.length === 2) {
      next = piece.lead;
      // The usual way: the lead hand keeps the hi-hat; otherwise each hand takes the drum on its side.
      const [a, b] = /** @type {[string, string]} */ (n.drums);
      const xa = /** @type {import('./parse.js').Drum} */ (piece.kit.get(a)).x;
      const xb = /** @type {import('./parse.js').Drum} */ (piece.kit.get(b)).x;
      const aGoesRight = a === 'hh' ? piece.lead === 'R' : b === 'hh' ? piece.lead !== 'R' : xa >= xb;
      return /** @type {Hand[]} */ (aGoesRight ? ['R', 'L'] : ['L', 'R']);
    }
    const h = next;
    next = h === 'R' ? 'L' : 'R';
    return [h];
  });
}

/**
 * The fastest whole-number tempo at which `play(tempo)` still succeeds, or null if none does.
 * Every limit is a minimum time between strokes, so playability only gets harder as tempo rises.
 * @param {(tempo: number) => boolean} play
 */
export function fastestTempo(play) {
  if (!play(TEMPO.min)) return null;
  if (play(TEMPO.max)) return TEMPO.max;
  /** @type {number} */
  let lo = TEMPO.min;
  /** @type {number} */
  let hi = TEMPO.max;
  while (hi - lo > 1) {
    const mid = Math.floor((lo + hi) / 2);
    if (play(mid)) lo = mid;
    else hi = mid;
  }
  return lo;
}
