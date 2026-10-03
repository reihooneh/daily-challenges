// Seeded random numbers and strip codes.
//
// Math.random() can't be seeded, so two people could never see the same strip.
// mulberry32 is a tiny, well-known generator: the same seed always produces the
// same sequence, which makes every strip reproducible from a short code.

export const MAX_SEED = 0xffffffff;

/** Returns a function that yields numbers in [0, 1), deterministic for a seed. */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A number in [min, max). */
export function between(rand, min, max) {
  return min + rand() * (max - min);
}

/** A random element of a non-empty array. */
export function pick(rand, items) {
  return items[Math.floor(rand() * items.length)];
}

/** Fisher-Yates shuffle; returns a new array. */
export function shuffle(rand, items) {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

/** Turns a seed into a short shareable code such as "K7Q2M". */
export function codeFor(seed) {
  return (seed >>> 0).toString(36).toUpperCase();
}

/**
 * Parses a strip code typed by a user. Returns the seed, or null if the text
 * is not a valid code. Only 1-7 letters and digits are accepted, so nothing
 * typed here can ever be anything other than a number.
 */
export function parseCode(text) {
  if (typeof text !== 'string') return null;
  const trimmed = text.trim();
  if (!/^[0-9a-z]{1,7}$/i.test(trimmed)) return null;
  const seed = Number.parseInt(trimmed, 36);
  return Number.isSafeInteger(seed) && seed <= MAX_SEED ? seed : null;
}
