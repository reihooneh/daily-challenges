-- Plans one oven: when each dish goes in and comes out, and what the oven is set to,
-- so that everything is ready to serve at once.
--
-- Time is cut into 5-minute slots counted back from serving. temps[k] is the oven's
-- temperature at the end of slot k; during the slot it moves steadily from temps[k-1].
-- A dish in the oven for slots start..finish-1 needs every temperature from the end of
-- slot start-1 (the oven is hot when the dish goes in) to the end of slot finish-1 to be
-- in its range. The oven can only rise or fall so fast in one slot.
--
-- The search tries finishing times for each dish (freshest first),
-- and after each choice checks that some sequence of oven temperatures still works.

local Menu = require("hotslot.menu")

local M = {}

M.SLOT = 5        -- minutes
M.MAX_TEMP = 300
M.NODE_LIMIT = 100000
M.WORK_LIMIT = 4000000 -- slot checks; keeps the worst case to a few seconds

local ROOM = Menu.ROOM

local function ceilDiv(a, b) return (a + b - 1) // b end

-- Turns minutes into slots and lists each dish's possible finishing slots.
local function prepare(menu, skip)
  local dishes = {}
  for i, d in ipairs(menu.dishes) do
    if not (skip and skip[i]) then
      dishes[#dishes + 1] = {
        index = i, dish = d,
        cook = ceilDiv(d.cook, M.SLOT),
        rest = ceilDiv(d.rest, M.SLOT),
        hold = d.hold // M.SLOT,
        lo = d.temp - d.tolerance,
        hi = d.temp + d.tolerance,
      }
    end
  end
  local up = menu.heats * M.SLOT
  local down = menu.cools * M.SLOT
  local longest, hottest = 0, ROOM
  for _, s in ipairs(dishes) do
    longest = math.max(longest, s.cook + s.rest + s.hold)
    hottest = math.max(hottest, s.lo)
  end
  local horizon = longest + ceilDiv(hottest - ROOM, up) + 2
  for _, s in ipairs(dishes) do
    -- A dish finishing at slot e (it is in the oven for slots e-cook .. e-1) waits
    -- horizon - e slots before serving, which must be between rest and rest + hold.
    s.options = {}
    for wait = s.rest, s.rest + s.hold do
      s.options[#s.options + 1] = horizon - wait
    end
  end
  return { dishes = dishes, horizon = horizon, up = up, down = down, shelves = menu.shelves }
end

-- Forward pass: the set of temperatures the oven can be at in each slot, given what each
-- slot needs (lo..hi). Each set is an interval, so this is exact. Returns nil if impossible.
local function reachable(p, lo, hi)
  local rlo, rhi = ROOM, ROOM
  local out = {}
  for k = 0, p.horizon - 1 do
    rlo = math.max(math.max(rlo - p.down, ROOM), lo[k])
    rhi = math.min(math.min(rhi + p.up, M.MAX_TEMP), hi[k])
    if rlo > rhi then return nil end
    out[k] = { rlo, rhi }
  end
  return out
end

-- Picks one temperature per slot, working backwards: hold steady where possible, keep
-- the oven cold until it must preheat, and turn it off after the last dish comes out.
local function profile(p, reach, busy, ideal)
  local first, last
  for k = 0, p.horizon - 1 do
    if busy[k] then
      first = first or k
      last = k
    end
  end
  local temps = {}
  local r = reach[last]
  temps[last] = math.min(math.max(ideal[last], r[1]), r[2]) -- nearest the dishes' own temperatures
  for k = last - 1, 0, -1 do
    local nextT = temps[k + 1]
    local lo = math.max(reach[k][1], nextT - p.up)
    local hi = math.min(reach[k][2], nextT + p.down)
    if k < first then
      temps[k] = lo -- as cold as possible: preheat only as late as needed
    else
      temps[k] = math.min(math.max(nextT, lo), hi) -- as steady as possible
    end
  end
  for k = last + 1, p.horizon - 1 do temps[k] = ROOM end
  local changes = 0
  for k = first + 1, last do
    if temps[k] ~= temps[k - 1] then changes = changes + 1 end
  end
  return temps, changes, first, last
end

-- A quick proof that the shelves are too few: some stretch of time must hold more
-- cooking than the shelves can, counting only dishes that have to cook inside it.
-- Returns { from = slot, to = slot, need = shelf-minutes, have = shelf-minutes } or nil.
local function crowded(p)
  local starts, ends = {}, {}
  for _, s in ipairs(p.dishes) do
    s.earliest = s.options[#s.options] - s.cook
    s.latest = s.options[1]
    starts[#starts + 1] = s.earliest
    ends[#ends + 1] = s.latest
  end
  for _, a in ipairs(starts) do
    for _, b in ipairs(ends) do
      if b > a then
        local need = 0
        for _, s in ipairs(p.dishes) do
          if s.earliest >= a and s.latest <= b then need = need + s.cook * s.dish.shelves end
        end
        if need > p.shelves * (b - a) then
          return { from = a, to = b, need = need * M.SLOT, have = p.shelves * (b - a) * M.SLOT }
        end
      end
    end
  end
  return nil
end

-- skip: optional set of dish numbers to leave out (used to explain impossible menus).
function M.solve(menu, skip, nodeLimit)
  local p = prepare(menu, skip)
  local H = p.horizon
  local lo, hi, used, sum, count = {}, {}, {}, {}, {}
  for k = 0, H - 1 do lo[k], hi[k], used[k], sum[k], count[k] = ROOM, M.MAX_TEMP, 0, 0, 0 end
  local finish = {}
  local result = { ok = false, nodes = 0, work = 0, stopped = false, horizon = H, prepared = p }

  -- Most constrained dishes first: fewest finishing times, then the narrowest temperature range.
  local order = {}
  for i, s in ipairs(p.dishes) do order[i] = s end
  table.sort(order, function(a, b)
    if #a.options ~= #b.options then return #a.options < #b.options end
    if a.hi - a.lo ~= b.hi - b.lo then return a.hi - a.lo < b.hi - b.lo end
    return a.index < b.index
  end)

  -- Can dish s finish at slot e, given the dishes placed so far?
  local function fitsAt(s, e)
    local start = e - s.cook
    if start < 1 then return false end
    result.work = result.work + s.cook + 1
    for k = start - 1, e - 1 do
      if math.max(lo[k], s.lo) > math.min(hi[k], s.hi) then return false end
      if k >= start and used[k] + s.dish.shelves > p.shelves then return false end
    end
    return true
  end

  -- Forward checking: every dish still to place must have at least one time left.
  local function stillPossible(from)
    for j = from, #order do
      local any = false
      for _, e in ipairs(order[j].options) do
        if fitsAt(order[j], e) then
          any = true
          break
        end
      end
      if not any then return false end
    end
    return true
  end

  local limit = nodeLimit or M.NODE_LIMIT
  local best

  local function search(i, stale)
    if result.nodes >= limit or result.work >= M.WORK_LIMIT then
      result.stopped = true
      return
    end
    result.nodes = result.nodes + 1
    if best and stale > best.stale then return end
    if i > #order then
      local reach = reachable(p, lo, hi)
      local busy, ideal = {}, {}
      for k = 0, H - 1 do
        busy[k] = used[k] > 0
        ideal[k] = count[k] > 0 and sum[k] // count[k] or ROOM
      end
      local temps, changes, first, last = profile(p, reach, busy, ideal)
      if not best or stale < best.stale or (stale == best.stale and changes < best.changes) then
        local f = {}
        for idx, e in pairs(finish) do f[idx] = e end
        best = { stale = stale, changes = changes, finish = f, temps = temps, first = first, last = last }
      end
      return
    end
    local s = order[i]
    for _, e in ipairs(s.options) do
      if fitsAt(s, e) then
        local start = e - s.cook
        local saved = {}
        for k = start - 1, e - 1 do
          saved[k] = { lo[k], hi[k] }
          lo[k] = math.max(lo[k], s.lo)
          hi[k] = math.min(hi[k], s.hi)
        end
        for k = start, e - 1 do
          used[k] = used[k] + s.dish.shelves
          sum[k], count[k] = sum[k] + s.dish.temp, count[k] + 1
        end
        if reachable(p, lo, hi) and stillPossible(i + 1) then
          finish[s.index] = e
          search(i + 1, stale + (H - e - s.rest) * M.SLOT)
          finish[s.index] = nil
        end
        for k = start - 1, e - 1 do lo[k], hi[k] = saved[k][1], saved[k][2] end
        for k = start, e - 1 do
          used[k] = used[k] - s.dish.shelves
          sum[k], count[k] = sum[k] - s.dish.temp, count[k] - 1
        end
      end
      if result.stopped then return end
    end
  end

  result.crowded = crowded(p)
  if not result.crowded then search(1, 0) end
  if best then
    result.ok = true
    result.stale = best.stale
    result.changes = best.changes
    result.temps = best.temps
    result.first, result.last = best.first, best.last
    result.items = {}
    for _, s in ipairs(p.dishes) do
      local e = best.finish[s.index]
      result.items[#result.items + 1] = {
        dish = s.dish, index = s.index,
        start = e - s.cook, finish = e,  -- slots
        wait = (H - e) * M.SLOT,         -- minutes between coming out and serving
      }
    end
  end
  return result
end

-- For an impossible menu: pairs of dishes that cannot share the oven, and single dishes
-- that, left out, let everything else fit.
function M.explain(menu)
  local n = #menu.dishes
  local pairs_, singles = {}, {}
  for a = 1, n do
    for b = a + 1, n do
      local skip = {}
      for i = 1, n do skip[i] = (i ~= a and i ~= b) end
      if not M.solve(menu, skip, 20000).ok then pairs_[#pairs_ + 1] = { a, b } end
    end
  end
  for a = 1, n do
    if n > 1 and M.solve(menu, { [a] = true }, 20000).ok then singles[#singles + 1] = a end
  end
  return pairs_, singles
end

return M
