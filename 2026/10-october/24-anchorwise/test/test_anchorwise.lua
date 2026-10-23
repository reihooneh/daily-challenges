-- Tests for Anchorwise. Run from the project folder:  lua test/test_anchorwise.lua
ANCHORWISE_TESTING = true
package.path = "./?.lua;" .. package.path

-- Strict globals: reading or writing an undeclared global anywhere is an error (a cheap linter).
setmetatable(_G, {
  __newindex = function(_, k) error("assignment to undeclared global '" .. tostring(k) .. "'", 2) end,
  __index = function(_, k) error("read of undeclared global '" .. tostring(k) .. "'", 2) end,
})

local V = require("anchorwise.vec")
local Parse = require("anchorwise.parse")
local Fixed = require("anchorwise.fixed")
local Sliding = require("anchorwise.sliding")
local Analyse = require("anchorwise.analyse")
local Main = require("anchorwise")

local checks, failed = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    failed = failed + 1
    print("FAIL: " .. what)
  end
end
local function near(a, b, tol, what) check(math.abs(a - b) <= tol, string.format("%s (%.6g vs %.6g)", what, a, b)) end

local function rejects(text, fragment)
  local ok, e = pcall(Parse.parse, text)
  check(not ok and type(e) == "table" and e.input and e.input:find(fragment, 1, true) ~= nil,
    "should reject with '" .. fragment .. "' (got " .. tostring(ok and "success" or (type(e) == "table" and e.input or e)) .. ")")
end

-- Net force on the master point for a solved fixed anchor: must be (nearly) zero.
local function balance(anchor, r)
  local f = V.scale(anchor.dir, anchor.load)
  for i, p in ipairs(anchor.pieces) do
    f = V.add(f, V.scale(V.unit(V.sub(p.pos, r.master)), r.forces[i]))
  end
  return V.len(f)
end

local TWO = [[
anchor Test
load 2 kN
rigging fixed nylon
master 0 -0.5
piece A -0.3 0
piece B 0.3 0
]]

-- ---------- vectors ----------
local x = V.solve2(2, 1, 1, 3, { 5, 10 })
near(x[1], 1, 1e-12, "solve2 x")
near(x[2], 3, 1e-12, "solve2 y")
check(V.solve2(1, 2, 2, 4, { 1, 1 }) == nil, "singular systems are reported")
near(V.angle({ 1, 0 }, { 0, 1 }), 90, 1e-12, "right angle")

-- ---------- fixed rigging ----------
do
  local a = Parse.parse(TWO)
  local r = Analyse.run(a)
  near(r.forces[1], r.forces[2], 1e-9, "symmetric arms share equally")
  near(balance(a, r), 0, 1e-8, "forces balance the load")
  -- Textbook: T = W / (2 cos(half angle)), using the settled geometry.
  local half = math.rad(V.angle(V.sub(a.pieces[1].pos, r.master), V.sub(a.pieces[2].pos, r.master)) / 2)
  near(r.forces[1], 2 / (2 * math.cos(half)), 1e-6, "the two-leg formula")
  near(r.master[1], 0, 1e-9, "the master point stays centred")
  check(r.master[2] < -0.5, "the master point moves down as the arms stretch")

  -- An arm tied 3 mm long comes tight late, so it takes less than its share (but not nothing).
  local b = Parse.parse((TWO:gsub("piece B 0.3 0", "piece B 0.3 0 slack 0.003")))
  local rb = Analyse.run(b)
  check(rb.forces[2] < rb.forces[1] and rb.forces[2] > 0, "a slightly long arm takes less")
  near(balance(b, rb), 0, 1e-8, "uneven arms still balance")
  -- Same geometry, but one arm three times as long (pieces higher up on one side): it's softer.
  local tall = Parse.parse("load 2 kN\nrigging fixed nylon\nmaster 0 -0.3\npiece Near -0.2 0\npiece Far 0.6 0.6\n")
  local rt = Analyse.run(tall)
  near(balance(tall, rt), 0, 1e-8, "different arm lengths balance")

  -- Slack: tied 40 cm long, the arm never comes tight, even after the master point swings.
  local c = Parse.parse((TWO:gsub("piece B 0.3 0", "piece B 0.3 0 slack 0.4")))
  local rc = Analyse.run(c)
  near(rc.forces[2], 0, 1e-12, "a slack arm carries nothing")
  near(rc.forces[1], 2, 1e-6, "so the other carries everything")

  -- One bolt fails: the master point swings under the other and drops.
  local f = r.failures[1]
  check(f.drop > 0.04 and f.drop < 0.1, "a failed bolt drops the master point a few centimetres")
  near(f.forces[2], 2, 1e-6, "the remaining arm then holds the whole load")
  check(f.peak > 2 * 2, "and the jolt is more than twice the load")
end

-- ---------- sliding rigging ----------
do
  local a = Parse.parse("load 3 kN\nrigging sliding dyneema\nsling 1.4\npiece A -0.4 0\npiece B 0.4 0\n")
  local r = Analyse.run(a)
  near(r.master[1], 0, 1e-6, "sliding: hangs below the middle")
  near(r.forces[1], r.forces[2], 1e-12, "sliding: the same tension in every arm")
  near(balance(a, r), 0, 1e-6, "sliding: forces balance")
  -- The sling forms two equal arms of 0.7 m: depth sqrt(0.7^2 - 0.4^2).
  near(r.master[2], -math.sqrt(0.49 - 0.16), 1e-6, "sliding: geometry of the loop")
  local tilted = Parse.parse("load 3 kN at 20\nrigging sliding dyneema\nsling 1.4\npiece A -0.4 0\npiece B 0.4 0\n")
  local rt = Analyse.run(tilted)
  check(rt.master[1] > 0.05, "sliding: the master point follows a load from the right")
  near(balance(tilted, rt), 0, 1e-6, "sliding: tilted load still balances")
  local ok, e = pcall(Analyse.run, Parse.parse("load 3 kN\nrigging sliding nylon\nsling 0.5\npiece A -0.4 0\npiece B 0.4 0\n"))
  check(not ok and e.input:find("too short", 1, true), "a sling too short to reach is reported")
  -- Limiter knots catch the drop.
  local lim = Analyse.run(Parse.parse("load 3 kN\nrigging sliding dyneema\nsling 1.4\nlimit 0.05\npiece A -0.4 0\npiece B 0.4 0\n"))
  check(lim.failures[1].caught and math.abs(lim.failures[1].drop - 0.05) < 1e-12, "limiter knot caps the drop")
  check(lim.failures[1].peak < r.failures[1].peak, "and so the jolt is smaller")
  -- Three pieces: still equal tension, and the anchor survives any one failure.
  local three = Analyse.run(Parse.parse("load 2 kN\nrigging sliding nylon\nsling 2\npiece A -0.4 0\npiece B 0 0.1\npiece C 0.4 0\n"))
  for j = 1, 3 do check(not three.failures[j].gone, "three-piece anchor survives losing piece " .. j) end
end

-- ---------- the jolt formula ----------
near(Analyse.peak(2, 100, 0), 2, 0, "no drop, no jolt")
near(Analyse.peak(2, 100, 1e-12), 4, 1e-6, "a weight released onto a slack system: twice its weight")
check(Analyse.peak(2, 100, 0.1) > Analyse.peak(2, 100, 0.05), "a longer drop is a bigger jolt")
check(Analyse.peak(2, 200, 0.1) > Analyse.peak(2, 100, 0.1), "a stiffer system is a bigger jolt")

-- ---------- the file ----------
rejects(TWO:gsub("load 2 kN\n", ""), "needs a load line")
rejects(TWO:gsub("master 0 %-0.5\n", ""), "needs a master line")
rejects(TWO:gsub("piece B 0.3 0\n", ""), "at least two pieces")
rejects(TWO:gsub("piece B 0.3 0", "piece B -0.3 0"), "same place")
rejects(TWO:gsub("rigging fixed nylon", "rigging fixed steel"), "rigging is")
rejects(TWO:gsub("load 2 kN", "load 99 kN"), "between 0.1 and 25")
rejects(TWO:gsub("load 2 kN", "load 2 kN at 90"), "load angle")
rejects(TWO:gsub("load 2 kN", "load 1e1 kN"), "plain number")
rejects(TWO:gsub("piece A", "piece <b>A"), "piece names")
rejects(TWO .. "sling 2\n", "sling is for sliding")
rejects(TWO .. "limit 0.1\n", "limiter knots are for sliding")
rejects(TWO:gsub("piece A %-0.3 0", "piece A -0.3 0 slack 9"), "slack must be between")
rejects("load 3 kN\nrigging sliding dyneema\npiece A -0.4 0\npiece B 0.4 0\n", "needs a sling line")
rejects("load 3 kN\nrigging sliding dyneema\nsling 1\npiece A -0.4 0 slack 0.1\npiece B 0.4 0\n", "slack is for fixed")
rejects(TWO .. "hello\n", "lines start with")
rejects(TWO .. "anchor bad\27[2J\n", "control or hidden")
rejects(TWO .. "anchor right\226\128\174left\n", "control or hidden")
rejects(TWO .. "anchor " .. string.rep("x", 200) .. "\n", "longer than")
rejects(string.rep("#", 20000), "larger than 16 KB")
rejects("anchor \255\254\n", "not valid UTF-8")
local many = TWO
for i = 1, 6 do many = many .. "piece P" .. i .. " " .. i .. " 1\n" end
rejects(many, "more than 6 pieces")
check(Parse.parse(TWO .. "piece Big flake 0 0.4 slack 0.01\n").pieces[3].name == "Big flake", "multi-word piece names")

-- ---------- the command line ----------
local function stdin(text)
  return { read = function(_, n) return text:sub(1, n) end }
end
local code, out = Main.run({ "examples/two-bolts.txt" }, nil)
check(code == 1 and out:find("ANCHORWISE  Two bolts", 1, true), "an example runs (with its shock-load warning)")
local code2, out2 = Main.run({ "-" }, stdin(io.open("examples/two-bolts.txt"):read("a")))
check(code2 == code and out2 == out, "standard input works the same")
check(Main.run({}, nil) == 2 and Main.run({ "--help" }, nil) == 2, "usage errors exit 2")
local c3, _, e3 = Main.run({ "examples" }, nil)
check(c3 == 2 and e3:find("could not be read", 1, true), "a folder is refused")
local c4, _, e4 = Main.run({ "-" }, stdin(string.rep("#", 20000)))
check(c4 == 2 and e4:find("larger than 16 KB", 1, true), "an endless stream is cut off")
local c5, _, e5 = Main.run({ "no-such-file.txt" }, nil)
check(c5 == 2 and e5:find("could not be read", 1, true) and not e5:find("no-such", 1, true), "errors don't echo the path")
local c6, out6 = Main.run({ "-" }, stdin("\239\187\191" .. TWO))
check(c6 <= 1 and out6:find("ANCHORWISE", 1, true), "a byte-order mark is ignored")
for _, f in ipairs({ "examples/three-uneven.txt", "examples/wide-sliding.txt" }) do
  local c, o = Main.run({ f }, nil)
  check(c == 1 and o:find("If one piece fails", 1, true), f .. " runs")
end

print(string.format("%d checks, %d failed", checks, failed))
os.exit(failed == 0 and 0 or 1)
