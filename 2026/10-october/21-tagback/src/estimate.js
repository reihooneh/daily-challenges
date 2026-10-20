// Population estimates from mark-recapture counts.
//
// The idea (Petersen, 1896): mark M animals and release them. Later catch C animals, of which R
// are marked. If marked animals mix in evenly, R/C ≈ M/N, so N ≈ M·C/R.

const Z95 = 1.959964;

/**
 * Chapman's version of the two-session estimate, nearly unbiased when R ≥ 7 (Robson & Regier).
 * The 95% interval is on the log scale, so it is never negative and is skewed upwards, as the
 * real uncertainty is.
 * @param {number} M marked in session 1  @param {number} C caught in session 2  @param {number} R marked among them
 */
export function chapman(M, C, R) {
  const N = ((M + 1) * (C + 1)) / (R + 1) - 1;
  const v = ((M + 1) * (C + 1) * (M - R) * (C - R)) / ((R + 1) ** 2 * (R + 2));
  const known = M + C - R; // animals actually seen: the population can't be smaller
  if (v <= 0 || N <= known) return { N, low: Math.max(known, N), high: N, se: Math.sqrt(Math.max(v, 0)) };
  // Log-normal interval on the part of N we haven't seen (Chao 1987).
  const f = N - known;
  const c = Math.exp(Z95 * Math.sqrt(Math.log(1 + v / (f * f))));
  return { N, low: known + f / c, high: known + f * c, se: Math.sqrt(v) };
}

/**
 * Schnabel's estimate for several sessions: N = Σ C·M / (Σ R + 1).
 * 95% interval: when recaptures are few (ΣR < 50) treat ΣR as Poisson; otherwise use the normal
 * approximation for 1/N. Both are the textbook choices (Krebs, Ecological Methodology).
 * @param {{C:number, R:number, M:number}[]} rows
 */
export function schnabel(rows) {
  let sumCM = 0;
  let sumR = 0;
  for (const r of rows) {
    sumCM += r.C * r.M;
    sumR += r.R;
  }
  const N = sumCM / (sumR + 1);
  let low;
  let high;
  if (sumR < 50) {
    const [lo, hi] = poissonInterval(sumR);
    low = sumCM / (hi + 1);
    high = lo > 0 ? sumCM / lo : Infinity;
  } else {
    const inv = sumR / sumCM;
    const se = Math.sqrt(sumR) / sumCM;
    low = 1 / (inv + Z95 * se);
    high = inv - Z95 * se > 0 ? 1 / (inv - Z95 * se) : Infinity;
  }
  return { N, low, high, recaptures: sumR };
}

/**
 * Schumacher–Eschmeyer: the share of marked animals in each catch (R/C) should rise in a straight
 * line through the origin as more are marked (slope 1/N). A weighted regression gives N, and how
 * well the points fit that line is a check on the assumptions.
 * @param {{C:number, R:number, M:number}[]} rows
 */
export function schumacher(rows) {
  const used = rows.filter((r) => r.M > 0 && r.C > 0);
  let sxx = 0;
  let sxy = 0;
  let syy = 0;
  for (const r of used) {
    sxx += r.C * r.M * r.M;
    sxy += r.R * r.M;
    syy += (r.R * r.R) / r.C;
  }
  if (sxy === 0 || used.length < 2) return null;
  const N = sxx / sxy;
  // Weighted R² of the line through the origin: how much of the pattern the line explains.
  const fit = syy > 0 ? (sxy * sxy) / (sxx * syy) : 0;
  const points = used.map((r) => ({ label: /** @type {any} */ (r).label, marked: r.M, share: r.R / r.C, expected: r.M / N }));
  return { N, fit, points };
}

/**
 * Chao's estimate for animals that differ in how catchable they are: N = S + f1² / (2·f2), where
 * S animals were seen, f1 of them once and f2 twice. Animals seen only once hint at many more that
 * were never seen. It is best read as a lower bound (Chao 1987). Uses the bias-corrected form
 * f1(f1−1) / (2(f2+1)) so it stays finite when f2 = 0.
 * @param {number} S @param {number} f1 @param {number} f2
 */
export function chaoLowerBound(S, f1, f2) {
  return S + (f1 * (f1 - 1)) / (2 * (f2 + 1));
}

/** Exact 95% interval for a Poisson count k (Garwood), via the chi-square quantile. @param {number} k */
export function poissonInterval(k) {
  const lo = k === 0 ? 0 : chiSquareQuantile(0.025, 2 * k) / 2;
  const hi = chiSquareQuantile(0.975, 2 * (k + 1)) / 2;
  return [lo, hi];
}

/** Chi-square quantile by bisection on the regularised gamma function. @param {number} p @param {number} df */
export function chiSquareQuantile(p, df) {
  let lo = 0;
  let hi = Math.max(10, df * 4 + 50);
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (gammaP(df / 2, mid / 2) < p) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}

/** Regularised lower incomplete gamma P(a, x), series or continued fraction (Numerical Recipes). */
function gammaP(/** @type {number} */ a, /** @type {number} */ x) {
  if (x <= 0) return 0;
  const lnGammaA = lnGamma(a);
  if (x < a + 1) {
    let sum = 1 / a;
    let term = sum;
    for (let n = 1; n < 500; n++) {
      term *= x / (a + n);
      sum += term;
      if (Math.abs(term) < Math.abs(sum) * 1e-15) break;
    }
    return sum * Math.exp(-x + a * Math.log(x) - lnGammaA);
  }
  let b = x + 1 - a;
  let c = 1e300;
  let d = 1 / b;
  let h = d;
  for (let i = 1; i < 500; i++) {
    const an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (Math.abs(d) < 1e-300) d = 1e-300;
    c = b + an / c;
    if (Math.abs(c) < 1e-300) c = 1e-300;
    d = 1 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1) < 1e-15) break;
  }
  return 1 - Math.exp(-x + a * Math.log(x) - lnGammaA) * h;
}

/** Lanczos approximation of ln Γ(z). @param {number} z @returns {number} */
export function lnGamma(z) {
  const g = 7;
  const coef = [
    0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
    12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
  ];
  if (z < 0.5) return Math.log(Math.PI / Math.sin(Math.PI * z)) - lnGamma(1 - z);
  const zz = z - 1;
  let x = coef[0];
  for (let i = 1; i < g + 2; i++) x += coef[i] / (zz + i);
  const t = zz + g + 0.5;
  return 0.5 * Math.log(2 * Math.PI) + (zz + 0.5) * Math.log(t) - t + Math.log(x);
}

/**
 * Planning the next survey: with a population of about N, how many must be marked and then
 * caught (the same number each time) for the 95% interval to be within ±precision of N?
 * Uses Chapman's variance with the expected recaptures R = M·C/N, so it's an approximation.
 * @param {number} N @param {number} precision e.g. 0.1 for ±10%
 */
export function planSample(N, precision) {
  for (let k = 2; k <= N; k++) {
    const R = (k * k) / N;
    if (R < 1) continue;
    const v = ((k + 1) * (k + 1) * (k - R) * (k - R)) / ((R + 1) ** 2 * (R + 2));
    if (Z95 * Math.sqrt(v) <= precision * N) return { mark: k, recaptures: R };
  }
  return { mark: Math.ceil(N), recaptures: N };
}
