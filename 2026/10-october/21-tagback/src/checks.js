// Checking the assumptions behind the estimates.
//
// Mark-recapture assumes every animal is equally likely to be caught in a session. If some are
// much easier to catch (bolder, bigger, living near the traps), the same animals keep turning up
// and the population is UNDER-estimated. That leaves a fingerprint in how many times each animal
// was caught, which we compare with what equal catchability predicts.

/**
 * Probability of being caught exactly k times (k = 0..T) when the chance in session t is p[t]:
 * the Poisson-binomial distribution, by dynamic programming.
 * @param {number[]} p
 */
export function poissonBinomial(p) {
  let dist = [1];
  for (const q of p) {
    const next = new Array(dist.length + 1).fill(0);
    for (let k = 0; k < dist.length; k++) {
      next[k] += dist[k] * (1 - q);
      next[k + 1] += dist[k] * q;
    }
    dist = next;
  }
  return dist;
}

/**
 * Observed animals caught 1, 2, 3+ times, against the expectation with equal catchability.
 * Ignores animals kept (not released), since they couldn't be caught again.
 * @param {{caught: string[], kept: Set<string>}[]} sessions @param {number} N estimated population
 */
export function captureFrequencies(sessions, N) {
  const times = new Map();
  const removed = new Set();
  for (const s of sessions) {
    for (const tag of s.caught) times.set(tag, (times.get(tag) ?? 0) + 1);
    for (const tag of s.kept) removed.add(tag);
  }
  const p = sessions.map((s) => Math.min(1, s.caught.length / N));
  const dist = poissonBinomial(p);
  const T = sessions.length;
  const observed = new Array(T + 1).fill(0);
  for (const [tag, k] of times) if (!removed.has(tag)) observed[k]++;
  const animals = [...times.keys()].filter((t) => !removed.has(t)).length;
  // Expected counts among the animals actually seen (k ≥ 1), scaled to the same total.
  const seenProb = 1 - dist[0];
  const expected = dist.map((d, k) => (k === 0 || seenProb <= 0 ? 0 : (animals * d) / seenProb));
  // Group into 1, 2, 3+ so expected counts aren't tiny.
  const group = (/** @type {number[]} */ arr) => [arr[1] ?? 0, arr[2] ?? 0, arr.slice(3).reduce((a, b) => a + b, 0)];
  const obs = group(observed);
  const exp = group(expected);
  let chi = 0;
  for (let i = 0; i < 3; i++) if (exp[i] > 0) chi += (obs[i] - exp[i]) ** 2 / exp[i];
  // 5.99 is the 95% point of chi-square with 2 degrees of freedom. Too many animals seen once AND
  // too many seen often (with too few in between) is the classic sign of mixed catchability.
  return { observed: obs, expected: exp, chi, heterogeneous: chi > 5.99, f1: observed[1] ?? 0, f2: observed[2] ?? 0, animals };
}
