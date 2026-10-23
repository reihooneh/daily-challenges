-- Puts it together: the loads with every piece holding, then what happens if each piece fails
-- in turn: how far the master point drops, and how hard the drop loads what's left.
local V = require("anchorwise.vec")
local Fixed = require("anchorwise.fixed")
local Sliding = require("anchorwise.sliding")

local A = {}

-- A mass that drops h onto a spring of stiffness k, already carrying its weight W, peaks at
-- W (1 + sqrt(1 + 2 k h / W)). With no drop that is 2W, the "sudden load" of a weight
-- released onto a slack system; dropping further onto a stiff system is far worse.
function A.peak(w, k, h)
  if h <= 0 then return w end
  return w * (1 + math.sqrt(1 + 2 * k * h / w))
end

local function spread(points, m)
  local widest = 0
  for i = 1, #points do
    for j = i + 1, #points do
      local ang = V.angle(V.sub(points[i], m), V.sub(points[j], m))
      if ang > widest then widest = ang end
    end
  end
  return widest
end

local function slidingStiffness(points, m, ea, L)
  local sum = { 0, 0 }
  for _, p in ipairs(points) do sum = V.add(sum, V.unit(V.sub(m, p))) end
  return ea * V.dot(sum, sum) / L
end

function A.run(anchor)
  local load = { dir = anchor.dir, size = anchor.load }
  local n = #anchor.pieces
  local result = { anchor = anchor, failures = {} }
  local points = {}
  for i, p in ipairs(anchor.pieces) do points[i] = p.pos end

  if anchor.rigging == "fixed" then
    local arms = Fixed.arms(anchor)
    local s = Fixed.solve(arms, anchor.master, load)
    if not s then error({ input = "the master point couldn't settle; check the piece and master positions" }, 0) end
    result.master, result.forces = s.master, s.forces
    for j = 1, n do
      local rest = Fixed.arms(anchor, j)
      local after = Fixed.solve(rest, s.master, load)
      if after then
        local drop = V.dot(V.sub(after.master, s.master), load.dir)
        local k = Fixed.stiffness(rest, after.master, load)
        result.failures[j] = { drop = drop, peak = A.peak(anchor.load, k, drop), forces = after.forces }
      else
        result.failures[j] = { gone = true }
      end
    end
  else
    local s = Sliding.solve(points, anchor.sling, load)
    if not s then error({ input = "the sling is too short to reach round the pieces" }, 0) end
    result.master, result.tension = s.master, s.tension
    result.forces = {}
    for i = 1, n do result.forces[i] = s.tension end
    for j = 1, n do
      local restPoints, idx = {}, {}
      for i = 1, n do
        if i ~= j then restPoints[#restPoints + 1] = points[i]; idx[#idx + 1] = i end
      end
      local after = Sliding.solve(restPoints, anchor.sling, load)
      if after then
        local drop = V.dot(V.sub(after.master, s.master), load.dir)
        local caught = anchor.limit and drop > anchor.limit
        if caught then drop = anchor.limit end
        local k = slidingStiffness(restPoints, after.master, anchor.ea, anchor.sling)
        local forces = {}
        for _, i in ipairs(idx) do forces[i] = after.tension end
        result.failures[j] = { drop = drop, caught = caught, peak = A.peak(anchor.load, k, drop), forces = forces }
      else
        result.failures[j] = { gone = true }
      end
    end
  end
  result.spread = spread(points, result.master)
  return result
end

return A
