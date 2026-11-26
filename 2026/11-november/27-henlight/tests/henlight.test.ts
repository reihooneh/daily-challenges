import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { clockDay, isDst, DstRule, Day } from '../src/sun.js';
import { plan, fewestChanges, totalLight, windows, Options } from '../src/plan.js';
import { check, ConfigError, readConfigFile } from '../src/config.js';
import { compute, run, seasonDays } from '../src/cli.js';

const at = (y: number, m: number, d: number): Date => new Date(Date.UTC(y, m - 1, d));
const clock = (s: string): number => Number(s.slice(0, 2)) * 60 + Number(s.slice(3));

test('sunrise and sunset match published times to within 4 minutes', () => {
  // Sydney (AEST/AEDT) and London (GMT/BST), solstices of 2026.
  const cases: [string, number, number, number, DstRule, Date, string, string][] = [
    ['Sydney winter', -33.87, 151.21, 10, 'au', at(2026, 6, 21), '07:00', '16:54'],
    ['Sydney summer', -33.87, 151.21, 10, 'au', at(2026, 12, 21), '05:41', '20:05'],
    ['London summer', 51.5, -0.13, 0, 'eu', at(2026, 6, 21), '04:43', '21:21'],
    ['London winter', 51.5, -0.13, 0, 'eu', at(2026, 12, 21), '08:04', '15:53'],
  ];
  for (const [what, lat, lon, tz, rule, date, rise, set] of cases) {
    const d = clockDay(date, lat, lon, tz, rule)!;
    assert.ok(Math.abs(d.rise - clock(rise)) <= 4, `${what} sunrise ${d.rise.toFixed(1)} vs ${rise}`);
    assert.ok(Math.abs(d.set - clock(set)) <= 4, `${what} sunset ${d.set.toFixed(1)} vs ${set}`);
  }
  assert.equal(clockDay(at(2026, 6, 21), 80, 0, 0, 'none'), null, 'midnight sun: no sunset');
});

test('daylight saving starts and ends on the right Sundays of 2026', () => {
  const flips = (rule: DstRule): string[] => {
    const out: string[] = [];
    for (let t = at(2026, 1, 2).getTime(); t <= at(2026, 12, 31).getTime(); t += 86400000) {
      const d = new Date(t), y = new Date(t - 86400000);
      if (isDst(d, rule) !== isDst(y, rule)) out.push(d.toISOString().slice(5, 10));
    }
    return out;
  };
  assert.deepEqual(flips('au'), ['04-05', '10-04']);
  assert.deepEqual(flips('eu'), ['03-29', '10-25']);
  assert.deepEqual(flips('us'), ['03-08', '11-01']);
  assert.deepEqual(flips('none'), []);
});

test('the greedy plan needs no more timer changes than the best possible (dynamic programming)', () => {
  let seed = 27;
  const rnd = (): number => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let trial = 0; trial < 25; trial++) {
    const lat = -55 + 110 * rnd(), lon = -180 + 360 * rnd();
    const start = Date.UTC(2026, Math.floor(rnd() * 12), 1 + Math.floor(rnd() * 28));
    const days: Day[] = [];
    for (let k = 0; k < 50; k++) days.push(clockDay(new Date(start + k * 86400000), lat, lon, Math.round(lon / 15), 'none')!);
    const o: Options = { target: 13 * 60 + Math.floor(rnd() * 120), most: 0, ramp: 20 + Math.floor(rnd() * 40), step: rnd() < 0.5 ? 15 : 30 };
    o.most = o.target + 20 + Math.floor(rnd() * 60);
    let greedy: number;
    try {
      greedy = plan(days, o).length;
    } catch {
      continue; // some random seasons can't be lit within the range: covered below
    }
    assert.equal(greedy, fewestChanges(days, o), `trial ${trial}`);
  }
});

test('every day of the plan is inside its window, lit before dawn and dark only at dusk', () => {
  for (const file of ['sydney', 'london']) {
    const r = compute(check(readConfigFile(new URL(`../../examples/${file}.json`, import.meta.url).pathname)));
    const c = r.config;
    const win = windows(r.days, { target: c.target * 60, most: c.most * 60, ramp: c.ramp, step: c.step });
    let covered = 0;
    for (const s of r.segments) {
      for (let i = s.from; i <= s.to; i++, covered++) {
        const d = r.days[i]!, t = totalLight(d, s.setting);
        assert.ok(t >= win[i]!.lo - 1e-9 && t <= win[i]!.hi + 1e-9, `${file} day ${i}`);
        if (!s.setting.off) {
          assert.ok(s.setting.on < d.rise && s.setting.until >= d.rise, `${file} day ${i}: no dark gap at dawn`);
          assert.equal(s.setting.on % c.step, 0);
          assert.equal(s.setting.until % c.step, 0);
        }
      }
    }
    assert.equal(covered, r.days.length, 'every day is planned once');
    // After the ramp, never below the target.
    const lastRamp = win.findIndex((w) => w.lo >= c.target * 60);
    for (let i = lastRamp; i < r.days.length; i++) {
      const s = r.segments.find((g) => g.from <= i && i <= g.to)!;
      assert.ok(totalLight(r.days[i]!, s.setting) >= c.target * 60 - 1e-9);
    }
  }
});

test('the ramp: light never grows by more than a week’s step above where it should be', () => {
  const days = seasonDays(check({}));
  const o = { target: 14 * 60, most: 14.5 * 60, ramp: 30, step: 15 };
  const win = windows(days, o);
  for (let i = 0; i < 14; i++) assert.ok(win[i]!.hi - win[i]!.lo <= 30 + 1e-9);
  assert.ok(Math.abs(win[7]!.lo - (win[0]!.lo + 30)) < 1e-9, 'thirty minutes more after a week');
});

test('the command line prints a plan, and explains when none is possible', () => {
  const ok = run([]);
  assert.equal(ok.code, 0);
  assert.match(ok.out, /Set the timer \d+ times this season/);
  assert.match(ok.out, /\(clocks changed\)/);
  const none = run(['--step', '30', '--ramp', '5', '--most', '14.25']);
  assert.equal(none.code, 1);
  assert.match(none.out, /no timer setting/);
});

test('hostile settings are refused', () => {
  const bad: Record<string, unknown>[] = [
    { lat: 70 }, { lat: 'NaN' }, { lat: '1e999' }, { lon: 200 }, { step: 7 }, { step: 1 }, { from: '02-30' },
    { from: '9-1' }, { from: '06-01', to: '05-01' }, { dst: 'mars' }, { name: 'a\u001b[2J' }, { name: '<b>' },
    { target: 14, most: 14.1 }, { year: 2026.5 }, { utcOffset: 5.1 }, { evil: 1 }, { watts: -3 }, { ramp: 0 },
  ];
  for (const b of bad) assert.throws(() => check(b), ConfigError, JSON.stringify(b));
  const dir = mkdtempSync(join(tmpdir(), 'henlight-'));
  try {
    const good = join(dir, 'good.json');
    writeFileSync(good, '{"__proto__": {"polluted": true}, "name": "Test"}');
    assert.throws(() => check(readConfigFile(good)), ConfigError, '__proto__ is an unknown key, not a prototype');
    assert.equal(({} as Record<string, unknown>).polluted, undefined);
    writeFileSync(join(dir, 'big.json'), `{"name": "${'x'.repeat(20000)}"}`);
    assert.throws(() => readConfigFile(join(dir, 'big.json')), /16 KB/);
    writeFileSync(join(dir, 'array.json'), '[1, 2]');
    assert.throws(() => readConfigFile(join(dir, 'array.json')), /JSON object/);
    writeFileSync(join(dir, 'broken.json'), '{');
    assert.throws(() => readConfigFile(join(dir, 'broken.json')), /not valid JSON/);
    symlinkSync(good, join(dir, 'link.json'));
    assert.throws(() => readConfigFile(join(dir, 'link.json')), /regular file/);
    assert.throws(() => readConfigFile(dir), /regular file/);
    assert.equal(run([join(dir, 'link.json')]).code, 2);
    assert.equal(run(['--lat']).code, 2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
