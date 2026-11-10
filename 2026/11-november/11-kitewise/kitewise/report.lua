-- Writes the check as a course setter's notes.
local Check = require("kitewise.check")

local M = {}

local function m(v) return string.format("%.0f m", v) end

local function compass(dx, dy)
  local names = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" }
  local a = math.deg(math.atan(dy, dx)) % 360
  return names[math.floor((a + 22.5) / 45) % 8 + 1]
end

function M.describe(issue, course)
  local rule = course.sprint and Check.RULES.sprint or Check.RULES.forest
  if issue.kind == "dogleg" then
    return string.format("dog-leg at %s: the legs in and out meet at %.0f°, so runners leaving show the control for %s beyond the first %s",
      issue.at, issue.angle, m(issue.metres), m(rule.sight))
  elseif issue.kind == "tooClose" then
    return string.format("%s and %s are %s apart: closer than the %s minimum", issue.a, issue.b, m(issue.metres), m(rule.minimum))
  elseif issue.kind == "sameFeature" then
    return string.format("%s and %s are both on a %s only %s apart (under %s, they need different features)",
      issue.a, issue.b, issue.feature, m(issue.metres), m(rule.distinct))
  elseif issue.kind == "passBy" then
    return string.format("leg %d (%s to %s) passes %s from %s, within sight", issue.leg, course.order[issue.leg], course.order[issue.leg + 1], m(issue.metres), issue.at)
  else
    return string.format("legs %d and %d cross", issue.leg, issue.other)
  end
end

function M.text(course, issues, cost, fixed)
  local out = {}
  local function say(s) out[#out + 1] = s end
  local rule = course.sprint and "sprint" or "forest and park"
  local pos = {}
  for code, c in pairs(course.controls) do pos[code] = { x = c.x, y = c.y } end
  local legs, total = Check.legs(course, pos)
  say(string.format("Kitewise: %s", course.title))
  local n = #course.order - 2
  say(string.format("%d control%s, %d legs, %.2f km in straight lines (%s distances)", n, n == 1 and "" or "s", #legs, total / 1000, rule))
  say("")
  local parts = {}
  for k, d in ipairs(legs) do parts[#parts + 1] = string.format("%s-%s %.0f", course.order[k], course.order[k + 1], d) end
  say("Legs (m): " .. table.concat(parts, ", "))
  say("")
  if #issues == 0 then
    say("No dog-legs, crowded controls, pass-bys or crossings. Clean course.")
  else
    say("Problems:")
    for _, issue in ipairs(issues) do say("  - " .. M.describe(issue, course)) end
  end
  if fixed then
    local newPos, before, after, exhaustive, movable = table.unpack(fixed)
    local moves = {}
    for _, mv in ipairs(movable) do
      if mv.at.dx ~= 0 or mv.at.dy ~= 0 then
        moves[#moves + 1] = string.format("  - move %s %s %s (to %.0f, %.0f)", mv.code, m(math.sqrt(mv.at.dx ^ 2 + mv.at.dy ^ 2)), compass(mv.at.dx, mv.at.dy), newPos[mv.code].x, newPos[mv.code].y)
      end
    end
    say("")
    if #movable == 0 then
      say("No control is marked as movable (add \"move 20\" to a control to let Kitewise suggest a better spot).")
    elseif #moves == 0 then
      say("Moving the movable controls within their limits doesn't help.")
    else
      say(string.format("Suggested moves (problem score %.0f -> %.0f%s):", before, after, exhaustive and ", best of every combination" or ""))
      for _, s in ipairs(moves) do say(s) end
      local left = Check.problems(course, newPos)
      if #left > 0 then
        say("Still to fix by hand:")
        for _, issue in ipairs(left) do say("  - " .. M.describe(issue, course)) end
      end
    end
  end
  return table.concat(out, "\n") .. "\n"
end

return M
