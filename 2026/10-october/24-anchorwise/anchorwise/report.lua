-- The printed check.
local Parse = require("anchorwise.parse")

local R = {}

local function pct(x) return string.format("%3.0f%%", x * 100) end

function R.render(r)
  local a = r.anchor
  local out = {}
  local function add(...) out[#out + 1] = string.format(...) end
  local n = #a.pieces
  add("ANCHORWISE  %s", a.name)
  add("%s rigging in %s, %d pieces, %.1f kN load%s.", a.rigging == "fixed" and "Fixed (pre-equalized)" or "Sliding",
    Parse.MATERIALS[a.material].name, n, a.load,
    a.angle == 0 and " straight down" or string.format(" pulling %d° %s of straight down", math.floor(math.abs(a.angle) + 0.5),
      a.angle > 0 and "right" or "left"))
  add("")
  add("With everything holding (master point settles at %.2f, %.2f; arms spread %.0f°):", r.master[1], r.master[2], r.spread)
  add("  %-22s %8s  %6s  %s", "Piece", "Load", "Share", "vs an even split")
  local most, total = 0, 0
  for i, p in ipairs(a.pieces) do
    local f = r.forces[i]
    total = total + f
    if f > most then most = f end
    local even = a.load / n
    add("  %-22s %5.2f kN  %s  %s", p.name:sub(1, 22), f, pct(f / a.load), f < 1e-6 and "carries nothing (slack)"
      or string.format("x%.2f", f / even))
  end
  add("  The pieces carry %.2f kN between them for a %.1f kN load%s.", total, a.load,
    total > a.load * 1.05 and string.format(" (%.0f%% more: wide angles multiply force)", (total / a.load - 1) * 100) or "")
  add("")
  add("If one piece fails (the jolt assumes the load falls freely through the drop, so it is an upper estimate):")
  local worst = 0
  for j, p in ipairs(a.pieces) do
    local f = r.failures[j]
    if f.gone then
      add("  %-22s nothing left holds the load", p.name:sub(1, 22))
      worst = math.huge
    else
      local most2 = 0
      for _, v in pairs(f.forces) do if v > most2 then most2 = v end end
      add("  %-22s drops %4.0f mm%s, jolt up to about %.1f kN, then %.2f kN on the busiest piece", p.name:sub(1, 22), f.drop * 1000,
        f.caught and " (caught by a limiter knot)" or "", f.peak, most2)
      if f.peak > worst then worst = f.peak end
    end
  end
  add("")
  local notes = {}
  if r.spread > 120 then
    notes[#notes + 1] = string.format("The arms spread %.0f°: past 120° each piece holds more than the whole load. Bring the pieces closer or lengthen the arms.", r.spread)
  elseif r.spread > 60 then
    notes[#notes + 1] = string.format("The arms spread %.0f°. Keeping it under 60° keeps each piece's share close to even.", r.spread)
  end
  if a.rigging == "fixed" and most > 1.5 * a.load / n then
    notes[#notes + 1] = "One piece takes far more than its share: arms of unequal length or slack in an arm. Re-tie so the arms come tight together, or use sliding rigging."
  end
  if worst == math.huge then
    notes[#notes + 1] = "Losing one piece loses the anchor. Add a piece."
  elseif worst > 2.5 * a.load then
    notes[#notes + 1] = string.format("A failure could shock-load what's left to about %.1f kN. Less extension (limiter knots, shorter arms) keeps that down.", worst)
  end
  if #notes == 0 then notes[1] = "No warnings: loads are shared fairly and a single failure is caught with little drop." end
  for _, s in ipairs(notes) do add("- %s", s) end
  add("")
  add("A teaching model (2D, ideal knots, no friction): never a substitute for training and a proper check on the rock.")
  return table.concat(out, "\n") .. "\n"
end

return R
