#!/usr/bin/env python3
"""Bundle the world/tower builders with a Roblox API mock and run check.lua.

Usage: python3 tests/geometry/run_geometry.py [path/to/luau]
"""
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
MODULES = {
    "Config": ROOT / "src/shared/Config.lua",
    "Build": ROOT / "src/server/Build.lua",
    "TowerBuilder": ROOT / "src/server/TowerBuilder.lua",
    "WorldBuilder": ROOT / "src/server/WorldBuilder.lua",
    "WallClimb": ROOT / "src/client/WallClimb.lua",
}
REQUIRE = re.compile(r"require\((?:script\.Parent|ReplicatedStorage\.Shared|Shared)\.(\w+)\)")


def bundle() -> str:
    parts = [(HERE / "mock.lua").read_text()]
    parts.append("local __mods, __cache = {}, {}\n"
                 "function __req(name)\n"
                 "\tif __cache[name] == nil then __cache[name] = __mods[name]() end\n"
                 "\treturn __cache[name]\n"
                 "end\n")
    for name, path in MODULES.items():
        src = REQUIRE.sub(lambda m: f'__req("{m.group(1)}")', path.read_text())
        src = src.replace("--!strict", "").replace("export type ", "type ")
        parts.append(f"__mods[{name!r}] = function()\n{src}\nend\n".replace("'", '"', 2))
    parts.append((HERE / "check.lua").read_text())
    return "\n".join(parts)


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    with tempfile.TemporaryDirectory() as tmp:
        out = pathlib.Path(tmp) / "geometry_bundle.lua"
        out.write_text(bundle())
        return subprocess.run([luau, str(out)]).returncode


if __name__ == "__main__":
    sys.exit(main())
