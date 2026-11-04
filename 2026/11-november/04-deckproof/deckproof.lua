-- Deckproof: proves a self-working card trick always works, or shows the case where it fails.
-- Run with Lua 5.4:  lua deckproof.lua examples/twenty-one.txt
-- Exit codes: 0 works every time, 1 fails in some case, 2 bad usage or input.

local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path

local Parse = require("deckproof.parse")
local Run = require("deckproof.run")
local Report = require("deckproof.report")

local M = {}

M.USAGE = "usage: lua deckproof.lua TRICK-FILE   (use - for standard input)"

local function fail(message) error({ input = message }, 0) end

-- Reads at most MAX_BYTES + 1 bytes, so a huge file or an endless stream is refused, not loaded.
local function readLimited(path, stdin)
  local data
  if path == "-" then
    data = stdin:read(Parse.MAX_BYTES + 1) or ""
  else
    local f = io.open(path, "rb")
    if not f then fail("the trick file could not be read") end
    local ok, got, problem = pcall(f.read, f, Parse.MAX_BYTES + 1)
    f:close()
    if not ok or (got == nil and problem) then fail("the trick file could not be read") end -- e.g. a folder
    data = got or ""
  end
  if #data > Parse.MAX_BYTES then fail("the trick file is larger than 16 KB") end
  return (data:gsub("^\239\187\191", ""))
end

-- Returns exit code, text for stdout, text for stderr. No printing here, so tests can call it.
function M.run(args, stdin)
  if #args ~= 1 or args[1]:sub(1, 2) == "--" then return 2, "", M.USAGE .. "\n" end
  local ok, result = pcall(function()
    local trick = Parse.parse(readLimited(args[1], stdin))
    local r = Run.run(trick)
    return { text = Report.render(trick, r), works = r.passed == r.cases and not r.limit }
  end)
  if not ok then
    if type(result) == "table" and result.input then return 2, "", "deckproof: " .. result.input .. "\n" end
    error(result, 0)
  end
  return result.works and 0 or 1, result.text, ""
end

if arg and arg[0] and arg[0]:match("deckproof%.lua$") and not DECKPROOF_TESTING then
  local code, out, err = M.run({ table.unpack(arg) }, io.stdin)
  io.stdout:write(out)
  io.stderr:write(err)
  os.exit(code)
end

return M
