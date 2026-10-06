// Pure functions: no DOM here, so everything in this file is unit-tested in Node.
//
// The form state is a plain object. buildInput turns it into the same text
// format the command-line tool reads, which means the browser and the CLI
// share one parser and one set of validation rules (in Go).

export const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export const LIMITS = Object.freeze({ coursesChars: 40000, busyChars: 2000, busyLines: 10, hashChars: 16000 });

export function defaultState() {
  return {
    courses: '',
    noDays: [],
    before: { on: false, time: '10:00' },
    after: { on: false, time: '18:00' },
    maxDays: { on: false, n: 3 },
    maxHours: { on: false, n: 6 },
    minGap: { on: false, n: 15 },
    lunch: { on: false, n: 45, from: '12:00', to: '14:00' },
    busy: '',
  };
}

const isTime = (value) => typeof value === 'string' && /^([01]\d|2[0-3]):[0-5]\d$/.test(value);
const clampInt = (value, min, max, fallback) =>
  (Number.isInteger(value) && value >= min && value <= max ? value : fallback);

/**
 * Rebuilds a state object from untrusted data (a shared link). Every field is
 * type-checked and range-checked; anything unexpected falls back to the
 * default. The result never contains keys that were not asked for.
 */
export function sanitizeState(raw) {
  const clean = defaultState();
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return clean;
  if (typeof raw.courses === 'string') clean.courses = raw.courses.slice(0, LIMITS.coursesChars);
  if (typeof raw.busy === 'string') clean.busy = raw.busy.slice(0, LIMITS.busyChars);
  if (Array.isArray(raw.noDays)) {
    clean.noDays = [...new Set(raw.noDays.filter((d) => Number.isInteger(d) && d >= 0 && d < 7))].sort();
  }
  const toggle = (key, fields) => {
    const value = raw[key];
    if (value === null || typeof value !== 'object') return;
    clean[key].on = value.on === true;
    for (const [field, check] of Object.entries(fields)) clean[key][field] = check(value[field], clean[key][field]);
  };
  const time = (value, fallback) => (isTime(value) ? value : fallback);
  toggle('before', { time });
  toggle('after', { time });
  toggle('maxDays', { n: (v, f) => clampInt(v, 1, 7, f) });
  toggle('maxHours', { n: (v, f) => clampInt(v, 1, 24, f) });
  toggle('minGap', { n: (v, f) => clampInt(v, 1, 240, f) });
  toggle('lunch', { n: (v, f) => clampInt(v, 1, 240, f), from: time, to: time });
  return clean;
}

/**
 * Turns the form into planner text. Also returns `sources`: for each wish
 * line, which form control produced it, so "give this up" can untick it.
 */
export function buildInput(state) {
  const lines = [];
  const sources = [];
  const add = (line, source) => { lines.push(`wish: ${line}`); sources.push(source); };
  for (const day of state.noDays) add(`no classes on ${DAYS[day]}`, { type: 'noDay', day });
  if (state.before.on) add(`nothing before ${state.before.time}`, { type: 'before' });
  if (state.after.on) add(`nothing after ${state.after.time}`, { type: 'after' });
  if (state.maxDays.on) add(`at most ${state.maxDays.n} days`, { type: 'maxDays' });
  if (state.maxHours.on) add(`at most ${state.maxHours.n} hours per day`, { type: 'maxHours' });
  if (state.minGap.on) add(`at least ${state.minGap.n} min between classes`, { type: 'minGap' });
  if (state.lunch.on) add(`lunch ${state.lunch.from}-${state.lunch.to} for ${state.lunch.n} min`, { type: 'lunch' });
  const busyLines = state.busy.split('\n').map((line) => line.trim()).filter(Boolean).slice(0, LIMITS.busyLines);
  // A "#" would start a comment and silently swallow the rest of the line.
  busyLines.forEach((line, index) => add(`busy ${line.replaceAll('#', ' ')}`, { type: 'busy', index }));

  const courseText = state.courses.replace(/\s+$/, '');
  const courseLines = courseText === '' ? 0 : courseText.split('\n').length;
  return { text: `${courseText}\n${lines.join('\n')}\n`, sources, courseLines };
}

/** Returns a copy of the state with one wish switched off. */
export function withoutWish(state, source) {
  const next = structuredClone(state);
  if (source.type === 'noDay') next.noDays = next.noDays.filter((d) => d !== source.day);
  else if (source.type === 'busy') {
    const lines = next.busy.split('\n').map((line) => line.trim()).filter(Boolean);
    lines.splice(source.index, 1);
    next.busy = lines.join('\n');
  } else if (source.type in next) next[source.type].on = false;
  return next;
}

/** Planner errors say "line N". Lines past the class list came from the form. */
export function friendlyError(message, courseLines) {
  const match = /^line (\d+): (.*)$/s.exec(String(message));
  if (!match) return String(message);
  return Number(match[1]) > courseLines ? `In your wishes or busy times: ${match[2]}` : `Line ${match[1]} of your classes: ${match[2]}`;
}

// ---- share links ------------------------------------------------------------
// The whole plan is stored after "#" in the address, which browsers never
// send to a server. It is treated as hostile when read back.

export function encodeShare(state) {
  const bytes = new TextEncoder().encode(JSON.stringify(sanitizeState(state)));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

export function decodeShare(hash) {
  if (typeof hash !== 'string' || hash.length === 0 || hash.length > LIMITS.hashChars) return null;
  if (!/^[A-Za-z0-9_-]+$/.test(hash)) return null;
  try {
    const binary = atob(hash.replaceAll('-', '+').replaceAll('_', '/'));
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    const parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return sanitizeState(parsed);
  } catch {
    return null;
  }
}

// ---- timetable layout ---------------------------------------------------------

export const clock = (minutes) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;

export function describeMinutes(minutes) {
  if (minutes === 0) return 'no waiting between classes';
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  const parts = [];
  if (hours) parts.push(`${hours} hour${hours === 1 ? '' : 's'}`);
  if (rest) parts.push(`${rest} min`);
  return `${parts.join(' ')} waiting between classes`;
}

/** Which days and hours the grid needs to show for a set of classes. */
export function gridBounds(classes) {
  let firstHour = 9;
  let lastHour = 17;
  let lastDay = 4;
  for (const c of classes) {
    firstHour = Math.min(firstHour, Math.floor(c.start / 60));
    lastHour = Math.max(lastHour, Math.ceil(c.end / 60));
    lastDay = Math.max(lastDay, c.day);
  }
  return { firstHour, lastHour, days: lastDay + 1 };
}

// ---- examples -----------------------------------------------------------------

const FRIDAY = `COMP1010 Programming Fundamentals
  Lecture: Mon 10:00-12:00
  Tutorial: Mon 09:00-10:00 | Thu 14:00-15:00 | Fri 13:00-14:00
  Lab: Mon 13:00-15:00 | Wed 16:00-18:00

BIOL1020 Molecules, Cells and Genes
  Lecture: Wed 10:00-12:00
  Lab: Wed 13:00-16:00 | Mon 15:00-18:00

MATH1030 Calculus and Linear Algebra
  Lecture: Tue 11:00-13:00 | Fri 10:00-12:00
  Tutorial: Tue 14:00-15:00 | Wed 12:00-13:00 | Fri 12:00-13:00`;

const FIRST_YEAR = `COMP1010 Programming Fundamentals
  Lecture: Mon 10:00-12:00 + Wed 10:00-11:00 | Tue 14:00-16:00 + Thu 14:00-15:00
  Tutorial: Mon 13:00-14:00 | Tue 09:00-10:00 | Wed 15:00-16:00 | Thu 11:00-12:00 | Fri 10:00-11:00
  Lab: Mon 14:00-16:00 | Wed 12:00-14:00 | Thu 16:00-18:00 | Fri 13:00-15:00

BIOL1020 Molecules, Cells and Genes
  Lecture: Tue 10:00-12:00 + Thu 10:00-11:00 | Mon 16:00-18:00 + Wed 16:00-17:00
  Lab: Tue 13:00-16:00 | Wed 09:00-12:00 | Fri 09:00-12:00
  Tutorial: Mon 09:00-10:00 | Thu 13:00-14:00 | Fri 14:00-15:00

MATH1030 Calculus and Linear Algebra
  Lecture: Mon 12:00-13:00 + Wed 14:00-15:00 + Thu 12:00-13:00 | Tue 16:00-17:00 + Wed 11:00-12:00 + Fri 12:00-13:00
  Tutorial: Tue 12:00-13:00 | Wed 13:00-14:00 | Thu 15:00-16:00 | Fri 11:00-12:00

CHEM1040 Chemistry for Life Sciences
  Lecture: Wed 09:00-10:00 + Fri 09:00-10:00 | Tue 17:00-18:00 + Thu 17:00-18:00
  Lab: Mon 09:00-12:00 | Thu 09:00-12:00 | Fri 14:00-17:00`;

const PAIR = `PHYS2001 Quantum Mechanics
  Lecture: Mon 10:00-12:00 + Wed 10:00-12:00

STAT2002 Statistical Inference
  Lecture: Wed 11:00-13:00 + Fri 11:00-12:00
  Tutorial: Thu 09:00-10:00 | Thu 15:00-16:00

HIST1003 The Modern World
  Lecture: Tue 13:00-15:00
  Tutorial: Tue 15:00-16:00 | Fri 13:00-14:00`;

export function sampleState(name) {
  const state = defaultState();
  if (name === 'firstyear') {
    state.courses = FIRST_YEAR;
    state.before = { on: true, time: '09:00' };
    state.after = { on: true, time: '18:00' };
    state.noDays = [4];
  } else if (name === 'pair') {
    state.courses = PAIR;
  } else {
    state.courses = FRIDAY;
    state.noDays = [4];
    state.before = { on: true, time: '10:00' };
    state.maxDays = { on: true, n: 3 };
  }
  return state;
}
