"""Compile every addon Lua file and report syntax errors.

Nothing is executed - the files are only handed to the Lua parser - so this is
safe to run outside the game. Bundled libraries under Lib/ are skipped; they are
upstream code and not ours to fix.

Requires: pip install lupa

Usage:
    python tools/check-lua-syntax.py
"""

import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed. Run: python -m pip install lupa")

REPO = Path(__file__).resolve().parent.parent
ADDON_DIRS = ("GSE", "GSE_GUI", "GSE_LDB")


def lua_files():
    for top in ADDON_DIRS:
        root = REPO / top
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.lua")):
            if "Lib" in path.relative_to(REPO).parts:
                continue
            yield path


def lua51_runtime():
    """Compile against the Lua the game actually runs.

    WoW 3.3.5a is Lua 5.1. lupa bundles several runtimes and LuaRuntime() picks
    the newest, which happily accepts syntax 5.1 rejects - so a file could pass
    here and still be refused in game. Ask for 5.1 explicitly and only fall back
    if this lupa build does not carry it.
    """
    try:
        from lupa import lua51
        return lua51.LuaRuntime(), "5.1"
    except ImportError:
        runtime = lupa.LuaRuntime()
        return runtime, "%d.%d (5.1 unavailable in this lupa build)" % runtime.lua_version


def main():
    runtime, luaversion = lua51_runtime()
    print("checking against Lua %s" % luaversion)
    failures = []
    checked = 0

    for path in lua_files():
        rel = path.relative_to(REPO)
        source = path.read_text(encoding="utf-8")
        checked += 1
        try:
            runtime.compile(source, name=str(rel))
        except lupa.LuaSyntaxError as exc:
            failures.append((rel, str(exc)))
            print(f"FAIL  {rel}\n      {exc}")
        except lupa.LuaError as exc:
            failures.append((rel, str(exc)))
            print(f"ERROR {rel}\n      {exc}")
        else:
            print(f"ok    {rel}  ({len(source):,} bytes)")

    print(f"\n{checked} files checked, {len(failures)} with problems.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
