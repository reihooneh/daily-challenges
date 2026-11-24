// Crownwind: plans when to wind a collection of mechanical watches so none of them stops,
// with the fewest winding sessions, and then the fewest turns of each crown.
//
// Times are minutes from the start of the plan. A watch runs for its power reserve after a full
// wind; we keep a safety margin, so it is treated as stopping a little early. Automatic watches
// worn for a stretch are fully wound by the end of it.

export const LIMITS = { watches: 60, slots: 40, wear: 20, days: 60, bytes: 64 * 1024 };
const DAY = 24 * 60;
const NAME = /^[\p{L}\p{N} .,'&()/-]{1,40}$/u;
const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/;

export class PlanError extends Error {}

function num(v, lo, hi, what) {
  if (typeof v !== 'number' || !Number.isFinite(v) || v < lo || v > hi) throw new PlanError(`${what} must be a number from ${lo} to ${hi}`);
  return v;
}
function minutes(v, what) {
  const m = typeof v === 'string' ? HHMM.exec(v) : null;
  if (!m) throw new PlanError(`${what} must be a time like 07:30`);
  return Number(m[1]) * 60 + Number(m[2]);
}
function days(v, what) {
  if (!Array.isArray(v) || v.length === 0 || v.length > 7 || !v.every((d) => Number.isInteger(d) && d >= 0 && d <= 6)) {
    throw new PlanError(`${what} must list weekdays 0 (Monday) to 6`);
  }
  return new Set(v);
}

/** Reads and checks a collection; returns everything in minutes. */
export function parse(text) {
  if (typeof text !== 'string' || text.length > LIMITS.bytes) throw new PlanError('the file is larger than 64 KB');
  let d;
  try {
    d = JSON.parse(text);
  } catch {
    throw new PlanError("the file isn't valid JSON");
  }
  if (!d || typeof d !== 'object' || Array.isArray(d)) throw new PlanError('the file must be a JSON object');
  const horizon = num(d.days ?? 14, 1, LIMITS.days, 'days') * DAY;
  if (!Number.isInteger(horizon / DAY)) throw new PlanError('days must be a whole number');
  const margin = num(d.margin ?? 0.1, 0, 0.5, 'margin');
  const startDay = num(d.startWeekday ?? 0, 0, 6, 'startWeekday');
  const startTime = minutes(d.startTime ?? '07:00', 'startTime');

  if (!Array.isArray(d.slots) || d.slots.length === 0 || d.slots.length > LIMITS.slots) throw new PlanError(`slots must list 1 to ${LIMITS.slots} groups of times you can wind`);
  const slots = [];
  // Weekday and minute-of-day for an absolute minute in the plan.
  const at = (t) => {
    const abs = startTime + t;
    return { weekday: (startDay + Math.floor(abs / DAY)) % 7, time: abs % DAY };
  };
  const slotRules = d.slots.map((s, i) => {
    if (!s || typeof s !== 'object') throw new PlanError(`slot group ${i + 1} must be an object`);
    if (!Array.isArray(s.at) || s.at.length === 0 || s.at.length > 24) throw new PlanError(`slot group ${i + 1}: at must list times`);
    return { days: days(s.days, `slot group ${i + 1} days`), times: s.at.map((x) => minutes(x, `slot group ${i + 1} time`)) };
  });
  for (let day = 0; day * DAY < horizon + DAY; day++) {
    for (const rule of slotRules) {
      for (const tm of rule.times) {
        const t = day * DAY + tm - startTime;
        if (t < 0 || t > horizon) continue;
        if (rule.days.has(at(t).weekday)) slots.push(t);
      }
    }
  }
  slots.sort((a, b) => a - b);
  const uniqueSlots = slots.filter((t, i) => i === 0 || t !== slots[i - 1]);

  if (!Array.isArray(d.watches) || d.watches.length === 0 || d.watches.length > LIMITS.watches) throw new PlanError(`watches must list 1 to ${LIMITS.watches} watches`);
  const names = new Set();
  const watches = d.watches.map((w, i) => {
    if (!w || typeof w !== 'object') throw new PlanError(`watch ${i + 1} must be an object`);
    if (typeof w.name !== 'string' || !NAME.test(w.name)) throw new PlanError(`watch ${i + 1} needs a short name`);
    if (names.has(w.name)) throw new PlanError(`two watches are called ${w.name}`);
    names.add(w.name);
    const reserve = num(w.reserve, 6, 2000, `${w.name}: reserve (hours)`) * 60;
    const left = num(w.left ?? 0, 0, reserve / 60, `${w.name}: hours left`) * 60;
    const kind = w.kind ?? 'manual';
    if (kind !== 'manual' && kind !== 'automatic') throw new PlanError(`${w.name}: kind must be manual or automatic`);
    const wearRaw = w.worn ?? [];
    if (!Array.isArray(wearRaw) || wearRaw.length > LIMITS.wear) throw new PlanError(`${w.name}: worn must be a list`);
    const wear = [];
    for (const [j, r] of wearRaw.entries()) {
      if (!r || typeof r !== 'object') throw new PlanError(`${w.name}: wear ${j + 1} must be an object`);
      const ds = days(r.days, `${w.name}: wear ${j + 1} days`);
      const from = minutes(r.from, `${w.name}: wear ${j + 1} from`), to = minutes(r.to, `${w.name}: wear ${j + 1} to`);
      if (to <= from) throw new PlanError(`${w.name}: wear ${j + 1} must end after it starts`);
      for (let day = 0; day * DAY < horizon + DAY; day++) {
        const s = day * DAY + from - startTime, e = day * DAY + to - startTime;
        if (e <= 0 || s > horizon) continue;
        if (ds.has(at(Math.max(s, 0)).weekday)) wear.push([Math.max(s, 0), Math.min(e, horizon)]);
      }
    }
    wear.sort((a, b) => a[0] - b[0]);
    return {
      name: w.name, reserve, left, kind, wear, mayStop: w.mayStop === true,
      run: reserve * (1 - margin), // how long we let it run after a full wind
      firstStop: left - reserve * margin,
    };
  });
  return { horizon, margin, startDay, startTime, slots: uniqueSlots, watches };
}

/** When the watch would stop if its last full wind was at `wound` (or it starts with `firstStop`),
 * taking automatic wear into account: wearing it before it stops keeps it going and leaves it full. */
export function stopAfter(w, stop) {
  if (w.kind !== 'automatic') return stop;
  let s = stop;
  for (const [a, b] of w.wear) {
    if (a <= s && b > s - w.run) s = Math.max(s, b + w.run);
  }
  return s;
}

/** The fewest winding sessions that keep every watch (that mustn't stop) running.
 * Greedy: hold off each session until the latest slot before the next watch would stop, then
 * wind everything. Winding everyone never hurts the session count, and a later session can only
 * push every deadline further, so no plan uses fewer sessions. */
export function sessions(plan) {
  const ws = plan.watches.filter((w) => !w.mayStop);
  const stop = new Map(ws.map((w) => [w, stopAfter(w, w.firstStop)]));
  const chosen = [];
  const stranded = []; // watches no slot can reach in time: { watch, at }
  const dead = new Set();
  let after = -1;
  for (;;) {
    let first = Infinity, who = null;
    for (const w of ws) {
      if (!dead.has(w) && stop.get(w) < first) [first, who] = [stop.get(w), w];
    }
    if (first >= plan.horizon) break;
    let pick = -1;
    for (const t of plan.slots) if (t > after && t <= first) pick = t;
    if (pick < 0) {
      stranded.push({ watch: who, at: first });
      dead.add(who);
      continue;
    }
    chosen.push(pick);
    after = pick;
    for (const w of ws) if (!dead.has(w)) stop.set(w, stopAfter(w, pick + w.run));
  }
  return { sessions: chosen, stranded };
}

/** Given the sessions, the fewest of them at which each watch needs winding (latest first). */
export function windings(plan, chosen) {
  const out = new Map();
  for (const w of plan.watches) {
    if (w.mayStop) continue;
    const mine = [];
    let stop = stopAfter(w, w.firstStop);
    let last = -1;
    while (stop < plan.horizon) {
      let pick = -1;
      for (const t of chosen) if (t > last && t <= stop) pick = t;
      if (pick < 0) break;
      mine.push(pick);
      last = pick;
      stop = stopAfter(w, pick + w.run);
    }
    out.set(w.name, mine);
  }
  return out;
}

/** Does a set of session times keep every watch running (each wound whenever it helps)? */
export function feasible(plan, chosen) {
  const sorted = [...chosen].sort((a, b) => a - b);
  for (const w of plan.watches) {
    if (w.mayStop) continue;
    let stop = stopAfter(w, w.firstStop);
    for (const t of sorted) {
      if (t > stop) return false;
      stop = stopAfter(w, t + w.run);
    }
    if (stop < plan.horizon) return false;
  }
  return true;
}

export function label(plan, t) {
  const abs = plan.startTime + t;
  const wd = (plan.startDay + Math.floor(abs / DAY)) % 7;
  const m = abs % DAY;
  return `${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][wd]} day ${Math.floor(abs / DAY) + 1} ${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}
