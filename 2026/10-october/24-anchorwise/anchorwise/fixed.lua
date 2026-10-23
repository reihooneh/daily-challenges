-- Fixed (pre-equalized) rigging: each arm is tied off at the master point, so its length is set.
--
-- Each arm behaves like a stiff spring: it carries no force while slack, and once taut its force
-- grows with stretch: force = (EA / rest length) x stretch. Under load the master point moves
-- until the arm forces balance the load. Pulling the same way, a short arm is stiffer than a long one,
-- and an arm tied a little long comes tight late: why a cordelette seldom shares load evenly.
local V = require("anchorwise.vec")

local F = {}

-- Rest length of each arm: the distance from piece to master point as tied, plus any slack.
function F.arms(anchor, skip)
  local arms = {}
  for i, p in ipairs(anchor.pieces) do
    if i ~= skip then
      local rest = V.dist(p.pos, anchor.master) + p.slack
      arms[#arms + 1] = { index = i, pos = p.pos, rest = rest, k = anchor.ea / rest }
    end
  end
  return arms
end

-- Net force on the master point at position m (arms pulling towards their pieces, plus the load).
local function net(arms, m, load)
  local f = V.scale(load.dir, load.size)
  for _, a in ipairs(arms) do
    local d = V.dist(m, a.pos)
    local stretch = d - a.rest
    if stretch > 0 then f = V.add(f, V.scale(V.unit(V.sub(a.pos, m)), a.k * stretch)) end
  end
  return f
end

-- Finds where the master point settles: Newton's method on the 2D force balance, with a
-- numerical Jacobian and step halving so it never makes things worse.
function F.solve(arms, start, load)
  local m = V.add(start, V.scale(load.dir, 1e-4))
  local f = net(arms, m, load)
  for _ = 1, 200 do
    if V.len(f) < 1e-10 then break end
    local h = 1e-7
    local fx = V.scale(V.sub(net(arms, V.add(m, { h, 0 }), load), f), 1 / h)
    local fy = V.scale(V.sub(net(arms, V.add(m, { 0, h }), load), f), 1 / h)
    local step = V.solve2(fx[1], fy[1], fx[2], fy[2], V.scale(f, -1))
    if not step then step = V.scale(load.dir, 1e-3) end
    -- Never jump more than 10 cm in one go, and halve the step until the force gets smaller.
    local s = V.len(step)
    if s > 0.1 then step = V.scale(step, 0.1 / s) end
    local accepted = false
    for _ = 1, 40 do
      local trial = V.add(m, step)
      local ft = net(arms, trial, load)
      if V.len(ft) < V.len(f) then
        m, f, accepted = trial, ft, true
        break
      end
      step = V.scale(step, 0.5)
    end
    if not accepted then break end
  end
  if V.len(f) > 1e-6 * load.size then return nil end
  local forces = {}
  for _, a in ipairs(arms) do
    local stretch = V.dist(m, a.pos) - a.rest
    forces[a.index] = stretch > 0 and a.k * stretch or 0
  end
  return { master = m, forces = forces }
end

-- How stiff the system is along the load at its resting position (kN per metre).
function F.stiffness(arms, m, load)
  local h = 1e-6
  local f1 = net(arms, V.add(m, V.scale(load.dir, h)), load)
  local f0 = net(arms, m, load)
  return -V.dot(V.sub(f1, f0), load.dir) / h
end

return F
