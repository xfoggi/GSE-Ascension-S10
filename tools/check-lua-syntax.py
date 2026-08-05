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


def main():
    runtime = lupa.LuaRuntime()
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
