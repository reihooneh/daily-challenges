#!/usr/bin/env node
// tagback: estimate an animal population from mark-recapture sessions.
//
//   tagback survey.txt                 the report
//   tagback --json survey.txt          the same numbers as JSON
//   tagback --precision 15 survey.txt  plan for a ±15% estimate as well
//   tagback - < survey.txt             read from standard input
//
// Exit codes: 0 done, 2 bad input or usage.

import fs from 'node:fs';
import path from 'node:path';
import { parseSurvey, SurveyError, LIMITS } from '../src/survey.js';
import { analyse, render, toJSON } from '../src/report.js';

const USAGE = 'usage: tagback [--json] [--precision PERCENT] FILE|-\n';

class UsageError extends Error {}

/** Only plain characters of a file name go into messages. @param {string} name */
function cleanName(name) {
  return path.basename(name).replace(/[^\w .,-]/g, '?').slice(0, 60);
}

/** @param {Buffer} buf */
function decode(buf) {
  if (buf.length > LIMITS.bytes) throw new SurveyError('the survey file is larger than 256 KB');
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    throw new SurveyError('the survey file is not valid UTF-8 text');
  }
  return text.startsWith('﻿') ? text.slice(1) : text;
}

/** Opens a regular file without following symlinks, and reads at most the limit + 1 byte. @param {string} file */
function readFileSafely(file) {
  let fd;
  try {
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW | fs.constants.O_NONBLOCK);
  } catch (err) {
    const code = /** @type {NodeJS.ErrnoException} */ (err).code;
    if (code === 'ELOOP') throw new SurveyError(`${cleanName(file)} is a symbolic link; give the real file`);
    if (code === 'ENOENT') throw new SurveyError(`${cleanName(file)} does not exist`);
    throw new SurveyError(`cannot open ${cleanName(file)}`);
  }
  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) throw new SurveyError(`${cleanName(file)} is not a regular file`);
    if (st.size > LIMITS.bytes) throw new SurveyError('the survey file is larger than 256 KB');
    const buf = Buffer.alloc(LIMITS.bytes + 1);
    let n = 0;
    while (n < buf.length) {
      const got = fs.readSync(fd, buf, n, buf.length - n, null);
      if (got === 0) break;
      n += got;
    }
    return decode(buf.subarray(0, n));
  } finally {
    fs.closeSync(fd);
  }
}

async function readStdin() {
  const chunks = [];
  let total = 0;
  for await (const chunk of process.stdin) {
    total += chunk.length;
    if (total > LIMITS.bytes) throw new SurveyError('the survey file is larger than 256 KB');
    chunks.push(chunk);
  }
  return decode(Buffer.concat(chunks));
}

/** @param {string[]} argv */
function parseArgs(argv) {
  const opts = { json: false, precisions: [0.2, 0.1], file: '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') opts.json = true;
    else if (a === '--precision') {
      const v = argv[++i];
      if (v === undefined || !/^\d{1,2}(\.\d{1,2})?$/.test(v)) throw new UsageError('--precision takes a percentage such as 15');
      const p = Number(v);
      if (p < 1 || p > 50) throw new UsageError('--precision must be between 1 and 50');
      if (!opts.precisions.includes(p / 100)) opts.precisions.push(p / 100);
    } else if (a === '-h' || a === '--help') throw new UsageError('');
    else if (a.startsWith('-') && a !== '-') throw new UsageError(`unknown option ${a.replace(/[^\w-]/g, '?').slice(0, 30)}`);
    else if (opts.file) throw new UsageError('give one survey file');
    else opts.file = a;
  }
  if (!opts.file) throw new UsageError('give a survey file, or - for standard input');
  opts.precisions.sort((x, y) => y - x);
  return opts;
}

async function main() {
  try {
    const opts = parseArgs(process.argv.slice(2));
    const text = opts.file === '-' ? await readStdin() : readFileSafely(opts.file);
    const result = analyse(parseSurvey(text), opts.precisions);
    process.stdout.write(opts.json ? toJSON(result) : render(result));
    return 0;
  } catch (err) {
    if (err instanceof UsageError) {
      process.stderr.write((err.message ? `tagback: ${err.message}\n` : '') + USAGE);
      return 2;
    }
    if (err instanceof SurveyError) {
      process.stderr.write(`tagback: ${err.message}\n`);
      return 2;
    }
    throw err;
  }
}

process.exitCode = await main();
