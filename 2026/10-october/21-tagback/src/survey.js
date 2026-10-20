// Reading a survey file: the animals caught in each session, by tag.
//
//   study Frog pond, spring
//   session Mon: F01 F02 F03 F04
//   session Tue: F02 F05 F06 F03!      ← "!" = caught but not released (kept or died)
//
// The first time a tag appears, that animal was caught unmarked, tagged and released.
// Later appearances are recaptures.

export const LIMITS = Object.freeze({ bytes: 256 * 1024, line: 4000, sessions: 50, tags: 20_000, perSession: 2000 });

const TAG = /^[A-Za-z0-9][A-Za-z0-9-]{0,11}$/;
const LABEL = /^[\p{L}\p{N}][\p{L}\p{N} .,'()/-]{0,39}$/u;
const BAD_CHARS = /[\p{Cc}‎‏‪-‮⁦-⁩]/u;

export class SurveyError extends Error {}

/**
 * @typedef {{ label: string, caught: string[], kept: Set<string>, line: number }} Session
 * @typedef {{ study: string, sessions: Session[] }} Survey
 */

/** @param {string} text @returns {Survey} */
export function parseSurvey(text) {
  if (Buffer.byteLength(text, 'utf8') > LIMITS.bytes) throw new SurveyError('the survey file is larger than 256 KB');
  /** @type {Survey} */
  const out = { study: 'Unnamed study', sessions: [] };
  let totalTags = 0;
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const n = i + 1;
    const raw = lines[i];
    if (raw.length > LIMITS.line) throw new SurveyError(`line ${n} is longer than ${LIMITS.line} characters`);
    if (BAD_CHARS.test(raw.replace(/\t/g, ' '))) throw new SurveyError(`line ${n} contains control or hidden direction characters`);
    const line = raw.split('#')[0].trim();
    if (!line) continue;
    const [word] = line.split(/\s+/, 1);
    const rest = line.slice(word.length).trim();
    if (word === 'study') {
      if (!LABEL.test(rest)) throw new SurveyError(`line ${n}: study names are 1-40 letters, digits, spaces and simple punctuation`);
      out.study = rest;
    } else if (word === 'session') {
      const colon = rest.indexOf(':');
      if (colon < 0) throw new SurveyError(`line ${n}: expected 'session NAME: TAG TAG ...'`);
      const label = rest.slice(0, colon).trim();
      if (!LABEL.test(label)) throw new SurveyError(`line ${n}: session names are 1-40 letters, digits, spaces and simple punctuation`);
      if (out.sessions.length >= LIMITS.sessions) throw new SurveyError(`line ${n}: more than ${LIMITS.sessions} sessions`);
      const tokens = rest.slice(colon + 1).split(/[\s,]+/).filter(Boolean);
      if (tokens.length > LIMITS.perSession) throw new SurveyError(`line ${n}: more than ${LIMITS.perSession} animals in one session`);
      /** @type {string[]} */
      const caught = [];
      const kept = new Set();
      const seen = new Set();
      for (const tok of tokens) {
        const notReleased = tok.endsWith('!');
        const tag = notReleased ? tok.slice(0, -1) : tok;
        if (!TAG.test(tag)) throw new SurveyError(`line ${n}: tags are 1-12 letters, digits or dashes (add ! for an animal not released)`);
        const key = tag.toUpperCase();
        if (seen.has(key)) throw new SurveyError(`line ${n}: tag ${key} is listed twice in one session`);
        seen.add(key);
        caught.push(key);
        if (notReleased) kept.add(key);
      }
      totalTags += caught.length;
      if (totalTags > LIMITS.tags) throw new SurveyError(`line ${n}: more than ${LIMITS.tags} captures in total`);
      out.sessions.push({ label, caught, kept, line: n });
    } else {
      throw new SurveyError(`line ${n}: lines start with study or session`);
    }
  }
  if (out.sessions.length < 2) throw new SurveyError('a mark-recapture survey needs at least 2 sessions');
  return out;
}

/**
 * Per-session counts: C caught, R already marked among them, M marked animals at large before
 * the session, U newly marked. Also checks that no animal was caught after it was kept.
 * @param {Survey} s
 */
export function tally(s) {
  const marked = new Set();
  const gone = new Map(); // tag -> label of the session it was kept in
  const rows = [];
  for (const sess of s.sessions) {
    let recaptured = 0;
    const atLarge = marked.size;
    for (const tag of sess.caught) {
      if (gone.has(tag)) {
        throw new SurveyError(`line ${sess.line}: ${tag} was kept in session "${gone.get(tag)}" but is caught again`);
      }
      if (marked.has(tag)) recaptured++;
    }
    const fresh = sess.caught.length - recaptured;
    for (const tag of sess.caught) marked.add(tag);
    for (const tag of sess.kept) {
      marked.delete(tag);
      gone.set(tag, sess.label);
    }
    rows.push({ label: sess.label, C: sess.caught.length, R: recaptured, M: atLarge, U: fresh, kept: sess.kept.size });
  }
  return { rows, everMarked: marked.size + gone.size };
}
