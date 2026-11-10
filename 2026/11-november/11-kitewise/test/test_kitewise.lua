-- Tests for Kitewise. Run with Lua 5.4:  lua test/test_kitewise.lua
local dir = (arg and arg[0] or ""):match("^(.*)[/\\]test[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path
KITEWISE_TEST = true
local before = {}
for k in pairs(_G) do before[k] = true end

local Parse = require("kitewise.parse")
local Check = require("kitewise.check")
local Fix = require("kitewise.fix")
local Main = dofile(dir .. "/kitewise.lua")

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end
local function near(a, b, tol, what) assert(math.abs(a - b) <= (tol or 1e-9), (what or "") .. ": " .. a .. " vs " .. b) end

local function read(path)
  local f = assert(io.open(dir .. "/" .. path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local function positions(course)
  local pos = {}
  for code, c in pairs(course.controls) do pos[code] = { x = c.x, y = c.y } end
  return pos
end

local function kinds(issues)
  local out = {}
  for _, i in ipairs(issues) do out[i.kind] = (out[i.kind] or 0) + 1 end
  return out
end

test("reads the example course", function()
  local c = Parse.parse(read("examples/park-sprint.txt"))
  assert(c.title == "Riverside Park sprint, course B")
  assert(c.sprint)
  assert(#c.order == 9)
  assert(c.controls["32"].feature == "path junction")
  assert(c.controls["33"].move == 20)
end)

test("bad courses are refused without repeating them", function()
  local base = "control S at 0 0 start\ncontrol 31 at 100 0\ncontrol F at 200 0 finish\n"
  local cases = {
    { base .. "course S 31 F\nbanana", "unknown line" },
    { base .. "control 31 at 5 5\ncourse S 31 F", "already defined" },
    { base .. "course S 32 F", "not defined" },
    { base .. "course S 31 31 F", "follows itself" },
    { base .. "course S F", "at least 3" },
    { base, "no course" },
    { base .. "course S 31 F\ncourse S 31 F", "only one course" },
    { "control S at 0\ncourse S S S", "must be a number" },
    { "control S at 0 0 colour red\n", "unexpected word" },
    { "control <img> at 0 0\n", "control code" },
    { "control S at 99999 0\n", "between" },
    { "title <script>alert(1)</script>\n" .. base .. "course S 31 F", "a title is" },
    { "title a\7b\n" .. base .. "course S 31 F", "control" },
    { "title abc\226\128\174def\n" .. base .. "course S 31 F", "invisible" },
    { "title \255\254\n", "UTF-8" },
    { string.rep("x", 40000), "larger than 32 KB" },
    { base .. "control 32 at 1 1 feature Big Rock\ncourse S 31 F", "feature" },
  }
  for k, case in ipairs(cases) do
    local ok, err = pcall(Parse.parse, case[1])
    assert(not ok, "case " .. k .. " was accepted")
    assert(type(err) == "table" and err.input, "case " .. k .. ": not an input error")
    assert(err.input:find(case[2], 1, true), "case " .. k .. ": " .. err.input)
    assert(not err.input:find("script", 1, true) and not err.input:find("<img", 1, true) and not err.input:find("banana", 1, true))
  end
end)

test("angles and dog-leg lengths have the right geometry", function()
  local c = { x = 0, y = 0 }
  near(Check.angle({ x = 100, y = 0 }, c, { x = 0, y = 100 }), 90, 1e-9, "right angle")
  near(Check.angle({ x = 100, y = 0 }, c, { x = 100, y = 0 }), 0, 1e-9, "straight back")
  -- Straight back out along the same line: in sight the whole way, minus the first 30 m.
  near(Check.doglegLength({ x = 100, y = 0 }, c, { x = 200, y = 0 }, 30), 70, 1e-9, "straight back")
  -- At 60° runners the same distance out are exactly that distance apart: never more than 30 m.
  near(Check.doglegLength({ x = 100, y = 0 }, c, { x = 50, y = 50 * math.sqrt(3) }, 30), 0, 1e-6, "60 degrees")
  -- At 20° they are 2 d sin 10° apart: within 30 m until d = 86.4 m, 56.4 m beyond the first 30.
  local a = { x = 200, y = 0 }
  local b = { x = 200 * math.cos(math.rad(20)), y = 200 * math.sin(math.rad(20)) }
  near(Check.doglegLength(a, c, b, 30), 30 / (2 * math.sin(math.rad(10))) - 30, 1e-6, "20 degrees")
  assert(Check.crosses({ x = 0, y = 0 }, { x = 10, y = 10 }, { x = 0, y = 10 }, { x = 10, y = 0 }))
  assert(not Check.crosses({ x = 0, y = 0 }, { x = 10, y = 0 }, { x = 0, y = 5 }, { x = 10, y = 5 }))
  near(Check.toSegment({ x = 5, y = 7 }, { x = 0, y = 0 }, { x = 10, y = 0 }), 7, 1e-9, "point to segment")
end)

test("finds each kind of problem", function()
  local course = Parse.parse([[
control S at 0 0 start
control 1 at 200 0 feature boulder
control 2 at 20 10 feature boulder
control 3 at 40 30 feature boulder
control 4 at 300 300 feature knoll
control 5 at 300 -100 feature knoll
control F at 100 250 finish
course S 1 2 3 4 5 F
]])
  local issues = Check.problems(course, positions(course))
  local k = kinds(issues)
  assert(k.dogleg and k.dogleg >= 1, "the 1 -> 2 dog-leg")
  local pair = false
  for _, i in ipairs(issues) do
    if i.kind == "tooClose" and i.a == "2" and i.b == "3" then pair = true; near(i.metres, math.sqrt(800), 1e-9, "2 to 3") end
  end
  assert(pair, "2 and 3 are 28 m apart")
  assert(k.passBy and k.passBy >= 1, "S -> 1 passes 2")
  assert(k.crossing and k.crossing >= 1, "3 -> 4 crosses 5 -> F?")
  local clean = Parse.parse(read("examples/forest-clean.txt"))
  assert(#Check.problems(clean, positions(clean)) == 0)
end)

test("the example's problems and the fixer's moves", function()
  local course = Parse.parse(read("examples/park-sprint.txt"))
  local issues, before = Check.problems(course, positions(course))
  local k = kinds(issues)
  assert(k.dogleg == 2 and k.sameFeature == 1 and k.passBy == 2 and k.crossing == 1)
  local pos, b, after = Fix.fix(course)
  near(b, before, 1e-9, "before")
  assert(after < before / 5, "the moves clear most of it: " .. after)
  for code, c in pairs(course.controls) do
    local d = math.sqrt((pos[code].x - c.x) ^ 2 + (pos[code].y - c.y) ^ 2)
    assert(d <= c.move + 1e-9, code .. " moved further than allowed")
    assert((pos[code].x - c.x) % Fix.STEP == 0 and (pos[code].y - c.y) % Fix.STEP == 0, "off the 5 m grid")
  end
end)

-- Small random courses: the fixer never makes things worse, its exhaustive search really is the
-- best of every combination, and the one-at-a-time search never beats it.
test("the fixer is exact when it says so", function()
  math.randomseed(11)
  local saved = Fix.EXHAUSTIVE
  for t = 1, 40 do
    local lines = { "control S at 0 0 start" }
    local order = { "S" }
    for i = 1, 5 do
      local mv = (i == 2 or i == 4) and " move 10" or ""
      lines[#lines + 1] = string.format("control %d at %d %d feature %s%s", i, math.random(-150, 150), math.random(-150, 150), ({ "boulder", "knoll", "pit" })[math.random(3)], mv)
      order[#order + 1] = tostring(i)
    end
    lines[#lines + 1] = "control F at 10 10 finish"
    order[#order + 1] = "F"
    lines[#lines + 1] = "course " .. table.concat(order, " ")
    local course = Parse.parse(table.concat(lines, "\n"))
    Fix.EXHAUSTIVE = saved
    local _, before, best, exhaustive = Fix.fix(course)
    assert(exhaustive, "two controls within 10 m should be tried exhaustively")
    assert(best <= before + 1e-9, "course " .. t .. " got worse")
    -- Brute force by hand.
    local c2, c4 = course.controls["2"], course.controls["4"]
    local brute = math.huge
    local pos = positions(course)
    for _, a in ipairs(Fix.candidates(c2)) do
      for _, b in ipairs(Fix.candidates(c4)) do
        pos["2"], pos["4"] = { x = a.x, y = a.y }, { x = b.x, y = b.y }
        local _, cost = Check.problems(course, pos)
        brute = math.min(brute, cost)
      end
    end
    near(best, brute, 1e-6, "course " .. t)
    Fix.EXHAUSTIVE = 0
    local _, _, greedy, ex2 = Fix.fix(course)
    assert(not ex2 and greedy >= brute - 1e-6)
  end
  Fix.EXHAUSTIVE = saved
end)

test("command line: exit codes, help, and broken input", function()
  local code, out = Main.main({ dir .. "/examples/park-sprint.txt" })
  assert(code == 3 and out:find("Suggested moves", 1, true))
  code = Main.main({ dir .. "/examples/forest-clean.txt" })
  assert(code == 0)
  code, out = Main.main({ "--help" })
  assert(code == 0 and out:find("usage", 1, true))
  assert(Main.main({}) == 2)
  local cases = { { dir .. "/examples" }, { dir .. "/no-such-file.txt" } }
  for _, args in ipairs(cases) do
    local c, o, e = Main.main(args)
    assert(c == 1 and o == "" and e:find("could not be read", 1, true), e)
  end
  local fake = { read = function() return "password hunter2\n" end }
  local c, o, e = Main.main({ "-" }, fake)
  assert(c == 1 and o == "" and not e:find("hunter2", 1, true), e)
  local huge = { read = function(_, n) return string.rep("x", n) end }
  local _
  c, _, e = Main.main({ "-" }, huge)
  assert(c == 1 and e:find("larger than 32 KB", 1, true))
end)

-- A lint check: no module or test may leak a global variable (a misspelt local, say).
test("no global variables leak", function()
  for k in pairs(_G) do
    assert(before[k], "global leaked: " .. tostring(k))
  end
end)

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
