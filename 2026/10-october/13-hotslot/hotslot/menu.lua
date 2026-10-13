-- Reads a menu file: when to serve, the oven, and each dish's temperature and timings.
-- Every check raises { input = "message" }; messages never repeat the input.

local M = {}

M.MAX_BYTES = 8192
M.MAX_DISHES = 15
M.MAX_LINE = 200
M.ROOM = 20 -- degrees C: a cold oven

local function fail(message)
  error({ input = message }, 0)
end

local function whole(text, low, high, what, where)
  if not text or not text:match("^%d+$") or #text > 4 then
    fail(where .. ": " .. what .. " must be a whole number")
  end
  local n = tonumber(text)
  if n < low or n > high then
    fail(where .. ": " .. what .. " must be from " .. low .. " to " .. high)
  end
  return n
end

-- "13:00" -> minutes after midnight
function M.clock(text, where)
  local h, m = (text or ""):match("^(%d%d?):(%d%d)$")
  if not h or tonumber(h) > 23 or tonumber(m) > 59 then
    fail(where .. ": serve time must look like 18:30")
  end
  return tonumber(h) * 60 + tonumber(m)
end

local function parseDish(rest, where, menu)
  local name, spec = rest:match("^(.-)%s*:%s*(.+)$")
  if not name or name == "" then
    fail(where .. ": write a dish as 'dish Name: 180C +-10, 45 min'")
  end
  if #name > 40 or not name:match("^[%w][%w %-&'/]*$") then
    fail(where .. ": a dish name must be up to 40 letters, digits, spaces or - & ' /")
  end
  local dish = { name = name, rest = 0, hold = 0, shelves = 1 }
  local parts = {}
  for part in (spec .. ","):gmatch("%s*(.-)%s*,") do
    parts[#parts + 1] = part
  end
  if #parts < 2 or #parts > 6 then
    fail(where .. ": a dish needs a temperature and a cooking time")
  end
  local temp, tol = parts[1]:match("^(%d+)%s*C%s*%+%-%s*(%d+)$")
  if not temp then
    temp = parts[1]:match("^(%d+)%s*C$")
    tol = "0"
  end
  if not temp then
    fail(where .. ": the temperature must look like 180C or 180C +-10")
  end
  dish.temp = whole(temp, 50, 280, "the temperature", where)
  dish.tolerance = whole(tol, 0, 50, "the tolerance", where)
  dish.cook = whole(parts[2]:match("^(%d+)%s*min$"), 5, 300, "the cooking time (in min)", where)
  local seen = {}
  for i = 3, #parts do
    local key, value = parts[i]:match("^(%a+)%s+(%d+)$")
    if not key or not (key == "rest" or key == "hold" or key == "shelves") or seen[key] then
      fail(where .. ": after the cooking time, use rest N, hold N or shelves N, once each")
    end
    seen[key] = true
    if key == "shelves" then
      dish.shelves = whole(value, 1, 4, "shelves", where)
    else
      dish[key] = whole(value, 0, key == "rest" and 120 or 240, key, where)
    end
  end
  return dish
end

function M.parse(text)
  if #text > M.MAX_BYTES then fail("the menu is larger than 8 KB") end
  -- The only non-ASCII allowed: the plus-minus and degree signs, turned into plain text.
  text = text:gsub("\194\177", "+-"):gsub("\194\176", "")
  if text:find("[^\t\n\r\32-\126]") then
    fail("the menu has a control character or a character that is not plain text")
  end
  local menu = { shelves = 2, heats = 15, cools = 5, dishes = {} }
  local seen = {}
  local n = 0
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    local where = "line " .. n
    if #line > M.MAX_LINE then fail(where .. " is longer than " .. M.MAX_LINE .. " characters") end
    line = line:gsub("#.*$", ""):match("^%s*(.-)%s*$")
    if line ~= "" then
      local word, rest = line:match("^(%a+)%s*(.*)$")
      if word == "dish" then
        if #menu.dishes >= M.MAX_DISHES then fail("the menu has more than " .. M.MAX_DISHES .. " dishes") end
        local dish = parseDish(rest, where, menu)
        if seen[dish.name:lower()] then fail(where .. ": two dishes have the same name") end
        seen[dish.name:lower()] = true
        menu.dishes[#menu.dishes + 1] = dish
      elseif word == "serve" then
        menu.serve = M.clock(rest, where)
      elseif word == "oven" then
        menu.shelves = whole((rest:match("^(%d+)%s+shelves$") or rest:match("^(%d+)%s+shelf$")), 1, 4, "oven N shelves", where)
      elseif word == "heats" or word == "cools" then
        menu[word] = whole(rest:match("^(%d+)%s+per%s+min"), 1, 40, word .. " N per min", where)
      else
        fail(where .. ": start the line with dish, serve, oven, heats or cools")
      end
    end
  end
  if not menu.serve then fail("the menu needs a line like 'serve 18:30'") end
  if #menu.dishes == 0 then fail("the menu has no dishes") end
  for _, d in ipairs(menu.dishes) do
    if d.shelves > menu.shelves then fail("a dish needs more shelves than the oven has") end
  end
  return menu
end

return M
