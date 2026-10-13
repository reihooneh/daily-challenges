-- Hotslot: plans one oven so every dish is ready to serve at the same time.
-- Run with Lua 5.3 or newer:  lua hotslot.lua examples/christmas.txt

local dir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
package.path = dir .. "/?.lua;" .. package.path

local Menu = require("hotslot.menu")
local Plan = require("hotslot.plan")
local Report = require("hotslot.report")

local M = {}

M.USAGE = "usage: lua hotslot.lua MENU   (use - for standard input)"

local function fail(message) error({ input = message }, 0) end

-- Reads at most MAX_BYTES + 1 bytes, so a huge file or an endless stream is refused, not loaded.
local function readLimited(path, stdin)
  local data
  if path == "-" then
    data = stdin:read(Menu.MAX_BYTES + 1) or ""
  else
    local f = io.open(path, "rb")
    if not f then fail("the menu file could not be read") end
    local ok, got, problem = pcall(f.read, f, Menu.MAX_BYTES + 1)
    f:close()
    if not ok or (got == nil and problem) then fail("the menu file could not be read") end -- e.g. a folder
    data = got or ""
  end
  if #data > Menu.MAX_BYTES then fail("the menu is larger than 8 KB") end
  return data
end

-- Only plain characters from a file name reach the terminal.
local function safeName(path)
  if path == "-" then return "standard input" end
  local name = path:match("([^/\\]*)$")
  return (name:gsub("[^%w%.%-_ ]", "?")):sub(1, 80)
end

-- Returns 0 with a plan, 1 when the menu can't fit one oven, 2 for bad input.
function M.main(args, stdin, out, err)
  local ok, result = pcall(function()
    local path
    for _, a in ipairs(args) do
      if a == "-h" or a == "--help" then
        out:write(M.USAGE, "\n")
        return 0
      elseif a:sub(1, 1) == "-" and a ~= "-" then
        fail("unknown option")
      elseif path then
        fail("give exactly one menu")
      else
        path = a
      end
    end
    if not path then fail("give a menu to plan") end
    local menu = Menu.parse(readLimited(path, stdin))
    local plan = Plan.solve(menu)
    out:write(Report.render(menu, plan, safeName(path)))
    return plan.ok and 0 or 1
  end)
  if ok then return result end
  if type(result) == "table" and result.input then
    err:write("hotslot: ", result.input, "\n", M.USAGE, "\n")
    return 2
  end
  error(result, 0) -- a bug, not bad input
end

if arg and arg[0] and arg[0]:match("hotslot%.lua$") and not HOTSLOT_TESTING then
  os.exit(M.main(arg, io.stdin, io.stdout, io.stderr))
end

return M
