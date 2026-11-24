"""Runs a Lua 5.4 script with arguments when there's no `lua` binary: python3 tools/lua.py SCRIPT [ARGS...]

Uses lupa's embedded Lua 5.4. The script sees `arg` like the real interpreter, and `os.exit` works.
"""

import sys

from lupa import lua54


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: python3 tools/lua.py SCRIPT [ARGS...]", file=sys.stderr)
        return 2
    lua = lua54.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path = './?.lua;./?/init.lua;' .. package.path")
    args = lua.table_from({i: a for i, a in enumerate(sys.argv[1:])})
    lua.globals().arg = args
    with open(sys.argv[1], encoding="utf-8") as f:
        source = f.read()
    try:
        lua.execute(source)
    except lua54.LuaError as e:
        print(f"lua: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
