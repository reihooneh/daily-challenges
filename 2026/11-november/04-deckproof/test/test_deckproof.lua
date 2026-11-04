-- Tests for Deckproof. Run from the project folder:  lua test/test_deckproof.lua
DECKPROOF_TESTING = true
package.path = "./?.lua;" .. package.path

-- Strict globals: reading or writing an undeclared global anywhere is an error (a cheap linter).
setmetatable(_G, {
  __newindex = function(_, k) error("assignment to undeclared global '" .. tostring(k) .. "'", 2) end,
  __index = function(_, k) error("read of undeclared global '" .. tostring(k) .. "'", 2) end,
})

local Parse = require("deckproof.parse")
local Run = require("deckproof.run")
local Main = require("deckproof")

local checks, failed = 0, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    failed = failed + 1
    print("FAIL: " .. what)
  end
end

local function deck(n)
  local d = {}
  for i = 1, n do d[i] = i end
  return d
end

local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function result(text) return Run.run(Parse.parse(text)) end

local function rejects(text, fragment)
  local ok, e = pcall(Parse.parse, text)
  local msg = (not ok and type(e) == "table" and e.input) or ""
  check(not ok and msg:find(fragment, 1, true) ~= nil, "should reject with '" .. fragment .. "' (got " .. tostring(ok and "success" or msg) .. ")")
  check(not msg:find("SECRET", 1, true), "never echoes the input")
end

-- ---------- Shuffles ----------
check(same(Run.cut(deck(5), 2), { 3, 4, 5, 1, 2 }), "cut moves the top cards to the bottom")
check(same(Run.cut(deck(5), 0), deck(5)), "a cut of nothing")
check(same(Run.faro(deck(6), true), { 1, 4, 2, 5, 3, 6 }), "out-faro keeps the top card on top")
check(same(Run.faro(deck(6), false), { 4, 1, 5, 2, 6, 3 }), "in-faro moves it second")

-- The order of the perfect shuffles: 8 out-faros restore 52 cards; in-faros need 52 (2 has order 52 mod 53).
local function order(n, out)
  local d = Run.faro(deck(n), out)
  local k = 1
  while not same(d, deck(n)) do
    d = Run.faro(d, out)
    k = k + 1
  end
  return k
end
check(order(52, true) == 8, "8 out-faros for 52 cards")
check(order(52, false) == 52, "52 in-faros for 52 cards")
check(order(10, true) == 6 and order(32, true) == 5, "out-faro orders for 10 and 32 cards")

local p = Run.piles(deck(7), 3, false)
check(same(p[1], { 7, 4, 1 }) and same(p[2], { 5, 2 }) and same(p[3], { 6, 3 }), "face-down piles reverse")
local q = Run.piles(deck(7), 3, true)
check(same(q[1], { 1, 4, 7 }), "face-up piles keep order")
check(same(Run.gather(p, 3, "top"), { 6, 3, 7, 4, 1, 5, 2 }), "gather with the picked pile on top")
check(same(Run.gather(p, 1, "middle"), { 5, 2, 7, 4, 1, 6, 3 }), "gather with the picked pile in the middle")
check(same(Run.gather(p, nil, nil), { 7, 4, 1, 5, 2, 6, 3 }), "gather in pile order")

-- ---------- Tricks ----------
local r = result("deck 21\nchoose card X\nrepeat 3\npiles 3\npick X\ngather middle\nend\nexpect X at 11\n")
check(r.cases == 21 and r.passed == 21, "the 21-card trick always works")
-- The same trick with 27 cards lands on 14 (the middle), with face-up columns too.
r = result("deck 27\nchoose card X\nrepeat 3\npiles 3 faceup\npick X\ngather middle\nend\nexpect X at 14\n")
check(r.cases == 27 and r.passed == 27, "27 cards, face up: always 14th")
-- But two rounds aren't enough with 21 cards.
r = result("deck 21\nchoose card X\nrepeat 2\npiles 3\npick X\ngather middle\nend\nexpect X at 11\n")
check(r.passed < r.cases and #r.failures == 3, "two rounds sometimes fail, and failures are shown")
local total = 0
for _, c in pairs(r.ends) do total = total + c end
check(total == r.cases, "the end positions add up to the cases")

r = result("deck 52\nrepeat 8\nfaro out\nend\nexpect original\n")
check(r.cases == 1 and r.passed == 1, "8 out-faros restore the deck")
r = result("deck 52\nrepeat 7\nfaro out\nend\nexpect original\n")
check(r.passed == 0, "7 don't")

-- Free cuts branch over every cut; a cut never changes the cyclic order, so a cut and then
-- reversing the cut puts any card back.
r = result("deck 10\nchoose card X\nchoose number k 0..9\ncut k\ncut any\nexpect X at 1\n")
check(r.cases == 10 * 10 * 10, "choices multiply: 10 cards x 10 numbers x 10 cuts")
check(r.passed == 100, "exactly one cut in ten brings X to the top (" .. r.passed .. ")")

-- Dealing and dealing under.
r = result("deck 10\nchoose card X\ndeal 10\nexpect X at 1\n")
check(r.passed == 1, "dealing the whole deck reverses it: only the bottom card ends on top")
r = result("deck 10\nchoose number k 0..10\nchoose card X\ndeal-under k\ndeal-under k\nexpect original\n")
check(r.cases == 11 * 10, "deal-under cases")
r = result("deck 5\nfaro out\nexpect original\n")
check(r.passed == 0 and r.failures[1].reason:find("even number", 1, true), "an odd perfect shuffle is a failed case")
r = result("deck 6\nchoose card X\npiles 2\nexpect X on top\n")
check(r.passed == 0 and r.failures[1].reason:find("never gathered", 1, true), "piles left on the table")

-- The case limit stops a file that asks for too much.
local saved = Run.MAX_CASES
Run.MAX_CASES = 500
r = result("deck 52\ncut any\ncut any\nexpect original\n")
check(r.limit and r.cases == 500, "the case limit is enforced")
Run.MAX_CASES = saved

-- ---------- Hostile and broken files ----------
rejects("", "'deck' line")
rejects("deck 21\n", "at least one 'expect'")
rejects("choose card X\ndeck 21\n", "how many cards first")
rejects("deck 200\nexpect original\n", "from 2 to 104")
rejects("deck 21\nexpect Y at 3\n", "names no chosen card")
rejects("deck 21\nchoose card X\nchoose card X\nexpect X at 1\n", "new short name")
rejects("deck 21\nchoose number k 9..2\nexpect original\n", "smallest number comes first")
rejects("deck 21\ncut q\nexpect original\n", "a count is a number")
rejects("deck 6\ndeal 7\nexpect original\n", "from 0 to 6")
rejects("deck 21\nrepeat 3\nexpect original\n", "has no 'end'")
rejects("deck 21\nend\nexpect original\n", "without a 'repeat'")
rejects("deck 21\nrepeat 200\nrepeat 200\nreverse\nend\nend\nexpect original\n", "more than 2000 steps")
rejects("deck 21\nrepeat 2\nrepeat 2\nrepeat 2\nrepeat 2\nrepeat 2\nreverse\nend\nend\nend\nend\nend\nexpect original\n", "nest at most")
rejects("trick Card\226\128\174SECRET\ndeck 21\nexpect original\n", "invisible formatting")
rejects("trick A\27[2J\ndeck 21\nexpect original\n", "control")
rejects("deck 21\nos.execute SECRET\n", "lines are trick")
rejects("trick <script>\ndeck 21\nexpect original\n", "trick's name")
rejects("deck 21\n# " .. string.rep("x", 300) .. "\nexpect original\n", "longer than 200")
rejects(string.rep("#\n", 9000), "larger than 16 KB")
rejects("deck 21\n\255\nexpect original\n", "UTF-8")

-- ---------- The command line ----------
local function stdin(text)
  return { read = function() return text end }
end
local code, out = Main.run({ "examples/twenty-one.txt" }, stdin(""))
check(code == 0 and out:find("always ends 11th", 1, true), "example: works every time")
local f = assert(io.open("examples/twenty-one.txt", "rb"))
local text = f:read("a")
f:close()
local code2, out2 = Main.run({ "-" }, stdin(text))
check(code2 == 0 and out2 == out, "standard input gives the same report")
code = Main.run({ "examples/two-piles.txt" }, stdin(""))
check(code == 1, "a failing trick exits 1")
local c3, _, e3 = Main.run({ "test" }, stdin(""))
check(c3 == 2 and e3:find("could not be read", 1, true), "a folder is refused")
local c4, _, e4 = Main.run({ "secret-name-zz.txt" }, stdin(""))
check(c4 == 2 and not e4:find("secret-name", 1, true), "the path isn't echoed")
local c5, _, e5 = Main.run({ "-" }, stdin(string.rep("#", 100000)))
check(c5 == 2 and e5:find("16 KB", 1, true), "big input refused")
check(Main.run({}, stdin("")) == 2 and Main.run({ "a", "b" }, stdin("")) == 2, "usage")

print(checks .. " checks, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
