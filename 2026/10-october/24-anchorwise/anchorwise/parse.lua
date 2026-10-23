-- Reads an anchor file strictly. Every line has a fixed form, every number a range, and errors
-- name the line without repeating it.
--
--   anchor Two bolts on the belay ledge
--   load 2.5 kN              (straight down)   or   load 2.5 kN at 15   (15 degrees right of down)
--   rigging fixed nylon      fixed (cordelette, tied off) or sliding (sliding X, quad style)
--   master 0 -0.6            fixed: where the master point is tied, metres
--   sling 1.6                sliding: total sling length running through the pieces, metres
--   limit 0.15               sliding, optional: extension limiter knots, metres from the master point
--   piece Left bolt -0.25 0  name, then x (right) and y (up) in metres
--   piece Right cam 0.4 -0.05 slack 0.02     fixed, optional: this arm was tied 2 cm long

local P = {}

P.MAX_BYTES = 16 * 1024
P.MAX_LINE = 160
P.MAX_PIECES = 6

-- Approximate stretchiness of each material as EA (kN): force per unit strain.
-- Nylon cord stretches about 5-6% near 4 kN; Dyneema slings about 1.5%; static rope about 3%.
P.MATERIALS = {
  nylon = { ea = 70, name = "nylon cord" },
  dyneema = { ea = 270, name = "Dyneema sling" },
  static = { ea = 140, name = "static rope" },
}

local function fail(n, message)
  error({ input = (n and ("line " .. n .. ": ") or "") .. message }, 0)
end

local function number(text, lo, hi, what, n)
  if not text or #text > 8 or not text:match("^%-?%d+%.?%d*$") then
    fail(n, what .. " must be a plain number")
  end
  local v = tonumber(text)
  if not v or v < lo or v > hi then
    fail(n, string.format("%s must be between %g and %g", what, lo, hi))
  end
  return v
end

local function label(text, n, what)
  if not text or #text == 0 or #text > 40 or not text:match("^[%w][%w %.,'()/-]*$") then
    fail(n, what .. " names are 1-40 letters, digits, spaces and simple punctuation")
  end
  return text
end

function P.parse(text)
  if #text > P.MAX_BYTES then fail(nil, "the anchor file is larger than 16 KB") end
  if utf8.len(text) == nil then fail(nil, "the anchor file is not valid UTF-8 text") end
  local a = { name = "Anchor", pieces = {}, angle = 0 }
  local n = 0
  for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
    n = n + 1
    if #raw > P.MAX_LINE then fail(n, "longer than " .. P.MAX_LINE .. " characters") end
    -- Control characters (terminal escapes) and the Unicode marks that reverse text direction.
    if raw:find("[\0-\8\11-\31\127]") or raw:find("\226\128[\170-\174]") or raw:find("\226\129[\166-\169]")
        or raw:find("\226\128[\142\143]") then
      fail(n, "contains control or hidden direction characters")
    end
    local line = raw:gsub("#.*$", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if line ~= "" then
      local word, rest = line:match("^(%S+)%s*(.*)$")
      if word == "anchor" then
        a.name = label(rest, n, "anchor")
      elseif word == "load" then
        local kn, deg = rest:match("^(%S+) ?kN at (%S+)$")
        if not kn then kn = rest:match("^(%S+) ?kN$") end
        if not kn then fail(n, "write the load as 'load 2.5 kN' or 'load 2.5 kN at 15'") end
        a.load = number(kn, 0.1, 25, "load", n)
        if deg then a.angle = number(deg, -60, 60, "load angle", n) end
      elseif word == "rigging" then
        local kind, mat = rest:match("^(%a+) (%a+)$")
        if not kind or (kind ~= "fixed" and kind ~= "sliding") or not P.MATERIALS[mat] then
          fail(n, "rigging is 'fixed' or 'sliding' followed by nylon, dyneema or static")
        end
        a.rigging, a.material = kind, mat
      elseif word == "master" then
        local x, y = rest:match("^(%S+) (%S+)$")
        if not x then fail(n, "write the master point as 'master X Y'") end
        a.master = { number(x, -5, 5, "x", n), number(y, -5, 5, "y", n) }
      elseif word == "sling" then
        a.sling = number(rest, 0.1, 10, "sling length", n)
      elseif word == "limit" then
        a.limit = number(rest, 0.01, 2, "limiter distance", n)
      elseif word == "piece" then
        if #a.pieces >= P.MAX_PIECES then fail(n, "more than " .. P.MAX_PIECES .. " pieces") end
        local tokens = {}
        for t in rest:gmatch("%S+") do tokens[#tokens + 1] = t end
        local slack = 0
        if #tokens >= 5 and tokens[#tokens - 1] == "slack" then
          slack = number(tokens[#tokens], 0, 0.5, "slack", n)
          tokens[#tokens], tokens[#tokens - 1] = nil, nil
        end
        if #tokens < 3 then fail(n, "write a piece as 'piece NAME X Y'") end
        local y = number(tokens[#tokens], -5, 5, "y", n)
        local x = number(tokens[#tokens - 1], -5, 5, "x", n)
        tokens[#tokens], tokens[#tokens - 1] = nil, nil
        local name = label(table.concat(tokens, " "), n, "piece")
        a.pieces[#a.pieces + 1] = { name = name, pos = { x, y }, slack = slack, line = n }
      else
        fail(n, "lines start with anchor, load, rigging, master, sling, limit or piece")
      end
    end
  end
  if not a.load then fail(nil, "the file needs a load line") end
  if not a.rigging then fail(nil, "the file needs a rigging line") end
  if #a.pieces < 2 then fail(nil, "an anchor needs at least two pieces") end
  for i = 1, #a.pieces do
    for j = i + 1, #a.pieces do
      local dx = a.pieces[i].pos[1] - a.pieces[j].pos[1]
      local dy = a.pieces[i].pos[2] - a.pieces[j].pos[2]
      if dx * dx + dy * dy < 1e-4 then fail(a.pieces[j].line, "two pieces are in the same place") end
    end
  end
  if a.rigging == "fixed" then
    if not a.master then fail(nil, "fixed rigging needs a master line (where the master point is tied)") end
    if a.sling then fail(nil, "sling is for sliding rigging; fixed rigging uses the master point") end
  else
    if not a.sling then fail(nil, "sliding rigging needs a sling line (its total length)") end
    for _, p in ipairs(a.pieces) do
      if p.slack ~= 0 then fail(p.line, "slack is for fixed rigging; a sliding sling evens itself out") end
    end
  end
  if a.limit and a.rigging ~= "sliding" then fail(nil, "limiter knots are for sliding rigging") end
  a.ea = P.MATERIALS[a.material].ea
  -- The load pulls down, turned `angle` degrees towards the right.
  local r = math.rad(a.angle)
  a.dir = { math.sin(r), -math.cos(r) }
  return a
end

return P
