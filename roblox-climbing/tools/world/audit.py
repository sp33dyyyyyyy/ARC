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
GROUND = 0.0
# Parts that are meant to go into the floor/ground (foundations, rock, terrain-ish things).
ALLOWED_SINK = ("Floor", "Rock", "Bush", "Stone", "RockFace", "Plateau", "Mountain", "Ridge", "Snow", "Trunk", "Foundation", "Path", "Wall", "Clad", "Band", "Slat", "Post", "Core", "Mat", "Boulder", "Pad", "StartPad")


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

    # Covered: something standing on the floor whose foot is buried in a floor covering
    # (mats, tiles, padding, decking) laid over it - you'd see it cut off at the covering.
    coverings = []
    for p, lo, hi in boxes:
        size = hi - lo
        if size[1] <= 1.3 and size[0] * size[2] >= 16 and p["shape"] == "Block" and p["transparency"] < 0.5:
            coverings.append((p, lo, hi))
    cover_grid = defaultdict(list)
    for i, (p, lo, hi) in enumerate(coverings):
        for gx in range(int(lo[0] // 16), int(hi[0] // 16) + 1):
            for gz in range(int(lo[2] // 16), int(hi[2] // 16) + 1):
                cover_grid[(gx, gz)].append(i)
    for p in world["parts"]:
        if p["transparency"] >= 0.95 or "Crags" in p["path"] or "Holds" in p["path"]:
            continue
        c = corners(p)
        lo, hi = c.min(axis=0), c.max(axis=0)
        up = np.array(p["cf"][3:]).reshape(3, 3)[:, 1]
        if hi[1] - lo[1] > 40 or abs(up[1]) < 0.95 or any(n in name_of(p) for n in ("Core", "SeamV")):
            continue  # tall/tilted parts' boxes aren't their feet; wall cores meet the pads by design
        foot = (lo + hi) / 2
        foot[1] = lo[1]
        for i in cover_grid.get((int(foot[0] // 16), int(foot[2] // 16)), []):
            q, qlo, qhi = coverings[i]
            if q is p or q["path"] == p["path"] and q["cf"] == p["cf"]:
                continue
            inside = qlo[0] < foot[0] < qhi[0] and qlo[2] < foot[2] < qhi[2]
            depth = qhi[1] - foot[1]
            if inside and 0.015 < depth < 1.3 and foot[1] >= qlo[1] - 1.5 and hi[1] > qhi[1] + 0.05:
                problems["covered"].append(f"{p['path']} has {depth:.2f} studs buried in {q['path']}")
                break

    # Props: each slot's space (its fit box standing on the floor) mustn't run into
    # another prop's or into solid scenery (walls, counters, rock faces).
    slots = world.get("slots", [])
    def slot_box(s):
        pos = np.array(s["cf"][:3]); rot = np.array(s["cf"][3:]).reshape(3, 3)
        half = np.array(s["size"]) / 2 * 0.8  # models rarely fill their whole box
        corners_ = np.array([[x, y, z] for x in (-1, 1) for y in (0, 2) for z in (-1, 1)]) * half
        pts = pos + corners_ @ rot.T
        return pts.min(axis=0), pts.max(axis=0)
    sboxes = [(s, *slot_box(s)) for s in slots]
    def footprint(s):
        pos = np.array(s["cf"][:3])
        return pos, 0.8 * max(s["size"][0], s["size"][2]) / 2, pos[1], pos[1] + s["size"][1]
    feet = [footprint(s) for s in slots]
    for a in range(len(sboxes)):
        sa, lo1, hi1 = sboxes[a]
        pa, ra, ya0, ya1 = feet[a]
        for b in range(a + 1, len(sboxes)):
            sb = sboxes[b][0]
            pb, rb, yb0, yb1 = feet[b]
            d = np.hypot(pa[0] - pb[0], pa[2] - pb[2])
            if d < ra + rb - 0.2 and min(ya1, yb1) - max(ya0, yb0) > 0.2:
                problems["propclash"].append(f"{sa['path']} ({sa['key']}) overlaps {sb['path']} ({sb['key']}): {d:.1f} apart, needs {ra + rb:.1f}")
        for p, lo2, hi2 in axis_aligned:
            if p["path"].startswith(sa["path"] + ".") or hi2[1] <= lo1[1] + 0.15 or "Crags" in p["path"] and "Ledge" not in p["path"] and "RockFace" not in p["path"]:
                continue  # its own stand-in, a floor under it
            overlap = np.minimum(hi1, hi2) - np.maximum(lo1, lo2)
            if (overlap > 0.3).all() and np.prod(overlap) > 0.2 * np.prod(np.maximum(hi1 - lo1, 1e-3)):
                problems["propclash"].append(f"{sa['path']} ({sa['key']}) runs into {p['path']}")
                break

    for light in world["lights"]:
        if light["brightness"] > 2.5 or (light["class"] == "SurfaceLight" and light["brightness"] * light["range"] > 40):
            problems["lights"].append(f"{light['path']} {light['class']} brightness {light['brightness']} range {light['range']}")

    total = 0
    for kind in ("sunk", "buried", "floating", "covered", "clash", "propclash", "lights"):
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
