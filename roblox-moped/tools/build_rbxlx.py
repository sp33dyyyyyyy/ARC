#!/usr/bin/env python3
"""Builds MopedDays.rbxlx (a Roblox place file) from src/. No Rojo needed.

Usage: python3 tools/build_rbxlx.py [output.rbxlx]
File suffix -> class: .server.lua = Script, .client.lua = LocalScript, .lua = ModuleScript.
"""
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
_ref = 0


def ref():
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def script_item(path: Path):
    n = path.name
    if n.endswith(".server.lua"):
        cls, name = "Script", n[: -len(".server.lua")]
    elif n.endswith(".client.lua"):
        cls, name = "LocalScript", n[: -len(".client.lua")]
    else:
        cls, name = "ModuleScript", n[: -len(".lua")]
    src = path.read_text(encoding="utf-8")
    assert "]]>" not in src, path
    extra = '<token name="RunContext">0</token>' if cls == "Script" else ""
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>'
            f'<bool name="Disabled">false</bool>{extra}'
            f'<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>'
            f'</Properties></Item>')


def folder_items(d: Path):
    out = []
    for p in sorted(d.iterdir()):
        if p.is_dir():
            out.append(item("Folder", p.name, folder_items(p)))
        elif p.suffix == ".lua":
            out.append(script_item(p))
    return "".join(out)


def item(cls, name, children="", props=""):
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>'
            f'<string name="Name">{escape(name)}</string>{props}</Properties>{children}</Item>')


def static_part(cls, name, size, pos, rgb):
    r, g, b = rgb
    packed = 0xFF000000 | (r << 16) | (g << 8) | b
    extra = '<bool name="Neutral">true</bool>' if cls == "SpawnLocation" else ""
    cf = (f'<CoordinateFrame name="CFrame"><X>{pos[0]}</X><Y>{pos[1]}</Y><Z>{pos[2]}</Z>'
          '<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12>'
          '<R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>')
    props = (f'<bool name="Anchored">true</bool>{extra}{cf}'
             f'<Color3uint8 name="Color3uint8">{packed}</Color3uint8>'
             f'<Vector3 name="size"><X>{size[0]}</X><Y>{size[1]}</Y><Z>{size[2]}</Z></Vector3>')
    return item(cls, name, "", props)


def build():
    rs = item("ReplicatedStorage", "ReplicatedStorage",
              item("Folder", "Shared", folder_items(SRC / "ReplicatedStorage/Shared")) +
              item("Folder", "VehicleModels"))
    sss = item("ServerScriptService", "ServerScriptService", folder_items(SRC / "ServerScriptService"))
    sps = item("StarterPlayerScripts", "StarterPlayerScripts", folder_items(SRC / "StarterPlayerScripts"))
    sp = item("StarterPlayer", "StarterPlayer", sps + item("StarterCharacterScripts", "StarterCharacterScripts"))
    # A plain ground + spawn pad so the place is never an empty void, even if
    # the generated town fails. TownBuilder's own ground sits 1 stud above it.
    base = static_part("Part", "Baseplate", (2048, 4, 2048), (0, -3, 0), (104, 146, 74))
    spawn = static_part("SpawnLocation", "SpawnLocation", (12, 1, 12), (0, 0.5, 56), (160, 150, 130))
    ws = item("Workspace", "Workspace", item("Terrain", "Terrain") + base + spawn,
              '<float name="Gravity">196.2</float>')
    parts = [ws, rs, sss, sp,
             item("StarterGui", "StarterGui"), item("StarterPack", "StarterPack"),
             item("Lighting", "Lighting"), item("SoundService", "SoundService")]
    return ('<?xml version="1.0" encoding="utf-8"?>'
            '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
            '<Meta name="ExplicitAutoJoints">true</Meta>' + "".join(parts) + '</roblox>')


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "MopedDays.rbxlx"
    out.write_text(build(), encoding="utf-8")
    print("wrote", out)
