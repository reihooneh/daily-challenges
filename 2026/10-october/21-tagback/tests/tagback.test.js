import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSurvey, tally, SurveyError } from '../src/survey.js';
import { chapman, schnabel, schumacher, poissonInterval, chiSquareQuantile, lnGamma, planSample, chaoLowerBound } from '../src/estimate.js';
import { poissonBinomial, captureFrequencies } from '../src/checks.js';
import { analyse, render, toJSON } from '../src/report.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const bin = path.join(here, '..', 'bin', 'tagback.js');
const examples = path.join(here, '..', 'examples');

/** A small seeded random number generator, so the simulations are repeatable. */
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A survey text for a population of N, each caught with probability p(i, t). */
function simulate(N, T, p, seed) {
  const r = rng(seed);
  const lines = ['study Simulated'];
  for (let t = 0; t < T; t++) {
    const caught = [];
    for (let i = 0; i < N; i++) if (r() < p(i, t)) caught.push(`A${i}`);
    lines.push(`session S${t + 1}: ${caught.join(' ')}`);
  }
  return lines.join('\n');
}

// ---------- reading surveys ----------

test('parses sessions, upper-cases tags and notes animals not released', () => {
  const s = parseSurvey('study Pond\n# comment\nsession Mon: f1 F2, f3\nsession Tue: F2 F4! # kept one\n');
  assert.equal(s.study, 'Pond');
  assert.deepEqual(s.sessions[0].caught, ['F1', 'F2', 'F3']);
  assert.deepEqual([...s.sessions[1].kept], ['F4']);
});

test('tally counts caught, recaptured, at large and new', () => {
  const { rows, everMarked } = tally(parseSurvey('session A: X Y Z\nsession B: Y Z W!\nsession C: X Q'));
  assert.deepEqual(
    rows.map((r) => [r.C, r.R, r.M, r.U, r.kept]),
    [
      [3, 0, 0, 3, 0],
      [3, 2, 3, 1, 1],
      [2, 1, 3, 1, 0],
    ],
  );
  assert.equal(everMarked, 5);
});

test('an animal kept and then caught again is an error', () => {
  assert.throws(() => tally(parseSurvey('session A: X!\nsession B: X')), /was kept in session "A"/);
});

for (const [name, text, msg] of [
  ['one session', 'session A: X', /at least 2 sessions/],
  ['no colon', 'session A X Y\nsession B: X', /expected 'session NAME/],
  ['bad tag', 'session A: X<script>\nsession B: X', /tags are 1-12/],
  ['long tag', 'session A: ABCDEFGHIJKLM\nsession B: X', /tags are 1-12/],
  ['duplicate', 'session A: X x\nsession B: X', /listed twice/],
  ['unknown line', 'hello\nsession A: X\nsession B: X', /start with study or session/],
  ['escape code', 'study \u001b[31mred\nsession A: X\nsession B: X', /control or hidden/],
  ['bidi mark', 'session A‮: X\nsession B: X', /control or hidden/],
  ['long line', `session A: ${'X '.repeat(2100)}`, /longer than 4000/],
  ['too many sessions', Array.from({ length: 51 }, (_, i) => `session S${i}: X${i}`).join('\n'), /more than 50 sessions/],
]) {
  test(`rejects ${name}`, () => {
    assert.throws(() => parseSurvey(/** @type {string} */ (text)), (e) => e instanceof SurveyError && /** @type {RegExp} */ (msg).test(e.message));
  });
}

test('rejects files over 256 KB before parsing', () => {
  assert.throws(() => parseSurvey('#'.repeat(300 * 1024)), /larger than 256 KB/);
});

// ---------- the statistics ----------

test('lnGamma matches known factorials', () => {
  assert.ok(Math.abs(lnGamma(5) - Math.log(24)) < 1e-10);
  assert.ok(Math.abs(lnGamma(0.5) - Math.log(Math.sqrt(Math.PI))) < 1e-10);
});

test('chi-square quantiles match tables', () => {
  assert.ok(Math.abs(chiSquareQuantile(0.95, 1) - 3.8415) < 1e-3);
  assert.ok(Math.abs(chiSquareQuantile(0.95, 2) - 5.9915) < 1e-3);
  assert.ok(Math.abs(chiSquareQuantile(0.025, 10) - 3.247) < 1e-3);
});

test('Poisson intervals match the exact (Garwood) table', () => {
  const [lo0, hi0] = poissonInterval(0);
  assert.equal(lo0, 0);
  assert.ok(Math.abs(hi0 - 3.689) < 1e-3);
  const [lo5, hi5] = poissonInterval(5);
  assert.ok(Math.abs(lo5 - 1.6235) < 1e-3);
  assert.ok(Math.abs(hi5 - 11.668) < 1e-3);
});

test('Chapman on a textbook example', () => {
  // M = 100 marked, C = 80 caught, R = 20 marked: Chapman N = 101·81/21 − 1 = 388.57
  const c = chapman(100, 80, 20);
  assert.ok(Math.abs(c.N - 388.571) < 1e-3);
  assert.ok(c.low < c.N && c.N < c.high);
  assert.ok(c.low >= 160, 'never below the animals actually seen');
});

test('Schnabel and Schumacher agree on a perfect survey', () => {
  // N = 200, each catch exactly matches the expected share of marked animals.
  const rows = [
    { C: 40, R: 0, M: 0 },
    { C: 40, R: 8, M: 40 },
    { C: 40, R: 14.4, M: 72 },
  ];
  const s = schnabel(rows);
  const e = schumacher(rows);
  assert.ok(e && Math.abs(e.N - 200) < 1e-9);
  assert.ok(e && Math.abs(e.fit - 1) < 1e-12);
  assert.ok(Math.abs(s.N - (40 * 40 + 40 * 72) / 23.4) < 1e-9);
});

test('Poisson-binomial probabilities sum to 1 and match a binomial', () => {
  const d = poissonBinomial([0.3, 0.3, 0.3]);
  assert.ok(Math.abs(d.reduce((a, b) => a + b, 0) - 1) < 1e-12);
  assert.ok(Math.abs(d[2] - 3 * 0.09 * 0.7) < 1e-12);
});

test('Chao lower bound', () => {
  assert.equal(chaoLowerBound(100, 20, 9), 100 + (20 * 19) / 20);
  assert.ok(Number.isFinite(chaoLowerBound(10, 10, 0)));
});

test('the planner gets the precision it promises', () => {
  for (const [N, p] of [
    [500, 0.1],
    [200, 0.2],
    [1000, 0.05],
  ]) {
    const { mark, recaptures } = planSample(N, p);
    assert.ok(Math.abs(recaptures - (mark * mark) / N) < 1e-9);
    const smaller = planSample(N, p * 2).mark;
    assert.ok(smaller < mark, 'a looser target needs fewer animals');
  }
});

test('simulation: the 95% intervals contain the true N about 95% of the time', () => {
  const N = 250;
  let inChapman = 0;
  let inSchnabel = 0;
  const runs = 300;
  for (let k = 0; k < runs; k++) {
    const a = analyse(parseSurvey(simulate(N, 4, () => 0.15, 1000 + k)));
    if (a.chapman.low <= N && N <= a.chapman.high) inChapman++;
    if (a.schnabel.low <= N && N <= a.schnabel.high) inSchnabel++;
  }
  assert.ok(inChapman / runs > 0.9, `Chapman coverage ${inChapman / runs}`);
  assert.ok(inSchnabel / runs > 0.9, `Schnabel coverage ${inSchnabel / runs}`);
});

test('simulation: estimates centre on the true N', () => {
  const N = 400;
  let sum = 0;
  const runs = 100;
  for (let k = 0; k < runs; k++) sum += analyse(parseSurvey(simulate(N, 5, () => 0.2, 7 + k))).schnabel.N;
  assert.ok(Math.abs(sum / runs - N) < 0.05 * N, `mean ${sum / runs}`);
});

test('simulation: trap-happy animals are detected, and Chao is closer to the truth', () => {
  const N = 300;
  const text = simulate(N, 6, (i) => (i % 3 === 0 ? 0.5 : 0.05), 99);
  const a = analyse(parseSurvey(text));
  assert.ok(a.checks.some((c) => c.level === 'warn' && /trap-happy/.test(c.text)));
  assert.ok(a.schnabel.N < 0.75 * N, 'equal-catchability estimates come out low');
  assert.ok(a.chao !== null && Math.abs(a.chao - N) < Math.abs(a.schnabel.N - N));
});

test('simulation: equal catchability passes the check most of the time', () => {
  let flagged = 0;
  for (let k = 0; k < 100; k++) {
    const a = analyse(parseSurvey(simulate(300, 5, () => 0.2, 500 + k)));
    if (a.frequencies?.heterogeneous) flagged++;
  }
  assert.ok(flagged <= 15, `flagged ${flagged} of 100`);
});

test('few recaptures and no recaptures give warnings, not crashes', () => {
  const few = analyse(parseSurvey('session A: X1 X2 X3 X4\nsession B: X1 Y1 Y2'));
  assert.ok(few.checks.some((c) => /Only 1 recaptures in session 2|Only 1 recaptures/.test(c.text)));
  const none = analyse(parseSurvey('session A: X1 X2\nsession B: Y1 Y2'));
  assert.equal(none.schnabel.high, Infinity);
  assert.ok(render(none).includes('no limit'));
  assert.ok(toJSON(none).includes('"high": null'));
});

test('captureFrequencies ignores animals that were kept', () => {
  const s = parseSurvey('session A: X Y Z!\nsession B: X Y\nsession C: X');
  const f = captureFrequencies(s.sessions, 10);
  assert.equal(f.animals, 2);
  assert.deepEqual(f.observed, [0, 1, 1]);
});

// ---------- the command line ----------

/** @param {string[]} args @param {string} [input] */
function run(args, input) {
  return spawnSync(process.execPath, [bin, ...args], { input, encoding: 'utf8' });
}

test('CLI: report on each example', () => {
  for (const f of fs.readdirSync(examples)) {
    const r = run([path.join(examples, f)]);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /^TAGBACK /);
    assert.match(r.stdout, /Schnabel, all sessions/);
  }
});

test('CLI: --json, --precision and standard input', () => {
  const text = fs.readFileSync(path.join(examples, 'frog-pond.txt'), 'utf8');
  const r = run(['--json', '--precision', '15', '-'], text);
  assert.equal(r.status, 0, r.stderr);
  const j = JSON.parse(r.stdout);
  assert.deepEqual(
    j.plans.map((/** @type {{precision:number}} */ p) => p.precision),
    [0.2, 0.15, 0.1],
  );
});

test('CLI: usage errors exit 2', () => {
  assert.equal(run([]).status, 2);
  assert.equal(run(['--precision', '90', 'x']).status, 2);
  assert.equal(run(['--precision', '1e1', 'x']).status, 2);
  assert.equal(run(['--bogus\u001b[2J', 'x']).stderr.includes('\u001b'), false);
});

test('CLI: refuses symlinks, directories, devices, big and non-UTF-8 files', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tagback-'));
  try {
    const real = path.join(dir, 'real.txt');
    fs.writeFileSync(real, 'session A: X\nsession B: X\n');
    const link = path.join(dir, 'link.txt');
    fs.symlinkSync(real, link);
    assert.match(run([link]).stderr, /symbolic link/);
    assert.match(run([dir]).stderr, /not a regular file/);
    assert.match(run(['/dev/zero']).stderr, /not a regular file/);
    const big = path.join(dir, 'big.txt');
    fs.writeFileSync(big, '#'.repeat(300 * 1024));
    assert.match(run([big]).stderr, /larger than 256 KB/);
    const bad = path.join(dir, 'bad.txt');
    fs.writeFileSync(bad, Buffer.from([0x73, 0x65, 0xff, 0xfe, 0x0a]));
    assert.match(run([bad]).stderr, /not valid UTF-8/);
    assert.match(run([path.join(dir, 'missing\u001b.txt')]).stderr, /missing\?\.txt does not exist/);
    assert.equal(run(['-'], 'x'.repeat(300 * 1024)).status, 2);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
