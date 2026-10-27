#!/usr/bin/env node
import { closeSync, fstatSync, openSync, readSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { InputError, MAX_INPUT, parseLog } from './log.js';
import { sweep } from './replay.js';
import { render } from './report.js';

const USAGE = 'usage: gapkeeper <arrival-log.txt>   (or - to read standard input)\n' +
  'Measures bus bunching from a route log and finds the holding rule that cuts waiting most.\n';

/** Reads at most MAX_INPUT + 1 bytes from a regular file (or standard input). */
export function readBounded(path: string): string {
  let fd: number;
  try {
    fd = path === '-' ? 0 : openSync(path, 'r');
  } catch {
    throw new InputError('the log could not be read (it must be a readable file)');
  }
  try {
    if (path !== '-' && !fstatSync(fd).isFile()) throw new InputError('the log could not be read (it must be a readable file)');
    const buf = Buffer.alloc(MAX_INPUT + 1);
    let used = 0;
    for (;;) {
      let n = 0;
      try {
        n = readSync(fd, buf, used, buf.length - used, null);
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code === 'EAGAIN') continue;
        throw new InputError('the log could not be read (it must be a readable file)');
      }
      if (n === 0) break;
      used += n;
      if (used >= buf.length) break;
    }
    const text = new TextDecoder('utf-8', { fatal: true });
    try {
      return text.decode(buf.subarray(0, used));
    } catch {
      throw new InputError('the log is not valid UTF-8');
    }
  } finally {
    if (path !== '-') closeSync(fd);
  }
}

/** The whole command; returns the exit code (0 report printed, 2 bad usage or input). */
export function main(args: string[], write: (s: string) => void, warn: (s: string) => void, read = readBounded): number {
  if (args.length !== 1 || args[0] === '-h' || args[0] === '--help') {
    warn(USAGE);
    return 2;
  }
  try {
    const log = parseLog(read(args[0]!));
    const { none, rules, best } = sweep(log);
    write(render(log, none, rules, best));
    return 0;
  } catch (e) {
    if (e instanceof InputError) {
      warn(`gapkeeper: ${e.message}\n`);
      return 2;
    }
    throw e;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  process.exitCode = main(process.argv.slice(2), (s) => process.stdout.write(s), (s) => process.stderr.write(s));
}
