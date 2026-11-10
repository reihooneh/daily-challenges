-- Suggests where to move controls the setter has said may move, to clear the problems.
--
-- Each movable control may go anywhere on a 5 m grid within its move radius (the setter knows
-- the terrain has other suitable features there). When the number of combinations is small the
-- fixer tries every one; otherwise it moves one control at a time to its best spot, over and over,
-- until nothing improves.
local Check = require("kitewise.check")

local M = {}

M.STEP = 5
M.EXHAUSTIVE = 20000 -- combinations tried exhaustively
M.ROUNDS = 20

local function candidates(c)
  local out = { { x = c.x, y = c.y, dx = 0, dy = 0 } }
  local r = c.move
  local n = math.floor(r / M.STEP)
  for i = -n, n do
    for j = -n, n do
      local dx, dy = i * M.STEP, j * M.STEP
      if (i ~= 0 or j ~= 0) and dx * dx + dy * dy <= r * r + 1e-9 then
        out[#out + 1] = { x = c.x + dx, y = c.y + dy, dx = dx, dy = dy }
      end
    end
  end
  return out
end

M.candidates = candidates

-- Cost of a layout, plus a tiny pull towards the setter's original spots, so a move is only
-- suggested when it helps and is no bigger than it needs to be.
local function score(course, pos, movable)
  local _, cost = Check.problems(course, pos)
  local moved = 0
  for _, m in ipairs(movable) do
    moved = moved + math.sqrt(m.at.dx ^ 2 + m.at.dy ^ 2)
  end
  return cost + 0.001 * moved
end

-- Returns new positions, the cost before and after, and whether every combination was tried.
function M.fix(course)
  local pos = {}
  for code, c in pairs(course.controls) do pos[code] = { x = c.x, y = c.y } end
  local movable = {}
  local seen = {}
  for _, code in ipairs(course.order) do
    local c = course.controls[code]
    if c.move > 0 and not seen[code] then
      seen[code] = true
      local cands = candidates(c)
      movable[#movable + 1] = { code = code, cands = cands, at = cands[1] }
    end
  end
  table.sort(movable, function(a, b) return a.code < b.code end)
  local _, before = Check.problems(course, pos)
  if #movable == 0 then return pos, before, before, true, movable end

  local combos = 1
  for _, m in ipairs(movable) do
    combos = combos * #m.cands
    if combos > M.EXHAUSTIVE then break end
  end
  local function place(m, cand)
    m.at = cand
    pos[m.code] = { x = cand.x, y = cand.y }
  end

  local exhaustive = combos <= M.EXHAUSTIVE
  if exhaustive then
    local best, bestAt = math.huge, nil
    local function walk(i)
      if i > #movable then
        local s = score(course, pos, movable)
        if s < best - 1e-9 then
          best = s
          bestAt = {}
          for k, m in ipairs(movable) do bestAt[k] = m.at end
        end
        return
      end
      for _, cand in ipairs(movable[i].cands) do
        place(movable[i], cand)
        walk(i + 1)
      end
    end
    walk(1)
    for k, m in ipairs(movable) do place(m, bestAt[k]) end
  else
    local current = score(course, pos, movable)
    for _ = 1, M.ROUNDS do
      local improved = false
      for _, m in ipairs(movable) do
        local keep = m.at
        local bestCand, best = keep, current
        for _, cand in ipairs(m.cands) do
          place(m, cand)
          local s = score(course, pos, movable)
          if s < best - 1e-9 then bestCand, best = cand, s end
        end
        place(m, bestCand)
        if best < current - 1e-9 then current, improved = best, true end
      end
      if not improved then break end
    end
  end
  local _, after = Check.problems(course, pos)
  return pos, before, after, exhaustive, movable
end

return M
