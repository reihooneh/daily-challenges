// Reads a whole pattern, row by row, carrying the stitch count forward.

import { LIMITS, PatternError } from './errors.js';
import { evaluateRow } from './evaluate.js';
import { parseRow } from './parser.js';
import { tokenize } from './tokenizer.js';

export interface RowReport {
  readonly line: number;
  readonly label: string;
  readonly before: number;
  readonly after: number;
  readonly problems: readonly string[];
}

export interface Report {
  readonly castOn: number | null;
  readonly rows: readonly RowReport[];
  /** Problems that are not about one row, such as a missing cast-on. */
  readonly general: readonly string[];
  readonly problemCount: number;
}

// Row headers are matched with small, linear patterns (no nested repetition).
const CAST_ON = /^(?:cast on|co)\s+(\d{1,6})(?:\s+(?:sts?|stitch(?:es)?))?\s*\.?$/i;
const HEADER = /^(rows?|rounds?|rnds?)\s+([0-9][0-9 ,and&-]{0,60})\s*(?:\((?:rs|ws)\))?\s*:/i;

/** "2", "2 and 4", "2, 4, 6", "5-8" -> list of row numbers. */
export function expandRowNumbers(text: string): number[] {
  const numbers: number[] = [];
  for (const part of text.toLowerCase().replace(/and|&/g, ',').split(',')) {
    const piece = part.trim();
    if (piece === '') continue;
    const range = /^(\d{1,5})\s*-\s*(\d{1,5})$/.exec(piece);
    if (range) {
      const from = Number(range[1]);
      const to = Number(range[2]);
      if (to < from) throw new PatternError('row range runs backwards');
      if (to - from >= LIMITS.rows) throw new PatternError('row range is too large');
      for (let n = from; n <= to; n++) numbers.push(n);
    } else if (/^\d{1,5}$/.test(piece)) {
      numbers.push(Number(piece));
    } else {
      throw new PatternError('row numbers could not be read');
    }
    if (numbers.length > LIMITS.rows) throw new PatternError(`more than ${LIMITS.rows} rows`);
  }
  if (numbers.length === 0) throw new PatternError('row numbers could not be read');
  return numbers;
}

export function lint(text: string): Report {
  if (typeof text !== 'string') throw new PatternError('pattern is not text');
  if (text.length > LIMITS.fileBytes) throw new PatternError(`pattern is larger than ${LIMITS.fileBytes} characters`);
  const lines = text.split(/\r?\n/);
  if (lines.length > LIMITS.lines) throw new PatternError(`pattern has more than ${LIMITS.lines} lines`);

  const rows: RowReport[] = [];
  const general: string[] = [];
  let castOn: number | null = null;
  let count: number | null = null;
  let previousRow: number | null = null;

  lines.forEach((raw, index) => {
    const lineNumber = index + 1;
    const hash = raw.indexOf('#');
    const line = (hash >= 0 ? raw.slice(0, hash) : raw).trim();
    if (line === '') return;
    if (raw.length > LIMITS.lineLength) {
      general.push(`line ${lineNumber}: longer than ${LIMITS.lineLength} characters, skipped`);
      return;
    }

    const cast = CAST_ON.exec(line);
    if (cast) {
      const value = Number(cast[1]);
      if (value < 1 || value > LIMITS.stitches) {
        general.push(`line ${lineNumber}: cast on must be between 1 and ${LIMITS.stitches}`);
        return;
      }
      if (castOn === null) castOn = value;
      count = value;
      return;
    }

    const header = HEADER.exec(line);
    if (!header) {
      general.push(`line ${lineNumber}: not a "Cast on N" or "Row N: ..." line, skipped`);
      return;
    }
    if (count === null) {
      general.push(`line ${lineNumber}: a row appears before any "Cast on N" line, so it cannot be checked`);
      return;
    }

    const kind = /^r(?:ou)?nd/i.test(header[1] ?? '') ? 'Round' : 'Row';
    // Padding keeps every character at its original position, so the column
    // numbers in error messages point at the right place in the user's file.
    const keepWidth = (short: string) => (match: string): string => short.padEnd(match.length);
    const instructions = ' '.repeat(raw.length - raw.trimStart().length + header[0].length)
      + line.slice(header[0].length).replace(/\bbind[ \t]+off\b/gi, keepWidth('bo')).replace(/\bcast[ \t]+on\b/gi, keepWidth('co'));
    let numbers: number[];
    try {
      numbers = expandRowNumbers(header[2] ?? '');
    } catch (error) {
      general.push(`line ${lineNumber}: ${error instanceof PatternError ? error.message : 'could not be read'}`);
      return;
    }

    let parsed;
    try {
      parsed = parseRow(tokenize(instructions));
    } catch (error) {
      if (!(error instanceof PatternError)) throw error;
      rows.push({ line: lineNumber, label: `${kind} ${numbers[0]}`, before: count, after: count, problems: [error.message] });
      return;
    }

    for (const number of numbers) {
      if (rows.length >= LIMITS.rows) {
        general.push(`more than ${LIMITS.rows} rows: the rest were not checked`);
        return;
      }
      const problems: string[] = [];
      if (previousRow !== null && number !== previousRow + 1) {
        problems.push(`follows ${kind.toLowerCase()} ${previousRow}: is ${kind.toLowerCase()} ${previousRow + 1} missing?`);
      }
      previousRow = number;
      const result = evaluateRow(parsed.nodes, count);
      problems.push(...result.problems);
      // The claimed count is checked on the last row of a group ("Rows 1-4: ... (20 sts)").
      if (result.problems.length === 0 && parsed.declared !== null && number === numbers[numbers.length - 1]
          && parsed.declared !== result.after) {
        problems.push(`the pattern says (${parsed.declared} sts) but the instructions make ${result.after}`);
      }
      rows.push({ line: lineNumber, label: `${kind} ${number}`, before: result.before, after: result.after, problems });
      count = result.after;
    }
  });

  if (castOn === null) general.push('no "Cast on N" line found');
  if (rows.length === 0 && castOn !== null) general.push('no rows found');
  const problemCount = general.length + rows.reduce((sum, row) => sum + row.problems.length, 0);
  return { castOn, rows, general, problemCount };
}

/** Plain-text report. Everything printed is either ours or already validated. */
export function render(report: Report): string {
  const out: string[] = [];
  if (report.castOn !== null) out.push(`Cast on ${report.castOn}`);
  for (const row of report.rows) {
    const change = row.after - row.before;
    const delta = change === 0 ? '' : ` (${change > 0 ? '+' : ''}${change})`;
    if (row.problems.length === 0) {
      out.push(`  ok   ${row.label}: ${row.before} -> ${row.after} sts${delta}`);
    } else {
      out.push(`  XX   ${row.label} (line ${row.line}): ${row.before} sts on the needle`);
      for (const problem of row.problems) out.push(`         ${problem}`);
    }
  }
  for (const problem of report.general) out.push(`  !!   ${problem}`);
  out.push('');
  const bad = report.rows.filter((row) => row.problems.length > 0).length;
  out.push(report.problemCount === 0
    ? `All ${report.rows.length} rows add up. Safe to cast on.`
    : `${report.problemCount} problem${report.problemCount === 1 ? '' : 's'} found${bad > 0 ? ` in ${bad} row${bad === 1 ? '' : 's'}` : ''}. Fix the pattern before you knit it.`);
  return `${out.join('\n')}\n`;
}
