// Reads a drum passage: the kit, the tempo and grid, and the bars of notes.

/** @typedef {{ name: string, x: number, label: string, foot: boolean }} Drum */
/**
 * One moment in the music where the hands play something.
 * @typedef {{ index: number, bar: number, slot: number, beat: number, onBeat: boolean, drums: string[] }} Note
 */
/**
 * @typedef {{
 *   title: string, tempo: number, grid: number, lead: 'R' | 'L',
 *   kit: Map<string, Drum>, bars: string[][], notes: Note[]
 * }} Piece
 */

export class InputError extends Error {}

export const LIMITS = Object.freeze({ bytes: 64 * 1024, lines: 2000, bars: 64, notes: 1024, drums: 16, title: 80 });
export const GRIDS = Object.freeze([4, 8, 12, 16, 24, 32]);
export const TEMPO = Object.freeze({ min: 20, max: 400 });

/** A right-handed kit seen from the stool: x is metres from the snare's left, negative to the left. */
const DEFAULT_KIT = [
  ['crash', -0.6, 'crash cymbal', false],
  ['hh', -0.45, 'hi-hat', false],
  ['sn', -0.1, 'snare', false],
  ['t1', 0.15, 'high tom', false],
  ['t2', 0.4, 'mid tom', false],
  ['ft', 0.75, 'floor tom', false],
  ['ride', 0.95, 'ride cymbal', false],
  ['k', 0, 'kick', true],
  ['hf', 0, 'hi-hat foot', true],
];

const NAME = /^[a-z][a-z0-9]{0,7}$/;
const UNSAFE = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/;

/** @param {number} line @param {string} message */
function fail(line, message) {
  throw new InputError(line > 0 ? `line ${line}: ${message}` : message);
}

/** @param {string} text @param {number} line @param {number} lo @param {number} hi */
function number(text, line, lo, hi) {
  if (!/^-?\d+(\.\d+)?$/.test(text)) fail(line, 'expected a number');
  const v = Number(text);
  if (!(v >= lo && v <= hi)) fail(line, `number must be between ${lo} and ${hi}`);
  return v;
}

/** @param {string} label @param {number} line */
function cleanLabel(label, line) {
  const v = label.trim();
  if (v.length > LIMITS.title) fail(line, `text is longer than ${LIMITS.title} characters`);
  return v;
}

/**
 * Parses the text of a passage file.
 * @param {string} text
 * @returns {Piece}
 */
export function parsePiece(text) {
  if (typeof text !== 'string') throw new InputError('input must be text');
  if (Buffer.byteLength(text, 'utf8') > LIMITS.bytes) fail(0, `input is larger than ${LIMITS.bytes / 1024} KB`);
  if (UNSAFE.test(text)) fail(0, 'input contains control or direction-changing characters');
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  if (lines.length > LIMITS.lines) fail(0, `input has more than ${LIMITS.lines} lines`);

  /** @type {Map<string, Drum>} */
  const kit = new Map(DEFAULT_KIT.map(([name, x, label, foot]) => [String(name), { name: String(name), x: Number(x), label: String(label), foot: Boolean(foot) }]));
  let title = 'Untitled';
  let tempo = 100;
  let grid = 16;
  /** @type {'R' | 'L'} */
  let lead = 'R';
  /** @type {{ tokens: string[], line: number }[]} */
  const rawBars = [];
  const seen = new Set();

  lines.forEach((raw, k) => {
    const line = k + 1;
    const body = raw.replace(/#.*$/, '').trim();
    if (!body) return;
    const m = /^([a-z]+)\s*:?\s*(.*)$/.exec(body);
    if (!m) fail(line, 'expected "key: value"');
    const [, key, rest] = /** @type {RegExpExecArray} */ (m);
    if (['title', 'tempo', 'grid', 'lead'].includes(key)) {
      if (seen.has(key)) fail(line, `${key} is given twice`);
      seen.add(key);
    }
    switch (key) {
      case 'title':
        title = cleanLabel(rest, line) || 'Untitled';
        break;
      case 'tempo':
        tempo = number(rest, line, TEMPO.min, TEMPO.max);
        break;
      case 'grid':
        grid = number(rest, line, 1, 64);
        if (!GRIDS.includes(grid)) fail(line, `grid must be one of ${GRIDS.join(', ')} (notes per bar of 4/4)`);
        break;
      case 'lead':
        if (rest !== 'right' && rest !== 'left') fail(line, 'lead must be "right" or "left"');
        lead = rest === 'right' ? 'R' : 'L';
        break;
      case 'drum':
      case 'foot': {
        const parts = rest.split(/\s+/);
        const name = parts[0] ?? '';
        if (!NAME.test(name)) fail(line, 'a drum name is 1-8 lowercase letters or digits, starting with a letter');
        let label = name;
        let x = 0;
        if (key === 'drum') {
          x = number(parts[1] ?? '', line, -2, 2);
          label = cleanLabel(parts.slice(2).join(' '), line) || name;
        } else {
          label = cleanLabel(parts.slice(1).join(' '), line) || name;
        }
        if (!kit.has(name) && kit.size >= LIMITS.drums) fail(line, `a kit can have at most ${LIMITS.drums} drums`);
        kit.set(name, { name, x, label, foot: key === 'foot' });
        break;
      }
      case 'bar': {
        if (rawBars.length >= LIMITS.bars) fail(line, `at most ${LIMITS.bars} bars`);
        rawBars.push({ tokens: rest.split(/\s+/).filter((t) => t && t !== '|'), line });
        break;
      }
      default:
        fail(line, 'unknown key (use title, tempo, grid, lead, drum, foot or bar)');
    }
  });

  if (rawBars.length === 0) fail(0, 'no bars: add lines like "bar: hh - sn - hh - sn -"');

  /** @type {Note[]} */
  const notes = [];
  const bars = rawBars.map(({ tokens, line }, b) => {
    if (tokens.length !== grid) fail(line, `bar has ${tokens.length} slots but the grid is ${grid}`);
    tokens.forEach((token, slot) => {
      if (token === '-') return;
      const names = token.split('+');
      for (const n of names) {
        if (!kit.has(n)) fail(line, `slot ${slot + 1}: unknown drum (${n.length <= 16 ? n : 'name too long'})`);
      }
      if (new Set(names).size !== names.length) fail(line, `slot ${slot + 1}: the same drum twice at once`);
      const hands = names.filter((n) => !/** @type {Drum} */ (kit.get(n)).foot);
      if (hands.length > 2) fail(line, `slot ${slot + 1}: needs more than two hands`);
      if (hands.length === 0) return;
      if (notes.length >= LIMITS.notes) fail(line, `at most ${LIMITS.notes} hand notes`);
      notes.push({
        index: notes.length,
        bar: b,
        slot,
        beat: ((b * grid + slot) * 4) / grid,
        onBeat: slot % (grid / 4) === 0,
        drums: hands,
      });
    });
    return tokens;
  });
  if (notes.length === 0) fail(0, 'there are no notes for the hands to play');
  return { title, tempo, grid, lead, kit, bars, notes };
}
