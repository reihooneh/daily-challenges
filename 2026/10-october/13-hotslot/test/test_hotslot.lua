-- Tests for Hotslot. Run from the project folder:  lua test/test_hotslot.lua
HOTSLOT_TESTING = true
package.path = "./?.lua;" .. package.path

local Menu = require("hotslot.menu")
local Plan = require("hotslot.plan")
local Report = require("hotslot.report")
local Cli = require("hotslot")

local checks, failures = 0, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("  failed: " .. label .. "  (" .. debug.traceback("", 2):match("test_hotslot.lua:(%d+)") .. ")")
  end
end

local function rejects(text, message)
  local ok, e = pcall(Menu.parse, text)
  check(not ok and type(e) == "table" and e.input:find(message, 1, true) ~= nil, "rejects: " .. message)
  return ok and "" or e.input
end

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

local EXAMPLE = readFile("examples/christmas.txt")
local ROOM = Menu.ROOM

-- Independent checker: does a solved plan obey every rule?
local function obeys(menu, r)
  local p = r.prepared
  local used = {}
  for k = 0, r.horizon - 1 do used[k] = 0 end
  -- Temperatures start cold and change no faster than the oven can manage.
  local prev = ROOM
  for k = 0, r.last do -- after the last dish the oven is simply off
    local t = r.temps[k]
    if t > prev + p.up or t < prev - p.down or t < ROOM then return false, "ramp at slot " .. k end
    prev = t
  end
  for _, item in ipairs(r.items) do
    local d = item.dish
    if item.start < 1 then return false, "starts too early" end
    for k = item.start - 1, item.finish - 1 do
      local t = r.temps[k]
      if t < d.temp - d.tolerance or t > d.temp + d.tolerance then return false, d.name .. " too hot or cold" end
    end
    for k = item.start, item.finish - 1 do used[k] = used[k] + d.shelves end
    if (item.finish - item.start) * Plan.SLOT < d.cook then return false, d.name .. " undercooked" end
    local restSlots = (d.rest + Plan.SLOT - 1) // Plan.SLOT
    if item.wait < restSlots * Plan.SLOT or item.wait > (restSlots + d.hold // Plan.SLOT) * Plan.SLOT then
      return false, d.name .. " waits the wrong time"
    end
  end
  for k = 0, r.horizon - 1 do
    if used[k] > menu.shelves then return false, "too many shelves" end
  end
  return true
end

-- Brute force: every combination of finishing times, with the oven checked by dynamic
-- programming over every temperature in steps of 5. Returns the least waiting, or nil.
local function brute(menu)
  local p = Plan.solve(menu, nil, 1).prepared -- just for the horizon and options
  local H = p.horizon
  local temps = {}
  for t = ROOM, Plan.MAX_TEMP, 5 do temps[#temps + 1] = t end
  local best
  local choice = {}
  local function feasible()
    local lo, hi, used = {}, {}, {}
    for k = 0, H - 1 do lo[k], hi[k], used[k] = ROOM, Plan.MAX_TEMP, 0 end
    for i, s in ipairs(p.dishes) do
      local e = choice[i]
      local start = e - s.cook
      if start < 1 then return false end
      for k = start - 1, e - 1 do
        lo[k] = math.max(lo[k], s.lo)
        hi[k] = math.min(hi[k], s.hi)
      end
      for k = start, e - 1 do used[k] = used[k] + s.dish.shelves end
    end
    for k = 0, H - 1 do
      if used[k] > p.shelves then return false end
    end
    local can = {}
    for j, t in ipairs(temps) do can[j] = (t == ROOM) end
    for k = 0, H - 1 do
      local nextCan = {}
      local any = false
      for j, t in ipairs(temps) do
        local ok = false
        if t >= lo[k] and t <= hi[k] then
          for i2, s in ipairs(temps) do
            if can[i2] and t <= s + p.up and t >= s - p.down then ok = true break end
          end
        end
        nextCan[j] = ok
        any = any or ok
      end
      if not any then return false end
      can = nextCan
    end
    return true
  end
  local function go(i, stale)
    if i > #p.dishes then
      if (not best or stale < best) and feasible() then best = stale end
      return
    end
    local s = p.dishes[i]
    for _, e in ipairs(s.options) do
      choice[i] = e
      go(i + 1, stale + (H - e - s.rest) * Plan.SLOT)
    end
  end
  go(1, 0)
  return best
end

local function randomMenu(rng)
  local lines = { "serve 18:30", "oven " .. rng(1, 2) .. " shelves", "heats " .. rng(5, 15) .. " per min",
    "cools " .. rng(2, 6) .. " per min" }
  for i = 1, rng(1, 3) do
    lines[#lines + 1] = string.format("dish D%d: %dC +-%d, %d min, rest %d, hold %d", i, rng(10, 46) * 5,
      rng(0, 4) * 5, rng(1, 8) * 5, rng(0, 2) * 5, rng(0, 3) * 5)
  end
  return Menu.parse(table.concat(lines, "\n"))
end

-- A small seeded generator, so runs are repeatable on every Lua version.
local function generator(seed)
  local state = seed
  return function(a, b)
    state = (state * 1103515245 + 12345) % 2147483648
    return a + state % (b - a + 1)
  end
end

local tests = {}

function tests.parse_the_example()
  local m = Menu.parse(EXAMPLE)
  check(m.serve == 13 * 60, "serve time")
  check(m.shelves == 3 and m.heats == 15 and m.cools == 5, "oven settings")
  check(#m.dishes == 5, "five dishes")
  local lamb = m.dishes[1]
  check(lamb.name == "Roast lamb" and lamb.temp == 180 and lamb.tolerance == 10 and lamb.cook == 90, "lamb")
  check(lamb.rest == 20 and lamb.hold == 15 and lamb.shelves == 1, "lamb timings")
  -- The plus-minus and degree signs are accepted, and Windows line endings.
  local m2 = Menu.parse("serve 6:05\r\ndish Bread: 220\194\176C \194\177 5, 30 min, shelves 2\r\n")
  check(m2.serve == 365 and m2.dishes[1].tolerance == 5 and m2.dishes[1].shelves == 2, "unicode signs")
end

function tests.hostile_and_bad_menus()
  rejects("dish A: 180C, 20 min\n", "needs a line like 'serve")
  rejects("serve 18:30\n", "no dishes")
  rejects("serve 25:00\ndish A: 180C, 20 min\n", "serve time must look like")
  rejects("serve 18:30\nbake A\n", "start the line with")
  rejects("serve 18:30\ndish A 180C 20 min\n", "write a dish as")
  rejects("serve 18:30\ndish A: hot, 20 min\n", "temperature must look like")
  rejects("serve 18:30\ndish A: 900C, 20 min\n", "from 50 to 280")
  rejects("serve 18:30\ndish A: 180C, 999 min\n", "from 5 to 300")
  rejects("serve 18:30\ndish A: 180C, 20 min, rest 5, rest 5\n", "once each")
  rejects("serve 18:30\ndish A: 180C, 20 min\ndish a: 180C, 20 min\n", "same name")
  rejects("serve 18:30\noven 1 shelf\ndish A: 180C, 20 min, shelves 2\n", "more shelves than the oven")
  rejects("serve 18:30\ndish A: 180C, 20 min, hold 99999\n", "whole number")
  local many = { "serve 18:30" }
  for i = 1, 16 do many[#many + 1] = "dish D" .. i .. ": 180C, 20 min" end
  rejects(table.concat(many, "\n"), "more than 15 dishes")
  rejects(string.rep("#", 9000), "larger than 8 KB")
  rejects("serve 18:30\n" .. string.rep("x", 201) .. "\n", "longer than 200")
  -- Escape codes, NUL, invisible and non-ASCII characters are refused; messages never echo them.
  for _, bad in ipairs({ "serve 18:30\ndish A\27[2J: 180C, 20 min\n", "serve 18:30\0\n",
    "serve 18:30\ndish Caf\195\169: 180C, 20 min\n", "serve 18:30 \226\128\174\n" }) do
    local m = rejects(bad, "not plain text")
    check(not m:find("\27") and not m:find("Caf"), "message does not echo input")
  end
  rejects("serve 18:30\ndish <script>: 180C, 20 min\n", "a dish name must be")
end

function tests.example_plan_obeys_every_rule()
  local menu = Menu.parse(EXAMPLE)
  local r = Plan.solve(menu)
  check(r.ok and not r.stopped, "a plan is found")
  local ok, why = obeys(menu, r)
  check(ok, "plan obeys the rules: " .. tostring(why))
  check(r.changes == 1, "one temperature change")
  local text = Report.render(menu, r, "christmas.txt")
  check(text:find("10:55  Turn the oven on to 190C to preheat", 1, true) ~= nil, "preheat line")
  check(text:find("12:40  Put in: Yorkshire puddings  [oven 210C]", 1, true) ~= nil, "oven hot for the puddings")
  check(text:find("13:00  Serve", 1, true) ~= nil, "serve line")
end

function tests.matches_brute_force_on_random_menus()
  local rng = generator(42)
  local compared, solvable, impossible = 0, 0, 0
  for _ = 1, 150 do
    local menu = randomMenu(rng)
    local r = Plan.solve(menu)
    local b = brute(menu)
    compared = compared + 1
    check(r.ok == (b ~= nil), "solver and brute force agree whether a plan exists")
    if r.ok then
      solvable = solvable + 1
      check(r.stale == b, "solver finds the least waiting")
      local ok, why = obeys(menu, r)
      check(ok, "random plan obeys the rules: " .. tostring(why))
    else
      impossible = impossible + 1
    end
  end
  check(solvable > 20 and impossible > 5, "the random menus include both kinds (" .. solvable .. "/" .. impossible .. ")")
end

function tests.impossible_menus_are_explained()
  local menu = Menu.parse([[
serve 19:00
oven 2 shelves
dish Pavlova: 120C +-5, 60 min
dish Pizza: 250C +-10, 15 min
dish Salad croutons: 180C +-10, 10 min, hold 120
]])
  local r = Plan.solve(menu)
  check(not r.ok, "no plan")
  local pairs_, singles = Plan.explain(menu)
  check(#pairs_ == 1 and pairs_[1][1] == 1 and pairs_[1][2] == 2, "pavlova and pizza clash")
  check(#singles == 2, "leaving out either clashing dish works")
  local text = Report.render(menu, r, "x")
  check(text:find("Pavlova (115-125C) and Pizza (240-260C) can't share the oven", 1, true) ~= nil, "clash explained")
end

function tests.big_menus_are_quick()
  -- 15 dishes that fit: the search may stop at its limit, but whatever it returns must work.
  local lines = { "serve 12:00", "oven 4 shelves" }
  for i = 1, 15 do
    lines[#lines + 1] = string.format("dish Dish %d: %dC +-20, %d min, hold 90", i, 150 + (i % 5) * 10, 10 + (i % 4) * 10)
  end
  local menu = Menu.parse(table.concat(lines, "\n"))
  local started = os.clock()
  local r = Plan.solve(menu)
  check(os.clock() - started < 30, "finishes in time")
  check(r.nodes <= Plan.NODE_LIMIT and r.work <= Plan.WORK_LIMIT + 400, "limits respected")
  check(r.ok, "a plan is found")
  local ok, why = obeys(menu, r)
  check(ok, "big plan obeys the rules: " .. tostring(why))

  -- 15 dishes that can't fit the shelves: proved at once, without searching.
  lines = { "serve 12:00", "oven 4 shelves" }
  for i = 1, 15 do
    lines[#lines + 1] = string.format("dish Dish %d: %dC +-20, %d min, hold 60", i, 150 + (i % 5) * 10, 20 + i * 5)
  end
  menu = Menu.parse(table.concat(lines, "\n"))
  r = Plan.solve(menu)
  check(not r.ok and r.crowded and r.nodes == 0, "too much food is spotted without a search")
  check(r.crowded.need > r.crowded.have, "the proof adds up")
  check(Report.render(menu, r, "x"):find("Too much food for the shelves", 1, true) ~= nil, "and explained")
end

local function buffer()
  local b = { text = "" }
  function b:write(...)
    for _, s in ipairs({ ... }) do self.text = self.text .. s end
    return self
  end
  return b
end

local function cli(args, input)
  local out, err = buffer(), buffer()
  local stdin = { read = function(_, n) return (input or ""):sub(1, n) end }
  return Cli.main(args, stdin, out, err), out.text, err.text
end

function tests.command_line()
  local code, out, err = cli({ "examples/christmas.txt" })
  check(code == 0 and err == "" and out:find("TIMELINE", 1, true), "example runs")
  code, out = cli({ "-" }, "serve 19:00\ndish Pavlova: 120C, 60 min\ndish Pizza: 250C, 15 min\n")
  check(code == 1 and out:find("NO PLAN", 1, true), "impossible menu exits 1")
  code, out = cli({ "--help" })
  check(code == 0 and out:find("usage", 1, true), "help")
  for _, args in ipairs({ {}, { "a", "b" }, { "--bogus" }, { "/no/such/menu" }, { "." }, { "/dev/zero" },
    { "\27]0;owned\7$(reboot)" } }) do
    code, out, err = cli(args)
    check(code == 2 and out == "" and err:sub(1, 9) == "hotslot: ", "bad arguments exit 2")
    check(not err:find("owned") and not err:find("reboot"), "errors do not echo arguments")
  end
  code, out, err = cli({ "-" }, string.rep("a", 100000))
  check(code == 2 and err:find("8 KB", 1, true), "huge standard input refused")
end

function tests.odd_file_names_are_printed_safely()
  local path = os.tmpname()
  local dir = path:match("^(.*)/") or "."
  local odd = dir .. "/bad\27[31mname.txt"
  local f = assert(io.open(odd, "wb"))
  f:write(EXAMPLE)
  f:close()
  local code, out = cli({ odd })
  os.remove(odd)
  os.remove(path)
  check(code == 0 and not out:find("\27") and out:find("bad??31mname.txt", 1, true), "name is cleaned")
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
print("Hotslot tests on " .. _VERSION)
for _, name in ipairs(names) do
  local before = failures
  local ok, e = pcall(tests[name])
  if not ok then
    failures = failures + 1
    print("  error: " .. tostring(e))
  end
  print((failures == before and "ok    " or "FAIL  ") .. name:gsub("_", " "))
end
print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
