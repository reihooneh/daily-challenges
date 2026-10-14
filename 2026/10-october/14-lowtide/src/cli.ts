#!/usr/bin/env node
// Command line: lowtide PLANFILE (or - for standard input).
import { closeSync, fstatSync, openSync, readSync } from 'node:fs';
import { basename } from 'node:path';
import { pathToFileURL } from 'node:url';
import { forecast } from './ledger.js';
import { optimise } from './optimise.js';
import { InputError, LIMITS, parsePlan } from './plan.js';
import { render } from './report.js';

const USAGE = 'usage: lowtide PLANFILE   (use - for standard input)';

// Reads at most LIMITS.bytes + 1 bytes, so a huge file or an endless stream is refused.
export function readLimited(path: string, fd?: number): string {
  let handle = fd;
  try {
    if (handle === undefined) {
      handle = openSync(path, 'r');
      if (!fstatSync(handle).isFile()) throw new InputError('the plan file could not be read');
    }
    const buf = Buffer.alloc(LIMITS.bytes + 1);
    let got = 0;
    while (got < buf.length) {
      const n = readSync(handle, buf, got, buf.length - got, null);
      if (n === 0) break;
      got += n;
    }
    if (got > LIMITS.bytes) throw new InputError('the file is larger than 32 KB');
    const text = buf.subarray(0, got).toString('utf8');
    if (text.includes('�')) throw new InputError('the file is not valid UTF-8 text');
    return text;
  } catch (e) {
    if (e instanceof InputError) throw e;
    throw new InputError('the plan file could not be read');
  } finally {
    if (fd === undefined && handle !== undefined) closeSync(handle);
  }
}

export function safeName(path: string): string {
  return path === '-' ? 'standard input' : basename(path).replace(/[^\w.\- ]/g, '?').slice(0, 60);
}

// Returns the exit code: 0 the plan stays above the buffer, 1 it doesn't, 2 bad input.
export function main(args: string[], write: (s: string) => void, writeErr: (s: string) => void, stdinFd = 0): number {
  if (args.length === 1 && (args[0] === '-h' || args[0] === '--help')) {
    write(USAGE + '\n');
    return 0;
  }
  try {
    if (args.length !== 1 || (args[0]!.startsWith('-') && args[0] !== '-')) throw new InputError('give exactly one plan file');
    const path = args[0]!;
    const plan = parsePlan(readLimited(path, path === '-' ? stdinFd : undefined));
    const before = forecast(plan);
    const result = optimise(plan);
    const items = plan.items.map((it) => {
      const k = plan.items.filter((x) => x.movable).indexOf(it);
      return k < 0 ? it : { ...it, schedule: { every: 'month' as const, on: result.days[k]! } };
    });
    const after = forecast(plan, items);
    write(render(plan, before, after, result, safeName(path)));
    return after.lowTide >= plan.buffer ? 0 : 1;
  } catch (e) {
    if (!(e instanceof InputError)) throw e;
    writeErr(`lowtide: ${e.message}\n${USAGE}\n`);
    return 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = main(process.argv.slice(2), (s) => process.stdout.write(s), (s) => process.stderr.write(s));
}
