// Measuring a strip: what a clinician works out before naming a rhythm.
//
// Rate and regularity are measured from the waveform itself by detecting R
// peaks, exactly as you would with calipers. P waves and QRS width come from
// how the strip was generated.

/**
 * Finds R peaks: local maxima above a threshold, at least 200 ms apart (the
 * heart's refractory period, so one beat can never be counted twice).
 * Returns peak times in seconds.
 */
export function detectBeats(samples, sampleRate) {
  const threshold = 0.5; // mV; P and T waves stay well below this
  const refractory = Math.round(0.2 * sampleRate);
  const peaks = [];
  let last = -Infinity;
  for (let i = 1; i < samples.length - 1; i++) {
    if (samples[i] < threshold || i - last < refractory) continue;
    // Look at the neighbourhood so noise on the peak doesn't create extra maxima.
    let isMax = true;
    for (let j = Math.max(0, i - 10); j <= Math.min(samples.length - 1, i + 10); j++) {
      if (samples[j] > samples[i]) { isMax = false; break; }
    }
    if (isMax) { peaks.push(i / sampleRate); last = i; }
  }
  return peaks;
}

/** Works out the features a learner is asked about. */
export function measure(strip) {
  const peaks = detectBeats(strip.samples, strip.sampleRate);
  const gaps = peaks.slice(1).map((t, i) => t - peaks[i]);
  const meanGap = gaps.reduce((a, b) => a + b, 0) / Math.max(1, gaps.length);
  const rate = gaps.length ? Math.round(60 / meanGap) : 0;

  // Coefficient of variation: how much the gaps differ, relative to their size.
  const variance = gaps.reduce((a, g) => a + (g - meanGap) ** 2, 0) / Math.max(1, gaps.length);
  const variation = gaps.length ? Math.sqrt(variance) / meanGap : 0;

  const withP = strip.beats.filter((b) => b.pr !== null).length;
  const wide = strip.beats.filter((b) => b.wide).length;
  const total = strip.beats.length;

  let pWaves = 'every';
  if (strip.baseline === 'flutter') pWaves = 'sawtooth';
  else if (withP === 0) pWaves = 'none';
  else if (withP < total) pWaves = 'most';

  let qrs = 'narrow';
  if (wide === total) qrs = 'wide';
  else if (wide > 0) qrs = 'mixed';

  const prs = strip.beats.filter((b) => b.pr !== null).map((b) => b.pr);
  return {
    beatCount: peaks.length,
    rate,
    rateClass: rate < 60 ? 'slow' : rate > 100 ? 'fast' : 'normal',
    regular: variation < 0.08,
    variation,
    pWaves,
    qrs,
    prMs: prs.length ? Math.round((prs.reduce((a, b) => a + b, 0) / prs.length) * 1000) : null,
  };
}
