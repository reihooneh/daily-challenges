#!/usr/bin/env node
import { closeSync, fstatSync, openSync, readSync } from 'node:fs';
import { LIMITS, PatternError } from './errors.js';
import { lint, render } from './lint.js';
import { STITCHES } from './stitches.js';

const USAGE = `Usage: dropstitch PATTERN_FILE     check a knitting pattern (use - for standard input)
       dropstitch --stitches       list the stitches it understands

Exit codes: 0 every row adds up, 1 problems found, 2 could not read the pattern.`;

/** Reads at most the size limit plus one byte, so a huge file is never loaded. */
function readLimited(path: string): string {
  let descriptor: number;
  try {
    descriptor = path === '-' ? 0 : openSync(path, 'r');
  } catch {
    throw new PatternError('cannot read that file');
  }
  try {
    if (path !== '-' && !fstatSync(descriptor).isFile()) throw new PatternError('cannot read that file');
    const buffer = Buffer.alloc(LIMITS.fileBytes + 1);
    let total = 0;
    for (;;) {
      let read: number;
      try {
        read = readSync(descriptor, buffer, total, buffer.length - total, null);
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'EAGAIN') continue;
        if ((error as NodeJS.ErrnoException).code === 'EOF') break;
        throw new PatternError('cannot read that file');
      }
      if (read === 0) break;
      total += read;
      if (total > LIMITS.fileBytes) throw new PatternError(`pattern is larger than ${LIMITS.fileBytes} bytes`);
    }
    try {
      return new TextDecoder('utf-8', { fatal: true }).decode(buffer.subarray(0, total));
    } catch {
      throw new PatternError('pattern is not valid UTF-8 text');
    }
  } finally {
    if (path !== '-') closeSync(descriptor);
  }
}

export function main(argv: readonly string[]): number {
  const [argument] = argv;
  if (argv.length !== 1 || argument === undefined) {
    process.stderr.write(`${USAGE}\n`);
    return 2;
  }
  if (argument === '-h' || argument === '--help') {
    process.stdout.write(`${USAGE}\n`);
    return 0;
  }
  if (argument === '--stitches') {
    for (const [name, stitch] of STITCHES) {
      process.stdout.write(`${name.toUpperCase().padEnd(6)} uses ${stitch.uses}, makes ${stitch.makes}   ${stitch.meaning}\n`);
    }
    return 0;
  }
  try {
    const report = lint(readLimited(argument));
    process.stdout.write(render(report));
    return report.problemCount === 0 ? 0 : 1;
  } catch (error) {
    if (error instanceof PatternError) {
      process.stderr.write(`dropstitch: ${error.message}\n`);
      return 2;
    }
    throw error;
  }
}

process.exitCode = main(process.argv.slice(2));
