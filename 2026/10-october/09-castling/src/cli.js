// Command line: castling [--actors N] [--warn M:SS] FILE   (FILE may be -)
// Exit codes: 0 a plan with no problems, 1 problems, 2 the input could not be used.

import { closeSync, openSync, readSync } from 'node:fs';

import { LIMITS, PlayError, parsePlay, parseTime } from './parse.js';
import { cast } from './plan.js';
import { report } from './report.js';

const USAGE = 'usage: castling [--actors N] [--warn M:SS] FILE   (use - for standard input)';

/** Read at most LIMITS.bytes + 1 bytes, so an endless stream can't fill memory. @param {string} path */
export function readLimited(path) {
  const buffer = Buffer.alloc(LIMITS.bytes + 1);
  let fd;
  try {
    fd = path === '-' ? 0 : openSync(path, 'r');
  } catch {
    throw new PlayError('the breakdown file could not be opened');
  }
  let total = 0;
  try {
    while (total < buffer.length) {
      const got = readSync(fd, buffer, total, buffer.length - total, null);
      if (got === 0) break;
      total += got;
    }
  } catch {
    throw new PlayError('the breakdown file could not be read');
  } finally {
    if (path !== '-') closeSync(fd);
  }
  if (total > LIMITS.bytes) throw new PlayError(`the breakdown is larger than ${LIMITS.bytes} bytes`);
  const bytes = buffer.subarray(0, total);
  const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false });
  try {
    return text.decode(bytes);
  } catch {
    throw new PlayError('the breakdown is not valid UTF-8 text');
  }
}

/**
 * @param {string[]} argv
 * @param {{ out: (s: string) => void, err: (s: string) => void }} io
 * @returns {number}
 */
export function main(argv, io) {
  /** @type {string | null} */
  let path = null;
  /** @type {number | undefined} */
  let actors;
  let warn = 60;
  try {
    for (let i = 0; i < argv.length; i++) {
      const arg = argv[i];
      if (arg === '--help' || arg === '-h') {
        io.out(USAGE + '\n');
        return 0;
      } else if (arg === '--actors') {
        const value = argv[++i] ?? '';
        if (!/^\d{1,2}$/.test(value) || Number(value) < 1 || Number(value) > LIMITS.roles)
          throw new PlayError(`--actors must be a whole number from 1 to ${LIMITS.roles}`);
        actors = Number(value);
      } else if (arg === '--warn') {
        const value = parseTime(argv[++i] ?? '');
        if (value === null || value > LIMITS.changeSeconds) throw new PlayError('--warn must be a time like 1:00');
        warn = value;
      } else if (arg.startsWith('-') && arg !== '-') {
        throw new PlayError('unknown option');
      } else if (path !== null) {
        throw new PlayError('give exactly one breakdown file');
      } else {
        path = arg;
      }
    }
    if (path === null) throw new PlayError('give a breakdown file');
    const play = parsePlay(readLimited(path));
    const result = cast(play, { actors });
    const { text, problems } = report(play, result, { warn });
    io.out(text);
    return problems ? 1 : 0;
  } catch (error) {
    if (error instanceof PlayError) {
      io.err(`castling: ${error.message}\n${USAGE}\n`);
      return 2;
    }
    throw error;
  }
}
