import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { test } from "node:test";
import { fix, problems, split, warnings, MAX_LINES, type Plan, type Shape } from "../src/check.js";
import { main, readBounded } from "../src/cli.js";
import { area, dist, hull, inside, isSimple, rayHit, segmentsMeet, turn, width, type Pt } from "../src/geometry.js";
import { InputError, parse, type Settings } from "../src/parse.js";
import { analyse, escapeXml } from "../src/report.js";

const SET: Settings = { minWidth: 10, minAngle: 30, sharpCorner: 15, maxCurve: 0.3 };
const shape = (pts: [number, number][]): Shape => ({ pts: pts.map(([x, y]) => ({ x, y })), cut: pts.map(() => false) });
const P = (x: number, y: number): Pt => ({ x, y });
const EXAMPLE = resolve(import.meta.dirname, "..", "..", "examples", "sampler.txt");

const ELL = shape([[0, 0], [120, 0], [120, 40], [50, 40], [50, 110], [0, 110]]);
const TEE = shape([[0, 120], [0, 90], [45, 90], [45, 0], [75, 0], [75, 90], [120, 90], [120, 120]]);

// ---------- Geometry ----------

test("areas, turns and simple outlines", () => {
  const sq = [P(0, 0), P(10, 0), P(10, 10), P(0, 10)];
  assert.equal(area(sq), 100);
  assert.equal(area([...sq].reverse()), -100);
  assert.equal(Math.round(turn(sq, 1)), 90);
  assert.equal(Math.round(turn(ELL.pts, 3)), -90, "the L's inside corner turns right");
  assert.ok(isSimple(sq));
  assert.ok(!isSimple([P(0, 0), P(10, 10), P(10, 0), P(0, 10)]), "a bow tie crosses itself");
  assert.ok(!isSimple([P(0, 0), P(10, 0), P(10, 0), P(0, 10)]), "a repeated point");
  assert.ok(inside(sq, P(5, 5)) && !inside(sq, P(15, 5)));
  assert.ok(segmentsMeet(P(0, 0), P(10, 10), P(0, 10), P(10, 0)) && !segmentsMeet(P(0, 0), P(1, 1), P(5, 0), P(6, 1)));
});

test("hull, width and rays", () => {
  const pts = [P(0, 0), P(10, 0), P(5, 2), P(10, 10), P(0, 10)];
  assert.deepEqual([...hull(pts)].sort(), [0, 1, 3, 4]);
  assert.equal(width([P(0, 0), P(100, 0), P(100, 6), P(0, 6)]), 6);
  const hit = rayHit(ELL.pts, 3, -1, 0); // from the L's inside corner, straight on to the left
  assert.ok(hit !== null && hit.edge === 5 && Math.abs(hit.point.x) < 1e-9 && Math.abs(hit.point.y - 40) < 1e-9);
});

// ---------- What can't be cut ----------

test("problems", () => {
  assert.deepEqual(problems(shape([[0, 0], [80, 0], [80, 80], [0, 80]]), SET), [], "a square cuts as drawn");
  const ell = problems(ELL, SET);
  assert.equal(ell.length, 1);
  assert.equal(ell[0]!.kind, "corner", "the corner explains the L, with no extra curve");
  assert.equal(problems(TEE, SET).length, 2);
  const shallow = shape([[0, 0], [100, 0], [100, 50], [50, 40], [0, 50]]);
  assert.deepEqual(problems({ ...shallow }, { ...SET, sharpCorner: 30 }), [], "a shallow dip is fine");
  const deep = shape([[0, 0], [100, 0], [100, 80], [75, 30], [50, 20], [25, 30], [0, 80]]);
  const p = problems(deep, { ...SET, sharpCorner: 60 });
  assert.ok(p.length === 1 && p[0]!.kind === "curve" && p[0]!.ratio > 0.5, "a deep U-shaped curve");
});

test("warnings", () => {
  const sliver = warnings(shape([[0, 0], [100, 0], [100, 6], [0, 6]]), SET);
  assert.ok(sliver.some((w) => w.kind === "narrow"));
  const spike = warnings(shape([[0, 0], [100, 0], [0, 20]]), SET);
  assert.ok(spike.some((w) => w.kind === "point" && w.angle < 15));
});

// ---------- Fixing ----------

test("an L needs one line, the shorter one", () => {
  const plan = fix(ELL, SET) as Plan;
  assert.equal(plan.lines.length, 1);
  assert.ok(Math.abs(plan.length - 40) < 1e-6, `straight down from the corner is 40 mm, not 50 or 70 (got ${plan.length})`);
});

test("a T needs one line joining both corners", () => {
  const plan = fix(TEE, SET) as Plan;
  assert.equal(plan.lines.length, 1);
  assert.ok(Math.abs(plan.length - 30) < 1e-6);
});

test("a star needs three lines: one line can fix at most two corners", () => {
  const star = shape(Array.from({ length: 10 }, (_, k): [number, number] => {
    const r = k % 2 === 0 ? 60 : 26;
    const a = ((90 + 36 * k) * Math.PI) / 180;
    return [r * Math.cos(a), r * Math.sin(a)];
  }));
  assert.equal(problems(star, SET).filter((p) => p.kind === "corner").length, 5);
  assert.equal((fix(star, SET) as Plan).lines.length, 3);
});

/** Applies a plan's lines to a piece, independently of the search, and returns the parts. */
function applyPlan(start: Shape, plan: Plan): Shape[] {
  let parts = [start];
  const withVertex = (s: Shape, q: Pt): { s: Shape; i: number } => {
    const found = s.pts.findIndex((p) => dist(p, q) < 1e-6);
    if (found >= 0) return { s, i: found };
    for (let k = 0; k < s.pts.length; k++) {
      const a = s.pts[k]!;
      const b = s.pts[(k + 1) % s.pts.length]!;
      if (Math.abs(dist(a, q) + dist(q, b) - dist(a, b)) < 1e-6) {
        return { s: { pts: [...s.pts.slice(0, k + 1), q, ...s.pts.slice(k + 1)], cut: [...s.cut.slice(0, k + 1), false, ...s.cut.slice(k + 1)] }, i: k + 1 };
      }
    }
    throw new Error("a lead line ends off the outline");
  };
  for (const line of plan.lines) {
    const mid = P((line.a.x + line.b.x) / 2, (line.a.y + line.b.y) / 2);
    const idx = parts.findIndex((s) => inside(s.pts, mid));
    assert.ok(idx >= 0, "each line runs through one part");
    const first = withVertex(parts[idx]!, line.a);
    const second = withVertex(first.s, line.b);
    const i = second.s.pts.findIndex((p) => dist(p, line.a) < 1e-6);
    parts = [...parts.slice(0, idx), ...split(second.s, i, second.i), ...parts.slice(idx + 1)];
  }
  return parts;
}

test("on random skylines, every plan really leaves cuttable parts, with between corners/2 and corners lines", () => {
  let seed = 11;
  const rand = (): number => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  let checked = 0;
  for (let round = 0; round < 150; round++) {
    const cols = 2 + Math.floor(rand() * 4);
    const xs = [0];
    for (let c = 0; c < cols; c++) xs.push(xs[xs.length - 1]! + 20 + Math.round(rand() * 40));
    const hs = Array.from({ length: cols }, () => 20 + 10 * Math.floor(rand() * 10));
    const pts: [number, number][] = [[0, 0], [xs[cols]!, 0]];
    for (let c = cols - 1; c >= 0; c--) {
      pts.push([xs[c + 1]!, hs[c]!], [xs[c]!, hs[c]!]);
    }
    // Drop repeated points where neighbouring columns are the same height.
    const clean = pts.filter((p, i) => {
      const q = pts[(i + 1) % pts.length]!;
      const r = pts[(i + pts.length - 1) % pts.length]!;
      return !(p[0] === q[0] && p[1] === q[1]) && !((r[1] === p[1] && p[1] === q[1]) || (r[0] === p[0] && p[0] === q[0]));
    });
    const s = shape(clean);
    const corners = problems(s, SET).filter((p) => p.kind === "corner").length;
    const result = fix(s, SET);
    if (typeof result === "string") continue;
    checked++;
    assert.ok(result.lines.length >= Math.ceil(corners / 2) && result.lines.length <= corners, `round ${round}: ${result.lines.length} lines for ${corners} corners`);
    for (const part of applyPlan(s, result)) {
      assert.deepEqual(problems(part, SET), [], `round ${round}: a part still can't be cut`);
      assert.ok(width(part.pts) >= SET.minWidth - 1e-9, `round ${round}: a sliver`);
    }
  }
  assert.ok(checked > 120, `most skylines can be fixed (${checked})`);
});

test("a comb with too many teeth gives up quickly instead of searching for ever", () => {
  // Twenty 10 mm teeth with 10 mm gaps: 38 inside corners, far more than 8 lines can fix.
  const pts: [number, number][] = [[0, 0], [390, 0]];
  for (let k = 19; k >= 0; k--) {
    pts.push([20 * k + 10, 100], [20 * k, 100]);
    if (k > 0) pts.push([20 * k, 30], [20 * k - 10, 30]);
  }
  const comb = shape(pts);
  const started = Date.now();
  const result = fix(comb, SET);
  assert.ok(typeof result === "string" || result.lines.length <= MAX_LINES);
  assert.ok(Date.now() - started < 20_000, "bounded by the node budget");
});

// ---------- The design file ----------

test("rejects bad and hostile files without repeating them", () => {
  const ok = "piece a red\n0,0 50,0 50,50\n";
  const cases: [string, string][] = [
    ["", "no pieces"],
    ["0,0 1,1\n", "after a piece line"],
    ["piece a red\n0,0 50,0\n", "at least 3 points"],
    ["piece a red\n0,0 60,40 60,0 0,50\n", "crosses or touches"],
    ["piece a red\n0,0 50,0 100,0\n", "no area"],
    ["piece a red\n0,0 9000,0 0,50\n", "within 5000"],
    ["piece a red\n0,0 -5,0 0,50\n", "points are written"],
    ["piece a red\n0,0 5e3,0 0,50\n", "points are written"],
    ["piece A red\n", "lower-case"],
    ["piece a constructor\n", "colours are"],
    ["piece a __proto__\n", "colours are"],
    [ok + "piece a red\n0,0 50,0 50,50\n", "different"],
    [ok + "min-width 5\n", "before the first piece"],
    ["min-width 5\nmin-width 6\n", "only appear once"],
    ["min-width 500\n", "from 1 to 100"],
    ["max-curve NaN\n", "a number like"],
    ["window <script>SECRET</script>\n", "window's name"],
    ["window Rose\u202eSECRET\n", "invisible formatting"],
    ["window Rose\u001b[2J\n", "control"],
    ["rm -rf SECRET\n", "lines are"],
    ["# " + "x".repeat(300) + "\n", "longer than 200"],
    ["#\n".repeat(40000), "larger than 64 KB"],
    ["piece a red\n" + "1,1 ".repeat(40) + "\n" + "2,2 ".repeat(41) + "\n", "at most 80 points"],
  ];
  for (const [text, want] of cases) {
    assert.throws(
      () => parse(text),
      (e: unknown) => e instanceof InputError && e.message.includes(want) && !e.message.includes("SECRET") && !e.message.includes("<script"),
      `should reject with "${want}"`,
    );
  }
});

test("random text never crashes the parser or the report", () => {
  let seed = 3;
  const rand = (): number => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  const words = ["piece", "a", "b", "red", "0,0", "50,0", "50,50", "0,50", "25,25", "min-width", "12", "\n", "\n", "#", "window", "x"];
  for (let i = 0; i < 3000; i++) {
    const text = Array.from({ length: 1 + Math.floor(rand() * 30) }, () => words[Math.floor(rand() * words.length)]).join(" ");
    try {
      analyse(parse(text));
    } catch (e) {
      assert.ok(e instanceof InputError, `only input errors escape: ${String(e)}`);
    }
  }
});

test("the drawing escapes text", () => {
  assert.equal(escapeXml(`<a href="x">'&'</a>`), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;");
});

// ---------- The command line ----------

function run(args: string[], read?: (p: string) => string): { code: number; out: string; err: string } {
  let out = "";
  let err = "";
  const code = main(args, (s) => (out += s), (s) => (err += s), read);
  return { code, out, err };
}

test("the example", () => {
  const r = run([EXAMPLE]);
  assert.equal(r.code, 1);
  assert.match(r.out, /In all: 4 cut as drawn, 4 need lead lines \(6 lines, 186\.8 mm of extra lead\), 0 can't be fixed automatically\./);
  const drawing = run(["--svg", EXAMPLE]);
  assert.ok(drawing.out.startsWith("<svg") && drawing.out.includes("stroke-dasharray") && !drawing.out.includes("<script"));
  const text = readFileSync(EXAMPLE, "utf8");
  assert.equal(run(["-"], () => text).out, r.out, "standard input gives the same report");
});

test("files are read safely", () => {
  const dir = mkdtempSync(join(tmpdir(), "grozer-"));
  try {
    const link = join(dir, "link.txt");
    symlinkSync(EXAMPLE, link);
    assert.equal(run([link]).code, 2, "a symbolic link is refused");
    const folder = run([dir]);
    assert.ok(folder.code === 2 && folder.err.includes("regular file"), "a folder is refused");
    const missing = run([join(dir, "secret-name-zz.txt")]);
    assert.ok(missing.code === 2 && !missing.err.includes("secret-name"), "the path is never echoed");
  } finally {
    rmSync(dir, { recursive: true });
  }
  assert.equal(run([]).code, 2);
  assert.equal(run(["a", "b"]).code, 2);
  assert.equal(run(["--json", "x"]).code, 2);
  assert.ok(typeof readBounded === "function");
});
