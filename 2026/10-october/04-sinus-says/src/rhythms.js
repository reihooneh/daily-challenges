// Synthetic ECG generation.
//
// Each heartbeat is drawn as a sum of smooth bumps (Gaussians): a small P wave,
// the sharp QRS complex and a rounded T wave. A rhythm is then just a schedule
// of when beats happen and what shape each one has.
//
// These are simplified teaching waveforms, not physiological simulations.

import { between, mulberry32 } from './rng.js';

export const DURATION = 6; // seconds: the classic "6-second strip"
export const SAMPLE_RATE = 250; // samples per second

export const RHYTHMS = [
  { id: 'nsr', name: 'Normal sinus rhythm' },
  { id: 'brady', name: 'Sinus bradycardia' },
  { id: 'tachy', name: 'Sinus tachycardia' },
  { id: 'afib', name: 'Atrial fibrillation' },
  { id: 'flutter', name: 'Atrial flutter' },
  { id: 'pvc', name: 'Sinus rhythm with PVCs' },
  { id: 'avb1', name: 'First-degree AV block' },
  { id: 'vt', name: 'Ventricular tachycardia' },
];

const IDS = new Set(RHYTHMS.map((r) => r.id));

const gauss = (t, centre, width) => Math.exp(-((t - centre) ** 2) / (2 * width * width));

/** Voltage (mV) contributed at time t by one beat whose R peak is at beat.t. */
function beatVoltage(t, beat) {
  const dt = t - beat.t;
  if (dt < -0.5 || dt > 0.6) return 0; // a beat only affects its own neighbourhood
  if (beat.wide) {
    // Ventricular beat: broad, bizarre QRS with the T wave pointing the other way.
    return 1.1 * gauss(dt, 0, 0.035) - 0.55 * gauss(dt, 0.075, 0.035) - 0.3 * gauss(dt, 0.26, 0.06);
  }
  let v = -0.08 * gauss(dt, -0.022, 0.008) + 1.0 * gauss(dt, 0, 0.01) - 0.18 * gauss(dt, 0.024, 0.01);
  v += (beat.flat ? 0 : 0.28) * gauss(dt, beat.tWave, 0.045);
  if (beat.pr !== null) {
    // PR interval runs from the start of P to the start of QRS (about 30 ms before R).
    const pPeak = -0.03 - beat.pr + 0.045;
    v += 0.15 * gauss(dt, pPeak, 0.018);
  }
  return v;
}

/** Regular sinus-style beats across the strip, with slight natural variation. */
function regularBeats(rand, rate, pr, wide = false) {
  const rr = 60 / rate;
  const beats = [];
  for (let t = between(rand, 0.1, rr); t < DURATION + rr; t += rr * between(rand, 0.985, 1.015)) {
    beats.push({ t, pr, wide, tWave: Math.min(0.26, 0.42 * rr) });
  }
  return beats;
}

const SCHEDULES = {
  nsr: (rand) => ({ beats: regularBeats(rand, between(rand, 64, 96), 0.16), baseline: 'flat' }),
  brady: (rand) => ({ beats: regularBeats(rand, between(rand, 38, 50), 0.16), baseline: 'flat' }),
  tachy: (rand) => ({ beats: regularBeats(rand, between(rand, 112, 140), 0.14), baseline: 'flat' }),
  avb1: (rand) => ({ beats: regularBeats(rand, between(rand, 64, 88), between(rand, 0.26, 0.32)), baseline: 'flat' }),
  vt: (rand) => ({ beats: regularBeats(rand, between(rand, 150, 190), null, true), baseline: 'flat' }),

  afib: (rand) => {
    // "Irregularly irregular": every gap is different, and there are no P waves.
    const mean = 60 / (rand() < 0.5 ? between(rand, 68, 90) : between(rand, 115, 135));
    const beats = [];
    for (let t = between(rand, 0.1, mean); t < DURATION + mean; t += mean * between(rand, 0.6, 1.45)) {
      beats.push({ t, pr: null, wide: false, tWave: Math.min(0.26, 0.42 * mean) });
    }
    return { beats, baseline: 'fib' };
  },

  flutter: (rand) => {
    // The atria fire about 300 times a minute; only every 4th (or 2nd) impulse gets through.
    const ratio = rand() < 0.7 ? 4 : 2;
    const rr = (60 / 300) * ratio;
    const beats = [];
    for (let t = between(rand, 0.1, rr); t < DURATION + rr; t += rr) {
      // The flutter waves bury the T wave, so none is drawn.
      beats.push({ t, pr: null, wide: false, flat: true, tWave: 0.26 });
    }
    return { beats, baseline: 'flutter' };
  },

  pvc: (rand) => {
    // A PVC arrives early, has no P wave, looks wide, and is followed by a pause.
    const rr = 60 / between(rand, 62, 86);
    const sinusCount = Math.ceil(DURATION / rr) + 2;
    const first = between(rand, 0.1, rr);
    const pvcAfter = new Set([2 + Math.floor(rand() * 2)]);
    if (rand() < 0.5) pvcAfter.add([...pvcAfter][0] + 3);
    const beats = [];
    for (let i = 0; i < sinusCount; i++) {
      const t = first + i * rr;
      if (pvcAfter.has(i - 1)) continue; // the sinus beat after a PVC is blocked: the pause
      beats.push({ t, pr: 0.16, wide: false, tWave: Math.min(0.26, 0.42 * rr) });
      if (pvcAfter.has(i)) beats.push({ t: t + rr * 0.62, pr: null, wide: true, tWave: 0.26 });
    }
    return { beats, baseline: 'flat' };
  },
};

/** Baseline activity between beats (mV). */
function baselineVoltage(t, kind, phases) {
  if (kind === 'fib') {
    // Chaotic, fine wobble instead of P waves.
    return 0.035 * Math.sin(2 * Math.PI * 5.3 * t + phases[0]) + 0.025 * Math.sin(2 * Math.PI * 7.1 * t + phases[1]) +
      0.02 * Math.sin(2 * Math.PI * 9.4 * t + phases[2]);
  }
  if (kind === 'flutter') {
    // Sawtooth at 5 Hz (300 per minute): slow fall, sharp rise.
    const phase = (t * 5 + phases[0]) % 1;
    return 0.2 * (0.5 - phase);
  }
  return 0;
}

const EDGE = 0.08; // seconds

const rateClass = (rate) => (rate < 60 ? 'slow' : rate > 100 ? 'fast' : 'normal');

/**
 * True when both ways of reading the rate agree (counting complexes x 10, and
 * measuring the gaps) and the rhythm is clearly regular or clearly irregular.
 */
function isClearCut(beats) {
  if (beats.length < 3) return false;
  const gaps = beats.slice(1).map((b, i) => b.t - beats[i].t);
  const mean = gaps.reduce((a, b) => a + b, 0) / gaps.length;
  const spread = Math.sqrt(gaps.reduce((a, g) => a + (g - mean) ** 2, 0) / gaps.length) / mean;
  const measured = 60 / mean;
  const nearLimit = Math.abs(measured - 60) < 4 || Math.abs(measured - 100) < 4;
  return !nearLimit && rateClass(beats.length * 10) === rateClass(measured) && (spread < 0.04 || spread > 0.12);
}

/**
 * Generates one strip. The same (rhythmId, seed) always gives the same result.
 * Throws RangeError for an unknown rhythm or an invalid seed.
 */
export function generateStrip(rhythmId, seed) {
  if (!IDS.has(rhythmId)) throw new RangeError(`unknown rhythm: ${String(rhythmId).slice(0, 20)}`);
  if (!Number.isInteger(seed) || seed < 0 || seed > 0xffffffff) throw new RangeError('seed must be a 32-bit unsigned integer');

  const rand = mulberry32(seed);
  // Random timing can land on a borderline strip (a rate of 59 or 61, or a
  // rhythm that is only slightly irregular). Those are unfair quiz questions,
  // so redraw until the strip is clear-cut. The loop is bounded and still
  // fully determined by the seed.
  let beats;
  let baseline;
  for (let attempt = 0; attempt < 50; attempt++) {
    const schedule = SCHEDULES[rhythmId](rand);
    baseline = schedule.baseline;
    // A complex cut in half by the edge of the paper is confusing: drop it.
    beats = schedule.beats.filter((b) => b.t > EDGE && b.t < DURATION - EDGE);
    if (isClearCut(beats)) break;
  }
  const phases = [rand() * 6.28, rand() * 6.28, rand() * 6.28];
  if (baseline === 'flutter') {
    // Lock the sawtooth to the beats, as in real flutter.
    phases[0] = 1 - ((beats[0].t * 5) % 1) + 0.35;
  }
  const wander = rand() * 6.28;

  const count = DURATION * SAMPLE_RATE;
  const samples = new Float64Array(count);
  for (let i = 0; i < count; i++) {
    const t = i / SAMPLE_RATE;
    let v = baselineVoltage(t, baseline, phases) + 0.015 * Math.sin(2 * Math.PI * 0.25 * t + wander);
    for (const beat of beats) v += beatVoltage(t, beat);
    samples[i] = v + (rand() - 0.5) * 0.012; // a little measurement noise
  }

  return { rhythmId, seed, baseline, beats, samples, sampleRate: SAMPLE_RATE, duration: DURATION };
}
