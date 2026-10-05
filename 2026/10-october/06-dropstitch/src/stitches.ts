// The stitch dictionary.
//
// Every knitting stitch can be described by two numbers: how many stitches it
// uses up from the left needle, and how many it leaves on the right needle.
// That is all a stitch-count checker needs to know.

export interface Stitch {
  readonly uses: number;
  readonly makes: number;
  /** True if the stitch can take a count, as in "K3" (knit three). */
  readonly countable: boolean;
  readonly meaning: string;
}

const stitch = (uses: number, makes: number, meaning: string, countable = false): Stitch =>
  Object.freeze({ uses, makes, countable, meaning });

// A Map, not a plain object: a pattern containing a word like "constructor"
// or "__proto__" must never match something inherited from Object.
export const STITCHES: ReadonlyMap<string, Stitch> = new Map([
  ['k', stitch(1, 1, 'knit', true)],
  ['p', stitch(1, 1, 'purl', true)],
  ['sl', stitch(1, 1, 'slip', true)],
  ['bo', stitch(1, 0, 'bind off', true)],
  ['co', stitch(0, 1, 'cast on', true)],
  ['yo', stitch(0, 1, 'yarn over (adds one)')],
  ['m1', stitch(0, 1, 'make one (adds one)')],
  ['m1l', stitch(0, 1, 'make one left (adds one)')],
  ['m1r', stitch(0, 1, 'make one right (adds one)')],
  ['kfb', stitch(1, 2, 'knit front and back (adds one)')],
  ['pfb', stitch(1, 2, 'purl front and back (adds one)')],
  ['k2tog', stitch(2, 1, 'knit two together (removes one)')],
  ['p2tog', stitch(2, 1, 'purl two together (removes one)')],
  ['ssk', stitch(2, 1, 'slip, slip, knit (removes one)')],
  ['ssp', stitch(2, 1, 'slip, slip, purl (removes one)')],
  ['skp', stitch(2, 1, 'slip, knit, pass over (removes one)')],
  ['k3tog', stitch(3, 1, 'knit three together (removes two)')],
  ['p3tog', stitch(3, 1, 'purl three together (removes two)')],
  ['sk2p', stitch(3, 1, 'slip, knit two together, pass over (removes two)')],
  ['s2kp', stitch(3, 1, 'slip two, knit, pass over (removes two)')],
  ['cdd', stitch(3, 1, 'centred double decrease (removes two)')],
]);

/** Other spellings people use for the same stitch. */
export const ALIASES: ReadonlyMap<string, string> = new Map([
  ['knit', 'k'],
  ['purl', 'p'],
  ['slip', 'sl'],
  ['yfwd', 'yo'],
  ['yon', 'yo'],
  ['yrn', 'yo'],
  ['inc', 'kfb'],
  ['dec', 'k2tog'],
]);
