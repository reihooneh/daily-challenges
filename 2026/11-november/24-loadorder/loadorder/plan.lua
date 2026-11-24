-- Planning the load: walls of items ("tiers") from the cab to the door, so each stop's things come
-- off first in the order you visit, heavy tiers forward within each stop, and the load balanced.
local M = {}

-- How an item sits in the truck: width across, depth along it, height. Upright items keep their
-- height; others may lie down. Picks the orientation that takes the least length of the truck.
function M.orient(item, truck)
  local d = item.dims
  local tries
  if item.upright then
    tries = { { d[1], d[2], d[3] }, { d[2], d[1], d[3] } }
  else
    tries = {
      { d[1], d[2], d[3] }, { d[2], d[1], d[3] }, { d[1], d[3], d[2] },
      { d[3], d[1], d[2] }, { d[2], d[3], d[1] }, { d[3], d[2], d[1] },
    }
  end
  local best
  for _, o in ipairs(tries) do
    local w, dep, h = o[1], o[2], o[3]
    if w <= truck.width and h <= truck.height then
      if not best or dep < best.depth or (dep == best.depth and h < best.height) then
        best = { width = w, depth = dep, height = h }
      end
    end
  end
  return best
end

-- Stack order inside a tier, bottom up: heaviest first, fragile things last.
local function stack(items)
  table.sort(items, function(a, b)
    if (a.fragile or false) ~= (b.fragile or false) then return not a.fragile end
    if a.kg ~= b.kg then return a.kg > b.kg end
    return a.name < b.name
  end)
end

-- Plans the load for an unloading order (a list of stop indices, first stop first).
function M.plan(move, order)
  local truck = move.truck
  local face = truck.width * truck.height * move.fill
  local tiers, too_big = {}, {}
  -- Load the last stop first, so it ends up at the cab.
  for pos = #order, 1, -1 do
    local stop = order[pos]
    local mine = {}
    for _, it in ipairs(move.items) do
      if it.stop == stop then
        local o = M.orient(it, truck)
        if o then
          mine[#mine + 1] = { item = it, o = o }
        else
          too_big[#too_big + 1] = it
        end
      end
    end
    -- Deepest first (so tiers take their depth from them), then heaviest.
    table.sort(mine, function(a, b)
      if a.o.depth ~= b.o.depth then return a.o.depth > b.o.depth end
      if a.item.kg ~= b.item.kg then return a.item.kg > b.item.kg end
      return a.item.name < b.item.name
    end)
    local group = {}
    for _, p in ipairs(mine) do
      local area = p.o.width * p.o.height
      local placed = false
      for _, t in ipairs(group) do
        if t.area + area <= face and p.o.depth <= t.depth then
          t.area = t.area + area
          t.kg = t.kg + p.item.kg
          t.items[#t.items + 1] = p.item
          placed = true
          break
        end
      end
      if not placed then
        group[#group + 1] = { stop = stop, depth = p.o.depth, area = area, kg = p.item.kg, items = { p.item } }
      end
    end
    -- Heaviest tiers towards the cab, within this stop's share of the truck.
    table.sort(group, function(a, b)
      if a.kg ~= b.kg then return a.kg > b.kg end
      return a.depth > b.depth
    end)
    for _, t in ipairs(group) do
      stack(t.items)
      tiers[#tiers + 1] = t
    end
  end
  -- Positions from the cab, the balance, and what doesn't fit.
  local x, mass, moment = 0, 0, 0
  local overflow = {}
  for _, t in ipairs(tiers) do
    t.from = x
    t.to = x + t.depth
    x = t.to
    if t.to > truck.length + 1e-9 then
      overflow[#overflow + 1] = t
    else
      mass = mass + t.kg
      moment = moment + t.kg * (t.from + t.to) / 2
    end
  end
  local balance = mass > 0 and moment / mass / truck.length or 0
  return {
    order = order, tiers = tiers, used = x, overflow = overflow, too_big = too_big, kg = mass,
    balance = balance, balanced = balance >= move.balance[1] and balance <= move.balance[2],
  }
end

local function permutations(n)
  local out, a = {}, {}
  for i = 1, n do a[i] = i end
  local function go(k)
    if k > n then
      local copy = {}
      for i = 1, n do copy[i] = a[i] end
      out[#out + 1] = copy
      return
    end
    for i = k, n do
      a[k], a[i] = a[i], a[k]
      go(k + 1)
      a[k], a[i] = a[i], a[k]
    end
  end
  go(1)
  return out
end

-- How far an order is from the one planned: the number of pairs of stops swapped.
local function distance(order)
  local d = 0
  for i = 1, #order do
    for j = i + 1, #order do
      if order[i] > order[j] then d = d + 1 end
    end
  end
  return d
end

local function ok(p)
  return #p.overflow == 0 and #p.too_big == 0 and p.balanced
end

-- The plan for the stops in the order given, and, if that doesn't work, the closest order that does.
function M.best(move)
  local given = {}
  for i = 1, #move.stops do given[i] = i end
  local plan = M.plan(move, given)
  if ok(plan) then return plan, nil end
  local alt, alt_d
  for _, order in ipairs(permutations(#move.stops)) do
    local p = M.plan(move, order)
    local d = distance(order)
    if ok(p) and (not alt or d < alt_d) then alt, alt_d = p, d end
  end
  return plan, alt
end

return M
