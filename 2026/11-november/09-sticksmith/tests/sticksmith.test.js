import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parsePiece, InputError, LIMITS } from '../src/parse.js';
import { solve, evaluate, alternating, fastestTempo } from '../src/stick.js';
import { analyse, report, where } from '../src/explain.js';

const root = fileURLToPath(new URL('..', import.meta.url));
const cli = join(root, 'bin', 'sticksmith.js');
/** @param {string[]} args */
const run = (args) => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });

/** @param {import('../src/stick.js').Sticking} s */
const flat = (s) => s.map((w) => w.join('+')).join(' ');

test('reads the kit, chords, feet and beats', () => {
  const p = parsePiece('tempo: 120\ngrid: 8\nbar: hh+k hh hh+sn hh k hh hh+sn+k -\n');
  assert.equal(p.notes.length, 6, 'a kick on its own is not a hand note');
  assert.deepEqual(p.notes[0]?.drums, ['hh']);
  assert.deepEqual(p.notes[2]?.drums, ['hh', 'sn']);
  assert.deepEqual(p.notes.map((n) => n.onBeat), [true, false, true, false, false, true]);
  assert.equal(p.notes[3]?.beat, 1.5);
  assert.equal(where(p, 3), 'bar 1 · 2.2');
});

test('a custom drum and a left lead are read', () => {
  const p = parsePiece('lead: left\ndrum gong 1.5 big gong\nfoot cow cowbell pedal\nbar: gong - cow+sn -\ngrid: 4\n');
  assert.equal(p.lead, 'L');
  assert.equal(p.kit.get('gong')?.x, 1.5);
  assert.equal(p.kit.get('gong')?.label, 'big gong');
  assert.equal(p.kit.get('cow')?.foot, true);
});

test('bad passages are refused with a clear reason', () => {
  const bad = [
    ['bar: sn sn sn\n', /3 slots but the grid is 16/],
    ['grid: 7\nbar: sn\n', /grid must be one of/],
    ['tempo: 1000\nbar: sn - - -\ngrid: 4\n', /between 20 and 400/],
    ['tempo: 1e3\n', /expected a number/],
    ['grid: 4\nbar: sn+t1+ft - - -\n', /more than two hands/],
    ['grid: 4\nbar: sn+sn - - -\n', /same drum twice/],
    ['grid: 4\nbar: k k k k\n', /no notes for the hands/],
    ['grid: 4\n', /no bars/],
    ['tempo: 100\ntempo: 120\n', /given twice/],
    ['banana: 3\n', /unknown key/],
    ['drum Snare 0.2\n', /drum name/],
    ['drum sn2 9\n', /between -2 and 2/],
    [`title: ${'x'.repeat(81)}\n`, /longer than 80/],
    ['title: a\u0007b\n', /control/],
    ['title: abc\u202edef\n', /direction/],
    [`grid: 4\n${'bar: sn - - -\n'.repeat(LIMITS.bars + 1)}`, /at most 64 bars/],
    ['x'.repeat(LIMITS.bytes + 1), /larger than 64 KB/],
  ];
  for (const [text, re] of bad) assert.throws(() => parsePiece(/** @type {string} */ (text)), (e) => e instanceof InputError && /** @type {RegExp} */ (re).test(e.message), String(re));
});

test('an unknown drum is named only when it is short', () => {
  assert.throws(() => parsePiece('grid: 4\nbar: cowbell - - -\n'), /unknown drum \(cowbell\)/);
  assert.throws(() => parsePiece(`grid: 4\nbar: ${'z'.repeat(40)} - - -\n`), (e) => e instanceof Error && !e.message.includes('zzzz'));
});

/** A small random passage, for checking the search against brute force. @param {() => number} rng */
function randomPassage(rng) {
  const drums = ['crash', 'hh', 'sn', 't1', 't2', 'ft', 'ride'];
  const grid = rng() < 0.5 ? 8 : 16;
  const pick = () => /** @type {string} */ (drums[Math.floor(rng() * drums.length)]);
  const tokens = [];
  let notes = 0;
  for (let k = 0; k < grid; k++) {
    if (notes >= 10 || rng() < 0.3) { tokens.push('-'); continue; }
    notes++;
    if (rng() < 0.2) {
      const a = pick();
      let b = pick();
      while (b === a) b = pick();
      tokens.push(`${a}+${b}`);
    } else tokens.push(rng() < 0.15 ? `${pick()}+k` : pick());
  }
  if (notes === 0) tokens[0] = 'sn';
  return parsePiece(`grid: ${grid}\nlead: ${rng() < 0.8 ? 'right' : 'left'}\nbar: ${tokens.join(' ')}\n`);
}

/** Every sticking of a passage. @param {import('../src/parse.js').Piece} p */
function* allStickings(p) {
  const n = p.notes.length;
  for (let m = 0; m < 2 ** n; m++) {
    yield p.notes.map((note, i) => {
      const bit = Math.floor(m / 2 ** i) % 2;
      if (note.drums.length === 2) return /** @type {import('../src/stick.js').Hand[]} */ (bit ? ['R', 'L'] : ['L', 'R']);
      return /** @type {import('../src/stick.js').Hand[]} */ ([bit ? 'R' : 'L']);
    });
  }
}

test('the search finds the cheapest sticking: checked against trying every one', () => {
  let seed = 11;
  const rng = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
  let checked = 0;
  let impossible = 0;
  for (let t = 0; t < 60; t++) {
    const p = randomPassage(rng);
    for (const player of /** @type {(keyof typeof import('../src/stick.js').PLAYERS)[]} */ (['beginner', 'average', 'fast'])) {
      for (const tempo of [70, 140, 260]) {
        let best = Infinity;
        for (const s of allStickings(p)) {
          const e = evaluate(p, s, { tempo, player });
          if (e.ok) best = Math.min(best, e.cost);
        }
        const r = solve(p, { tempo, player });
        if (best === Infinity) {
          assert.equal(r.ok, false, `passage ${t} ${player} ${tempo}: brute force found nothing playable`);
          impossible++;
        } else {
          assert.ok(r.ok, `passage ${t} ${player} ${tempo}: search found nothing`);
          if (!r.ok) continue;
          assert.ok(Math.abs(r.cost - best) < 1e-9, `passage ${t} ${player} ${tempo}: ${r.cost} vs ${best}`);
          const e = evaluate(p, r.sticking, { tempo, player });
          assert.ok(e.ok && Math.abs(e.cost - r.cost) < 1e-9, 'the chosen sticking replays at the same cost');
        }
        checked++;
      }
    }
  }
  assert.equal(checked, 540);
  assert.ok(impossible > 0, 'some cases are impossible, so both answers are exercised');
});

test('playability only gets harder as the tempo rises', () => {
  let seed = 5;
  const rng = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
  for (let t = 0; t < 20; t++) {
    const p = randomPassage(rng);
    const top = fastestTempo((tempo) => solve(p, { tempo }).ok);
    for (let tempo = 20; tempo <= 400; tempo += 20) {
      assert.equal(solve(p, { tempo }).ok, top !== null && tempo <= top, `passage ${t} at ${tempo}`);
    }
  }
});

test('a rock groove is played the usual way: right hand on the hi-hat, left on the backbeat', () => {
  const p = parsePiece('tempo: 110\nbar: hh+k - hh - hh+sn - hh - hh+k - hh - hh+sn - hh -\n');
  const r = solve(p);
  assert.ok(r.ok);
  if (r.ok) assert.equal(flat(r.sticking), 'R R R+L R R R R+L R');
});

test('a fast single-drum roll needs both hands, and a too-fast one needs doubles', () => {
  const p = parsePiece('tempo: 150\nbar: sn sn sn sn sn sn sn sn sn sn sn sn sn sn sn sn\n');
  const r = solve(p);
  assert.ok(r.ok);
  if (r.ok) assert.equal(flat(r.sticking), 'R L R L R L R L R L R L R L R L');
  // 32nd notes at 150 bpm are 50 ms apart: faster than any hand's single strokes or doubles.
  const fast = parsePiece(`tempo: 150\ngrid: 32\nbar: ${'sn '.repeat(32)}\n`);
  assert.equal(solve(fast).ok, false);
  const top = fastestTempo((tempo) => solve(fast, { tempo }).ok);
  assert.ok(top !== null && top < 150);
  const r2 = solve(fast, { tempo: /** @type {number} */ (top) });
  assert.ok(r2.ok && evaluate(fast, r2.sticking, { tempo: /** @type {number} */ (top) }).ok);
});

test('a fill that alternating plays with crossed hands is re-stuck to avoid them', () => {
  const p = parsePiece('tempo: 120\nbar: ft sn ft sn ft sn ft sn crash ride crash ride crash ride crash ride\n');
  const alt = evaluate(p, alternating(p));
  const r = solve(p);
  assert.ok(alt.ok && r.ok);
  if (!alt.ok || !r.ok) return;
  const mine = evaluate(p, r.sticking);
  assert.ok(mine.ok);
  if (!mine.ok) return;
  assert.ok(alt.tags.some((t) => t.crossover), 'alternating crosses');
  assert.equal(mine.tags.filter((t) => t.crossover).length, 0);
  assert.ok(mine.cost < alt.cost);
});

test('a left-handed player on a mirrored kit gets the mirrored sticking', () => {
  const right = 'tempo: 130\nbar: sn sn t1 t1 t2 t2 ft ft sn t1 t2 ft crash+k - hh -\n';
  const mirror = [
    'lead: left',
    'drum crash 0.6', 'drum hh 0.45', 'drum sn 0.1', 'drum t1 -0.15', 'drum t2 -0.4', 'drum ft -0.75', 'drum ride -0.95',
    'tempo: 130',
    'bar: sn sn t1 t1 t2 t2 ft ft sn t1 t2 ft crash+k - hh -',
  ].join('\n');
  const a = solve(parsePiece(right));
  const b = solve(parsePiece(mirror));
  assert.ok(a.ok && b.ok);
  if (a.ok && b.ok) {
    const swap = (/** @type {string} */ s) => s.replace(/[RL]/g, (h) => (h === 'R' ? 'L' : 'R'));
    assert.equal(flat(b.sticking), swap(flat(a.sticking)));
  }
});

test('a hand cannot jump across the kit in no time', () => {
  // crash to second floor tom (1.65 m) in a 32nd at 200 bpm: only the other hand can take it.
  const p = parsePiece('drum ft2 1.05\ngrid: 32\ntempo: 200\nbar: crash ft2 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -\n');
  const r = solve(p);
  assert.ok(r.ok);
  if (r.ok) assert.notEqual(r.sticking[0]?.[0], r.sticking[1]?.[0]);
  assert.equal(evaluate(p, [['R'], ['R']]).ok, false);
});

test('a malformed sticking is refused, not scored', () => {
  const p = parsePiece('grid: 4\nbar: hh+sn sn - -\n');
  assert.equal(evaluate(p, [['R', 'R'], ['L']]).ok, false);
  assert.equal(evaluate(p, [['R'], ['L']]).ok, false);
  assert.equal(evaluate(p, [['R', 'L']]).ok, false);
  assert.throws(() => solve(p, { tempo: 900 }), RangeError);
  assert.throws(() => solve(p, { player: /** @type {any} */ ('robot') }), RangeError);
});

test('the report says what to practise and compares alternating', () => {
  const p = parsePiece('title: Test fill\ntempo: 112\nbar: sn sn t1 t1 t2 t2 ft ft sn t1 t2 ft crash+k - hh -\n');
  const text = report(p);
  assert.match(text, /^Sticksmith: Test fill\n112 bpm · 16th-note grid · right hand leads · average hands/);
  assert.match(text, /Fastest playable tempo: \d+ bpm/);
  assert.match(text, /Plain alternating \(R L R L\)/);
  const a = analyse(p);
  assert.equal(a.playable, true);
  assert.equal(a.sticking?.length, p.notes.length);
  const slow = analyse(parsePiece(`tempo: 400\ngrid: 32\nbar: ${'sn '.repeat(32)}\n`));
  assert.equal(slow.playable, false);
  assert.match(report(parsePiece(`tempo: 400\ngrid: 32\nbar: ${'sn '.repeat(32)}\n`)), /can't play this at 400 bpm/);
});

test('command line: examples, JSON and options', () => {
  const r = run([join(root, 'examples', 'rock-fill.txt')]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Rock groove into a tom fill/);
  const j = run([join(root, 'examples', 'gospel-chops.txt'), '--json', '--player', 'fast', '--tempo', '100']);
  assert.equal(j.status, 0, j.stderr);
  const data = JSON.parse(j.stdout);
  assert.equal(data.player, 'fast');
  assert.equal(data.tempo, 100);
  assert.match(run(['--help']).stdout, /usage: sticksmith/);
});

test('command line: hostile and broken input is refused without echoing it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'sticksmith-'));
  try {
    const big = join(dir, 'big.txt');
    writeFileSync(big, 'x'.repeat(LIMITS.bytes + 10));
    const binary = join(dir, 'binary.txt');
    writeFileSync(binary, Buffer.from([0x62, 0x61, 0x72, 0xff, 0xfe]));
    const secret = join(dir, 'secret.txt');
    writeFileSync(secret, 'password=hunter2\n');
    mkdirSync(join(dir, 'folder'));
    const cases = [
      [[big], /larger than 64 KB/],
      [[binary], /not valid UTF-8/],
      [[secret], /line 1: expected "key: value"|unknown key/],
      [[join(dir, 'folder')], /regular file/],
      [[join(dir, 'missing.txt')], /cannot open/],
      [[], /give a passage file/],
      [[secret, '--tempo', '9999'], /--tempo must be/],
      [[secret, '--tempo', '120; rm -rf /'], /--tempo must be/],
      [[secret, '--player', '__proto__'], /--player must be/],
      [[secret, '--evil'], /unknown option/],
    ];
    for (const [args, re] of cases) {
      const r = run(/** @type {string[]} */ (args));
      assert.equal(r.status, 1, `${args}: ${r.stderr}`);
      assert.match(r.stderr, /** @type {RegExp} */ (re));
      assert.ok(!r.stderr.includes('hunter2'));
      assert.equal(r.stdout, '');
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
