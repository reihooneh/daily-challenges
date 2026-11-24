-- Reading a move: the truck, the stops in the order you'll visit them, and the items.
local M = {}

M.MAX_BYTES = 32 * 1024
M.MAX_ITEMS = 400 -- after expanding "x12"
M.MAX_STOPS = 6

local function fail(line, msg)
  error({ line = line, msg = msg }, 0)
end

-- A number with optional decimals, within a range.
local function number(s, lo, hi, line, what)
  if not s or not s:match("^%d+%.?%d*$") then fail(line, what .. " must be a number") end
  local v = tonumber(s)
  if not v or v < lo or v > hi then fail(line, string.format("%s must be between %g and %g", what, lo, hi)) end
  return v
end

-- Splits a line into words, keeping "quoted names" together. Only printable ASCII and UTF-8 letters.
local function words(text, line)
  local out, i, n = {}, 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c == " " or c == "\t" then
      i = i + 1
    elseif c == '"' then
      local j = text:find('"', i + 1, true)
      if not j then fail(line, "a name is missing its closing quote") end
      out[#out + 1] = { text = text:sub(i + 1, j - 1), quoted = true }
      i = j + 1
    else
      local j = i
      while j <= n and not text:sub(j, j):match("[ \t]") do j = j + 1 end
      out[#out + 1] = { text = text:sub(i, j - 1) }
      i = j
    end
  end
  return out
end

local function name(w, line, what)
  if not w or #w.text < 1 or #w.text > 40 or w.text:find("[%c\"<>]") then
    fail(line, what .. " must be a short name in quotes")
  end
  return w.text
end

function M.parse(text)
  if #text > M.MAX_BYTES then return nil, "the file is larger than 32 KB" end
  local move = { stops = {}, items = {}, balance = { 0.30, 0.55 }, fill = 0.85 }
  local stop_ids = {}
  local ok, err = pcall(function()
    local line = 0
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
      line = line + 1
      if #raw > 300 then fail(line, "the line is too long") end
      if raw:find("[%z\1-\8\11-\31\127]") and not raw:find("^%s*#") then fail(line, "the line has a control character") end
      local body = raw:gsub("#.*$", ""):gsub("\r$", "")
      local w = words(body, line)
      local key = w[1] and w[1].text
      if not key then
        -- blank
      elseif key == "truck" then
        move.truck = {
          length = number(w[2] and w[2].text, 1, 20, line, "truck length"),
          width = number(w[3] and w[3].text, 1, 3, line, "truck width"),
          height = number(w[4] and w[4].text, 1, 3, line, "truck height"),
        }
      elseif key == "balance" then
        local lo = number(w[2] and w[2].text, 0.1, 0.9, line, "balance from")
        local hi = number(w[3] and w[3].text, 0.1, 0.9, line, "balance to")
        if hi <= lo then fail(line, "balance must go from front to back") end
        move.balance = { lo, hi }
      elseif key == "stop" then
        local id = w[2] and w[2].text or ""
        if not id:match("^[%a][%w-]*$") or #id > 20 then fail(line, "a stop needs a short id like home") end
        if stop_ids[id] then fail(line, "stop " .. id .. " appears twice") end
        if #move.stops >= M.MAX_STOPS then fail(line, "at most " .. M.MAX_STOPS .. " stops") end
        move.stops[#move.stops + 1] = { id = id, name = name(w[3], line, "the stop's address") }
        stop_ids[id] = #move.stops
      elseif key == "item" then
        if not (w[2] and w[2].quoted) then fail(line, "an item needs a name in quotes") end
        local item = {
          name = name(w[2], line, "the item"),
          dims = {
            number(w[3] and w[3].text, 0.05, 3, line, "the item's first size"),
            number(w[4] and w[4].text, 0.05, 3, line, "the item's second size"),
            number(w[5] and w[5].text, 0.05, 3, line, "the item's height"),
          },
          kg = number(w[6] and w[6].text, 0.1, 500, line, "the item's weight in kg"),
        }
        local count, i = 1, 7
        while w[i] and w[i].text ~= "->" do
          local t = w[i].text
          if t == "upright" then item.upright = true
          elseif t == "fragile" then item.fragile = true
          elseif t:match("^x%d+$") then count = number(t:sub(2), 1, 100, line, "the count")
          else fail(line, "unknown word '" .. t:gsub("[^%w]", "") .. "' (use upright, fragile or x3)") end
          i = i + 1
        end
        local dest = w[i + 1] and w[i + 1].text
        if not dest or not stop_ids[dest] then fail(line, "say where it goes: -> and a stop id") end
        if w[i + 2] then fail(line, "unexpected text after the stop") end
        item.stop = stop_ids[dest]
        for k = 1, count do
          local copy = {}
          for key2, v in pairs(item) do copy[key2] = v end
          copy.base = item.name
          if count > 1 then copy.name = item.name .. " " .. k end
          move.items[#move.items + 1] = copy
          if #move.items > M.MAX_ITEMS then fail(line, "more than " .. M.MAX_ITEMS .. " items") end
        end
      else
        fail(line, "unknown keyword (use truck, balance, stop or item)")
      end
    end
    if not move.truck then fail(0, "the move needs a truck line") end
    if #move.stops == 0 then fail(0, "the move needs at least one stop") end
    if #move.items == 0 then fail(0, "the move needs at least one item") end
  end)
  if not ok then
    if type(err) == "table" then
      return nil, (err.line > 0 and ("line " .. err.line .. ": ") or "") .. err.msg
    end
    return nil, "couldn't read the move"
  end
  return move
end

return M
