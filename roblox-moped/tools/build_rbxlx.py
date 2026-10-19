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


def build():
    rs = item("ReplicatedStorage", "ReplicatedStorage",
              item("Folder", "Shared", folder_items(SRC / "ReplicatedStorage/Shared")) +
              item("Folder", "VehicleModels"))
    sss = item("ServerScriptService", "ServerScriptService", folder_items(SRC / "ServerScriptService"))
    sps = item("StarterPlayerScripts", "StarterPlayerScripts", folder_items(SRC / "StarterPlayerScripts"))
    sp = item("StarterPlayer", "StarterPlayer", sps + item("StarterCharacterScripts", "StarterCharacterScripts"))
    ws = item("Workspace", "Workspace", item("Terrain", "Terrain"),
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
