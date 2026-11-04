-- Plays the trick for every choice the spectator could make and checks every promise.
-- The deck is a list of card numbers, top card first. Choices (a card, a number, a free cut)
-- branch the run; everything else is a permutation of the list.

local M = {}

M.MAX_CASES = 2000000

local function copy(t)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  return c
end

local function clone(s)
  local piles
  if s.piles then
    piles = {}
    for i, p in ipairs(s.piles) do piles[i] = copy(p) end
  end
  local vars = {}
  for k, v in pairs(s.vars) do vars[k] = v end
  local trail = copy(s.trail)
  return { deck = copy(s.deck), piles = piles, picked = s.picked, vars = vars, trail = trail }
end

local function value(count, s)
  if count.n then return count.n end
  return s.vars[count.var]
end

local function oops(message) error({ case = message }, 0) end

-- Moves the top c cards to the bottom.
function M.cut(deck, c)
  local n = #deck
  local out = {}
  for i = 1, n do out[i] = deck[(i + c - 1) % n + 1] end
  return out
end

-- Perfect shuffle. An out-faro keeps the top card on top; an in-faro moves it to second.
function M.faro(deck, out)
  local n = #deck
  if n % 2 == 1 then oops("a perfect shuffle needs an even number of cards") end
  local half = n // 2
  local r = {}
  for i = 1, half do
    local a, b = deck[i], deck[half + i]
    if out then r[2 * i - 1], r[2 * i] = a, b else r[2 * i - 1], r[2 * i] = b, a end
  end
  return r
end

-- Deals the whole deck into k piles, round the piles in turn. Face down, each card lands on top
-- of its pile, so a pile ends up in reverse order; face up (overlapping columns) keeps the order.
function M.piles(deck, k, faceup)
  local piles = {}
  for i = 1, k do piles[i] = {} end
  for i, c in ipairs(deck) do
    local p = piles[(i - 1) % k + 1]
    if faceup then p[#p + 1] = c else table.insert(p, 1, c) end
  end
  return piles
end

-- Stacks the piles into one deck. The picked pile goes at place `at` (counting from the top);
-- the others keep their order.
function M.gather(piles, picked, at)
  local k = #piles
  local order = {}
  for i = 1, k do if i ~= picked then order[#order + 1] = i end end
  if picked then
    local place = at == "top" and 1 or at == "bottom" and k or at == "middle" and (k + 1) // 2 or at
    if place > k then oops("there are only " .. k .. " piles") end
    table.insert(order, place, picked)
  end
  local deck = {}
  for _, i in ipairs(order) do
    for _, c in ipairs(piles[i]) do deck[#deck + 1] = c end
  end
  return deck
end

local function step(s, st)
  local op = st.op
  if s.piles and op ~= "pick" and op ~= "gather" then oops("the piles must be gathered before line " .. st.line) end
  if op == "cut" then
    local c = value(st.count, s)
    if c > #s.deck then oops("you can't cut more cards than the deck has") end
    s.deck = M.cut(s.deck, c)
  elseif op == "deal" or op == "deal_under" then
    local c = value(st.count, s)
    if c > #s.deck then oops("you can't deal more cards than the deck has") end
    local top = {}
    for i = c, 1, -1 do top[#top + 1] = s.deck[i] end -- dealt one by one: reversed
    local rest = {}
    for i = c + 1, #s.deck do rest[#rest + 1] = s.deck[i] end
    local deck = {}
    local first, second = top, rest
    if op == "deal_under" then first, second = rest, top end
    for _, x in ipairs(first) do deck[#deck + 1] = x end
    for _, x in ipairs(second) do deck[#deck + 1] = x end
    s.deck = deck
  elseif op == "piles" then
    s.piles = M.piles(s.deck, st.k, st.faceup)
    s.picked = nil
  elseif op == "pick" then
    if not s.piles then oops("there are no piles to pick from at line " .. st.line) end
    local want = s.vars[st.name]
    for i, p in ipairs(s.piles) do
      for _, c in ipairs(p) do if c == want then s.picked = i end end
    end
  elseif op == "gather" then
    if not s.piles then oops("there are no piles to gather at line " .. st.line) end
    if st.at and not s.picked then oops("no pile was picked before line " .. st.line) end
    s.deck = M.gather(s.piles, st.at and s.picked or nil, st.at)
    s.piles, s.picked = nil, nil
  elseif op == "faro" then
    s.deck = M.faro(s.deck, st.out)
  elseif op == "reverse" then
    local r = {}
    for i = #s.deck, 1, -1 do r[#r + 1] = s.deck[i] end
    s.deck = r
  end
end

local function position(deck, cardNo)
  for i, c in ipairs(deck) do if c == cardNo then return i end end
end

local function judge(trick, s)
  if s.piles then return false, "the piles were never gathered back into a deck" end
  for _, e in ipairs(trick.expects) do
    if e.kind == "original" then
      for i = 1, trick.deck do
        if s.deck[i] ~= i then return false, "the deck is not back in its original order (card " .. i .. " is not " .. i .. "th)" end
      end
    else
      local at = position(s.deck, s.vars[e.name])
      local want = e.where.bottom and #s.deck or value(e.where, s)
      if at ~= want then return false, string.format("%s ends at position %d, not %d", e.name, at, want), at end
    end
  end
  return true
end

-- Plays every case. Returns { cases, passed, failures = { {trail, reason} ... }, ends = { [pos] = count } }.
function M.run(trick)
  local deck = {}
  for i = 1, trick.deck do deck[i] = i end
  local result = { cases = 0, passed = 0, failures = {}, ends = {}, limit = false }
  local firstCard
  for _, e in ipairs(trick.expects) do if e.kind == "card" then firstCard = firstCard or e.name end end

  local function go(s, i)
    if result.cases >= M.MAX_CASES then
      result.limit = true
      return
    end
    local st = trick.flat[i]
    if not st then
      result.cases = result.cases + 1
      local ok, why = judge(trick, s)
      if ok then result.passed = result.passed + 1
      elseif #result.failures < 3 then result.failures[#result.failures + 1] = { trail = s.trail, reason = why } end
      if firstCard and not s.piles then
        local at = position(s.deck, s.vars[firstCard])
        result.ends[at] = (result.ends[at] or 0) + 1
      end
      return
    end
    if st.op == "choose_card" or st.op == "choose_number" or st.op == "cut_any" then
      local lo, hi
      if st.op == "choose_card" then lo, hi = 1, #s.deck
      elseif st.op == "choose_number" then lo, hi = st.lo, st.hi
      else lo, hi = 0, #s.deck - 1 end
      for v = lo, hi do
        local t = clone(s)
        if st.op == "choose_card" then
          t.vars[st.name] = t.deck[v]
          t.trail[#t.trail + 1] = string.format("%s is the card at position %d", st.name, v)
        elseif st.op == "choose_number" then
          t.vars[st.name] = v
          t.trail[#t.trail + 1] = string.format("%s = %d", st.name, v)
        else
          t.deck = M.cut(t.deck, v)
          t.trail[#t.trail + 1] = string.format("the spectator cuts %d card%s (line %d)", v, v == 1 and "" or "s", st.line)
        end
        go(t, i + 1)
        if result.limit then return end
      end
      return
    end
    local ok, e = pcall(step, s, st)
    if not ok then
      if type(e) ~= "table" or not e.case then error(e, 0) end
      result.cases = result.cases + 1
      if #result.failures < 3 then result.failures[#result.failures + 1] = { trail = s.trail, reason = e.case } end
      return
    end
    go(s, i + 1)
  end

  go({ deck = deck, vars = {}, trail = {} }, 1)
  return result
end

return M
