import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseRoom, RoomError } from '../src/parse.js';
import { analyse, play, reachable, required, tails, warnings } from '../src/analyse.js';
import { clock, render } from '../src/report.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const EXAMPLE = path.join(ROOT, 'examples', 'clockmaker.txt');
const BIN = path.join(ROOT, 'bin', 'lockpace.js');

/** @param {string[]} args @param {string | Buffer} [input] */
const cli = (args, input = '') => spawnSync(process.execPath, [BIN, ...args], { input, encoding: 'utf8' });

const room = (body) => parseRoom(`goal out\n${body}`);

// ---------- Reading rooms ----------

test('a puzzle line with every part', () => {
  const r = room('players 3\npuzzle Clock face (8.5 min, 2 people) needs brass key, oil uses gear gives Out\n');
  const [p] = r.puzzles;
  assert.deepEqual(
    { name: p.name, time: p.time, crew: p.crew, needs: p.needs, uses: p.uses, gives: p.gives },
    { name: 'Clock face', time: 85, crew: 2, needs: ['brass key', 'oil'], uses: ['gear'], gives: ['out'] },
  );
  assert.equal(r.minPlayers, 3);
  assert.equal(r.maxPlayers, 3);
});

test('clauses may come in any order, and an item named like a keyword part is fine', () => {
  const r = room('puzzle Fuse box (3 min) gives out needs fuses\npuzzle Shelf (1 min) gives fuses\n');
  assert.deepEqual(r.puzzles[0].needs, ['fuses']);
});

test('hostile and broken rooms are refused without echoing them', () => {
  const cases = [
    ['', 'no puzzles'],
    ['puzzle A (2 min) gives x\n', "'goal'".replace('goal out\n', '')],
    ['puzzle <script> (2 min) gives out\n', 'names use letters'],
    ['puzzle Lock\u202eSECRET (2 min) gives out\n', 'invisible formatting'],
    ['puzzle Lock\x1b[2J (2 min) gives out\n', 'control character'],
    ['puzzle A (2 min) gives out\npuzzle a (3 min) gives out\n', 'same name'],
    ['puzzle A (0 min) gives out\n', '0.1 to 120'],
    ['puzzle A (2 min, 20 people) gives out\n', '1 to 12 people'],
    ['puzzle A (2 hours) gives out\n', 'write a puzzle like'],
    ['puzzle A (2 min) gives out, out\n', 'listed twice'],
    ['puzzle A (2 min) needs key uses key gives out\n', 'both needed and used up'],
    ['puzzle A (2 min) gives out gives more\n', 'comes once per puzzle'],
    ['puzzle A (2 min) needs\n', 'at least one item'],
    ['puzzle A (2 min) gives <img src=x>\n', 'items use letters'],
    ['players 9-3\npuzzle A (2 min) gives out\n', 'smaller first'],
    ['limit 999\npuzzle A (2 min) gives out\n', '5 to 240'],
    ['rm -rf SECRET\n', 'lines start with'],
    ['room A\nroom B\npuzzle A (2 min) gives out\n', 'comes once'],
    [`puzzle A (2 min) gives out ${'#'.repeat(300)}\n`, 'longer than 200'],
  ];
  for (const [body, want] of cases) {
    const text = body.startsWith('puzzle A (2 min) gives x') ? body : `goal out\n${body}`;
    assert.throws(() => parseRoom(text), (err) => {
      assert.ok(err instanceof RoomError, String(err));
      assert.ok(err.message.includes(want), `${JSON.stringify(body)} gave ${err.message}`);
      assert.ok(!/SECRET|script|img/.test(err.message));
      return true;
    });
  }
  assert.throws(() => parseRoom('#\n'.repeat(20000)), /larger than 32 KB/);
  const many = Array.from({ length: 61 }, (_, i) => `puzzle P${i} (1 min) gives out\n`).join('');
  assert.throws(() => room(many), /at most 60 puzzles/);
});

test('friendly input: BOM, CRLF, accents and comments', () => {
  const r = parseRoom('\uFEFFroom Le Cabinet de Zoé\r\ngoal sortie\r\npuzzle Clé dorée (2 min) gives sortie   # the last one\r\n');
  assert.equal(r.title, 'Le Cabinet de Zoé');
  assert.equal(r.puzzles[0].name, 'Clé dorée');
});

// ---------- The structure of a room ----------

test('reachable, required and tails', () => {
  const r = room(
    'puzzle A (2 min) gives k\npuzzle B (3 min) needs k gives out\npuzzle Side (4 min) gives coin\npuzzle Locked (1 min) needs nothing here gives z\n',
  );
  assert.deepEqual([...reachable(r).puzzles].sort(), [0, 1, 2]);
  assert.deepEqual([...required(r)].sort(), [0, 1]);
  const t = tails(r, required(r));
  assert.equal(t.get(0), 50);
  assert.equal(t.get(1), 30);
  const w = warnings(r).join('\n');
  assert.match(w, /Locked can never be solved: nothing gives nothing here/);
  assert.match(w, /Side isn't needed to escape/);
  assert.match(w, /red herrings\?\): coin, z/);
});

test('a used-up item wanted by two puzzles is a dead end', () => {
  const r = room('puzzle Drawer (1 min) gives key\npuzzle Chest (2 min) uses key gives gem\npuzzle Door (1 min) uses key, gem gives out\n');
  assert.match(warnings(r).join('\n'), /Dead end: Chest and Door each use up the key, but only 1 exists/);
  assert.equal(analyse(r).unlimited.finish, null);
});

// ---------- Playing a room ----------

test('one player does everything in turn; many players run branches side by side', () => {
  const r = room('puzzle A (4 min) gives a\npuzzle B (6 min) gives b\npuzzle C (2 min) needs a, b gives out\n');
  assert.equal(play(r, 1).finish, 120);
  assert.equal(play(r, 2).finish, 80);
  assert.equal(play(r, Infinity).finish, 80);
  const two = play(r, 2);
  assert.equal(two.idle, 2 * 80 - 120); // one player waits 2 min for B, then one waits during C
  assert.equal(two.wait.length, 20);
});

test('the longest remaining chain goes first', () => {
  // Long chain L1 -> L2 -> exit, and a quick side puzzle S that's also needed.
  const r = room('puzzle S (2 min) gives s\npuzzle L1 (5 min) gives l\npuzzle L2 (5 min) needs l gives m\npuzzle Exit (1 min) needs s, m gives out\n');
  const run = play(r, 1);
  assert.equal(r.puzzles[run.segments[0].puzzle].name, 'L1');
  assert.equal(run.finish, 130);
});

test('a puzzle needing more people than the team is reported, not hung on', () => {
  const r = room('puzzle Lift (3 min, 3 people) gives out\n');
  const run = play(r, 2);
  assert.equal(run.finish, null);
  assert.match(String(run.stuck), /Lift needs 3 people/);
  assert.equal(play(r, 3).finish, 30);
});

test('no team beats the bound, and bigger teams are never slower on the example', () => {
  const r = parseRoom(fs.readFileSync(EXAMPLE, 'utf8'));
  const a = analyse(r);
  let last = Infinity;
  for (const { run, bound } of a.runs) {
    if (run.finish === null) continue;
    assert.ok(run.finish >= /** @type {number} */ (bound));
    assert.ok(run.finish <= last);
    last = run.finish;
    // Nobody is in two places at once.
    for (const s of run.segments) for (const t of run.segments) {
      if (s === t) continue;
      const overlap = s.start < t.end && t.start < s.end;
      if (overlap) assert.ok(!s.players.some((p) => t.players.includes(p)));
    }
  }
  assert.equal(a.unlimited.finish, 370);
  assert.equal(a.deadlines[0].latest, 600 - 370);
});

test('random rooms: every schedule respects items, crews and the floor', () => {
  let seed = 7;
  const rnd = (n) => ((seed = (seed * 1103515245 + 12345) >>> 0) >>> 16) % n;
  for (let round = 0; round < 200; round++) {
    const count = 2 + rnd(9);
    let text = 'goal out\n';
    for (let i = 0; i < count; i++) {
      // Puzzle j gives item i(j+1), so puzzle i may need any of i1 .. i(i).
      const needs = i === 0 ? [] : Array.from({ length: rnd(3) }, () => `i${1 + rnd(i)}`).filter((x, j, all) => all.indexOf(x) === j);
      const gives = i === count - 1 ? 'out' : `i${i + 1}`;
      text += `puzzle P${i} (${1 + rnd(9)} min, ${1 + rnd(2)} people)${needs.length ? ` needs ${needs.join(', ')}` : ''} gives ${gives}\n`;
    }
    const r = parseRoom(text);
    const unl = play(r, Infinity);
    for (let k = 1; k <= 4; k++) {
      const run = play(r, k);
      if (run.finish === null) continue;
      assert.ok(unl.finish !== null && run.finish >= unl.finish, 'never faster than unlimited');
      const given = new Map();
      for (const s of run.segments) for (const it of r.puzzles[s.puzzle].gives) given.set(it, Math.min(given.get(it) ?? Infinity, s.end));
      for (const s of run.segments) {
        for (const it of r.puzzles[s.puzzle].needs) assert.ok((given.get(it) ?? Infinity) <= s.start, 'starts only once its items exist');
        assert.equal(s.players.length, r.puzzles[s.puzzle].crew);
      }
      for (let t = 0; t < run.finish; t += 5) {
        const busy = run.segments.filter((s) => s.start <= t && t < s.end).reduce((n, s) => n + s.players.length, 0);
        assert.ok(busy <= k, 'never more players busy than the team');
      }
    }
  }
});

// ---------- Output ----------

test('clock and the report', () => {
  assert.equal(clock(0), '0:00');
  assert.equal(clock(85), '8:30');
  assert.equal(clock(600), '60:00');
  const r = parseRoom(fs.readFileSync(EXAMPLE, 'utf8'));
  const out = render(r, analyse(r));
  assert.match(out, /2 {2}stuck: Grandfather clock needs 3 people/);
  assert.match(out, /Timeline for 4 players/);
  assert.match(out, /Bookshelf cipher +23:00/);
  assert.match(out, /red herrings\?\): old coin/);
});

// ---------- The command line ----------

test('command line: exit codes, files and standard input', () => {
  const ok = cli([EXAMPLE]);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(cli(['-'], fs.readFileSync(EXAMPLE)).stdout, ok.stdout);
  assert.equal(cli(['-'], 'goal out\npuzzle A (90 min) gives out\n').status, 1, 'over the limit');
  assert.equal(cli([]).status, 2);
  assert.equal(cli(['a', 'b']).status, 2);
  const dir = cli([ROOT]);
  assert.equal(dir.status, 2);
  assert.match(dir.stderr, /regular file/);
  assert.doesNotMatch(cli(['secret-name-zz.txt']).stderr, /secret-name/);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'lockpace-'));
  try {
    fs.symlinkSync(EXAMPLE, path.join(tmp, 'link.txt'));
    assert.equal(cli([path.join(tmp, 'link.txt')]).status, 2, 'symlinks refused');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  assert.match(cli(['-'], Buffer.alloc(100000, 35)).stderr, /larger than 32 KB/);
  assert.match(cli(['-'], Buffer.from([0x67, 0x6f, 0xff, 0x0a])).stderr, /UTF-8/);
});
