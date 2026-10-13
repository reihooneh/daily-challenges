-- Turns a plan into a timeline someone can cook from.

local Menu = require("hotslot.menu")
local Plan = require("hotslot.plan")

local M = {}

local ROOM = Menu.ROOM

function M.clock(minutes)
  minutes = minutes % (24 * 60)
  return string.format("%02d:%02d", minutes // 60, minutes % 60)
end

-- The time (minutes after midnight) a slot starts.
local function at(menu, result, slot)
  return menu.serve + (slot - result.horizon) * Plan.SLOT
end

function M.events(menu, result)
  local t = result.temps
  local events = {}
  local function add(slot, rank, text)
    events[#events + 1] = { slot = slot, rank = rank, text = text }
  end
  local first, last = result.first, result.last
  local on = first
  while on > 0 and t[on - 1] > ROOM do on = on - 1 end
  add(on, 0, string.format("Turn the oven on to %dC to preheat", t[first]))
  local k = first + 1
  while k <= last do
    if t[k] ~= t[k - 1] then
      local rising = t[k] > t[k - 1]
      local e = k
      while e + 1 <= last and t[e + 1] ~= t[e] and (t[e + 1] > t[e]) == rising do e = e + 1 end
      add(k, 3, string.format("%s the oven to %dC", rising and "Turn up" or "Turn down", t[e]))
      k = e + 1
    else
      k = k + 1
    end
  end
  for _, item in ipairs(result.items) do
    local d = item.dish
    local shelf = d.shelves > 1 and string.format(" (%d shelves)", d.shelves) or ""
    add(item.start, 4, "Put in: " .. d.name .. shelf)
    local out = "Take out: " .. d.name
    if d.rest > 0 then
      out = out .. string.format(", rest %d min", d.rest)
    end
    if item.wait > d.rest then
      out = out .. string.format(", keep warm (%d min until serving)", item.wait - d.rest)
    end
    add(item.finish, 1, out)
  end
  add(last + 1, 2, "Turn the oven off")
  add(result.horizon, 5, "Serve")
  table.sort(events, function(a, b)
    if a.slot ~= b.slot then return a.slot < b.slot end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.text < b.text
  end)
  return events
end

local function cookingRange(result, item)
  local lo, hi = math.huge, -math.huge
  for k = item.start - 1, item.finish - 1 do
    lo = math.min(lo, result.temps[k])
    hi = math.max(hi, result.temps[k])
  end
  if lo == hi then return string.format("%dC", lo) end
  return string.format("%d-%dC", lo, hi)
end

function M.render(menu, result, name)
  local out = {}
  local function line(s) out[#out + 1] = s end
  line(string.format("HOTSLOT  %s  (serve at %s, one oven with %d shel%s)", name, M.clock(menu.serve),
    menu.shelves, menu.shelves == 1 and "f" or "ves"))
  line("")
  if not result.ok then
    if result.stopped then
      line("NO PLAN FOUND: the search stopped before finding one. Try fewer dishes or wider tolerances.")
      return table.concat(out, "\n") .. "\n"
    end
    line("NO PLAN: these dishes can't all be ready on time in one oven.")
    local c = result.crowded
    if c then
      line(string.format("  Too much food for the shelves: between %s and %s the dishes need %d shelf-minutes,",
        M.clock(at(menu, result, c.from)), M.clock(at(menu, result, c.to)), c.need))
      line(string.format("  but %d shelves only give %d.", menu.shelves, c.have))
    end
    local conflicts, singles = Plan.explain(menu)
    for _, pair in ipairs(conflicts) do
      local a, b = menu.dishes[pair[1]], menu.dishes[pair[2]]
      line(string.format("  %s (%d-%dC) and %s (%d-%dC) can't share the oven in time.", a.name,
        a.temp - a.tolerance, a.temp + a.tolerance, b.name, b.temp - b.tolerance, b.temp + b.tolerance))
    end
    if #singles > 0 then
      line("")
      line("Leave out any one of these and everything else fits (cook it earlier and reheat, or use another oven):")
      for _, i in ipairs(singles) do line("  " .. menu.dishes[i].name) end
    else
      line("Leaving out any single dish isn't enough. Try wider tolerances, longer holds or another oven.")
    end
    return table.concat(out, "\n") .. "\n"
  end

  line("TIMELINE")
  for _, e in ipairs(M.events(menu, result)) do
    local temp = ""
    if e.rank == 4 then temp = string.format("  [oven %dC]", result.temps[e.slot - 1]) end
    line(string.format("  %s  %s%s", M.clock(at(menu, result, e.slot)), e.text, temp))
  end
  line("")
  line("DISHES")
  local width = 4
  for _, item in ipairs(result.items) do width = math.max(width, #item.dish.name) end
  line(string.format("  %-" .. width .. "s  %5s  %5s  %-9s  %s", "Dish", "In", "Out", "Oven", "Ideal"))
  for _, item in ipairs(result.items) do
    local d = item.dish
    line(string.format("  %-" .. width .. "s  %5s  %5s  %-9s  %dC +-%d", d.name, M.clock(at(menu, result, item.start)),
      M.clock(at(menu, result, item.finish)), cookingRange(result, item), d.temp, d.tolerance))
  end
  line("")
  local waiting = result.stale
  line(string.format("Oven changes while cooking: %d.  Extra waiting after resting, all dishes together: %d min.",
    result.changes, waiting))
  if result.stopped then
    line("(The search stopped early: this plan works, but a fresher one may exist.)")
  end
  return table.concat(out, "\n") .. "\n"
end

return M
