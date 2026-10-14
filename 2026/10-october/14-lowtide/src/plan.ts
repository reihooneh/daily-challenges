// Reading a money plan: the starting balance, a safety buffer, and every income, bill
// and regular spend with its schedule. Money is kept in whole cents, never floats.

export const LIMITS = { bytes: 32 * 1024, line: 200, items: 40, movable: 8, days: 400, cents: 100_000_000_00 };

export class InputError extends Error {}

export type Schedule =
  | { every: 'once' | 'week' | 'fortnight' | 'quarter' | 'year'; from: number } // day number
  | { every: 'month'; on: number } // day of the month, 1-31; 31 means "the last day"
  | { every: 'day' };

export interface Item {
  kind: 'income' | 'bill' | 'spend';
  name: string;
  cents: number;
  schedule: Schedule;
  movable: boolean;
}

export interface Plan {
  start: number; // day number of the first day
  days: number;
  balance: number; // cents
  buffer: number; // cents
  items: Item[];
}

// ---------- dates as whole day numbers (days since 1970-01-01, UTC) ----------

const MS_PER_DAY = 86_400_000;

export function parseDate(text: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (y < 2000 || y > 2100) return null;
  const ms = Date.UTC(y, mo - 1, d);
  const back = new Date(ms);
  if (back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) return null; // e.g. 2026-02-30
  return ms / MS_PER_DAY;
}

export function ymd(day: number): { y: number; m: number; d: number; weekday: number } {
  const dt = new Date(day * MS_PER_DAY);
  return { y: dt.getUTCFullYear(), m: dt.getUTCMonth() + 1, d: dt.getUTCDate(), weekday: dt.getUTCDay() };
}

export function daysInMonth(y: number, m: number): number {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

export function dayOf(y: number, m: number, d: number): number {
  return Date.UTC(y, m - 1, d) / MS_PER_DAY;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

export function formatDay(day: number): string {
  const { y, m, d, weekday } = ymd(day);
  return `${WEEKDAYS[weekday]} ${d} ${MONTHS[m - 1]} ${y}`;
}

export function ordinal(n: number): string {
  if (n === 31) return 'last day';
  const suffix = n % 10 === 1 && n !== 11 ? 'st' : n % 10 === 2 && n !== 12 ? 'nd' : n % 10 === 3 && n !== 13 ? 'rd' : 'th';
  return `${n}${suffix}`;
}

// ---------- money ----------

export function parseMoney(text: string): number | null {
  const m = /^\$?(\d{1,9})(?:\.(\d{2}))?$/.exec(text.replace(/,/g, ''));
  if (!m) return null;
  const cents = Number(m[1]) * 100 + Number(m[2] ?? '0');
  return cents <= LIMITS.cents ? cents : null;
}

export function formatMoney(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const dollars = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${sign}$${dollars}.${String(abs % 100).padStart(2, '0')}`;
}

// ---------- the plan file ----------

const NAME = /^[\p{L}\p{N}][\p{L}\p{N} '&.()/-]{0,29}$/u;
// Control characters, and invisible characters that can disguise text in a terminal.
const HOSTILE = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩﻿]/;

function fail(line: number, message: string): never {
  throw new InputError(line > 0 ? `line ${line}: ${message}` : message);
}

function parseSchedule(words: string[], line: number, kind: Item['kind']): Schedule {
  const [first, second, third] = words;
  if (first === 'daily' && words.length === 1) return { every: 'day' };
  if (first === 'monthly' && second === 'on' && third !== undefined && words.length === 3) {
    const on = third === 'last' ? 31 : Number(third);
    if (!Number.isInteger(on) || on < 1 || on > 31) fail(line, 'monthly bills need a day from 1 to 31, or "last"');
    return { every: 'month', on };
  }
  const every = { once: 'once', weekly: 'week', fortnightly: 'fortnight', quarterly: 'quarter', yearly: 'year' }[
    first ?? ''
  ] as Exclude<Schedule['every'], 'month' | 'day'> | undefined;
  const joiner = first === 'once' ? 'on' : 'from';
  if (every && second === joiner && third !== undefined && words.length === 3) {
    const from = parseDate(third);
    if (from === null) fail(line, 'dates must be real dates written like 2026-11-06');
    return { every, from };
  }
  fail(
    line,
    kind === 'spend'
      ? 'a spend needs a schedule, like: daily'
      : 'the schedule must be one of: once on DATE, weekly from DATE, fortnightly from DATE, monthly on DAY, quarterly from DATE, yearly from DATE',
  );
}

export function parsePlan(text: string): Plan {
  if (Buffer.byteLength(text, 'utf8') > LIMITS.bytes) fail(0, 'the file is larger than 32 KB');
  if (HOSTILE.test(text.replace(/\r?\n/g, ''))) fail(0, 'the file has control or invisible characters');
  const plan: Partial<Plan> & { items: Item[] } = { items: [] };
  const names = new Set<string>();
  text.split(/\r?\n/).forEach((raw, i) => {
    const n = i + 1;
    if (raw.length > LIMITS.line) fail(n, `the line is longer than ${LIMITS.line} characters`);
    const line = raw.replace(/(^|\s)#.*$/, '').trim();
    if (!line) return;
    const words = line.split(/\s+/);
    const key = words[0];
    if (key === 'start') {
      const d = words.length === 2 ? parseDate(words[1]!) : null;
      if (d === null) fail(n, 'start must be a date like 2026-11-01');
      plan.start = d;
    } else if (key === 'days') {
      const d = Number(words[1]);
      if (words.length !== 2 || !Number.isInteger(d) || d < 7 || d > LIMITS.days) fail(n, `days must be from 7 to ${LIMITS.days}`);
      plan.days = d;
    } else if (key === 'balance' || key === 'buffer') {
      const neg = words[1]?.startsWith('-') ?? false;
      const c = words.length === 2 ? parseMoney(neg ? words[1]!.slice(1) : words[1]!) : null;
      if (c === null || (neg && key === 'buffer')) fail(n, `${key} must be an amount like 820.00`);
      plan[key] = neg ? -c : c;
    } else if (key === 'income' || key === 'bill' || key === 'spend') {
      if (plan.items.length >= LIMITS.items) fail(n, `more than ${LIMITS.items} items`);
      // NAME AMOUNT SCHEDULE... [movable]; the amount is the first word that looks like money.
      const at = words.findIndex((w, j) => j > 0 && parseMoney(w) !== null);
      if (at < 0) fail(n, `write it as: ${key} Name 65.00 monthly on 14`);
      const name = key === 'spend' && at === 1 ? 'Everyday spending' : words.slice(1, at).join(' ');
      if (!NAME.test(name)) fail(n, "a name must be 1 to 30 letters, digits, spaces or ' & . ( ) / -");
      if (names.has(name.toLowerCase())) fail(n, 'two items have the same name');
      names.add(name.toLowerCase());
      const cents = parseMoney(words[at]!)!;
      let rest = words.slice(at + 1);
      const movable = rest.at(-1) === 'movable';
      if (movable || rest.at(-1) === 'fixed') rest = rest.slice(0, -1);
      const schedule = parseSchedule(rest, n, key);
      if (movable && (key !== 'bill' || schedule.every !== 'month')) {
        fail(n, 'only monthly bills can be movable (you pick their day of the month)');
      }
      plan.items.push({ kind: key, name, cents, schedule, movable });
    } else {
      fail(n, 'start the line with start, days, balance, buffer, income, bill or spend');
    }
  });
  if (plan.start === undefined) fail(0, 'the file needs a start line, like: start 2026-11-01');
  if (plan.balance === undefined) fail(0, 'the file needs a balance line, like: balance 820.00');
  if (!plan.items.some((it) => it.kind !== 'income')) fail(0, 'the file has no bills or spending');
  if (plan.items.filter((it) => it.movable).length > LIMITS.movable) {
    fail(0, `more than ${LIMITS.movable} movable bills: mark the ones you'd really change`);
  }
  return { start: plan.start, days: plan.days ?? 90, balance: plan.balance, buffer: plan.buffer ?? 0, items: plan.items };
}
