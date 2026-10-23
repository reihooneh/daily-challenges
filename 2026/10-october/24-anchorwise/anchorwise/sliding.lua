-- Sliding rigging: one sling runs freely through every piece, so every arm carries the same
-- tension T. The master point slides along the sling until it hangs as low as it can in the
-- direction of the load: the point on the curve "total arm length = sling length" that is
-- furthest along the load. There, the arm directions add up to point straight back against the
-- load, and T = load / |sum of the arm directions|.
local V = require("anchorwise.vec")

local S = {}

local function total(points, m)
  local s = 0
  for _, p in ipairs(points) do s = s + V.dist(m, p) end
  return s
end

-- Along a ray from c, the distance r where the total arm length reaches L (bisection; the total
-- is convex along the ray and starts below L, so there is exactly one crossing).
local function reach(points, c, dir, L)
  local lo, hi = 0, 1
  while total(points, V.add(c, V.scale(dir, hi))) < L do hi = hi * 2 end
  for _ = 1, 80 do
    local mid = (lo + hi) / 2
    if total(points, V.add(c, V.scale(dir, mid))) < L then lo = mid else hi = mid end
  end
  return (lo + hi) / 2
end

-- points: piece positions; L: sling length; load: {dir, size}. Returns nil if the sling is too
-- short to reach round the pieces.
function S.solve(points, L, load)
  local c = { 0, 0 }
  for _, p in ipairs(points) do c = V.add(c, V.scale(p, 1 / #points)) end
  if total(points, c) >= L then return nil end
  local function at(phi)
    local dir = { math.cos(phi), math.sin(phi) }
    return V.add(c, V.scale(dir, reach(points, c, dir, L)))
  end
  local function score(phi) return V.dot(at(phi), load.dir) end
  -- Scan all directions, then golden-section search around the best one.
  local best, bestPhi = -math.huge, 0
  for i = 0, 359 do
    local phi = math.rad(i)
    local s = score(phi)
    if s > best then best, bestPhi = s, phi end
  end
  local a, b = bestPhi - math.rad(1), bestPhi + math.rad(1)
  local g = (math.sqrt(5) - 1) / 2
  for _ = 1, 60 do
    local x1, x2 = b - g * (b - a), a + g * (b - a)
    if score(x1) > score(x2) then b = x2 else a = x1 end
  end
  local m = at((a + b) / 2)
  local sum = { 0, 0 }
  for _, p in ipairs(points) do sum = V.add(sum, V.unit(V.sub(p, m))) end
  local tension = load.size / V.len(sum)
  return { master = m, tension = tension, alignment = V.angle(sum, V.scale(load.dir, -1)) }
end

return S
