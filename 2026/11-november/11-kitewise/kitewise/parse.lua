-- Reads a course file: the controls (where they are, what feature, how far the setter may move
-- them) and the order runners visit them.
local M = {}

M.MAX_BYTES = 32 * 1024
M.MAX_LINES = 500
M.MAX_CONTROLS = 60
M.MAX_LEGS = 60

local function fail(line, message)
  error({ input = line > 0 and ("line " .. line .. ": " .. message) or message }, 0)
end

local function number(text, line, lo, hi, what)
  if not text or not text:match("^%-?%d+%.?%d*$") then fail(line, what .. " must be a number") end
  local v = tonumber(text)
  if not v or v < lo or v > hi then fail(line, what .. " must be between " .. lo .. " and " .. hi) end
  return v
end

-- Control codes: S1, F, 31, 100... (letters and digits, up to 6).
local function code(text, line)
  if not text or not text:match("^%w+$") or #text > 6 then
    fail(line, "a control code is 1-6 letters or digits")
  end
  return text
end

-- A feature name: up to 3 lowercase words (boulder, path junction, re-entrant).
local function feature(words, i, line)
  local parts = {}
  while words[i] and words[i]:match("^[a-z][a-z-]*$") and not ({ move = true, start = true, finish = true, at = true })[words[i]] do
    parts[#parts + 1] = words[i]
    i = i + 1
  end
  if #parts == 0 or #parts > 3 then fail(line, "a feature is 1-3 lowercase words") end
  return table.concat(parts, " "), i
end

function M.parse(text)
  if type(text) ~= "string" then fail(0, "the course must be text") end
  if #text > M.MAX_BYTES then fail(0, "the course is larger than 32 KB") end
  if not utf8.len(text) then fail(0, "the course is not valid UTF-8") end
  -- Control characters, and the invisible marks that can reorder text on screen.
  if text:find("[%z\1-\8\11-\31\127]") or text:find("\226\128[\139-\143\170-\174]") or text:find("\226\129[\166-\169]") then
    fail(0, "the course contains control or invisible formatting characters")
  end
  local course = { title = "Untitled course", sprint = false, controls = {}, order = {}, legs = nil }
  local lines = 0
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines = lines + 1
    if lines > M.MAX_LINES then fail(0, "the course has more than " .. M.MAX_LINES .. " lines") end
    local body = raw:gsub("\r$", ""):gsub("#.*$", "")
    local words = {}
    for w in body:gmatch("%S+") do words[#words + 1] = w end
    local key = words[1]
    if key == nil then
      -- blank
    elseif key == "title" or key == "title:" then
      local t = body:match("^%s*title:?%s*(.-)%s*$")
      if not t:match("^[%w ',.&()%-]+$") or #t > 60 then fail(lines, "a title is 1-60 letters, digits, spaces and simple punctuation") end
      course.title = t
    elseif key == "sprint" then
      if #words ~= 1 then fail(lines, "sprint takes no values") end
      course.sprint = true
    elseif key == "control" then
      local c = { code = code(words[2], lines), line = lines, move = 0 }
      if course.controls[c.code] then fail(lines, "control " .. c.code .. " is already defined") end
      local n = 0
      for _ in pairs(course.controls) do n = n + 1 end
      if n >= M.MAX_CONTROLS then fail(lines, "at most " .. M.MAX_CONTROLS .. " controls") end
      local i = 3
      while words[i] do
        local w = words[i]
        if w == "at" then
          c.x = number(words[i + 1], lines, -10000, 10000, "x")
          c.y = number(words[i + 2], lines, -10000, 10000, "y")
          i = i + 3
        elseif w == "feature" then
          c.feature, i = feature(words, i + 1, lines)
        elseif w == "move" then
          c.move = number(words[i + 1], lines, 0, 100, "move")
          i = i + 2
        elseif w == "start" or w == "finish" then
          c.kind = w
          i = i + 1
        else
          fail(lines, "unexpected word " .. (i - 1) .. " (expected at, feature, move, start or finish)")
        end
      end
      if not c.x then fail(lines, "give its position: at X Y (metres)") end
      c.feature = c.feature or (c.kind or "control")
      course.controls[c.code] = c
    elseif key == "course" then
      if course.legs then fail(lines, "only one course per file") end
      course.legs = {}
      for k = 2, #words do
        if #course.order >= M.MAX_LEGS + 1 then fail(lines, "at most " .. M.MAX_LEGS .. " legs") end
        course.order[#course.order + 1] = code(words[k], lines)
      end
      course.orderLine = lines
    else
      fail(lines, "unknown line (use title, sprint, control or course)")
    end
  end
  if not course.legs then fail(0, "no course: add a line like \"course S 31 32 F\"") end
  if #course.order < 3 then fail(course.orderLine, "a course visits at least 3 controls") end
  for k, c in ipairs(course.order) do
    if not course.controls[c] then fail(course.orderLine, "control " .. c .. " is not defined") end
    if k > 1 and course.order[k - 1] == c then fail(course.orderLine, "control " .. c .. " follows itself") end
  end
  return course
end

return M
