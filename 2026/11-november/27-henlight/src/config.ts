// The settings, from command-line flags or a small JSON file, all checked before use.
import { lstatSync, readFileSync } from 'node:fs';
import { DST_RULES, DstRule } from './sun.js';

export class ConfigError extends Error {}

export interface Config {
  name: string;
  lat: number;
  lon: number;
  utcOffset: number; // hours, standard time
  dst: DstRule;
  year: number;
  from: string; // MM-DD
  to: string; // MM-DD
  target: number; // hours
  most: number; // hours
  ramp: number; // minutes a week
  step: number; // minutes
  watts: number;
  price: number; // dollars per kWh
}

export const DEFAULTS: Config = {
  name: 'Sydney',
  lat: -33.87,
  lon: 151.21,
  utcOffset: 10,
  dst: 'au',
  year: 2026,
  from: '03-01',
  to: '09-30',
  target: 14,
  most: 14.5,
  ramp: 30,
  step: 15,
  watts: 9,
  price: 0.33,
};

const KEYS = Object.keys(DEFAULTS) as (keyof Config)[];
const MAX_FILE = 16 * 1024;
const NAME = /^[\p{L}\p{N} .,'()-]{1,40}$/u;
const MMDD = /^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

function num(v: unknown, lo: number, hi: number, what: string): number {
  const n = typeof v === 'string' && v.trim() !== '' ? Number(v) : v;
  if (typeof n !== 'number' || !Number.isFinite(n) || n < lo || n > hi) throw new ConfigError(`${what} must be a number from ${lo} to ${hi}`);
  return n;
}

/** Checks a partial set of settings on top of the defaults. */
export function check(raw: Record<string, unknown>): Config {
  for (const k of Object.keys(raw)) if (!KEYS.includes(k as keyof Config)) throw new ConfigError(`unknown setting "${k.slice(0, 20).replace(/[^\w-]/g, '?')}"`);
  const get = (k: keyof Config): unknown => (Object.hasOwn(raw, k) ? raw[k] : DEFAULTS[k]);
  const name = get('name');
  if (typeof name !== 'string' || !NAME.test(name)) throw new ConfigError('name must be up to 40 letters, digits and simple punctuation');
  const dst = get('dst');
  if (typeof dst !== 'string' || !DST_RULES.includes(dst as DstRule)) throw new ConfigError(`dst must be one of ${DST_RULES.join(', ')}`);
  const c: Config = {
    name,
    lat: num(get('lat'), -60, 60, 'lat'),
    lon: num(get('lon'), -180, 180, 'lon'),
    utcOffset: num(get('utcOffset'), -12, 14, 'utcOffset'),
    dst: dst as DstRule,
    year: num(get('year'), 2000, 2100, 'year'),
    from: String(get('from')),
    to: String(get('to')),
    target: num(get('target'), 10, 17, 'target'),
    most: num(get('most'), 10, 18, 'most'),
    ramp: num(get('ramp'), 5, 120, 'ramp'),
    step: num(get('step'), 5, 30, 'step'),
    watts: num(get('watts'), 0.5, 200, 'watts'),
    price: num(get('price'), 0, 5, 'price'),
  };
  if (!Number.isInteger(c.year)) throw new ConfigError('year must be a whole year');
  if (![5, 10, 15, 30].includes(c.step)) throw new ConfigError('step (the timer pin spacing) must be 5, 10, 15 or 30 minutes');
  if (Math.round(c.utcOffset * 4) !== c.utcOffset * 4) throw new ConfigError('utcOffset must be in quarter hours');
  if (c.most < c.target + 0.25) throw new ConfigError('most must be at least 15 minutes more than target');
  for (const k of ['from', 'to'] as const) {
    if (!MMDD.test(c[k])) throw new ConfigError(`${k} must be a date like 03-01 (month-day)`);
    const [m, d] = c[k].split('-').map(Number) as [number, number];
    const t = new Date(Date.UTC(c.year, m - 1, d));
    if (t.getUTCMonth() !== m - 1) throw new ConfigError(`${k} is not a date in ${c.year}`);
  }
  if (c.to < c.from) throw new ConfigError('to must come after from in the same year');
  return c;
}

/** Reads a JSON settings file: a regular file (not a link) up to 16 KB. */
export function readConfigFile(path: string): Record<string, unknown> {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    throw new ConfigError('the settings file could not be read');
  }
  if (!st.isFile()) throw new ConfigError('the settings file must be a regular file, not a link or folder');
  if (st.size > MAX_FILE) throw new ConfigError('the settings file is larger than 16 KB');
  let data: unknown;
  try {
    data = JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    throw new ConfigError('the settings file is not valid JSON');
  }
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new ConfigError('the settings file must hold a JSON object');
  // Copy own keys into a fresh object: "__proto__" and friends become plain (unknown) keys.
  const out: Record<string, unknown> = Object.create(null);
  for (const [k, v] of Object.entries(data)) out[k] = v;
  return out;
}

/** Command-line flags: --key value. */
export function parseFlags(args: string[]): { file: string | null; raw: Record<string, unknown> } {
  const raw: Record<string, unknown> = Object.create(null);
  let file: string | null = null;
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (!a.startsWith('--')) {
      if (file !== null) throw new ConfigError('give at most one settings file');
      file = a;
      continue;
    }
    const key = a.slice(2);
    const value = args[i + 1];
    if (value === undefined) throw new ConfigError(`--${key.slice(0, 20).replace(/[^\w-]/g, '?')} needs a value`);
    raw[key] = value;
    i++;
  }
  return { file, raw };
}
