import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';

import { main } from '../src/cli.js';
import { largestClique, minimumColouring } from '../src/colour.js';
import { formatTime, parsePlay, parseTime, PlayError } from '../src/parse.js';
import { cast } from '../src/plan.js';
import { pairing, timeline } from '../src/timeline.js';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const EXAMPLE = join(HERE, '..', 'examples', 'lighthouse.play');
const BIN = join(HERE, '..', 'bin', 'castling.js');

/** A tiny seeded random generator, so failures can be reproduced. */
function random(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 2 ** 32;
  };
}

/** @param {boolean[][]} g @param {number[]} colours */
function validColouring(g, colours) {
  for (let u = 0; u < g.length; u++) for (let v = 0; v < g.length; v++) if (g[u][v] && colours[u] === colours[v]) return false;
  return true;
}

/** Brute force: the smallest k for which some k-colouring exists. */
function bruteChromatic(g) {
  const n = g.length;
  for (let k = 1; k <= n; k++) {
    const colours = new Array(n).fill(0);
    const tryAll = (v) => {
      if (v === n) return true;
      for (let c = 0; c < k; c++) {
        colours[v] = c;
        if (colours.slice(0, v).every((cu, u) => !g[u][v] || cu !== c) && tryAll(v + 1)) return true;
      }
      return false;
    };
    if (tryAll(0)) return k;
  }
  return n;
}

function randomGraph(rand, n, p) {
  const g = Array.from({ length: n }, () => new Array(n).fill(false));
  for (let u = 0; u < n; u++) for (let v = u + 1; v < n; v++) if (rand() < p) g[u][v] = g[v][u] = true;
  return g;
}

describe('times', () => {
  it('reads minutes and minutes:seconds', () => {
    assert.equal(parseTime('8'), 480);
    assert.equal(parseTime('1:30'), 90);
    assert.equal(parseTime('0:05'), 5);
    for (const bad of ['1:60', '1:5', '-1', '1.5', '1e3', '1234', '', ' 1', '١']) assert.equal(parseTime(bad), null, bad);
  });

  it('formats times', () => {
    assert.equal(formatTime(90), '1:30');
    assert.equal(formatTime(3780), '1:03:00');
    assert.equal(formatTime(-45), '-0:45');
  });
});

describe('graph colouring', () => {
  const cycle = (n) => Array.from({ length: n }, (_, u) => Array.from({ length: n }, (_, v) => Math.abs(u - v) === 1 || Math.abs(u - v) === n - 1));

  it('knows the classic answers', () => {
    assert.equal(minimumColouring(cycle(5)).count, 3); // odd cycles need 3
    assert.equal(minimumColouring(cycle(6)).count, 2); // even cycles need 2
    const complete = Array.from({ length: 5 }, (_, u) => Array.from({ length: 5 }, (_, v) => u !== v));
    assert.equal(minimumColouring(complete).count, 5);
    assert.equal(minimumColouring([[false], [false]].map(() => [false, false])).count, 1);
    assert.deepEqual(minimumColouring([]), { colours: [], count: 0, complete: true, proven: true });
  });

  it('colours the Petersen graph with 3, though its largest clique is only 2', () => {
    const edges = [[0,1],[1,2],[2,3],[3,4],[4,0],[0,5],[1,6],[2,7],[3,8],[4,9],[5,7],[7,9],[9,6],[6,8],[8,5]];
    const g = Array.from({ length: 10 }, () => new Array(10).fill(false));
    for (const [u, v] of edges) g[u][v] = g[v][u] = true;
    const result = minimumColouring(g);
    assert.equal(result.count, 3);
    assert.ok(validColouring(g, result.colours));
    assert.equal(largestClique(g).members.length, 2);
  });

  it('matches brute force on 300 random graphs', () => {
    const rand = random(9);
    for (let trial = 0; trial < 300; trial++) {
      const g = randomGraph(rand, 1 + Math.floor(rand() * 8), rand());
      const result = minimumColouring(g);
      assert.ok(result.proven);
      assert.ok(validColouring(g, result.colours));
      assert.equal(result.count, bruteChromatic(g));
      const clique = largestClique(g).members;
      for (const u of clique) for (const v of clique) if (u !== v) assert.ok(g[u][v]);
      assert.ok(clique.length <= result.count);
    }
  });

  it('respects a maximum number of colours', () => {
    const result = minimumColouring(cycle(5), { maxColours: 2 });
    assert.equal(result.complete, false);
    assert.equal(result.proven, true); // proven impossible
  });

  it('stops at its step budget on a large dense graph', () => {
    const g = randomGraph(random(4), 60, 0.5);
    const started = Date.now();
    const result = minimumColouring(g, { budget: 20_000 });
    assert.ok(Date.now() - started < 5000);
    assert.equal(result.proven, false);
    assert.ok(result.complete && validColouring(g, result.colours)); // still a usable answer
  });
});

describe('the timeline', () => {
  const play = parsePlay(readFileSync(EXAMPLE, 'utf8'));
  const tl = timeline(play);

  it('adds scene changes and intervals', () => {
    // 45:00 of scenes + 15:00 interval + 6 scene changes of 0:30 (none either side of the interval)
    assert.equal(tl.runningTime, 45 * 60 + 15 * 60 + 6 * 30);
    assert.equal(tl.intervals, 1);
  });

  it('places entrances and exits inside scenes', () => {
    const scene2 = tl.scenes[1];
    assert.deepEqual(tl.appearances.get('nell')?.[0], { scene: 1, start: scene2.start + 60, end: scene2.end });
    assert.deepEqual(tl.appearances.get('tobias')?.[1], { scene: 2, start: tl.scenes[2].start, end: tl.scenes[2].end - 150 });
  });

  it('uses the right change time for the costume being put on', () => {
    const p = pairing(play, tl, 'gull', 'ghost');
    assert.ok(p.possible);
    assert.equal(p.tightest?.needed, 180); // ghost make-up, not the default
    assert.equal(p.tightest?.gap, 15 * 60);
    assert.equal(p.spare, 12 * 60);
  });

  it('allows a double inside one scene when the timing works', () => {
    const doubled = parsePlay('change 0:30\nscene 1 10:00 : a<6:00 b>5:00\n');
    const p = pairing(doubled, timeline(doubled), 'a', 'b');
    assert.ok(p.possible && p.spare === 30); // a leaves at 4:00, b enters at 5:00, 0:30 needed
    const clash = parsePlay('scene 1 10:00 : a<5:00 b>4:00\n');
    assert.deepEqual(pairing(clash, timeline(clash), 'a', 'b'), { possible: false, sharedScene: '1' });
  });
});

/** Check a plan independently of the code that made it. */
function checkPlan(play, result) {
  const tl = timeline(play);
  const seen = result.plan.flatMap((a) => a.roles);
  assert.deepEqual([...seen].sort(), [...play.roles].sort(), 'every role is cast exactly once');
  assert.ok(result.plan.length <= result.actors, 'never more actors than the company has');
  for (const actor of result.plan) {
    for (const a of actor.roles)
      for (const b of actor.roles) {
        if (a >= b) continue;
        const p = pairing(play, tl, a, b);
        assert.ok(p.possible && p.spare >= result.safety, `${a} + ${b}`);
        assert.ok(!play.apart.some(([x, y]) => (x === a && y === b) || (x === b && y === a)));
      }
  }
  for (const [a, b] of play.together) assert.ok(result.plan.some((actor) => actor.roles.includes(a) && actor.roles.includes(b)));
}

/** Brute force over every way to split the roles into actors (Bell numbers: 877 ways for 7 roles). */
function bruteBest(play) {
  const tl = timeline(play);
  const roles = play.roles;
  let fewest = Infinity;
  let safest = -Infinity;
  const ok = (group) => {
    let spare = Infinity;
    for (let i = 0; i < group.length; i++)
      for (let j = i + 1; j < group.length; j++) {
        const p = pairing(play, tl, group[i], group[j]);
        if (!p.possible || p.spare < 0) return null;
        if (play.apart.some(([x, y]) => (x === group[i] && y === group[j]) || (x === group[j] && y === group[i]))) return null;
        spare = Math.min(spare, p.spare);
      }
    return spare;
  };
  const results = [];
  const split = (i, groups) => {
    if (i === roles.length) {
      if (!play.together.every(([a, b]) => groups.some((g) => g.includes(a) && g.includes(b)))) return;
      const spares = groups.map(ok);
      if (spares.some((s) => s === null)) return;
      results.push({ size: groups.length, spare: Math.min(...spares) });
      return;
    }
    for (const g of groups) {
      g.push(roles[i]);
      split(i + 1, groups);
      g.pop();
    }
    groups.push([roles[i]]);
    split(i + 1, groups);
    groups.pop();
  };
  split(0, []);
  for (const r of results) fewest = Math.min(fewest, r.size);
  for (const r of results) if (r.size === fewest) safest = Math.max(safest, r.spare);
  return { fewest, safest };
}

function randomPlay(rand) {
  const roles = ['ada', 'bo', 'cy', 'di', 'ed', 'fay', 'gus'].slice(0, 3 + Math.floor(rand() * 5));
  const lines = [`change 0:${String(10 + Math.floor(rand() * 50))}`, `between 0:${String(Math.floor(rand() * 40)).padStart(2, '0')}`];
  const used = new Set();
  const scenes = 2 + Math.floor(rand() * 5);
  for (let s = 0; s < scenes; s++) {
    const cast = roles.filter(() => rand() < 0.45);
    if (cast.length === 0) cast.push(roles[Math.floor(rand() * roles.length)]);
    const words = cast.map((r) => {
      used.add(r);
      const enter = rand() < 0.3 ? `>0:${String(Math.floor(rand() * 50)).padStart(2, '0')}` : '';
      const exit = rand() < 0.3 ? `<0:${String(Math.floor(rand() * 50)).padStart(2, '0')}` : '';
      return r + enter + exit;
    });
    lines.push(`scene s${s} 2:00 : ${words.join(' ')}`);
    if (rand() < 0.2) lines.push('interval 2:00');
  }
  const present = roles.filter((r) => used.has(r));
  if (present.length >= 2 && rand() < 0.3) lines.push(`apart ${present[0]} ${present[1]}`);
  return parsePlay(lines.join('\n'));
}

describe('casting', () => {
  it('casts the example with the proven minimum', () => {
    const play = parsePlay(readFileSync(EXAMPLE, 'utf8'));
    const result = cast(play);
    assert.equal(result.minimum, 7);
    assert.ok(result.minimumProven && result.feasible && !result.budgetHit);
    assert.equal(result.safety, 120);
    assert.ok(result.plan.some((a) => a.roles.includes('gull') && a.roles.includes('ghost')));
    checkPlan(play, result);
  });

  it('says when the company is too small, and when it is generous', () => {
    const play = parsePlay(readFileSync(EXAMPLE, 'utf8'));
    assert.equal(cast(play, { actors: 6 }).feasible, false);
    const roomy = cast(play, { actors: 9 });
    assert.ok(roomy.feasible);
    checkPlan(play, roomy);
    assert.ok(roomy.safety >= cast(play).safety); // more actors never makes it less safe
    // With 9 actors nobody needs to double except the planned gull + ghost.
    assert.equal(roomy.plan.length, 8);
    assert.equal(roomy.safety, 12 * 60);
  });

  it('finds the true minimum and the safest plan on 200 random plays (checked by brute force)', () => {
    const rand = random(2026);
    for (let trial = 0; trial < 200; trial++) {
      const play = randomPlay(rand);
      const result = cast(play);
      const truth = bruteBest(play);
      assert.equal(result.minimum, truth.fewest, `trial ${trial}`);
      assert.equal(result.safety, truth.safest, `trial ${trial}`);
      checkPlan(play, result);
    }
  });

  it('refuses impossible "together" requests', () => {
    assert.throws(() => cast(parsePlay('scene 1 5 : a b\ntogether a b\n')), /both in scene 1/);
    assert.throws(() => cast(parsePlay('scene 1 5 : a\nscene 2 5 : b\ntogether a b\n')), /too quick/);
  });

  it('handles the largest allowed play quickly', () => {
    const rand = random(77);
    const roles = Array.from({ length: 60 }, (_, i) => `r${i}`);
    const lines = ['between 1:00', 'change 0:45'];
    for (let s = 0; s < 80; s++) lines.push(`scene s${s} 3:00 : ${roles.filter(() => rand() < 0.08).concat(roles[s % 60]).filter((r, i, a) => a.indexOf(r) === i).join(' ')}`);
    const play = parsePlay(lines.join('\n'));
    const started = Date.now();
    const result = cast(play, { budget: 200_000 });
    assert.ok(Date.now() - started < 20_000);
    assert.ok(result.feasible);
    checkPlan(play, result);
  });
});

describe('hostile breakdowns', () => {
  /** @param {string} text @param {RegExp} expected @param {string} [secret] */
  const rejects = (text, expected, secret) => {
    assert.throws(
      () => parsePlay(text),
      (error) => error instanceof PlayError && expected.test(error.message) && (!secret || !error.message.includes(secret)),
    );
  };

  it('rejects malformed lines with the line number and no echo', () => {
    rejects('scene 1 5 : a\nhack the planet\n', /^line 2: unknown keyword/, 'planet');
    rejects('scene 1 5 : <script>\n', /role 1 is not valid/, 'script');
    rejects('scene 1 5 : Mara\n', /role 1 is not valid/, 'Mara');
    rejects('scene 1 5 : a a\n', /listed twice/);
    rejects('scene 1 5 : a>5:00\n', /leave before it arrives/);
    rejects('scene 1 5 : a>3:00<2:00\n', /leave before it arrives/);
    rejects('scene 1 5 : a>9:99\n', /not M:SS/);
    rejects('scene 1 0 : a\n', /from 0:01 to 180:00/);
    rejects('scene 1 181 : a\n', /from 0:01 to 180:00/);
    rejects('scene ../x 5 : a\n', /scene label/, '../x');
    rejects('scene 1 5 : a\nscene 1 5 : b\n', /label is already used/);
    rejects('scene 1 5 a\n', /write a scene as/);
    rejects('change 31:00\nscene 1 5 : a\n', /up to 30:00/);
    rejects('change 1\nchange 2\nscene 1 5 : a\n', /only be one default/);
    rejects('role a change 1\nrole a change 2\nscene 1 5 : a\n', /already set on line 1/);
    rejects('role ghost change 1\nscene 1 5 : a\n', /^line 1: this role never appears/);
    rejects('scene 1 5 : a\ntogether a zed\n', /never appears/, 'zed');
    rejects('scene 1 5 : a\napart a a\n', /must be different/);
    rejects('title <h1>x</h1>\nscene 1 5 : a\n', /title must be/, 'h1');
    rejects('title Café\nscene 1 5 : a\n', /plain printable ASCII/);
    rejects('title a\u001b[2Jb\nscene 1 5 : a\n', /plain printable ASCII/);
    rejects('title a‮b\nscene 1 5 : a\n', /plain printable ASCII/);
    rejects('scene 1 5 : a\u0000b\n', /plain printable ASCII/);
    rejects('# only a comment\n', /no scenes/);
    rejects(`scene 1 5 : ${'a'.repeat(300)}\n`, /longer than 200/);
    rejects('\n'.repeat(70_000), /larger than/);
  });

  it('enforces the limits on scenes and roles', () => {
    const tooManyScenes = Array.from({ length: 81 }, (_, i) => `scene s${i} 1 : a`).join('\n');
    rejects(tooManyScenes, /too many scenes/);
    const names = Array.from({ length: 61 }, (_, i) => `r${i}`);
    const tooManyRoles = Array.from({ length: 7 }, (_, s) => `scene s${s} 1 : ${names.slice(s * 9, s * 9 + 9).join(' ')}`).join('\n');
    rejects(tooManyRoles, /too many roles/);
  });

  it('does not accept non-text input', () => {
    assert.throws(() => parsePlay(/** @type {any} */ (42)), /must be text/);
    assert.throws(() => parsePlay(/** @type {any} */ ({ toString: () => 'scene 1 5 : a' })), /must be text/);
  });
});

describe('command line', () => {
  /** @param {string[]} argv */
  const run = (argv) => {
    let out = '';
    let err = '';
    const code = main(argv, { out: (s) => (out += s), err: (s) => (err += s) });
    return { code, out, err };
  };

  it('prints the plan and sets the exit code', () => {
    const ok = run([EXAMPLE]);
    assert.equal(ok.code, 0);
    assert.match(ok.out, /Smallest cast: 7 actors \(proven minimum\)/);
    assert.match(ok.out, /gull \+ ghost\s+12:00 spare/);
    const tight = run(['--warn', '2:30', EXAMPLE]);
    assert.equal(tight.code, 1);
    assert.match(tight.out, /inspector -> widow before scene 7: 3:30 offstage for a 1:30 change/);
    const small = run(['--actors', '6', EXAMPLE]);
    assert.equal(small.code, 1);
    assert.match(small.out, /A cast of 6 is not enough: at least 7 are needed/);
  });

  it('turns bad arguments into one clean error that never echoes them', () => {
    const work = mkdtempSync(join(tmpdir(), 'castling-'));
    try {
      const big = join(work, 'big.play');
      writeFileSync(big, '\n'.repeat(70_000));
      const binary = join(work, 'binary.play');
      writeFileSync(binary, Buffer.from([0xff, 0xfe, 0x00, 0x41]));
      const cases = [
        [], ['a', 'b'], ['--actors'], ['--actors', '0'], ['--actors', '61'], ['--actors', '1e1'], ['--warn', 'soon'],
        ['--bogus'], ['/no/such/file'], ['/'], [big], [binary], ['\u001b]0;owned\u0007$(reboot)'],
      ];
      for (const argv of cases) {
        const { code, out, err } = run(argv);
        assert.equal(code, 2, JSON.stringify(argv));
        assert.equal(out, '');
        assert.match(err, /^castling: /);
        assert.ok(!err.includes('owned') && !err.includes('reboot'));
      }
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  });

  it('runs as a program, reads standard input, and stops an endless stream', () => {
    const viaStdin = spawnSync(process.execPath, [BIN, '-'], { input: readFileSync(EXAMPLE) });
    assert.equal(viaStdin.status, 0);
    assert.match(String(viaStdin.stdout), /Plan for 7 actors/);
    const endless = spawnSync(process.execPath, [BIN, '/dev/zero'], { timeout: 10_000 });
    assert.equal(endless.status, 2);
    assert.match(String(endless.stderr), /larger than/);
  });
});
