-- The trick file: a deck size, then the steps of the trick, then what it promises.
-- Every line has a fixed shape and every number a range. Errors are tables { input = message }
-- that give the line number and what was expected, never the line itself.

local M = {}

M.MAX_BYTES = 16 * 1024
M.MAX_LINE = 200
M.MAX_STEPS = 2000 -- after repeats are unrolled
M.MAX_DECK = 104
M.MAX_DEPTH = 4

local function fail(line, message)
  error({ input = line > 0 and ("line " .. line .. ": " .. message) or message }, 0)
end

local function int(text, line, what, lo, hi)
  if not text or not text:match("^%d+$") or #text > 6 then fail(line, what .. " must be a whole number") end
  local v = tonumber(text)
  if v < lo or v > hi then fail(line, what .. " must be from " .. lo .. " to " .. hi) end
  return v
end

local NAME = "^%a[%w_]?[%w_]?[%w_]?[%w_]?[%w_]?[%w_]?[%w_]?$" -- a letter, then up to 7 letters, digits or _

-- A count: a number, or the name of a number the spectator chose.
local function amount(text, line, vars, deck)
  if text and text:match("^%d+$") then return { n = int(text, line, "a count", 0, deck) } end
  if text and text:match(NAME) and vars[text] == "number" then return { var = text } end
  fail(line, "a count is a number or a number the spectator chose (see 'choose number')")
end

local function card(text, line, vars)
  if text and vars[text] == "card" then return text end
  fail(line, "that names no chosen card (use 'choose card X' first)")
end

local function hidden(s)
  if s:find("[%z\1-\8\11-\31\127]") then return true end
  -- Invisible Unicode formatting characters: zero-width, direction marks and overrides, BOM.
  return s:find("\226\128[\139-\143\170-\174]") or s:find("\226\129[\160-\175]") or s:find("\239\187\191")
end

function M.parse(text)
  if #text > M.MAX_BYTES then fail(0, "the trick file is larger than 16 KB") end
  if not utf8.len(text) then fail(0, "the trick file is not valid UTF-8 text") end
  local trick = { title = "A card trick", deck = nil, steps = {}, expects = {} }
  local vars = {}
  local stack = { { steps = trick.steps, times = 1 } }
  local n = 0
  local seenTitle = false
  for raw in (text .. "\n"):gmatch("(.-)\n") do
    n = n + 1
    raw = raw:gsub("\r$", "")
    if utf8.len(raw) > M.MAX_LINE then fail(n, "is longer than " .. M.MAX_LINE .. " characters") end
    if hidden(raw:gsub("\t", " ")) then fail(n, "contains a control or invisible formatting character") end
    local line = raw:gsub("#.*$", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if line ~= "" then
      local w = {}
      for word in line:gmatch("%S+") do w[#w + 1] = word end
      local head = w[1]
      local steps = stack[#stack].steps
      if head == "trick" then
        local name = line:sub(7)
        if seenTitle or not name:match("^[%w][%w %.,'&()!%-]*$") or #name > 60 then
          fail(n, "the trick's name comes once: letters, digits, spaces and . , ' & ( ) ! - (up to 60)")
        end
        trick.title, seenTitle = name, true
      elseif head == "deck" then
        if trick.deck then fail(n, "'deck' comes once") end
        trick.deck = int(w[2], n, "the deck size", 2, M.MAX_DECK)
      elseif not trick.deck then
        fail(n, "say how many cards first, like 'deck 21'")
      elseif head == "choose" and w[2] == "card" and #w == 3 then
        if not w[3]:match(NAME) or vars[w[3]] then fail(n, "name the card with a new short name, like 'choose card X'") end
        vars[w[3]] = "card"
        steps[#steps + 1] = { op = "choose_card", name = w[3], line = n }
      elseif head == "choose" and w[2] == "number" and #w == 4 then
        local lo, hi = w[4]:match("^(%d+)%.%.(%d+)$")
        if not w[3]:match(NAME) or vars[w[3]] or not lo then fail(n, "write it like 'choose number k 1..10'") end
        lo, hi = int(lo, n, "the smallest number", 0, trick.deck), int(hi, n, "the largest number", 0, trick.deck)
        if lo > hi then fail(n, "the smallest number comes first") end
        vars[w[3]] = "number"
        steps[#steps + 1] = { op = "choose_number", name = w[3], lo = lo, hi = hi, line = n }
      elseif head == "cut" and #w == 2 then
        if w[2] == "any" then steps[#steps + 1] = { op = "cut_any", line = n }
        else steps[#steps + 1] = { op = "cut", count = amount(w[2], n, vars, trick.deck), line = n } end
      elseif head == "deal" and #w == 2 then
        steps[#steps + 1] = { op = "deal", count = amount(w[2], n, vars, trick.deck), line = n }
      elseif head == "deal-under" and #w == 2 then
        steps[#steps + 1] = { op = "deal_under", count = amount(w[2], n, vars, trick.deck), line = n }
      elseif head == "piles" and (#w == 2 or (#w == 3 and w[3] == "faceup")) then
        steps[#steps + 1] = { op = "piles", k = int(w[2], n, "the number of piles", 2, 13), faceup = w[3] == "faceup", line = n }
      elseif head == "pick" and #w == 2 then
        steps[#steps + 1] = { op = "pick", name = card(w[2], n, vars), line = n }
      elseif head == "gather" and (#w == 1 or #w == 2) then
        local at = w[2] and (({ top = "top", middle = "middle", bottom = "bottom" })[w[2]] or int(w[2], n, "the picked pile's place", 1, 13))
        steps[#steps + 1] = { op = "gather", at = at, line = n }
      elseif head == "faro" and #w == 2 and (w[2] == "out" or w[2] == "in") then
        steps[#steps + 1] = { op = "faro", out = w[2] == "out", line = n }
      elseif head == "reverse" and #w == 1 then
        steps[#steps + 1] = { op = "reverse", line = n }
      elseif head == "repeat" and #w == 2 then
        if #stack > M.MAX_DEPTH then fail(n, "repeats nest at most " .. M.MAX_DEPTH .. " deep") end
        local block = { steps = {}, times = int(w[2], n, "a repeat count", 1, 200), line = n }
        steps[#steps + 1] = { op = "repeat", block = block, line = n }
        stack[#stack + 1] = block
      elseif head == "end" and #w == 1 then
        if #stack == 1 then fail(n, "'end' without a 'repeat'") end
        stack[#stack] = nil
      elseif head == "expect" and #w == 2 and w[2] == "original" then
        trick.expects[#trick.expects + 1] = { kind = "original", line = n }
      elseif head == "expect" and #w >= 3 then
        local name = card(w[2], n, vars)
        local where
        if w[3] == "on" and w[4] == "top" and #w == 4 then where = { n = 1 }
        elseif w[3] == "on" and w[4] == "bottom" and #w == 4 then where = { bottom = true }
        elseif w[3] == "at" and #w == 4 then
          where = w[4]:match("^%d+$") and { n = int(w[4], n, "a position", 1, trick.deck) } or amount(w[4], n, vars, trick.deck)
        else fail(n, "write it like 'expect X at 11', 'expect X on top' or 'expect original'") end
        trick.expects[#trick.expects + 1] = { kind = "card", name = name, where = where, line = n }
      else
        fail(n, "lines are trick, deck, choose, cut, deal, deal-under, piles, pick, gather, faro, reverse, repeat, end or expect")
      end
    end
  end
  if not trick.deck then fail(0, "the trick needs a 'deck' line") end
  if #stack > 1 then fail(stack[#stack].line, "this 'repeat' has no 'end'") end
  if #trick.expects == 0 then fail(0, "the trick needs at least one 'expect' line: what does it promise?") end

  -- Unroll the repeats into one flat list of steps, with a limit so a file can't explode.
  local flat = {}
  local function unroll(steps)
    for _, s in ipairs(steps) do
      if s.op == "repeat" then
        for _ = 1, s.block.times do unroll(s.block.steps) end
      else
        flat[#flat + 1] = s
        if #flat > M.MAX_STEPS then fail(s.line, "the trick has more than " .. M.MAX_STEPS .. " steps once repeats are counted") end
      end
    end
  end
  unroll(trick.steps)
  trick.flat = flat
  return trick
end

return M
