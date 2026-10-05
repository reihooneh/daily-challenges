/** A pattern line that could not be understood. The message is safe to print. */
export class PatternError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PatternError';
  }
}

/** Hard limits. Every loop and every number in the program is bounded by these. */
export const LIMITS = Object.freeze({
  fileBytes: 200_000,
  lines: 5_000,
  lineLength: 2_000,
  rows: 5_000,
  stitches: 100_000,
  nesting: 5,
  wordLength: 20,
});
