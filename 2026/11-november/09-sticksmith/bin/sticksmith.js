#!/usr/bin/env node
// Command line: sticksmith passage.txt [--tempo N] [--player beginner|average|fast] [--json]

import { lstatSync, readFileSync } from 'node:fs';
import { parsePiece, InputError, LIMITS, TEMPO } from '../src/parse.js';
import { analyse, report } from '../src/explain.js';
import { PLAYERS } from '../src/stick.js';

const USAGE = `usage: sticksmith passage.txt [--tempo N] [--player beginner|average|fast] [--json]

Chooses which hand plays every note of a drum passage, finds the fastest tempo it can be
played at, and compares it with plain alternating.`;

/** @param {string[]} argv */
function parseArgs(argv) {
  /** @type {{ file: string | null, tempo: number | undefined, player: keyof typeof PLAYERS, json: boolean }} */
  const o = { file: null, tempo: undefined, player: 'average', json: false };
  for (let k = 0; k < argv.length; k++) {
    const a = /** @type {string} */ (argv[k]);
    if (a === '--help' || a === '-h') return null;
    if (a === '--json') o.json = true;
    else if (a === '--tempo') {
      const v = argv[++k] ?? '';
      if (!/^\d{1,3}$/.test(v) || Number(v) < TEMPO.min || Number(v) > TEMPO.max) throw new InputError(`--tempo must be a whole number from ${TEMPO.min} to ${TEMPO.max}`);
      o.tempo = Number(v);
    } else if (a === '--player') {
      const v = argv[++k] ?? '';
      if (!Object.hasOwn(PLAYERS, v)) throw new InputError('--player must be beginner, average or fast');
      o.player = /** @type {keyof typeof PLAYERS} */ (v);
    } else if (a.startsWith('-')) throw new InputError('unknown option (see --help)');
    else if (o.file === null) o.file = a;
    else throw new InputError('give one passage file');
  }
  if (o.file === null) throw new InputError('give a passage file (see --help)');
  return o;
}

/** Reads a passage: a regular file, small, and valid UTF-8. @param {string} path */
function readPassage(path) {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    throw new InputError('cannot open the passage file');
  }
  if (!st.isFile()) throw new InputError('the passage must be a regular file');
  if (st.size > LIMITS.bytes) throw new InputError(`the passage file is larger than ${LIMITS.bytes / 1024} KB`);
  const bytes = readFileSync(path);
  if (bytes.length > LIMITS.bytes) throw new InputError(`the passage file is larger than ${LIMITS.bytes / 1024} KB`);
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new InputError('the passage file is not valid UTF-8 text');
  }
}

try {
  const o = parseArgs(process.argv.slice(2));
  if (o === null) {
    console.log(USAGE);
  } else {
    const piece = parsePiece(readPassage(/** @type {string} */ (o.file)));
    const opts = { tempo: o.tempo, player: o.player };
    console.log(o.json ? JSON.stringify(analyse(piece, opts), null, 2) : report(piece, opts));
  }
} catch (e) {
  if (e instanceof InputError || e instanceof RangeError) {
    console.error(`sticksmith: ${e.message}`);
    process.exitCode = 1;
  } else {
    console.error('sticksmith: unexpected error');
    process.exitCode = 2;
  }
}
