import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { PlanError, feasible, parse, sessions, stopAfter, windings } from '../src/crownwind.js';
import { report } from '../src/cli.js';

const example = readFileSync(new URL('../examples/collection.json', import.meta.url), 'utf8');

test('the example plan keeps every watch running', () => {
  const plan = parse(example);
  const { sessions: s, stranded } = sessions(plan);
  assert.equal(stranded.length, 0);
  assert.ok(feasible(plan, s));
  // each watch, wound only where planned, never runs past its margin
  const per = windings(plan, s);
  for (const w of plan.watches.filter((x) => !x.mayStop)) {
    let stop = stopAfter(w, w.firstStop);
    for (const t of per.get(w.name)) {
      assert.ok(t <= stop, `${w.name} wound after it stopped`);
      stop = stopAfter(w, t + w.run);
    }
    assert.ok(stop >= plan.horizon, `${w.name} stops before the end`);
  }
  assert.match(report(plan), /Allowed to stop \(not planned\): Seiko diver/);
});

test('wearing an automatic keeps it going and leaves it full', () => {
  const w = { kind: 'automatic', run: 600, wear: [[100, 300], [1000, 1100]] };
  assert.equal(stopAfter(w, 200), 900); // worn before it stopped: full at 300, runs to 900
  assert.equal(stopAfter(w, 50), 50); // stopped before it was put on
  assert.equal(stopAfter({ ...w, kind: 'manual' }, 200), 200);
  assert.equal(stopAfter({ ...w, wear: [[100, 300], [800, 900]] }, 200), 1500); // the stretches chain
});

function rng(seed) {
  let s = seed;
  return () => ((s = (s * 1103515245 + 12345) % 2147483648) / 2147483648);
}

test('the fewest sessions match a brute force over every set of slots', () => {
  const r = rng(11);
  for (let trial = 0; trial < 120; trial++) {
    const nSlots = 3 + Math.floor(r() * 9);
    const horizon = 3000;
    const slots = [...new Set(Array.from({ length: nSlots }, () => Math.round(r() * horizon)))].sort((a, b) => a - b);
    const watches = Array.from({ length: 1 + Math.floor(r() * 3) }, (_, i) => {
      const run = 400 + Math.round(r() * 1200);
      const auto = r() < 0.4;
      return { name: `w${i}`, kind: auto ? 'automatic' : 'manual', run, firstStop: Math.round(r() * run), mayStop: false,
        wear: auto ? [[Math.round(r() * 1500), Math.round(1500 + r() * 300)]] : [] };
    });
    const plan = { horizon, slots, watches };
    const greedy = sessions(plan);
    let best = Infinity;
    for (let mask = 0; mask < 1 << slots.length; mask++) {
      const chosen = slots.filter((_, i) => mask & (1 << i));
      if (chosen.length < best && feasible(plan, chosen)) best = chosen.length;
    }
    if (greedy.stranded.length === 0) {
      assert.equal(greedy.sessions.length, best, `trial ${trial}`);
      assert.ok(feasible(plan, greedy.sessions));
    } else {
      assert.equal(best, Infinity, `trial ${trial}: greedy gave up but a plan exists`);
    }
  }
});

test('the fewest windings per watch match a brute force over subsets of the sessions', () => {
  const r = rng(5);
  for (let trial = 0; trial < 80; trial++) {
    const horizon = 2500;
    const run = 500 + Math.round(r() * 700);
    const w = { name: 'w', kind: 'manual', run, firstStop: Math.round(r() * run), mayStop: false, wear: [] };
    const chosen = [...new Set(Array.from({ length: 8 }, () => Math.round(r() * horizon)))].sort((a, b) => a - b);
    const plan = { horizon, watches: [w] };
    if (!feasible(plan, chosen)) continue;
    const mine = windings(plan, chosen).get('w');
    let best = Infinity;
    for (let mask = 0; mask < 1 << chosen.length; mask++) {
      const sub = chosen.filter((_, i) => mask & (1 << i));
      if (sub.length < best && feasible(plan, sub)) best = sub.length;
    }
    assert.equal(mine.length, best);
  }
});

test('a watch no slot can save is reported, not hidden', () => {
  const plan = parse(JSON.stringify({
    slots: [{ days: [0, 1, 2, 3, 4, 5, 6], at: ['21:00'] }],
    watches: [{ name: 'Tiny', reserve: 6, left: 6 }, { name: 'Big', reserve: 100, left: 50 }],
  }));
  const { stranded } = sessions(plan);
  assert.equal(stranded[0].watch.name, 'Tiny');
  assert.match(report(plan), /Tiny will stop/);
});

test('hostile and broken files are refused with a reason', () => {
  const base = JSON.parse(example);
  const bad = [
    'nope',
    '[]',
    '{"__proto__": {"x": 1}}',
    JSON.stringify({ ...base, days: 1e9 }),
    JSON.stringify({ ...base, days: 2.5 }),
    JSON.stringify({ ...base, margin: -1 }),
    JSON.stringify({ ...base, slots: [] }),
    JSON.stringify({ ...base, slots: [{ days: [7], at: ['07:00'] }] }),
    JSON.stringify({ ...base, slots: [{ days: [1], at: ['25:00'] }] }),
    JSON.stringify({ ...base, watches: [{ name: '<script>', reserve: 40 }] }),
    JSON.stringify({ ...base, watches: [{ name: 'A', reserve: Number.MAX_VALUE }] }),
    JSON.stringify({ ...base, watches: [{ name: 'A', reserve: 40, left: 80 }] }),
    JSON.stringify({ ...base, watches: [{ name: 'A', reserve: 40 }, { name: 'A', reserve: 40 }] }),
    JSON.stringify({ ...base, watches: [{ name: 'A', reserve: 40, kind: 'quartz' }] }),
    JSON.stringify({ ...base, watches: [{ name: 'A', reserve: 40, worn: [{ days: [1], from: '10:00', to: '09:00' }] }] }),
    JSON.stringify({ ...base, watches: Array.from({ length: 61 }, (_, i) => ({ name: `w${i}`, reserve: 40 })) }),
    'x'.repeat(70000),
  ];
  for (const text of bad) assert.throws(() => parse(text), PlanError, text.slice(0, 60));
});
