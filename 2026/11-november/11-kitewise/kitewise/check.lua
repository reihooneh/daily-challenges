-- Finds what gives a course away or breaks the usual rules, and scores how bad it is.
--
--   Dog-leg: the leg into a control and the leg out of it run close together, so runners leaving
--     show the control to runners arriving. Measured as the stretch (in metres) along which a
--     runner coming in and one going out are within sight distance of each other, beyond the
--     first sight distance: 0 for a clean control, more the worse it is.
--   Too close: two controls nearer than the minimum distance, or on the same kind of feature
--     nearer than the distance at which they could be confused.
--   Pass-by: a leg passes within sight of a control that isn't on that leg.
--   Crossing: two legs cross (allowed, but every crossing makes the map harder to read).
local M = {}

-- Distances in metres, after the usual IOF minimums: forest and park, and sprint.
M.RULES = {
  forest = { sight = 30, minimum = 30, distinct = 60 },
  sprint = { sight = 15, minimum = 15, distinct = 30 },
}

-- What each kind of problem costs when the fixer compares courses.
M.COST = { tooClose = 1000, sameFeature = 500, crossing = 5, passBy = 2 }

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Shortest distance from point p to the segment a-b.
local function toSegment(p, a, b)
  local vx, vy = b.x - a.x, b.y - a.y
  local l2 = vx * vx + vy * vy
  local t = l2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / l2)) or 0
  return math.sqrt((p.x - a.x - t * vx) ^ 2 + (p.y - a.y - t * vy) ^ 2)
end

-- Do segments a-b and c-d cross (properly, not just touch at an end)?
local function crosses(a, b, c, d)
  local function side(p, q, r) return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) end
  local d1, d2 = side(c, d, a), side(c, d, b)
  local d3, d4 = side(a, b, c), side(a, b, d)
  return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

M.dist, M.toSegment, M.crosses = dist, toSegment, crosses

-- The angle at c between the directions to a and to b, in degrees (0 = straight back the same way).
function M.angle(a, c, b)
  local ux, uy, vx, vy = a.x - c.x, a.y - c.y, b.x - c.x, b.y - c.y
  local lu, lv = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
  if lu == 0 or lv == 0 then return 180 end
  local cos = math.max(-1, math.min(1, (ux * vx + uy * vy) / (lu * lv)))
  return math.deg(math.acos(cos))
end

-- How far (metres) runners coming in from a and leaving for b stay within sight of each other,
-- beyond the first `sight` metres that every control has. Two runners the same distance d from
-- the control are 2 d sin(θ/2) apart, so they are within sight until d = sight / (2 sin(θ/2)).
function M.doglegLength(a, c, b, sight)
  local theta = math.rad(M.angle(a, c, b))
  local reach = math.min(dist(a, c), dist(c, b))
  local s = 2 * math.sin(theta / 2)
  local within = s > 0 and math.min(reach, sight / s) or reach
  return math.max(0, within - sight)
end

-- Every problem with the course at these positions (pos[code] = {x, y}), and the total cost.
function M.problems(course, pos)
  local rule = course.sprint and M.RULES.sprint or M.RULES.forest
  local order, issues, cost = course.order, {}, 0
  local function add(issue)
    issues[#issues + 1] = issue
    cost = cost + issue.cost
  end
  for k = 2, #order - 1 do
    local a, c, b = pos[order[k - 1]], pos[order[k]], pos[order[k + 1]]
    local over = M.doglegLength(a, c, b, rule.sight)
    if over > 0.5 then
      add({ kind = "dogleg", at = order[k], index = k, metres = over, angle = M.angle(a, c, b), cost = over })
    end
  end
  local codes = {}
  for code in pairs(course.controls) do codes[#codes + 1] = code end
  table.sort(codes)
  local used = {}
  for _, code in ipairs(order) do used[code] = true end
  for i = 1, #codes do
    for j = i + 1, #codes do
      local p, q = codes[i], codes[j]
      if used[p] and used[q] then
        local d = dist(pos[p], pos[q])
        local cp, cq = course.controls[p], course.controls[q]
        if d < rule.minimum then
          add({ kind = "tooClose", a = p, b = q, metres = d, cost = M.COST.tooClose })
        elseif d < rule.distinct and cp.feature == cq.feature then
          add({ kind = "sameFeature", a = p, b = q, metres = d, feature = cp.feature, cost = M.COST.sameFeature })
        end
      end
    end
  end
  for k = 1, #order - 1 do
    local a, b = pos[order[k]], pos[order[k + 1]]
    for _, code in ipairs(codes) do
      if used[code] and code ~= order[k] and code ~= order[k + 1] then
        local d = toSegment(pos[code], a, b)
        if d < rule.sight then
          add({ kind = "passBy", at = code, leg = k, metres = d, cost = M.COST.passBy * (rule.sight - d) })
        end
      end
    end
    for m = k + 2, #order - 1 do
      if crosses(a, b, pos[order[m]], pos[order[m + 1]]) then
        add({ kind = "crossing", leg = k, other = m, cost = M.COST.crossing })
      end
    end
  end
  return issues, cost
end

-- Leg lengths and the course's straight-line length.
function M.legs(course, pos)
  local out, total = {}, 0
  for k = 1, #course.order - 1 do
    local d = dist(pos[course.order[k]], pos[course.order[k + 1]])
    out[k] = d
    total = total + d
  end
  return out, total
end

return M
