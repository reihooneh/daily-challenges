-- Tests for Loadorder: python3 tools/lua.py test/test_loadorder.lua (or lua test/test_loadorder.lua)
local parse = require("loadorder.parse")
local planner = require("loadorder.plan")
local cli = require("loadorder")

local passed, failed = 0, 0
local function check(cond, what)
  if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. what) end
end

local f = assert(io.open("examples/move.txt", "rb"))
local EXAMPLE = f:read("a")
f:close()

-- The example: every item placed once, stops in unloading order, heavy tiers forward, balanced.
do
  local move = assert(parse.parse(EXAMPLE))
  local plan, alt = planner.best(move)
  check(alt == nil, "the example works in the order given")
  check(#plan.overflow == 0 and #plan.too_big == 0 and plan.balanced, "the example fits and balances")
  local seen, count = {}, 0
  for _, t in ipairs(plan.tiers) do
    for _, it in ipairs(t.items) do
      check(not seen[it], "an item placed twice: " .. it.name)
      seen[it] = true
      count = count + 1
    end
  end
  check(count == #move.items, "every item is placed")
  -- From the cab back, stops go from last visited to first: the door holds the first stop.
  for i = 2, #plan.tiers do
    local a, b = plan.tiers[i - 1], plan.tiers[i]
    local ra, rb
    for r, idx in ipairs(plan.order) do
      if idx == a.stop then ra = r end
      if idx == b.stop then rb = r end
    end
    check(ra >= rb, "a later stop's wall is behind an earlier stop's")
    if a.stop == b.stop then check(a.kg >= b.kg, "heavier walls go forward") end
  end
  -- Inside each wall, nothing heavy sits on something fragile.
  for _, t in ipairs(plan.tiers) do
    local fragile_seen = false
    for _, it in ipairs(t.items) do
      if it.fragile then fragile_seen = true else check(not fragile_seen, "a fragile item under a heavy one") end
    end
  end
  -- The balance is the weighted centre of the walls.
  local m, mom = 0, 0
  for _, t in ipairs(plan.tiers) do m = m + t.kg; mom = mom + t.kg * (t.from + t.to) / 2 end
  check(math.abs(plan.balance - mom / m / move.truck.length) < 1e-12, "balance is the centre of mass")
  local text = cli.report(move, plan, alt)
  check(text:find("Book boxes x10", 1, true) ~= nil, "copies are grouped in the report")
end

-- Orientation: upright items stay upright; others lie down if that saves length.
do
  local truck = { width = 2.0, height = 2.1, length = 4 }
  local o = planner.orient({ dims = { 1.5, 0.3, 2.0 }, upright = true }, truck)
  check(o.height == 2.0 and o.depth == 0.3, "an upright mattress stands")
  local lie = planner.orient({ dims = { 0.5, 0.5, 1.8 } }, truck)
  check(lie.depth == 0.5, "a tall box can lie down")
  check(planner.orient({ dims = { 2.5, 2.5, 2.5 } }, truck) == nil, "too big for the truck")
end

-- A first stop full of heavy things at the door unbalances the truck; swapping the stops fixes it.
do
  local text = [[
truck 4.0 2.0 2.0
balance 0.10 0.55
stop gym "Gym"
stop flat "Flat"
item "Weights" 0.6 0.6 0.5 120 x6 -> gym
item "Pillows" 0.6 0.6 0.6 2 x45 -> flat
]]
  local move = assert(parse.parse(text))
  local plan, alt = planner.best(move)
  check(not plan.balanced and plan.balance > move.balance[2], "the given order is tail-heavy")
  check(alt ~= nil and alt.balanced and alt.order[1] == 2, "visiting the flat first balances it")
  check(cli.report(move, plan, alt):find("Visiting the stops in this order instead", 1, true) ~= nil, "the report suggests it")
end

-- Hostile and broken files.
do
  local bad = {
    "truck 4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 -> b\n",
    "truck nan 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 -> a\n",
    "truck -4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 -> a\n",
    "truck 1e9 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 -> a\n",
    "truck 4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 heavy -> a\n",
    "truck 4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 x1000 -> a\n",
    "truck 4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 x100 -> a\n" .. string.rep("item \"Y\" 1 1 1 1 x100 -> a\n", 4),
    "truck 4 2 2\nstop a \"A\"\nitem \"<b>X\" 1 1 1 10 -> a\n",
    "truck 4 2 2\nstop a \"A\27[31m\"\nitem \"X\" 1 1 1 10 -> a\n",
    "truck 4 2 2\nstop a \"A\"\nstop a \"B\"\nitem \"X\" 1 1 1 10 -> a\n",
    "truck 4 2 2\nstop a \"A\"\nitem \"X 1 1 1 10 -> a\n",
    "truck 4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 -> a extra\n",
    "stop a \"A\"\nitem \"X\" 1 1 1 10 -> a\n",
    "truck 4 2 2\nrm -rf /\n",
    string.rep("#", 40000),
  }
  for i, text in ipairs(bad) do
    local move, err = parse.parse(text)
    check(move == nil and type(err) == "string", "bad file " .. i .. " is refused")
  end
  local _, err = parse.parse("truck 4 2 2\nstop a \"A\"\nitem \"X\" 1 1 1 10 -> nowhere\n")
  check(err:find("^line 3") ~= nil, "errors name the line")
end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
