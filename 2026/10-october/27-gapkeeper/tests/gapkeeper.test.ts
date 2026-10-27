import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readFileSync } from 'node:fs';
import { main, readBounded } from '../src/cli.js';
import { analyse, averageWait, observed, overtakes } from '../src/headways.js';
import { InputError, formatClock, parseClock, parseLog, type Log } from '../src/log.js';
import { interpolate, replay, sweep } from '../src/replay.js';

const EXAMPLE = readFileSync(new URL('../../examples/route-99x.txt', import.meta.url), 'utf8');

/** A small log: `n` trips, `gaps` between dispatches (seconds), fixed running times. */
function makeLog(gaps: number[], opts: { control?: string; dwell?: number; runs?: number[] } = {}): string {
  const stops = ['A', 'B', 'C', 'D', 'E'];
  const runs = opts.runs ?? [0, 120, 120, 120, 120];
  const lines = ['route Test', 'headway 8 min', `stops ${stops.join(', ')}`];
  if (opts.control) lines.push(`control ${opts.control}`);
  lines.push(`dwell ${opts.dwell ?? 0} s per min`);
  let t = 7 * 3600;
  const dispatch = [t];
  for (const g of gaps) dispatch.push((t += g));
  dispatch.forEach((d, i) => {
    let x = d;
    const times = runs.map((r) => formatClock((x += r)));
    lines.push(`trip T${i} ${times.join(' ')}`);
  });
  return lines.join('\n') + '\n';
}

test('clock times', () => {
  assert.equal(parseClock('07:04'), 7 * 3600 + 240);
  assert.equal(parseClock('25:00:30'), 25 * 3600 + 30);
  for (const bad of ['7:04', '07:60', '30:00', '07:04:61', '0704', '07:04:5', '']) assert.equal(parseClock(bad), null, bad);
  assert.equal(formatClock(7 * 3600 + 245), '07:04:05');
});

test('waiting time from gaps', () => {
  assert.equal(averageWait([480, 480, 480]), 240, 'even gaps: half a headway');
  // Alternating 2 and 14 minutes on an 8-minute schedule: (4 + 196) / (2 x 16) = 6.25 min.
  assert.equal(averageWait([120, 840, 120, 840]), 6.25 * 60);
  assert.equal(averageWait([]), 0);
  const even = analyse(parseLog(makeLog([480, 480, 480])), observed(parseLog(makeLog([480, 480, 480]))));
  assert.equal(even.ewt, 0);
  assert.equal(even.bunched, 0);
  const bunched = parseLog(makeLog([60, 900, 60, 900]));
  const r = analyse(bunched, observed(bunched));
  assert.ok(Math.abs(r.ewt - 183.75) < 1e-9, 'bunched service: (60² + 900²) x 2 / (2 x 1920) - 240 = 183.75 s');
  assert.equal(r.bunched, 2 * 5, 'two bunched pairs at each of five stops');
  assert.equal(r.gaps, 2 * 5);
});

test('overtakes are counted', () => {
  assert.equal(overtakes([[0, 100, 200], [50, 150, 250]]), 0);
  assert.equal(overtakes([[0, 100, 300], [50, 150, 250]]), 1);
  assert.equal(overtakes([[0, null, 300], [50, 150, 250]]), 1, 'gaps in the log are skipped');
});

test('interpolation fills interior gaps only', () => {
  assert.deepEqual(interpolate([0, null, null, 90]), [0, 30, 60, 90]);
  assert.deepEqual(interpolate([0, 10, null, null]), [0, 10, null, null]);
});

test('a replay with no holding reproduces the log', () => {
  const log = parseLog(EXAMPLE);
  const none = replay(log, { alpha: 0, cap: 0 });
  log.trips.forEach((trip, k) => {
    const filled = interpolate(trip.times);
    filled.forEach((t, s) => assert.ok(t === null || Math.abs(none.table[k]![s]! - t) < 1e-9, `trip ${k} stop ${s}`));
  });
  assert.equal(none.holds, 0);
  assert.equal(none.addedRide, 0);
});

test('a perfectly regular route is never held', () => {
  const log = parseLog(makeLog([480, 480, 480, 480], { control: 'C', dwell: 6 }));
  for (const r of sweep(log).rules) {
    assert.equal(r.holds, 0, `alpha ${r.rule.alpha} cap ${r.rule.cap}`);
    assert.equal(r.report.ewt, 0);
  }
});

test('holding obeys the rule and the cap', () => {
  const log = parseLog(makeLog([60, 900, 60, 900], { control: 'C' }));
  const r = replay(log, { alpha: 0.8, cap: 120 });
  const C = 2;
  const order = [0, 1, 2, 3, 4];
  for (let i = 1; i < order.length; i++) {
    const before = interpolate(log.trips[i]!.times)[C]!;
    const now = r.table[i]![C]!;
    const lead = r.table[i - 1]![C]!;
    assert.ok(now - before <= 120 + 1e-9, 'never held longer than the cap');
    assert.ok(now >= before - 1e-9, 'holding never makes a bus leave early');
    if (now > before) assert.ok(now - lead <= 0.8 * 480 + 1e-9, 'held only until the target gap');
  }
  assert.ok(r.report.stops[3]!.ewt < replay(log, { alpha: 0, cap: 0 }).report.stops[3]!.ewt, 'gaps after the control stop are more even');
});

test('with dwell feedback, holding stops bunching from growing', () => {
  const log = parseLog(EXAMPLE);
  const { none, best, rules } = sweep(log);
  assert.ok(none.report.stops.at(-1)!.ewt > none.report.stops[0]!.ewt * 5, 'bunching grows along the route');
  assert.ok(best !== none && best.report.ewt < none.report.ewt * 0.7, 'the best rule cuts excess waiting by over 30%');
  assert.equal(rules.length, 20);
  assert.ok(rules.every((r) => r.score >= best.score - 1e-9), 'best really is best');
  // Bigger caps never hold less.
  for (const alpha of [0.5, 0.9]) {
    const holds = [60, 120, 180, 300].map((cap) => rules.find((r) => r.rule.alpha === alpha && r.rule.cap === cap)!.meanHold);
    for (let i = 1; i < holds.length; i++) assert.ok(holds[i]! >= holds[i - 1]! - 1e-9);
  }
});

test('the log format is strict', () => {
  const ok = makeLog([480, 480]);
  const bad: [string, string][] = [
    ['', "needs a 'stops' line"],
    [ok.replace('headway 8 min\n', ''), "needs a 'headway' line"],
    [ok.replace('headway 8 min', 'headway 8'), 'scheduled headway'],
    [ok.replace('headway 8 min', 'headway 90 min'), 'scheduled headway'],
    [ok.replace(/trip T2.*\n/, ''), 'at least 3 trips'],
    [ok.replace('stops A, B, C, D, E', 'stops A'), '2 to 60 stops'],
    [ok.replace('stops A, B, C, D, E', 'stops A, B, A, D, E'), 'appears once'],
    [ok.replace('stops A', 'stops <img src=x>'), 'stop names'],
    [ok + 'control Z\n', 'not on the route'],
    [ok + 'control E\n', 'last stop'],
    [ok + 'demand A 0\n', 'weight from 0.1'],
    [ok + 'demand A 1e3\n', 'weight from 0.1'],
    [ok.replace('dwell 0 s per min', 'dwell 99 s per min'), "write 'dwell"],
    [ok + 'ridevalue 3\n', "'ridevalue'"],
    [ok + 'trip T0 07:00 07:02 07:04 07:06 07:08\n', 'already logged'],
    [ok + 'trip X1 07:00 07:02\n', 'one time (or -)'],
    [ok + 'trip X1 - 07:02 07:04 07:06 07:08\n', 'time at the first stop'],
    [ok + 'trip X1 07:00 07:02 07:01 07:06 07:08\n', 'must not go backwards'],
    [ok + 'trip X1 07:00 07:02 07:04 07:06 7:08\n', 'times are like'],
    [ok + 'trip X1 07:00 07:02 07:04 07:06 12:08\n', 'longer than 4 hours'],
    [ok + 'trip $(rm) 07:00 07:02 07:04 07:06 07:08\n', 'trip ids'],
    ['trip X 07:00\n' + ok, "after the 'stops' line"],
    [ok + 'stops A, B\n', 'comes once'],
    [ok + 'bus 1\n', 'lines start with'],
    ['route A\u001b[2J\n' + ok, 'control, hidden'],
    ['route A\u202eB\n' + ok, 'control, hidden'],
    ['# ' + 'x'.repeat(1200) + '\n' + ok, 'longer than 1000'],
    ['#'.repeat(300 * 1024), 'larger than 256 KB'],
  ];
  for (const [text, want] of bad) {
    assert.throws(() => parseLog(text), (e: unknown) => e instanceof InputError && e.message.includes(want), want);
  }
  const log: Log = parseLog('\uFEFF' + ok + 'control C\ndemand A 3\n');
  assert.deepEqual(log.control, [2]);
  assert.equal(log.demand[0], 3);
  assert.equal(log.headway, 480);
});

test('the command line', () => {
  const out: string[] = [], err: string[] = [];
  const code = main(['examples/route-99x.txt'], (s) => out.push(s), (s) => err.push(s));
  assert.equal(code, 0, err.join(''));
  assert.match(out.join(''), /Recommendation: hold to 0\.\d x headway/);
  assert.equal(main([], () => {}, () => {}), 2);
  assert.equal(main(['--help'], () => {}, () => {}), 2);
  const e2: string[] = [];
  assert.equal(main(['examples'], () => {}, (s) => e2.push(s)), 2, 'a folder is refused');
  assert.match(e2.join(''), /could not be read/);
  const e3: string[] = [];
  assert.equal(main(['secret-name-zz.txt'], () => {}, (s) => e3.push(s)), 2);
  assert.ok(!e3.join('').includes('secret-name'), "errors don't echo the path");
  const e4: string[] = [];
  assert.equal(main(['x'], () => {}, (s) => e4.push(s), () => 'route <script>\n'), 2);
  assert.ok(!e4.join('').includes('<script>'), "errors don't echo the input");
  const dir = mkdtempSync(join(tmpdir(), 'gapkeeper-'));
  const big = join(dir, 'big.txt');
  writeFileSync(big, Buffer.alloc(400 * 1024, 35));
  assert.equal(readBounded(big).length, 256 * 1024 + 1, 'reading stops just past the limit');
  const bad = join(dir, 'bad.txt');
  writeFileSync(bad, Buffer.from([0x72, 0xff, 0x0a]));
  assert.throws(() => readBounded(bad), /not valid UTF-8/);
  const noControl: string[] = [];
  assert.equal(main(['x'], (s) => noControl.push(s), () => {}, () => makeLog([60, 900, 60])), 0);
  assert.match(noControl.join(''), /No control stop is set/);
});
