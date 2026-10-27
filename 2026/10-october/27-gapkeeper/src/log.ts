// Reads a route's arrival log: which stops, the scheduled headway, and when each trip reached each stop.

export const MAX_INPUT = 256 * 1024;
export const MAX_STOPS = 60;
export const MAX_TRIPS = 600;
const MAX_LINE = 1000;

export interface Trip {
  id: string;
  /** Seconds after midnight at each stop, or null where the log has no time. */
  times: (number | null)[];
  line: number;
}

export interface Log {
  route: string;
  /** Scheduled headway, seconds. */
  headway: number;
  stops: string[];
  /** How many people board at each stop, relatively (default 1 each). */
  demand: number[];
  /** Indexes of stops where buses may be held (timing points). */
  control: number[];
  /** Extra dwell per extra second of gap ahead (more people waiting, longer boarding). */
  dwell: number;
  /** How much a minute of extra riding counts against a minute of waiting. */
  rideValue: number;
  trips: Trip[];
}

export class InputError extends Error {}

const fail = (line: number, msg: string): never => {
  throw new InputError(line > 0 ? `line ${line}: ${msg}` : msg);
};

const NAME = /^[A-Za-z0-9][A-Za-z0-9 '.&()/-]{0,39}$/;
const TRIP_ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,15}$/;
const DECIMAL = /^\d{1,3}(\.\d{1,2})?$/;

/** "07:04" or "07:04:30" (up to 29:59:59 for service after midnight) into seconds. */
export function parseClock(s: string): number | null {
  const m = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(s);
  if (!m) return null;
  const h = Number(m[1]), min = Number(m[2]), sec = Number(m[3] ?? '0');
  if (h > 29 || min > 59 || sec > 59) return null;
  return h * 3600 + min * 60 + sec;
}

export function formatClock(t: number): string {
  const s = Math.round(t);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`;
}

/** Refuses control characters and invisible direction or zero-width marks. */
function checkText(text: string): void {
  let line = 1;
  for (const ch of text) {
    const c = ch.codePointAt(0)!;
    if (c === 10) { line++; continue; }
    if (c === 9 || c === 13) continue;
    if (c < 32 || (c >= 0x7f && c <= 0x9f) || (c >= 0x200b && c <= 0x200f) || (c >= 0x202a && c <= 0x202e) ||
        (c >= 0x2066 && c <= 0x2069) || c === 0xfeff || c === 0xfffd) {
      fail(line, 'contains a control, hidden or unreadable character');
    }
  }
}

export function parseLog(input: string): Log {
  if (input.length > MAX_INPUT) fail(0, 'the log is larger than 256 KB');
  const text = input.startsWith('\uFEFF') ? input.slice(1) : input;
  checkText(text);
  const log: Log = { route: 'Route', headway: 0, stops: [], demand: [], control: [], dwell: 0.1, rideValue: 0.5, trips: [] };
  const seen = new Set<string>();
  const ids = new Set<string>();
  const pendingDemand: [string, number, number][] = [];
  const pendingControl: [string, number][] = [];
  text.split('\n').forEach((raw, n) => {
    const line = n + 1;
    if (raw.length > MAX_LINE) fail(line, 'is longer than 1000 characters');
    const body = raw.replace(/#.*/, '').trim();
    if (!body) return;
    const [key = '', ...rest] = body.split(/\s+/);
    const value = rest.join(' ');
    const once = (k: string) => { if (seen.has(k)) fail(line, `'${k}' comes once`); seen.add(k); };
    switch (key) {
      case 'route':
        once(key);
        if (!NAME.test(value)) fail(line, "route names use letters, digits, spaces and ' . & ( ) / - (up to 40)");
        log.route = value;
        break;
      case 'headway': {
        once(key);
        const m = /^(\d{1,2}(?:\.\d)?) min$/.exec(value);
        const v = m ? Number(m[1]) : NaN;
        if (!(v >= 2 && v <= 60)) fail(line, "write the scheduled headway like 'headway 8 min' (2 to 60 minutes)");
        log.headway = Math.round(v * 60);
        break;
      }
      case 'stops': {
        once(key);
        if (log.trips.length) fail(line, "'stops' comes before the first trip");
        const names = value.split(',').map((s) => s.trim());
        if (names.length < 2 || names.length > MAX_STOPS) fail(line, 'a route has 2 to 60 stops, separated by commas');
        for (const s of names) {
          if (!NAME.test(s)) fail(line, "stop names use letters, digits, spaces and ' . & ( ) / - (up to 40)");
        }
        if (new Set(names).size !== names.length) fail(line, 'each stop name appears once');
        log.stops = names;
        break;
      }
      case 'control':
        if (!NAME.test(value)) fail(line, "write 'control <stop name>'");
        pendingControl.push([value, line]);
        break;
      case 'demand': {
        const m = /^(.+)\s+(\S+)$/.exec(value);
        if (!m || !NAME.test(m[1]!) || !DECIMAL.test(m[2]!) || Number(m[2]) < 0.1 || Number(m[2]) > 100) {
          fail(line, "write 'demand <stop name> <weight>' with a weight from 0.1 to 100");
        }
        pendingDemand.push([m![1]!, Number(m![2]), line]);
        break;
      }
      case 'dwell': {
        once(key);
        const m = /^(\d{1,2}(?:\.\d{1,2})?) s per min$/.exec(value);
        const v = m ? Number(m[1]) : NaN;
        if (!(v >= 0 && v <= 30)) fail(line, "write 'dwell 6 s per min': extra seconds at a stop for each extra minute of gap (0 to 30)");
        log.dwell = v / 60;
        break;
      }
      case 'ridevalue': {
        once(key);
        const v = DECIMAL.test(value) ? Number(value) : NaN;
        if (!(v >= 0 && v <= 2)) fail(line, "'ridevalue' is between 0 and 2");
        log.rideValue = v;
        break;
      }
      case 'trip': {
        if (!log.stops.length) fail(line, "trips come after the 'stops' line");
        if (log.trips.length >= MAX_TRIPS) fail(line, 'at most 600 trips');
        const [id = '', ...times] = rest;
        if (!TRIP_ID.test(id)) fail(line, 'trip ids are letters, digits, . _ - (up to 16)');
        if (ids.has(id)) fail(line, 'a trip with that id is already logged');
        if (times.length !== log.stops.length) fail(line, `a trip needs one time (or -) for each of the ${log.stops.length} stops`);
        const parsed = times.map((t) => (t === '-' ? null : parseClock(t) ?? fail(line, "times are like 07:04 or 07:04:30, or '-' if missing")));
        if (parsed[0] === null) fail(line, 'every trip needs a time at the first stop');
        let last = -1;
        for (const t of parsed) {
          if (t === null) continue;
          if (t < last) fail(line, 'times along a trip must not go backwards');
          last = t;
        }
        if (last - parsed[0]! > 4 * 3600) fail(line, 'a trip longer than 4 hours looks like a typo');
        ids.add(id);
        log.trips.push({ id, times: parsed, line });
        break;
      }
      default:
        fail(line, 'lines start with route, headway, stops, control, demand, dwell, ridevalue or trip');
    }
  });
  if (!log.stops.length) fail(0, "the log needs a 'stops' line");
  if (!log.headway) fail(0, "the log needs a 'headway' line");
  if (log.trips.length < 3) fail(0, 'the log needs at least 3 trips');
  log.demand = log.stops.map(() => 1);
  for (const [name, w, line] of pendingDemand) {
    const i = log.stops.indexOf(name);
    if (i < 0) fail(line, 'that stop is not on the route');
    log.demand[i] = w;
  }
  for (const [name, line] of pendingControl) {
    const i = log.stops.indexOf(name);
    if (i < 0) fail(line, 'that stop is not on the route');
    if (i === log.stops.length - 1) fail(line, 'holding at the last stop helps no one');
    if (!log.control.includes(i)) log.control.push(i);
  }
  log.control.sort((a, b) => a - b);
  return log;
}
