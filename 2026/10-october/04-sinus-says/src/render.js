// Drawing maths, kept separate from the page so it can be tested.
//
// ECG paper runs at 25 mm per second and 10 mm per millivolt. We use 10 px per
// mm, so a small box (1 mm = 40 ms) is 10 px and a large box (200 ms) is 50 px.

export const PX_PER_SECOND = 250;
export const PX_PER_MV = 100;
export const HEIGHT = 300;
export const BASELINE_Y = 190;

/** Builds the SVG path for a tracing. Output contains only numbers, M and L. */
export function tracePath(samples, sampleRate) {
  const parts = [];
  for (let i = 0; i < samples.length; i++) {
    const x = (i / sampleRate) * PX_PER_SECOND;
    const raw = BASELINE_Y - samples[i] * PX_PER_MV;
    const y = Number.isFinite(raw) ? Math.min(HEIGHT, Math.max(0, raw)) : BASELINE_Y;
    parts.push(`${i === 0 ? 'M' : 'L'}${x.toFixed(1)},${y.toFixed(1)}`);
  }
  return parts.join(' ');
}

export function stripWidth(duration) {
  return duration * PX_PER_SECOND;
}
