#!/usr/bin/env node
// lockpace: how an escape room plays for each team size.
//
//   lockpace room.txt          the report
//   lockpace - < room.txt      read from standard input
//
// Exit codes: 0 the room can be finished within the limit by some team size,
//             1 it can't (or a dead end was found), 2 bad input or usage.

import fs from 'node:fs';
import { parseRoom, RoomError, LIMITS } from '../src/parse.js';
import { analyse } from '../src/analyse.js';
import { render } from '../src/report.js';

const USAGE = 'usage: lockpace ROOM.txt   (or - for standard input)\n';

/** @param {Buffer} buf */
function decode(buf) {
  if (buf.length > LIMITS.bytes) throw new RoomError('the room file is larger than 32 KB');
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    throw new RoomError('the room file is not valid UTF-8 text');
  }
}

/** A regular file only, no symlinks, and never more than the limit + 1 byte. The path is never echoed. @param {string} file */
function readFile(file) {
  let fd;
  try {
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  } catch {
    throw new RoomError('the room file could not be opened (it must be a regular file, not a link)');
  }
  try {
    if (!fs.fstatSync(fd).isFile()) throw new RoomError('the room file could not be opened (it must be a regular file, not a link)');
    const buf = Buffer.alloc(LIMITS.bytes + 1);
    let got = 0;
    for (let n; got < buf.length && (n = fs.readSync(fd, buf, got, buf.length - got, null)) > 0; ) got += n;
    return buf.subarray(0, got);
  } finally {
    fs.closeSync(fd);
  }
}

function readStdin() {
  const buf = Buffer.alloc(LIMITS.bytes + 1);
  let got = 0;
  for (;;) {
    let n;
    try {
      n = fs.readSync(0, buf, got, buf.length - got, null);
    } catch (err) {
      if (/** @type {NodeJS.ErrnoException} */ (err).code === 'EAGAIN') continue;
      throw err;
    }
    if (n === 0) break;
    got += n;
    if (got === buf.length) break;
  }
  return buf.subarray(0, got);
}

function main() {
  const args = process.argv.slice(2);
  if (args.length !== 1 || args[0] === '-h' || args[0] === '--help') {
    process.stderr.write(USAGE);
    return 2;
  }
  try {
    const room = parseRoom(decode(args[0] === '-' ? readStdin() : readFile(args[0])));
    const a = analyse(room);
    process.stdout.write(render(room, a));
    const inTime = a.runs.some((r) => r.run.finish !== null && r.run.finish <= room.limit * 10);
    const deadEnd = a.warnings.some((w) => w.startsWith('Dead end') || w.includes('can never'));
    return inTime && !deadEnd ? 0 : 1;
  } catch (err) {
    if (err instanceof RoomError) {
      process.stderr.write(`lockpace: ${err.message}\n`);
      return 2;
    }
    process.stderr.write('lockpace: something went wrong reading the room\n');
    return 2;
  }
}

process.exitCode = main();
