-- The verdict: does the trick always work, and if not, a case where it fails.

local M = {}

local function ordinal(n)
  local s = "th"
  if n % 100 < 11 or n % 100 > 13 then s = ({ "st", "nd", "rd" })[n % 10] or "th" end
  return n .. s
end

function M.render(trick, r)
  local out = {}
  local function add(fmt, ...) out[#out + 1] = string.format(fmt, ...) end
  add("DECKPROOF  %s", trick.title)
  add("%d cards, %d steps once repeats are counted.", trick.deck, #trick.flat)
  add("")
  if r.limit then
    add("Stopped after %d cases (the limit): the trick has too many choices to check them all.", r.cases)
    add("")
  end
  if r.passed == r.cases and not r.limit then
    add("WORKS EVERY TIME: all %d possible case%s checked, and every promise holds.", r.cases, r.cases == 1 and "" or "s")
  else
    add("FAILS in %d of %d cases (works %d%% of the time).", r.cases - r.passed, r.cases, math.floor(100 * r.passed / math.max(1, r.cases) + 0.5))
    for i, f in ipairs(r.failures) do
      add("")
      add("Failing case %d:", i)
      for _, t in ipairs(f.trail) do add("  - %s", t) end
      add("  => %s", f.reason)
    end
  end

  local positions = {}
  for p in pairs(r.ends) do positions[#positions + 1] = p end
  table.sort(positions)
  if #positions > 0 then
    add("")
    if #positions == 1 then
      add("The chosen card always ends %s from the top.", ordinal(positions[1]))
    else
      add("Where the chosen card ends (position: cases):")
      local parts = {}
      for _, p in ipairs(positions) do parts[#parts + 1] = string.format("%d: %d", p, r.ends[p]) end
      -- Wrap the list at about 70 characters.
      local line = " "
      for _, part in ipairs(parts) do
        if #line + #part + 3 > 72 then
          add("%s", line)
          line = " "
        end
        line = line .. "  " .. part
      end
      add("%s", line)
    end
  end
  return table.concat(out, "\n") .. "\n"
end

return M
