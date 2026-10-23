-- Anchorwise: how a climbing anchor shares its load, and what happens if a piece fails.
-- Run with Lua 5.4:  lua anchorwise.lua examples/two-bolts.txt
-- Exit codes: 0 no warnings, 1 warnings to read, 2 bad usage or input.

local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path

local Parse = require("anchorwise.parse")
local Analyse = require("anchorwise.analyse")
local Report = require("anchorwise.report")

local M = {}

M.USAGE = "usage: lua anchorwise.lua ANCHOR-FILE   (use - for standard input)"

local function fail(message) error({ input = message }, 0) end

-- Reads at most MAX_BYTES + 1 bytes, so a huge file or an endless stream is refused, not loaded.
local function readLimited(path, stdin)
  local data
  if path == "-" then
    data = stdin:read(Parse.MAX_BYTES + 1) or ""
  else
    local f = io.open(path, "rb")
    if not f then fail("the anchor file could not be read") end
    local ok, got, problem = pcall(f.read, f, Parse.MAX_BYTES + 1)
    f:close()
    if not ok or (got == nil and problem) then fail("the anchor file could not be read") end -- e.g. a folder
    data = got or ""
  end
  if #data > Parse.MAX_BYTES then fail("the anchor file is larger than 16 KB") end
  return (data:gsub("^\239\187\191", ""))
end

-- Returns exit code, text for stdout, text for stderr. No printing here, so tests can call it.
function M.run(args, stdin)
  if #args ~= 1 or args[1]:sub(1, 2) == "--" then return 2, "", M.USAGE .. "\n" end
  local ok, result = pcall(function()
    local anchor = Parse.parse(readLimited(args[1], stdin))
    local r = Analyse.run(anchor)
    local text = Report.render(r)
    return { text = text, warned = not text:find("No warnings", 1, true) }
  end)
  if not ok then
    if type(result) == "table" and result.input then return 2, "", "anchorwise: " .. result.input .. "\n" end
    error(result, 0)
  end
  return result.warned and 1 or 0, result.text, ""
end

if arg and arg[0] and arg[0]:match("anchorwise%.lua$") and not ANCHORWISE_TESTING then
  local code, out, err = M.run({ table.unpack(arg) }, io.stdin)
  io.stdout:write(out)
  io.stderr:write(err)
  os.exit(code)
end

return M
