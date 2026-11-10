-- Kitewise: checks an orienteering course for dog-legs, crowded controls and pass-bys, and suggests
-- where to move the controls the setter allows.
-- Run with Lua 5.4:  lua kitewise.lua examples/park-sprint.txt
-- Exit codes: 0 clean, 3 problems found, 1 bad input, 2 bad usage.

local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path

local Parse = require("kitewise.parse")
local Check = require("kitewise.check")
local Fix = require("kitewise.fix")
local Report = require("kitewise.report")

local M = {}

M.USAGE = "usage: lua kitewise.lua COURSE-FILE   (use - for standard input)"

local function fail(message) error({ input = message }, 0) end

-- Reads at most MAX_BYTES + 1 bytes, so a huge file or an endless stream is refused, not loaded.
local function readLimited(path, stdin)
  local data
  if path == "-" then
    data = stdin:read(Parse.MAX_BYTES + 1) or ""
  else
    local f = io.open(path, "rb")
    if not f then fail("the course file could not be read") end
    local ok, got = pcall(f.read, f, Parse.MAX_BYTES + 1)
    f:close()
    if not ok or got == nil then fail("the course file could not be read (is it a folder?)") end
    data = got
  end
  if #data > Parse.MAX_BYTES then fail("the course is larger than 32 KB") end
  return data
end

-- Runs the program; returns the exit code and the text for standard output and standard error.
function M.main(args, stdin)
  if #args ~= 1 or args[1] == "-h" or args[1] == "--help" then
    return (#args == 1 and 0 or 2), M.USAGE .. "\n", ""
  end
  local ok, result = pcall(function()
    local course = Parse.parse(readLimited(args[1], stdin))
    local pos = {}
    for code, c in pairs(course.controls) do pos[code] = { x = c.x, y = c.y } end
    local issues, cost = Check.problems(course, pos)
    local fixed = { Fix.fix(course) }
    return { text = Report.text(course, issues, cost, fixed), clean = #issues == 0 }
  end)
  if ok then return (result.clean and 0 or 3), result.text, "" end
  if type(result) == "table" and result.input then return 1, "", "kitewise: " .. result.input .. "\n" end
  return 1, "", "kitewise: unexpected error\n"
end

-- Run as a program (not when loaded by the tests).
if arg and arg[0] and arg[0]:match("kitewise%.lua$") and not KITEWISE_TEST then
  local code, out, err = M.main({ table.unpack(arg, 1) }, io.stdin)
  io.stdout:write(out)
  io.stderr:write(err)
  os.exit(code)
end

return M
