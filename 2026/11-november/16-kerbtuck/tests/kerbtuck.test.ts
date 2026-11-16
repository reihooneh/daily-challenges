import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PRESETS, derive, parseCar, CarError, checkCar } from '../src/car.js';
import { drive, corners, hits, Pose } from '../src/motion.js';
import { scene, plan, oneMoveGap, replay, parked, SIDE, OTHER } from '../src/park.js';
import { run } from '../src/cli.js';

test('a car on full lock drives round a circle of its turning radius and comes back', () => {
  const car = PRESETS.golf!;
  const { radius, curvature } = derive(car);
  const start: Pose = { x: 1, y: 2, heading: 0.3 };
  const back = drive(start, curvature, 2 * Math.PI * radius);
  assert.ok(Math.hypot(back.x - start.x, back.y - start.y) < 1e-9);
  const half = drive(start, curvature, Math.PI * radius);
  assert.ok(Math.abs(Math.hypot(half.x - start.x, half.y - start.y) - 2 * radius) < 1e-9, 'half way round is a diameter away');
  const straight = drive({ x: 0, y: 0, heading: 0 }, 0, -2);
  assert.deepEqual([straight.x, straight.y], [-2, 0]);
  // The outer front wheel on full lock traces the published turning circle.
  const t = derive(car).track;
  const outer = Math.hypot(car.wheelbase, radius + t / 2);
  assert.ok(Math.abs(outer * 2 - car.turningCircle) < 1e-9);
});

test('collision checks: apart, overlapping, and a rotated corner just touching', () => {
  const box = { x0: 0, y0: 0, x1: 1, y1: 1 };
  const sq = (cx: number, cy: number, a: number): [number, number][] =>
    [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]].map(([x, y]) => [cx + x! * Math.cos(a) - y! * Math.sin(a), cy + x! * Math.sin(a) + y! * Math.cos(a)]);
  assert.equal(hits(sq(2, 0.5, 0), box), false);
  assert.equal(hits(sq(1.3, 0.5, 0), box), true);
  // A diamond whose corner is 0.05 m from the box: its bounding box overlaps, but it doesn't.
  const r = Math.SQRT1_2;
  assert.equal(hits(sq(1 + r + 0.05, 1 + r + 0.05, Math.PI / 4), box), false);
  assert.equal(hits(sq(1 + r - 0.05, 0.5, Math.PI / 4), box), true);
});

test('the one-go formula matches swinging the car out of the space, to 2 cm', () => {
  for (const car of Object.values(PRESETS)) {
    const { rearOverhang, curvature } = derive(car);
    const front = { y0: SIDE, y1: SIDE + OTHER.width };
    // Does the car, parked at the kerb with its rear bumper at x = 0, swing out of a gap this
    // long without touching the car in front? (Run the last part of the parking backwards.)
    const swings = (gap: number) => {
      const park: Pose = { x: rearOverhang, y: SIDE + car.width / 2, heading: 0 };
      for (let d = 0; d < 6; d += 0.01) {
        const p = drive(park, curvature, d);
        if (p.heading > Math.PI / 2) break;
        if (hits(corners(car, p), { x0: gap, x1: gap + OTHER.length, ...front })) return false;
      }
      return true;
    };
    let lo = car.length, hi = car.length + 4;
    for (let i = 0; i < 40; i++) {
      const mid = (lo + hi) / 2;
      if (swings(mid)) hi = mid; else lo = mid;
    }
    assert.ok(Math.abs(hi - oneMoveGap(car)) < 0.02, `${car.name}: simulated ${hi.toFixed(3)}, formula ${oneMoveGap(car).toFixed(3)}`);
  }
});

test('plenty of room: in one go; less room: more goes; too little: no way in', () => {
  for (const id of ['fiat500', 'golf', 'ranger']) {
    const car = PRESETS[id]!;
    let last = -1;
    for (const extra of [0.5, 0, -0.4, -0.65]) {
      const gap = oneMoveGap(car) + extra;
      const s = scene(car, gap);
      const p = plan(s);
      if (extra === 0.5) assert.ok(p.found && p.changes === 0, `${id} at +0.5 m`);
      if (!p.found) { last = Infinity; continue; }
      assert.ok(p.changes >= last, `${id}: fewer goes in a smaller gap`);
      last = p.changes;
      const check = replay(s, p.moves);
      assert.ok(check.ok, `${id}: the plan bumps something`);
      assert.ok(parked(s, check.end), `${id}: the plan doesn't end parked`);
    }
    assert.equal(plan(scene(car, car.length + 0.05)).found, false, `${id} fits a gap no longer than itself`);
  }
});

test('a bigger car needs a bigger gap', () => {
  const order = ['fiat500', 'golf', 'cx5', 'model3', 'ranger'].map((k) => oneMoveGap(PRESETS[k]!));
  for (let i = 1; i < order.length; i++) assert.ok(order[i]! > order[i - 1]!);
});

test('car files are read strictly and errors never repeat the input', () => {
  const good = { name: 'My Corolla', length: 4.4, width: 1.79, wheelbase: 2.64, frontOverhang: 0.93, turningCircle: 10.4 };
  assert.equal(parseCar(JSON.stringify(good)).name, 'My Corolla');
  const bad: [string, RegExp][] = [
    ['not json', /valid JSON/],
    ['[1,2]', /one JSON object/],
    [JSON.stringify({ ...good, colour: 'red' }), /doesn't know/],
    [JSON.stringify(good).replace('{', '{"__proto__":{"polluted":1},'), /doesn't know/],
    [JSON.stringify({ ...good, name: '<script>alert(1)</script>' }), /name uses/],
    [JSON.stringify({ ...good, length: '4.4' }), /length should be/],
    [JSON.stringify(good).replace('4.4', '1e999'), /length should be/],
    [JSON.stringify({ ...good, width: 9 }), /width should be/],
    [JSON.stringify({ ...good, turningCircle: 7, wheelbase: 4 }), /too tight|too little/],
    [`{"name":"${'a'.repeat(5000)}"}`, /at most 4 KB/],
  ];
  for (const [text, re] of bad) {
    assert.throws(() => parseCar(text), (e: unknown) => e instanceof CarError && re.test(e.message) && !/script|red|polluted/.test(e.message), text.slice(0, 40));
  }
  assert.equal(({} as Record<string, unknown>).polluted, undefined);
  for (const car of Object.values(PRESETS)) checkCar(car);
});

test('the command line: plans, compares, and refuses links, folders and bad numbers', () => {
  const lines: string[] = [];
  const errs: string[] = [];
  const go = (args: string[]) => { lines.length = 0; errs.length = 0; return run(args, (s) => lines.push(s), (s) => errs.push(s)); };
  assert.equal(go(['--car', 'golf', '--gap', '6.4']), 0);
  assert.match(lines.join('\n'), /It goes in in one go:/);
  assert.match(lines.join('\n'), /checked every 5 cm for bumps: clear/);
  assert.equal(go(['--compare', '5.6']), 0);
  assert.match(lines.join('\n'), /Fiat 500 .* in one go/);
  assert.equal(go(['--car', 'golf', '--gap', '-3']), 1);
  assert.match(errs[0]!, /from 2 to 15/);
  assert.equal(go(['--car', 'golf', '--gap', 'NaN']), 1);
  assert.equal(go(['--car', '__proto__', '--gap', '6']), 1);
  assert.equal(go(['--car', 'golf']), 1);
  assert.equal(go(['--wat']), 2);
  const dir = mkdtempSync(join(tmpdir(), 'kerbtuck-'));
  try {
    const real = join(dir, 'car.json');
    writeFileSync(real, JSON.stringify({ length: 4.4, width: 1.79, wheelbase: 2.64, frontOverhang: 0.93, turningCircle: 10.4 }));
    assert.equal(go(['--car-file', real, '--gap', '6.5']), 0);
    symlinkSync(real, join(dir, 'link.json'));
    assert.equal(go(['--car-file', join(dir, 'link.json'), '--gap', '6']), 1);
    assert.match(errs[0]!, /plain file/);
    assert.equal(go(['--car-file', dir, '--gap', '6']), 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
