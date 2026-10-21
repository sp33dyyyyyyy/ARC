#!/usr/bin/env python3
"""Audits world.json (from build.luau) for build mistakes:

  * sunk:      a visible part that sticks down through the floor it stands on (gym floor at
               y=0, outdoor ground at y=-0.5) - its bottom is below the floor but most of
               it is above, so you see it cut off at the floor
  * buried:    a visible part entirely under the floor (wasted, or a mistake)
  * floating:  a small visible part hovering just above the floor (0.05..0.6 studs gap)
  * clash:     two solid visible parts of different models interpenetrating a lot
  * lights:    very bright lights

    python3 tools/world/audit.py world.json [--verbose]

Exits with 1 if anything is found, so it can run as a check.
"""
import json
import sys
from collections import defaultdict

import numpy as np

GYM = (-66, 66, -42, 46)  # x0, x1, z0, z1 of the gym footprint (floor y = 0)
GYM_FLOOR = 0.0
GROUND = -0.5
# Parts that are meant to go into the floor/ground (foundations, rock, terrain-ish things).
ALLOWED_SINK = ("Floor", "RockFace", "Plateau", "Mountain", "Ridge", "Snow", "Trunk", "Foundation", "Path", "Wall", "Clad", "Band", "Slat", "Post", "Core", "Mat", "Boulder", "Pad", "StartPad")


def corners(p):
    size = np.array(p["size"]) / 2
    rot = np.array(p["cf"][3:]).reshape(3, 3)
    pos = np.array(p["cf"][:3])
    if p["shape"] == "Ball":
        r = min(p["size"]) / 2
        return pos + np.array([[0, -r, 0], [0, r, 0]])
    signs = np.array([[x, y, z] for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)])
    if p["shape"] == "Cylinder":
        # Axis along local X; sample the rims.
        ts = np.linspace(0, 2 * np.pi, 16, endpoint=False)
        local = np.array([[sx * size[0], size[1] * np.cos(t), size[2] * np.sin(t)] for sx in (-1, 1) for t in ts])
        return pos + local @ rot.T
    return pos + (signs * size) @ rot.T


def floor_at(x, z):
    if GYM[0] <= x <= GYM[1] and GYM[2] <= z <= GYM[3]:
        return GYM_FLOOR
    return GROUND


def name_of(p):
    return p["path"].split(".")[-1]


def main():
    world = json.load(open(sys.argv[1]))
    verbose = "--verbose" in sys.argv
    problems = defaultdict(list)
    boxes = []
    for p in world["parts"]:
        if p["transparency"] >= 0.95:
            continue
        c = corners(p)
        lo, hi = c.min(axis=0), c.max(axis=0)
        centre = np.array(p["cf"][:3])
        floor = floor_at(centre[0], centre[2])
        if "Crags" in p["path"] or "Mountains" in p["path"]:
            floor = GROUND
        height = hi[1] - lo[1]
        allowed = any(a in name_of(p) for a in ALLOWED_SINK)
        if hi[1] < floor - 0.02 and not allowed and "Crags" not in p["path"]:
            problems["buried"].append(f"{p['path']} top {hi[1]:.2f} under floor {floor}")
        elif lo[1] < floor - 0.05 and hi[1] > floor + 0.05 and not allowed:
            sunk = floor - lo[1]
            if sunk > 0.08 and sunk < height * 0.95:
                problems["sunk"].append(f"{p['path']} goes {sunk:.2f} studs into the floor (bottom {lo[1]:.2f}, floor {floor})")
        elif 0.07 < lo[1] - floor < 0.6 and height < 3 and max(p["size"]) < 6 and min(p["size"]) > 0.1 and not p["path"].startswith("Workspace.Routes") and "Hold" not in p["path"]:
            problems["floating"].append(f"{p['path']} floats {lo[1] - floor:.2f} above the floor")
        if p["collide"] and p["transparency"] < 0.5:
            boxes.append((p, lo, hi))

    # Clashes between different top-level models (coarse AABB check on axis-aligned parts).
    def top(path):
        return path.rsplit(".", 1)[0]  # the part's model

    axis_aligned = []
    for p, lo, hi in boxes:
        rot = np.abs(np.array(p["cf"][3:]).reshape(3, 3))
        if np.allclose(np.sort(rot, axis=1)[:, :2], 0, atol=1e-3) and p["shape"] == "Block":
            axis_aligned.append((p, lo, hi))
    grid = defaultdict(list)
    for i, (p, lo, hi) in enumerate(axis_aligned):
        for gx in range(int(lo[0] // 16), int(hi[0] // 16) + 1):
            for gz in range(int(lo[2] // 16), int(hi[2] // 16) + 1):
                if (hi[0] - lo[0]) < 400 and (hi[2] - lo[2]) < 400:
                    grid[(gx, gz)].append(i)
    seen = set()
    for cell in grid.values():
        for a in range(len(cell)):
            for b in range(a + 1, len(cell)):
                i, j = cell[a], cell[b]
                if (i, j) in seen:
                    continue
                seen.add((i, j))
                p, lo1, hi1 = axis_aligned[i]
                q, lo2, hi2 = axis_aligned[j]
                if top(p["path"]) == top(q["path"]):
                    continue
                overlap = np.minimum(hi1, hi2) - np.maximum(lo1, lo2)
                if (overlap > 0.3).all():
                    vol = overlap.prod()
                    small = min(np.prod(hi1 - lo1), np.prod(hi2 - lo2))
                    if vol > 0.25 * small:
                        problems["clash"].append(f"{p['path']} <-> {q['path']} ({overlap.round(2).tolist()})")

    for light in world["lights"]:
        if light["brightness"] > 2.5 or (light["class"] == "SurfaceLight" and light["brightness"] * light["range"] > 40):
            problems["lights"].append(f"{light['path']} {light['class']} brightness {light['brightness']} range {light['range']}")

    total = 0
    for kind in ("sunk", "buried", "floating", "clash", "lights"):
        items = problems[kind]
        total += len(items)
        print(f"{kind}: {len(items)}")
        for line in items[: (len(items) if verbose else 12)]:
            print("   ", line)
        if not verbose and len(items) > 12:
            print(f"    ... {len(items) - 12} more")
    print(f"lighting: {world['lighting']}")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
