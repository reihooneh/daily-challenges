import { test } from 'node:test';
import assert from 'node:assert/strict';
import { closeSync, mkdtempSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { main } from '../src/cli.js';
import { forecast, occurrences } from '../src/ledger.js';
import { CHOICES, NODE_LIMIT, optimise } from '../src/optimise.js';
import {
  InputError, type Item, type Plan, formatDay, formatMoney, ordinal, parseDate, parseMoney, parsePlan, ymd,
} from '../src/plan.js';
import { chart } from '../src/report.js';

const EXAMPLE = readFileSync(new URL('../../examples/november.txt', import.meta.url), 'utf8');
const day = (s: string) => parseDate(s)!;

test('money is whole cents, in and out', () => {
  assert.equal(parseMoney('1,180.00'), 118000);
  assert.equal(parseMoney('$55'), 5500);
  assert.equal(parseMoney('0.05'), 5);
  for (const bad of ['1.5', '1.555', '-3', 'abc', '1e5', '12345678901', '']) assert.equal(parseMoney(bad), null, bad);
  assert.equal(formatMoney(-144535), '-$1,445.35');
  assert.equal(formatMoney(5), '$0.05');
});

test('dates are real dates', () => {
  assert.equal(formatDay(day('2026-11-12')), 'Thu 12 Nov 2026');
  for (const bad of ['2026-02-30', '2026-13-01', '26-11-01', '1999-01-01', '2026-11-1']) assert.equal(parseDate(bad), null, bad);
  assert.deepEqual([1, 2, 3, 11, 12, 13, 21, 22, 23, 31].map(ordinal), [
    '1st', '2nd', '3rd', '11th', '12th', '13th', '21st', '22nd', '23rd', 'last day',
  ]);
});

test('schedules land on the right days', () => {
  const start = day('2027-01-01');
  const dates = (s: Parameters<typeof occurrences>[0], days = 120) =>
    occurrences(s, start, days).map((d) => { const x = ymd(start + d); return `${x.m}/${x.d}`; });
  assert.deepEqual(dates({ every: 'month', on: 31 }), ['1/31', '2/28', '3/31', '4/30']);
  assert.deepEqual(dates({ every: 'month', on: 30 }, 60), ['1/30', '2/28']);
  assert.deepEqual(dates({ every: 'fortnight', from: day('2026-12-25') }, 30), ['1/8', '1/22']);
  assert.deepEqual(dates({ every: 'quarter', from: day('2026-11-30') }, 200), ['2/28', '5/30']);
  assert.deepEqual(dates({ every: 'year', from: day('2026-03-15') }, 365), ['3/15']);
  assert.deepEqual(dates({ every: 'once', from: day('2027-02-01') }), ['2/1']);
  assert.equal(occurrences({ every: 'day' }, start, 10).length, 10);
});

test('the example parses', () => {
  const p = parsePlan(EXAMPLE);
  assert.equal(p.days, 91);
  assert.equal(p.balance, 160000);
  assert.equal(p.buffer, 15000);
  assert.equal(p.items.length, 11);
  const yaa = p.items.find((i) => i.name === 'Youth Allowance')!;
  assert.equal(yaa.cents, 42000);
  assert.equal(p.items.filter((i) => i.movable).length, 5);
  assert.equal(p.items.at(-1)!.name, 'Groceries and transport');
});

test('bad and hostile files are refused without echoing them', () => {
  const ok = 'start 2026-11-01\nbalance 100.00\n';
  const cases: Record<string, string> = {
    '': 'needs a start line',
    'start 2026-11-01\nbill A 5.00 daily\n': 'needs a balance line',
    [ok]: 'no bills or spending',
    [ok + 'days 5000\nbill A 5.00 daily\n']: 'days must be',
    [ok + 'bill A 5.00 monthly on 32\n']: 'from 1 to 31',
    [ok + 'bill A 5.00 weekly from 2026-02-30\n']: 'real dates',
    [ok + 'bill A 5.00 whenever\n']: 'the schedule must be',
    [ok + 'bill A 5.00 weekly from 2026-11-01 movable\n']: 'only monthly bills can be movable',
    [ok + 'bill A 5.00 daily\nbill a 5.00 daily\n']: 'same name',
    [ok + 'bill <img src=x> 5.00 daily\n']: 'a name must be',
    [ok + 'bill A\u001b[2J 5.00 daily\n']: 'control or invisible',
    [ok + 'bill A‮ 5.00 daily\n']: 'control or invisible',
    [ok + 'buffer -5.00\nbill A 5.00 daily\n']: 'buffer must be',
    [ok + 'transfer A 5.00 daily\n']: 'start the line with',
    [ok + 'x'.repeat(300)]: 'longer than 200',
    ['#\n'.repeat(20000)]: 'larger than 32 KB',
    [ok + Array.from({ length: 41 }, (_, i) => `bill B${'x'.repeat(i % 5)}${String.fromCharCode(65 + (i % 26))}${i} 1.00 daily`).join('\n')]: 'more than 40 items',
    [ok + Array.from({ length: 9 }, (_, i) => `bill Bill ${String.fromCharCode(65 + i)} 1.00 monthly on 5 movable`).join('\n')]: 'more than 8 movable',
  };
  for (const [text, want] of Object.entries(cases)) {
    assert.throws(() => parsePlan(text), (e: unknown) => {
      assert.ok(e instanceof InputError, String(e));
      assert.ok(e.message.includes(want), `${JSON.stringify(text.slice(0, 40))}: "${e.message}" should include "${want}"`);
      assert.ok(!/img|\u001b/.test(e.message), 'message repeats the input');
      return true;
    });
  }
});

test('the forecast takes payments out before the pay comes in', () => {
  const p = parsePlan('start 2026-11-01\ndays 7\nbalance 100.00\nincome Pay 500.00 once on 2026-11-03\nbill Rent 300.00 once on 2026-11-03\nspend 10.00 daily\n');
  const f = forecast(p);
  assert.deepEqual(f.low.slice(0, 4), [9000, 8000, -23000, 26000]);
  assert.equal(f.lowTide, -23000);
  assert.equal(f.lowDay, 2);
  assert.equal(f.close[2], 27000);
});

// Every combination of days, scored the same way as the optimiser.
function bruteForce(plan: Plan) {
  const movable = plan.items.filter((i) => i.movable);
  const homes = movable.map((it) => (it.schedule as { on: number }).on);
  let best: { cap: number; moved: number; low: number; shift: number } | null = null;
  const days = homes.map(() => 1);
  const total = Math.pow(CHOICES, movable.length);
  for (let n = 0; n < total; n++) {
    let k = n;
    for (let i = 0; i < movable.length; i++) {
      days[i] = (k % CHOICES) + 1;
      k = Math.floor(k / CHOICES);
    }
    const options = homes.map((h, i) => (h > CHOICES && days[i] === CHOICES ? [CHOICES, h] : [days[i]!]));
    for (const combo of cartesian(options)) {
      const items: Item[] = plan.items.map((it) => {
        const j = movable.indexOf(it);
        return j < 0 ? it : { ...it, schedule: { every: 'month', on: combo[j]! } };
      });
      const low = forecast(plan, items).lowTide;
      const moved = combo.filter((d, i) => d !== homes[i]).length;
      const shift = combo.reduce((s, d, i) => s + Math.abs(d - homes[i]!), 0);
      const cand = { cap: Math.min(low, plan.buffer), moved, low, shift };
      if (!best || cand.cap > best.cap || (cand.cap === best.cap && (cand.moved < best.moved ||
          (cand.moved === best.moved && (cand.low > best.low || (cand.low === best.low && cand.shift < best.shift)))))) {
        best = cand;
      }
    }
  }
  return best!;
}

function cartesian(lists: number[][]): number[][] {
  return lists.reduce<number[][]>((acc, list) => acc.flatMap((a) => list.map((x) => [...a, x])), [[]]);
}

function seeded(seed: number) {
  let s = seed;
  return (n: number) => {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s % n;
  };
}

test('the optimiser matches brute force on random budgets', () => {
  const r = seeded(7);
  let movedSomething = 0;
  for (let trial = 0; trial < 60; trial++) {
    const k = 1 + r(3);
    const lines = [
      'start 2026-11-01',
      `days ${30 + r(60)}`,
      `balance ${200 + r(1500)}.00`,
      `buffer ${r(300)}.00`,
      `income Pay ${800 + r(800)}.00 fortnightly from 2026-11-${String(1 + r(14)).padStart(2, '0')}`,
      `bill Rent ${400 + r(900)}.00 monthly on ${1 + r(28)}`,
      `spend ${10 + r(40)}.00 daily`,
    ];
    for (let i = 0; i < k; i++) {
      lines.push(`bill Bill ${String.fromCharCode(65 + i)} ${20 + r(300)}.${String(r(100)).padStart(2, '0')} monthly on ${trial % 7 === 0 && i === 0 ? 30 : 1 + r(28)} movable`);
    }
    const plan = parsePlan(lines.join('\n'));
    const got = optimise(plan);
    const want = bruteForce(plan);
    assert.ok(got.exhaustive);
    assert.equal(got.lowTide, want.low, lines.join('\n'));
    assert.equal(got.moves.length, want.moved, lines.join('\n'));
    if (got.moves.length) movedSomething++;
  }
  assert.ok(movedSomething > 10, `only ${movedSomething} budgets needed a move`);
});

test('eight movable bills stay within the work limit', () => {
  const lines = ['start 2026-11-01', 'days 120', 'balance 900.00', 'buffer 300.00', 'income Pay 1400.00 fortnightly from 2026-11-06',
    'bill Rent 1300.00 monthly on 2', 'spend 30.00 daily'];
  for (let i = 0; i < 8; i++) lines.push(`bill Bill ${String.fromCharCode(65 + i)} ${40 + i * 23}.00 monthly on ${1 + ((i * 5) % 28)} movable`);
  const plan = parsePlan(lines.join('\n'));
  const started = Date.now();
  const got = optimise(plan);
  assert.ok(got.nodes <= NODE_LIMIT + 1);
  assert.ok(Date.now() - started < 60_000);
  assert.ok(got.lowTide >= forecast(plan).lowTide, 'never worse than doing nothing');
});

test('the chart marks days below the buffer', () => {
  const [bars, marks] = chart([500, 400, 50, 600], 100);
  assert.equal([...bars!].length, 4);
  assert.equal(marks, '  ^');
  assert.equal(chart([500, 600], 100).length, 2, 'no marks line when never below');
});

function runCli(args: string[], stdinText?: string) {
  let out = '';
  let err = '';
  let fd: number | undefined;
  if (stdinText !== undefined) {
    const p = join(mkdtempSync(join(tmpdir(), 'lowtide-')), 'in.txt');
    writeFileSync(p, stdinText);
    fd = openSync(p, 'r');
  }
  const code = main(args, (s) => (out += s), (s) => (err += s), fd);
  if (fd !== undefined) closeSync(fd);
  return { code, out, err };
}

test('command line: the example, standard input and exit codes', () => {
  const ex = new URL('../../examples/november.txt', import.meta.url).pathname;
  const r = runCli([ex]);
  assert.equal(r.code, 0);
  assert.match(r.out, /MOVE THESE DUE DATES/);
  assert.match(r.out, /Student loan .* from the 8th to the 13th/);
  assert.match(r.out, /never below your buffer/);
  const tight = runCli(['-'], 'start 2026-11-01\ndays 20\nbalance 10.00\nbuffer 50.00\nbill Rent 900.00 monthly on 3\n');
  assert.equal(tight.code, 1);
  assert.match(tight.out, /you'd still need \$940\.00 more/);
});

test('command line: bad arguments and files', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lowtide-'));
  const big = join(dir, 'big.txt');
  writeFileSync(big, '#\n'.repeat(30000));
  for (const args of [[], ['a', 'b'], ['--bogus'], ['/no/such/file'], [dir], [big], ['/dev/zero'], ['\u001b]0;owned\u0007$(reboot)']]) {
    const r = runCli(args);
    assert.equal(r.code, 2, JSON.stringify(args));
    assert.equal(r.out, '');
    assert.ok(r.err.startsWith('lowtide: '), r.err);
    assert.ok(!/owned|reboot/.test(r.err));
  }
  const bin = join(dir, 'bin.txt');
  writeFileSync(bin, Buffer.from([0xff, 0xfe, 0x00, 0x41]));
  assert.match(runCli([bin]).err, /not valid UTF-8|control/);
  const odd = join(dir, 'plan\u001b[31m.txt');
  writeFileSync(odd, EXAMPLE);
  const r = runCli([odd]);
  assert.ok(!r.out.includes('\u001b'));
  assert.match(r.out, /plan\?\?31m\.txt/);
});
