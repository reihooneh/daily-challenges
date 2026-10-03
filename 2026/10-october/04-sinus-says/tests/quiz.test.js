import assert from 'node:assert/strict';
import { test } from 'node:test';

import { buildQuestion, EXPLANATIONS, grade } from '../src/quiz.js';
import { tracePath } from '../src/render.js';
import { generateStrip, RHYTHMS } from '../src/rhythms.js';
import { parseCode } from '../src/rng.js';

const SEEDS = Array.from({ length: 300 }, (_, i) => (i * 40503 + 17) >>> 0);

test('every question has five steps and exactly one right answer per step', () => {
  for (const seed of SEEDS) {
    const q = buildQuestion(seed);
    assert.deepEqual(q.steps.map((s) => s.id), ['rate', 'regular', 'p', 'qrs', 'name']);
    q.steps.forEach((step, i) => {
      const right = step.options.filter(([value]) => grade(q, i, value));
      assert.equal(right.length, 1, `seed ${seed} step ${step.id}`);
      assert.ok(step.detail.length > 0);
    });
  }
});

test('the rhythm choices are four different rhythms including the right one', () => {
  for (const seed of SEEDS) {
    const { steps, strip } = buildQuestion(seed);
    const values = steps[4].options.map(([value]) => value);
    assert.equal(new Set(values).size, 4);
    assert.ok(values.includes(strip.rhythmId));
  }
});

test('the same code gives the same question to everyone', () => {
  const a = buildQuestion(parseCode('K7Q2M'));
  const b = buildQuestion(parseCode('k7q2m'));
  assert.deepEqual(a.steps, b.steps);
  assert.deepEqual(a.strip.samples, b.strip.samples);
});

test('all eight rhythms turn up, and each has an explanation', () => {
  const seen = new Set(SEEDS.map((seed) => buildQuestion(seed).strip.rhythmId));
  assert.equal(seen.size, RHYTHMS.length);
  for (const { id } of RHYTHMS) assert.ok(EXPLANATIONS[id]);
});

test('the tracing path contains only drawing commands and numbers', () => {
  for (const { id } of RHYTHMS) {
    const strip = generateStrip(id, 5);
    assert.match(tracePath(strip.samples, strip.sampleRate), /^M[\d.]+,[\d.]+( L[\d.]+,[\d.]+)*$/);
  }
});

// ---- Hostile and broken input -------------------------------------------

test('strip codes reject anything that is not 1-7 letters or digits', () => {
  const hostile = [
    '', ' ', '<script>alert(1)</script>', '"><img src=x onerror=alert(1)>', 'javascript:alert(1)',
    '../../etc/passwd', "'; DROP TABLE strips;--", 'K7Q2M\nX', 'K7 Q2M', '-1', '+1', '1.5', '1_0', 'ZZZZZZZZ',
    '%3Cscript%3E', 'Ｋ７Ｑ２Ｍ', 'ⅷ', '\u0000', 'a'.repeat(100000), '__proto__', 'constructor',
  ];
  for (const text of hostile) assert.equal(parseCode(text), null, JSON.stringify(text.slice(0, 30)));
  for (const value of [null, undefined, 42, {}, [], true, Symbol('x')]) assert.equal(parseCode(value), null);
});

test('codes above the 32-bit range are rejected, not wrapped around', () => {
  assert.equal(parseCode('1Z141Z3'), 4294967295);
  assert.equal(parseCode('1Z141Z4'), null);
  assert.equal(parseCode('ZZZZZZZ'), null);
});

test('a hostile code is rejected quickly (no slow regular expression)', () => {
  const started = performance.now();
  for (let i = 0; i < 200; i++) parseCode(`${'a'.repeat(50000)}!`);
  assert.ok(performance.now() - started < 1000);
});

test('the generator refuses unknown rhythms and bad seeds', () => {
  for (const id of ['', 'NSR', '__proto__', 'constructor', 'toString', '<svg>', null, undefined, 7]) {
    assert.throws(() => generateStrip(id, 1), RangeError);
  }
  for (const seed of [-1, 1.5, NaN, Infinity, 2 ** 32, '1', null, undefined]) {
    assert.throws(() => generateStrip('nsr', seed), RangeError);
  }
});

test('an error about an unknown rhythm never echoes more than 20 characters', () => {
  assert.throws(() => generateStrip('x'.repeat(5000), 1), (error) => error.message.length < 60);
});

test('marking never throws: unknown steps and choices are just wrong', () => {
  const q = buildQuestion(123);
  for (const index of [-1, 5, 99, 1.5, NaN, '0', null, undefined, '__proto__']) {
    assert.equal(grade(q, index, q.steps[0].answer), false);
  }
  for (const choice of ['', 'SLOW', '__proto__', '<b>', null, undefined, 0, {}]) {
    assert.equal(grade(q, 0, choice), false);
  }
});

test('the path clamps impossible voltages instead of drawing off the paper', () => {
  const path = tracePath(Float64Array.of(0, 1e9, -1e9, NaN, Infinity), 250);
  assert.match(path, /^M[\d.]+,[\d.]+( L[\d.]+,[\d.]+)*$/);
  assert.ok(!/NaN|Infinity|e\+/.test(path));
});
