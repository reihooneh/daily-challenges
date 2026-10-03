import assert from 'node:assert/strict';
import { test } from 'node:test';

import { detectBeats, measure } from '../src/measure.js';
import { DURATION, RHYTHMS, SAMPLE_RATE, generateStrip } from '../src/rhythms.js';
import { MAX_SEED, codeFor, mulberry32, parseCode, shuffle } from '../src/rng.js';

const SEEDS = Array.from({ length: 150 }, (_, i) => (i * 2654435761) >>> 0);
const each = (id, check) => SEEDS.forEach((seed) => check(measure(generateStrip(id, seed)), seed));

test('the same seed always gives the same random sequence', () => {
  const a = mulberry32(42);
  const b = mulberry32(42);
  for (let i = 0; i < 100; i++) assert.equal(a(), b());
  assert.notEqual(mulberry32(1)(), mulberry32(2)());
});

test('random numbers stay inside [0, 1)', () => {
  const rand = mulberry32(7);
  for (let i = 0; i < 10000; i++) {
    const n = rand();
    assert.ok(n >= 0 && n < 1);
  }
});

test('shuffle keeps every item exactly once', () => {
  const out = shuffle(mulberry32(3), [1, 2, 3, 4, 5, 6]);
  assert.deepEqual([...out].sort(), [1, 2, 3, 4, 5, 6]);
});

test('strip codes round-trip for any seed', () => {
  for (const seed of [0, 1, 35, 36, 123456789, MAX_SEED]) assert.equal(parseCode(codeFor(seed)), seed);
  assert.equal(parseCode('  k7q2m '), parseCode('K7Q2M'));
});

test('a strip is exactly 6 seconds of finite samples', () => {
  for (const { id } of RHYTHMS) {
    const strip = generateStrip(id, 99);
    assert.equal(strip.samples.length, DURATION * SAMPLE_RATE);
    assert.ok(strip.samples.every((v) => Number.isFinite(v) && Math.abs(v) < 3));
  }
});

test('the same rhythm and seed reproduce the identical tracing', () => {
  for (const { id } of RHYTHMS) {
    assert.deepEqual(generateStrip(id, 2024).samples, generateStrip(id, 2024).samples);
  }
  assert.notDeepEqual(generateStrip('nsr', 1).samples, generateStrip('nsr', 2).samples);
});

test('the beat detector finds every generated beat, and nothing else', () => {
  for (const { id } of RHYTHMS) {
    for (const seed of SEEDS) {
      const strip = generateStrip(id, seed);
      const peaks = detectBeats(strip.samples, strip.sampleRate);
      assert.equal(peaks.length, strip.beats.length, `${id} seed ${seed}`);
      peaks.forEach((t, i) => assert.ok(Math.abs(t - strip.beats[i].t) < 0.03, `${id} seed ${seed}`));
    }
  }
});

test('normal sinus rhythm: normal rate, regular, P waves, narrow QRS', () => {
  each('nsr', (m) => assert.deepEqual([m.rateClass, m.regular, m.pWaves, m.qrs], ['normal', true, 'every', 'narrow']));
});

test('sinus bradycardia is slow and sinus tachycardia is fast', () => {
  each('brady', (m) => assert.deepEqual([m.rateClass, m.regular, m.pWaves], ['slow', true, 'every']));
  each('tachy', (m) => assert.deepEqual([m.rateClass, m.regular, m.pWaves], ['fast', true, 'every']));
});

test('atrial fibrillation is irregular with no P waves', () => {
  each('afib', (m) => assert.deepEqual([m.regular, m.pWaves, m.qrs], [false, 'none', 'narrow']));
});

test('atrial flutter is regular with a sawtooth baseline', () => {
  each('flutter', (m) => {
    assert.deepEqual([m.regular, m.pWaves, m.qrs], [true, 'sawtooth', 'narrow']);
    assert.ok(Math.abs(m.rate - 75) <= 2 || Math.abs(m.rate - 150) <= 3);
  });
});

test('PVCs make the rhythm irregular with a mix of narrow and wide beats', () => {
  each('pvc', (m) => assert.deepEqual([m.regular, m.pWaves, m.qrs], [false, 'most', 'mixed']));
});

test('first-degree block has a PR interval over 200 ms; normal rhythm does not', () => {
  each('avb1', (m) => assert.ok(m.prMs > 200 && m.regular && m.pWaves === 'every'));
  each('nsr', (m) => assert.ok(m.prMs >= 120 && m.prMs <= 200));
});

test('ventricular tachycardia is fast, regular and wide with no P waves', () => {
  each('vt', (m) => assert.deepEqual([m.rateClass, m.regular, m.pWaves, m.qrs], ['fast', true, 'none', 'wide']));
});

test('counting complexes x 10 always agrees with the measured rate class', () => {
  const classOf = (rate) => (rate < 60 ? 'slow' : rate > 100 ? 'fast' : 'normal');
  for (const { id } of RHYTHMS) each(id, (m, seed) => assert.equal(classOf(m.beatCount * 10), m.rateClass, `${id} seed ${seed}`));
});

test('the detector copes with empty, flat and tiny inputs', () => {
  assert.deepEqual(detectBeats(new Float64Array(0), 250), []);
  assert.deepEqual(detectBeats(new Float64Array(1500), 250), []);
  assert.deepEqual(detectBeats(Float64Array.of(1), 250), []);
  assert.equal(measure({ samples: new Float64Array(1500), sampleRate: 250, beats: [], baseline: 'flat' }).rate, 0);
});
