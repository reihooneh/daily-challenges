-- loadorder MOVE.txt: how to load a removal truck for several stops.
--   lua loadorder.lua examples/move.txt      (or: python3 tools/lua.py loadorder.lua examples/move.txt)
local parse = require("loadorder.parse")
local planner = require("loadorder.plan")

local R = {}

local function pct(x) return string.format("%d%%", math.floor(x * 100 + 0.5)) end

function R.diagram(move, p)
  local width = 60
  local scale = width / move.truck.length
  local cells = {}
  for i = 1, width do cells[i] = "." end
  for _, t in ipairs(p.tiers) do
    local a, b = math.floor(t.from * scale) + 1, math.floor(t.to * scale + 0.5)
    for i = a, math.min(b, width) do cells[i] = string.char(64 + t.stop) end
    if b <= width and b >= a then cells[b] = "|" end
  end
  local cog = math.floor(p.balance * width + 0.5)
  local marker = string.rep(" ", math.max(0, cog - 1)) .. "^ balance " .. pct(p.balance)
  return "  cab [" .. table.concat(cells) .. "] door\n        " .. marker
end

function R.report(move, p, alt)
  local out = {}
  local add = function(s) out[#out + 1] = s end
  add(string.format("%d items, %.0f kg, into a %.1f m truck. Stops in order:", #move.items, p.kg, move.truck.length))
  for i, idx in ipairs(p.order) do
    add(string.format("  %d. %s (%s)", i, move.stops[idx].name, string.char(64 + idx)))
  end
  add("")
  add(R.diagram(move, p))
  add("")
  add("Load from the cab back (each line is a wall, bottom first):")
  for i, t in ipairs(p.tiers) do
    -- Group copies ("Book boxes x8") in the order they're stacked.
    local names, seen = {}, {}
    for _, it in ipairs(t.items) do
      if seen[it.base] then
        seen[it.base].n = seen[it.base].n + 1
      else
        seen[it.base] = { n = 1, fragile = it.fragile }
        names[#names + 1] = it.base
      end
    end
    for i2, b in ipairs(names) do
      local s2 = seen[b]
      names[i2] = b .. (s2.n > 1 and (" x" .. s2.n) or "") .. (s2.fragile and " (fragile, on top)" or "")
    end
    add(string.format("  %2d. %s  %.2f-%.2f m  %3.0f kg  %s", i, string.char(64 + t.stop), t.from, t.to, t.kg, table.concat(names, ", ")))
  end
  add("")
  add(string.format("Truck used: %.2f of %.2f m. Load balance %s from the cab (aim for %s to %s).", math.min(p.used, move.truck.length),
    move.truck.length, pct(p.balance), pct(move.balance[1]), pct(move.balance[2])))
  for _, it in ipairs(p.too_big) do add("! " .. it.name .. " doesn't fit through the truck's width and height at all.") end
  if #p.overflow > 0 then
    local n = 0
    for _, t in ipairs(p.overflow) do n = n + #t.items end
    add(string.format("! %d item%s %s fit: %.2f m over. Take a second trip or a bigger truck.", n, n == 1 and "" or "s",
      n == 1 and "doesn't" or "don't", p.used - move.truck.length))
  end
  if not p.balanced then
    add(p.balance > move.balance[2] and "! Too much weight near the door: the front wheels will be light." or
      "! Too much weight over the cab: the front axle may be overloaded.")
  end
  if alt then
    local names = {}
    for _, idx in ipairs(alt.order) do names[#names + 1] = move.stops[idx].name end
    add(string.format("\nVisiting the stops in this order instead fits and balances (%s): %s.", pct(alt.balance), table.concat(names, " then ")))
  end
  return table.concat(out, "\n")
end

function R.main(argv)
  local path = argv[1]
  if not path or argv[2] then
    io.stderr:write("usage: loadorder MOVE.txt\n")
    return 2
  end
  local f = io.open(path, "rb")
  if not f then
    io.stderr:write("loadorder: can't open the file\n")
    return 2
  end
  local text = f:read(parse.MAX_BYTES + 1)
  f:close()
  if not text then
    io.stderr:write("loadorder: the move must be a text file\n")
    return 2
  end
  local move, err = parse.parse(text)
  if not move then
    io.stderr:write("loadorder: " .. err .. "\n")
    return 2
  end
  local plan, alt = planner.best(move)
  print(R.report(move, plan, alt))
  return 0
end

local script = arg and arg[0] or ""
if script == "loadorder.lua" or script:match("[/\\]loadorder%.lua$") then os.exit(R.main({ table.unpack(arg, 1) })) end
return R
