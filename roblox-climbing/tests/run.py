#!/usr/bin/env python3
"""Runs the offline tests with the Luau CLI (https://github.com/luau-lang/luau/releases).

    python3 tests/run.py            # from the roblox-climbing folder
    LUAU=/path/to/luau python3 tests/run.py

1. tests/unit.luau runs as-is (pure modules loaded with require).
2. tests/climbing.luau needs the real Config, HoldTypes, ClimbMath, LimbRig and
   TestWallLayout modules, which use Roblox types. This script builds one Luau file from
   tests/mocks.luau (Vector3/Vector2/CFrame/Color3/Enum stand-ins), those module sources
   and the hold grip points read out of HoldModels.luau, then runs it.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LUAU = os.environ.get("LUAU", "luau")


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
        return f.read()


def inline_module(name, *path):
    # `export type` is only allowed at the top level of a file; inside the wrapper
    # function the types are plain local types.
    source = re.sub(r"^export type", "type", read(*path), flags=re.M)
    return f"local {name} = (function()\n{source}\nend)()\n"


def grips_from_hold_models():
    source = read("src", "server", "World", "HoldModels.luau")
    grips = {}
    for name, body in re.findall(r"\n\t(\w+) = \{\n(.*?)\n\t\},", source, flags=re.S):
        match = re.search(r"grip = Vector3\.new\(([^)]*)\)", body)
        if match:
            grips[name] = match.group(1)
    if len(grips) < 8:
        sys.exit(f"could not read hold grips from HoldModels.luau (found {sorted(grips)})")
    entries = "\n".join(f"\t{name} = Vector3.new({args})," for name, args in sorted(grips.items()))
    return f"local GRIPS = {{\n{entries}\n}}\n"


def run(path):
    print(f"== {os.path.relpath(path, ROOT)}")
    result = subprocess.run([LUAU, path], cwd=ROOT)
    return result.returncode == 0


def main():
    ok = run(os.path.join(HERE, "unit.luau"))

    combined = "".join([
        read("tests", "mocks.luau"),
        inline_module("HoldTypes", "src", "shared", "HoldTypes.luau"),
        inline_module("Config", "src", "shared", "Config.luau"),
        inline_module("ClimbMath", "src", "shared", "ClimbMath.luau"),
        inline_module("Layout", "src", "server", "World", "TestWallLayout.luau"),
        inline_module("LimbRig", "src", "shared", "LimbRig.luau"),
        inline_module("StaminaMath", "src", "shared", "StaminaMath.luau"),
        grips_from_hold_models(),
        read("tests", "climbing.luau"),
    ])
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(combined)
        combined_path = f.name
    try:
        ok = run(combined_path) and ok
    finally:
        os.unlink(combined_path)

    print("\nALL TESTS PASSED" if ok else "\nSOME TESTS FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
