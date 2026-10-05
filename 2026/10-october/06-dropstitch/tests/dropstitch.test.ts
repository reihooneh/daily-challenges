import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { LIMITS, PatternError } from '../src/errors.js';
import { evaluateRow } from '../src/evaluate.js';
import { expandRowNumbers, lint, render } from '../src/lint.js';
import { parseRow } from '../src/parser.js';
import { STITCHES } from '../src/stitches.js';
import { tokenize } from '../src/tokenizer.js';

/** Works one row on `before` stitches and returns the new count, or the first problem. */
function row(instructions: string, before: number): number | string {
  const result = evaluateRow(parseRow(tokenize(instructions)).nodes, before);
  return result.problems[0] ?? result.after;
}

const example = (name: string): string =>
  readFileSync(fileURLToPath(new URL(`../../examples/${name}`, import.meta.url)), 'utf8');

const cli = fileURLToPath(new URL('../src/cli.js', import.meta.url));
const run = (args: string[], input = ''): { status: number | null; stdout: string; stderr: string } => {
  const result = spawnSync(process.execPath, [cli, ...args], { input, encoding: 'utf8', timeout: 20_000 });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
};

// ---- single stitches --------------------------------------------------------

test('plain stitches keep the count', () => {
  assert.equal(row('K10', 10), 10);
  assert.equal(row('K2, P2, K2, P2', 8), 8);
  assert.equal(row('knit 4, purl 4', 8), 8);
  assert.equal(row('Sl1, K7', 8), 8);
});

test('increases add and decreases remove', () => {
  assert.equal(row('K1, YO, K1', 2), 3);
  assert.equal(row('K1, M1, K1, M1L, M1R, K1', 3), 6);
  assert.equal(row('Kfb, K1', 2), 3);
  assert.equal(row('K2tog, SSK', 4), 2);
  assert.equal(row('K3tog, SK2P, CDD', 9), 3);
  assert.equal(row('BO 3, K5', 8), 5);
  assert.equal(row('bo 2 sts, knit to end', 10), 8);
});

test('every stitch in the dictionary is sane', () => {
  for (const [name, stitch] of STITCHES) {
    assert.ok(Number.isInteger(stitch.uses) && stitch.uses >= 0 && stitch.uses <= 3, name);
    assert.ok(Number.isInteger(stitch.makes) && stitch.makes >= 0 && stitch.makes <= 2, name);
    assert.ok(stitch.uses + stitch.makes > 0, name);
    assert.equal(name, name.toLowerCase());
  }
});

// ---- "the rest of the row" --------------------------------------------------

test('knit and purl on their own mean the whole row', () => {
  assert.equal(row('Knit', 17), 17);
  assert.equal(row('Purl.', 17), 17);
  assert.equal(row('K to end', 17), 17);
  assert.equal(row('Knit across', 17), 17);
});

test('"to last N sts" leaves stitches for what follows', () => {
  assert.equal(row('K2, purl to last 2 sts, K2', 12), 12);
  assert.equal(row('K1, M1, knit to last st, M1, K1', 10), 12);
  assert.equal(row('knit to last 3 sts, K2tog, K1', 10), 9);
});

// ---- repeats ----------------------------------------------------------------

test('star repeats to the end of the row', () => {
  assert.equal(row('*K2, P2; rep from * to end', 16), 16);
  assert.equal(row('*K2, P2; repeat from * across', 16), 16);
  assert.equal(row('*YO, K2tog*', 16), 16);
  assert.equal(row('*K6, K2tog; rep from * to end', 64), 56);
});

test('star repeats that stop early', () => {
  assert.equal(row('K2, *YO, K2tog; rep from * to last 2 sts, K2', 20), 20);
  assert.equal(row('K1, *Kfb; rep from * to last st, K1', 10), 18);
});

test('repeats a set number of times', () => {
  assert.equal(row('(K1, P1) 4 times', 8), 8);
  assert.equal(row('[K2tog] twice, K4', 8), 6);
  assert.equal(row('*K1, YO; rep from * 3 more times, K4', 8), 12);
  assert.equal(row('K2, (YO, K2tog) 3 times, K2', 10), 10);
});

test('nested repeats', () => {
  assert.equal(row('*K1, (YO, K2tog) twice; rep from * to end', 20), 20);
  assert.equal(row('((K1, P1) twice, K2tog) 3 times', 18), 15);
});

test('one stitch repeated along the row', () => {
  assert.equal(row('K2tog across', 16), 8);
  assert.equal(row('K1, Kfb to last st, K1', 6), 10);
});

// ---- the mistakes it exists to catch ---------------------------------------

test('running out of stitches', () => {
  assert.match(String(row('K8, K2tog, K2', 10)), /K2 needs 2 stitches but only 0 are left/);
  assert.match(String(row('K2tog', 1)), /K2TOG needs 2 stitches but only 1 is left/);
  assert.match(String(row('(K2, P2) 5 times', 16)), /needs 20 stitches but only 16 are left/);
});

test('stitches left over at the end', () => {
  assert.match(String(row('K8', 10)), /2 stitches are left unworked/);
  assert.match(String(row('(K1, P1) 4 times', 9)), /1 stitch is left unworked/);
});

test('a repeat that does not fit', () => {
  assert.match(String(row('*K2, P2; rep from * to end', 18)), /4 stitches wide but has 18 to cover: 2 left over/);
  assert.match(String(row('K2, knit to last 5 sts, K1', 4)), /"to last 5" is impossible/);
});

test('a repeat that could never finish is refused, not run', () => {
  assert.match(String(row('*YO; rep from * to end', 10)), /uses no stitches/);
  assert.match(String(row('*M1, YO*', 10)), /uses no stitches/);
});

test('the lace scarf example: the mistake is in row 5', () => {
  const report = lint(example('lace-scarf.txt'));
  const bad = report.rows.filter((r) => r.problems.length > 0);
  assert.deepEqual(bad.map((r) => r.label), ['Row 5']);
  assert.equal(report.problemCount, 1);
});

test('the hat example is correct and ends on 8 stitches', () => {
  const report = lint(example('hat-crown.txt'));
  assert.equal(report.problemCount, 0);
  assert.equal(report.rows.length, 14);
  assert.equal(report.rows.at(-1)?.after, 8);
  assert.match(render(report), /All 14 rows add up/);
});

test('a wrong "(N sts)" claim and a missing row are both reported', () => {
  const report = lint(example('shawl-wrong-count.txt'));
  const problems = report.rows.flatMap((r) => r.problems);
  assert.deepEqual(problems, [
    'the pattern says (12 sts) but the instructions make 11',
    'follows row 5: is row 6 missing?',
  ]);
});

test('row lists and ranges', () => {
  assert.deepEqual(expandRowNumbers('2 and 4'), [2, 4]);
  assert.deepEqual(expandRowNumbers('2, 4, 6'), [2, 4, 6]);
  assert.deepEqual(expandRowNumbers('5-8'), [5, 6, 7, 8]);
  const report = lint('Cast on 4\nRows 1-3: K1, YO, knit to end.\n');
  assert.deepEqual(report.rows.map((r) => r.after), [5, 6, 7]);
});

test('after a broken row the count carries on from the last good one', () => {
  const report = lint('CO 10\nRow 1: K99\nRow 2: Knit\n');
  assert.deepEqual(report.rows.map((r) => [r.before, r.after, r.problems.length]), [[10, 10, 1], [10, 10, 0]]);
});

test('patterns without a cast-on are reported, not guessed', () => {
  assert.match(lint('Row 1: Knit\n').general.join('\n'), /before any "Cast on N"/);
  assert.match(lint('').general.join('\n'), /no "Cast on N" line found/);
  assert.match(lint('Cast on 5\n').general.join('\n'), /no rows found/);
});

test('error columns point into the original line', () => {
  const report = lint('Cast on 10\n  Row 1: K2, bind off 3 sts, zzz9, K1\n');
  assert.deepEqual(report.rows[0]?.problems, ['column 30: unknown stitch "zzz9"']);
  assert.equal('  Row 1: K2, bind off 3 sts, zzz9, K1'.indexOf('zzz9') + 1, 30);
});

// ---- hostile and broken input ----------------------------------------------

test('only letters, digits and a few punctuation marks are allowed in a row', () => {
  const hostile = ['K2, <script>alert(1)</script>', 'K2, $(rm -rf ~)', 'K2 `id`', 'K2 | cat /etc/passwd', 'K2, ../../x',
    'K2\u001b[2J', 'K2\u0000', 'K2 ‮', 'K2 %s', 'K2 "x"', "K2 'x'", 'K2 {x}', 'Ｋ２', 'K2 \\n'];
  for (const text of hostile) {
    assert.throws(() => tokenize(text), (error: unknown) =>
      error instanceof PatternError && /^column \d+: unexpected character$/.test(error.message), text);
  }
});

test('messages never contain raw input', () => {
  const report = lint('Cast on 10\nRow 1: K2, \u001b]0;owned\u0007 <img src=x onerror=alert(1)>\nnot a row \u001b[31m at all\n');
  const text = render(report);
  assert.ok(!/owned|img|onerror|\u001b|\u0007|not a row/.test(text), text);
  assert.equal(report.problemCount, 2);
});

test('words that are properties of every JavaScript object are just unknown stitches', () => {
  for (const word of ['constructor', 'toString', 'hasOwnProperty', 'valueOf', 'proto']) {
    assert.match(String((() => { try { return row(word, 5); } catch (e) { return (e as Error).message; } })()), /unknown stitch/);
  }
});

test('enormous repeat counts are answered instantly, with arithmetic', () => {
  const started = performance.now();
  assert.match(String(row('(K1) 999999 times', 10)), /needs 999999 stitches/);
  assert.match(String(row('((((K1) 999999 times) 999999 times) 999999 times) 999999 times', 10)), /only 10 are left/);
  assert.equal(row('*K1, P1; rep from * to end', 100_000), 100_000);
  assert.ok(performance.now() - started < 200);
});

test('size limits', () => {
  assert.throws(() => tokenize('K'.repeat(LIMITS.lineLength + 1)), /longer than/);
  assert.throws(() => tokenize('K 1234567'), /number is too large/);
  assert.throws(() => parseRow(tokenize('K1234567')), /number is too large/);
  assert.throws(() => tokenize('k'.repeat(21)), /word is too long/);
  assert.throws(() => parseRow(tokenize('((((((K1))))))')), /nested too deeply/);
  assert.throws(() => lint('x'.repeat(LIMITS.fileBytes + 1)), /larger than/);
  assert.throws(() => lint('\n'.repeat(LIMITS.lines + 1)), /more than 5000 lines/);
  assert.throws(() => expandRowNumbers('1-99999'), /too large/);
  assert.throws(() => expandRowNumbers('9-3'), /backwards/);
  assert.match(lint('Cast on 0\n').general.join(), /between 1 and/);
  assert.match(lint('Cast on 999999\n').general.join(), /between 1 and/);
  assert.match(String(row('*Kfb; rep from * to end', 60_000)), /more than 100000 stitches/);
});

test('malformed structure gives a clear message', () => {
  assert.throws(() => parseRow(tokenize('(K1, P1')), /bracket is never closed/);
  assert.throws(() => parseRow(tokenize('K1, )')), /did not expect "\)"/);
  assert.throws(() => parseRow(tokenize('()')), /empty brackets/);
  assert.throws(() => parseRow(tokenize('* ; rep from *')), /empty repeat/);
  assert.throws(() => parseRow(tokenize('(K1) 3')), /expected "times"/);
  assert.throws(() => parseRow(tokenize('knit to somewhere')), /expected "to end"/);
  assert.throws(() => parseRow(tokenize(',,,')), /no instructions/);
  assert.throws(() => parseRow(tokenize('7')), /did not expect number 7/);
});

test('pathological lines are handled quickly', () => {
  const started = performance.now();
  lint(`Cast on 5\nRow ${'1, '.repeat(600)}: K5\n`);
  lint(`Cast on 5\nRows ${'1 and '.repeat(300)}\n`);
  lint(`Cast on 5\nRow 1: ${'bind '.repeat(390)}\n`);
  lint(`Cast on 5\nRow 1: ${'*'.repeat(1900)}\n`);
  lint(`Cast on 5\nRow 1: ${'K1, '.repeat(490)}\n`);
  assert.ok(performance.now() - started < 1000);
});

// ---- command line -----------------------------------------------------------

test('command line: exit codes', () => {
  assert.equal(run(['-'], 'Cast on 4\nRow 1: Knit\n').status, 0);
  assert.equal(run(['-'], 'Cast on 4\nRow 1: K5\n').status, 1);
  assert.equal(run([]).status, 2);
  assert.equal(run(['a', 'b']).status, 2);
  assert.equal(run(['--help']).status, 0);
  assert.match(run(['--stitches']).stdout, /K2TOG  uses 2, makes 1/);
});

test('command line: unreadable input gives one clean line', () => {
  for (const path of ['/no/such/file', '/', '../../../../etc/shadow/x']) {
    const result = run([path]);
    assert.equal(result.status, 2, path);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, 'dropstitch: cannot read that file\n');
  }
  const big = run(['-'], 'K'.repeat(LIMITS.fileBytes + 10));
  assert.equal(big.status, 2);
  assert.match(big.stderr, /larger than/);
  const binary = spawnSync(process.execPath, [cli, '-'], { input: Buffer.from([0x43, 0xff, 0xfe]), encoding: 'utf8' });
  assert.equal(binary.status, 2);
  assert.match(binary.stderr, /not valid UTF-8/);
});
