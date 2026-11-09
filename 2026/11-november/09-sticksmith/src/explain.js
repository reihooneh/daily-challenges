// Turns a solved passage into words: the sticking under each bar, the awkward spots, the
// fastest playable tempo, and how plain alternating would compare.

import { solve, evaluate, alternating, fastestTempo } from './stick.js';

/** @typedef {import('./parse.js').Piece} Piece */
/** @typedef {import('./stick.js').Sticking} Sticking */
/** @typedef {import('./stick.js').Tags} Tags */
/** @typedef {{ tempo?: number, player?: keyof typeof import('./stick.js').PLAYERS }} Options */

/** @param {Piece} piece @param {number} i Position of note i as "bar 2 · 3.2" (beat 3, second subdivision). */
export function where(piece, i) {
  const n = /** @type {import('./parse.js').Note} */ (piece.notes[i]);
  const per = piece.grid / 4;
  return `bar ${n.bar + 1} · ${Math.floor(n.slot / per) + 1}.${(n.slot % per) + 1}`;
}

/** @param {Tags[]} tags */
function summarise(tags) {
  return {
    move: Math.round(tags.reduce((s, t) => s + t.move, 0) * 100) / 100,
    doubles: tags.filter((t) => t.double).length,
    crossovers: tags.filter((t) => t.crossover).length,
    weakBeats: tags.filter((t) => t.weakBeat).length,
  };
}

/**
 * Everything worth saying about a passage, as data.
 * @param {Piece} piece @param {Options} [opts]
 */
export function analyse(piece, opts = {}) {
  const tempo = opts.tempo ?? piece.tempo;
  const player = opts.player ?? 'average';
  const at = (/** @type {number} */ t) => ({ tempo: t, player });
  const fastest = fastestTempo((t) => solve(piece, at(t)).ok);
  const breaksAt = fastest !== null && fastest < 400 ? solve(piece, at(fastest + 1)) : null;
  const fastestInfo = { tempo: fastest, breaksAt: breaksAt && !breaksAt.ok ? where(piece, breaksAt.at) : null };

  const alt = alternating(piece);
  const altHere = evaluate(piece, alt, at(tempo));
  const alternatingInfo = {
    playable: altHere.ok,
    failsAt: altHere.ok ? null : where(piece, altHere.at),
    summary: altHere.ok ? summarise(altHere.tags) : null,
    fastest: fastestTempo((t) => evaluate(piece, alt, at(t)).ok),
  };

  const best = solve(piece, at(tempo));
  if (!best.ok) {
    return { title: piece.title, tempo, player, lead: piece.lead, playable: false, failsAt: where(piece, best.at), fastest: fastestInfo, alternating: alternatingInfo };
  }
  const checked = evaluate(piece, best.sticking, at(tempo));
  if (!checked.ok) throw new Error('internal: the chosen sticking does not replay');
  return {
    title: piece.title,
    tempo,
    player,
    lead: piece.lead,
    playable: true,
    sticking: best.sticking,
    tags: checked.tags,
    summary: summarise(checked.tags),
    fastest: fastestInfo,
    alternating: alternatingInfo,
  };
}

/** @param {number} n @param {string} one @param {string} many */
const count = (n, one, many) => `${n} ${n === 1 ? one : many}`;

/**
 * The sticking written under each bar, column by column.
 * @param {Piece} piece @param {Sticking} sticking
 */
export function chart(piece, sticking) {
  /** @type {Map<string, string>} */
  const byPlace = new Map();
  for (const n of piece.notes) byPlace.set(`${n.bar}:${n.slot}`, /** @type {string[]} */ (sticking[n.index]).join('+'));
  /** @type {string[]} */
  const out = [];
  piece.bars.forEach((tokens, b) => {
    /** @type {string[]} */
    const top = [];
    /** @type {string[]} */
    const under = [];
    tokens.forEach((token, slot) => {
      const s = byPlace.get(`${b}:${slot}`) ?? '';
      const w = Math.max(token.length, s.length);
      const sep = slot > 0 && slot % (piece.grid / 4) === 0 ? '| ' : '';
      top.push(sep + token.padEnd(w));
      under.push(' '.repeat(sep.length) + s.padEnd(w));
    });
    out.push(`  bar ${String(b + 1).padStart(2)}  ${top.join(' ')}`.trimEnd());
    out.push(`          ${under.join(' ')}`.trimEnd());
  });
  return out.join('\n');
}

/**
 * The report a drummer reads.
 * @param {Piece} piece @param {Options} [opts]
 */
export function report(piece, opts = {}) {
  const a = analyse(piece, opts);
  const per = { 4: 'quarter', 8: '8th', 12: '8th-triplet', 16: '16th', 24: '16th-triplet', 32: '32nd' }[piece.grid];
  const lines = [
    `Sticksmith: ${a.title}`,
    `${a.tempo} bpm · ${per}-note grid · ${a.lead === 'R' ? 'right' : 'left'} hand leads · ${a.player} hands`,
    '',
  ];
  if (!a.playable || !a.sticking || !a.tags || !a.summary) {
    lines.push(`Two ${a.player} hands can't play this at ${a.tempo} bpm: nothing reaches ${a.failsAt} in time.`);
  } else {
    lines.push(chart(piece, a.sticking), '');
    /** @type {string[]} */
    const notes = [];
    a.tags.forEach((t, i) => {
      const n = /** @type {import('./parse.js').Note} */ (piece.notes[i]);
      const who = /** @type {string[]} */ (a.sticking?.[i]);
      const hand = who.length === 2 ? 'one' : who[0] === 'R' ? 'right' : 'left';
      if (t.double) notes.push(`${where(piece, i)} (${n.drums.join('+')}): second stroke of a ${hand === 'one' ? '' : `${hand}-hand `}double`);
      if (t.crossover) notes.push(`${where(piece, i)} (${n.drums.join('+')}): the hands pass each other`);
      if (t.weakBeat) notes.push(`${where(piece, i)} (${n.drums.join('+')}): the ${hand} hand takes the beat (the other is busy or too far away)`);
    });
    if (notes.length) {
      lines.push('Worth practising:');
      for (const n of notes.slice(0, 12)) lines.push(`  - ${n}`);
      if (notes.length > 12) lines.push(`  - and ${notes.length - 12} more`);
      lines.push('');
    }
    const s = a.summary;
    lines.push(`This sticking: ${s.move} m of hand travel, ${count(s.doubles, 'double', 'doubles')}, ${count(s.crossovers, 'crossover', 'crossovers')}, ${count(s.weakBeats, 'beat', 'beats')} on the weaker hand.`);
  }
  const f = a.fastest;
  if (f.tempo === null) lines.push(`Not playable at any tempo from 20 bpm.`);
  else if (f.tempo >= 400) lines.push('Playable at every tempo up to 400 bpm.');
  else lines.push(`Fastest playable tempo: ${f.tempo} bpm, re-sticking as needed${f.breaksAt ? `; beyond that, nothing reaches ${f.breaksAt} in time` : ''}.`);
  const alt = a.alternating;
  const altFast = alt.fastest === null ? 'not playable at any tempo' : `playable up to ${alt.fastest} bpm`;
  if (alt.playable && alt.summary) {
    lines.push(`Plain alternating (${a.lead === 'R' ? 'R L R L' : 'L R L R'}): ${alt.summary.move} m of travel, ${count(alt.summary.crossovers, 'crossover', 'crossovers')}, ${altFast}.`);
  } else {
    lines.push(`Plain alternating can't be played at ${a.tempo} bpm (stuck at ${alt.failsAt}); ${altFast}.`);
  }
  return lines.join('\n');
}
