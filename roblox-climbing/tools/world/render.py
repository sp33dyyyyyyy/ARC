#!/usr/bin/env python3
"""Renders world.json (from build.luau) to PNG with a tiny software rasterizer, so the
world can be looked at without Studio. Flat-shaded, sun from the south-east, no textures.

    python3 tools/world/render.py world.json out.png --eye 0,20,60 --at 0,8,0 [--fov 70]
        [--size 1280x720] [--only Gym]  [--clip 300]
"""
import argparse
import json
import math

import numpy as np
from PIL import Image

SUN = np.array([0.45, 0.8, 0.35])
SUN /= np.linalg.norm(SUN)


def unit_box():
    v = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = []
    for a, b, c, d in faces:
        tris += [(a, b, c), (a, c, d)]
    return v, np.array(tris)


def unit_cylinder(n=18):  # axis along X, like Roblox
    verts, tris = [], []
    for i in range(n):
        t = 2 * math.pi * i / n
        verts += [(-.5, .5 * math.cos(t), .5 * math.sin(t)), (.5, .5 * math.cos(t), .5 * math.sin(t))]
    verts += [(-.5, 0, 0), (.5, 0, 0)]
    c0, c1 = 2 * n, 2 * n + 1
    for i in range(n):
        j = (i + 1) % n
        a, b, c, d = 2 * i, 2 * i + 1, 2 * j, 2 * j + 1
        tris += [(a, c, d), (a, d, b), (c0, c, a), (c1, b, d)]
    return np.array(verts), np.array(tris)


def unit_sphere(nu=10, nv=14):
    verts, tris = [], []
    for i in range(nu + 1):
        p = math.pi * i / nu
        for j in range(nv):
            t = 2 * math.pi * j / nv
            verts.append((.5 * math.sin(p) * math.cos(t), .5 * math.cos(p), .5 * math.sin(p) * math.sin(t)))
    for i in range(nu):
        for j in range(nv):
            a, b = i * nv + j, i * nv + (j + 1) % nv
            c, d = a + nv, b + nv
            tris += [(a, c, b), (b, c, d)]
    return np.array(verts), np.array(tris)


def unit_wedge():  # Roblox wedge: slope rises towards -Z, full height at the back (+Z)? (front low)
    v = np.array([[-.5, -.5, -.5], [.5, -.5, -.5], [-.5, -.5, .5], [.5, -.5, .5], [-.5, .5, .5], [.5, .5, .5]])
    tris = [(0, 1, 3), (0, 3, 2), (2, 3, 5), (2, 5, 4), (0, 4, 5), (0, 5, 1), (0, 2, 4), (1, 5, 3)]
    return v, np.array(tris)


SHAPES = {"Block": unit_box(), "Cylinder": unit_cylinder(), "Ball": unit_sphere(), "Ellipsoid": unit_sphere(), "Wedge": unit_wedge(), "CornerWedge": unit_wedge()}


def part_mesh(p):
    verts, tris = SHAPES.get(p["shape"], SHAPES["Block"])
    size = np.array(p["size"])
    if p["shape"] == "Ball":
        size = np.full(3, min(size))
    c = p["cf"]
    pos = np.array(c[:3])
    rot = np.array(c[3:]).reshape(3, 3)
    world = (verts * size) @ rot.T + pos
    return world, tris


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("world")
    ap.add_argument("out")
    ap.add_argument("--eye", default="0,20,70")
    ap.add_argument("--at", default="0,8,0")
    ap.add_argument("--fov", type=float, default=70)
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--only", default=None, help="comma list of path substrings to keep")
    ap.add_argument("--skip", default=None, help="comma list of path substrings to drop")
    ap.add_argument("--clip", type=float, default=2000)
    ap.add_argument("--terrain", action="store_true")
    a = ap.parse_args()
    W, H = (int(x) for x in a.size.split("x"))
    eye = np.array([float(x) for x in a.eye.split(",")])
    at = np.array([float(x) for x in a.at.split(",")])
    fwd = at - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    f = 1 / math.tan(math.radians(a.fov) / 2)
    aspect = W / H

    world = json.load(open(a.world))
    parts = world["parts"]
    if a.terrain:
        for t in world["terrain"]:
            color = [0.33, 0.5, 0.22] if "Grass" in t["material"] else [0.42, 0.41, 0.4] if "Rock" in t["material"] else [0.45, 0.36, 0.25]
            if t["size"][0] > 600:
                continue  # the ground plane is drawn separately
            parts.append({"path": "Terrain", "shape": "Ball" if t.get("ball") else "Block", "size": t["size"], "cf": t["cf"], "color": color, "transparency": 0})
    only = a.only.split(",") if a.only else None
    skip = a.skip.split(",") if a.skip else []

    zbuf = np.full((H, W), np.inf)
    img = np.zeros((H, W, 3))
    sky = np.linspace(0.85, 0.55, H)[:, None]
    img[:] = np.stack([sky * 0.75, sky * 0.85, sky * 1.0], axis=-1)
    for p in parts:
        if p.get("transparency", 0) > 0.85:
            continue
        if only and not any(o in p["path"] for o in only):
            continue
        if any(s in p["path"] for s in skip):
            continue
        if np.linalg.norm(np.array(p["cf"][:3]) - eye) > a.clip + max(p["size"]):
            continue
        verts, tris = part_mesh(p)
        rel = verts - eye
        cx, cy, cz = rel @ right, rel @ up, rel @ fwd
        color = np.array(p["color"])
        if p.get("material") == "Neon":
            color = np.minimum(1, color * 1.4 + 0.15)
        for t in tris:
            z = cz[t]
            if (z < 0.1).any():
                continue
            sx = (cx[t] * f / aspect / z + 1) * W / 2
            sy = (1 - cy[t] * f / z) * H / 2
            x0, x1 = int(max(0, math.floor(sx.min()))), int(min(W - 1, math.ceil(sx.max())))
            y0, y1 = int(max(0, math.floor(sy.min()))), int(min(H - 1, math.ceil(sy.max())))
            if x0 > x1 or y0 > y1:
                continue
            v = verts[t]
            n = np.cross(v[1] - v[0], v[2] - v[0])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                continue
            n /= ln
            if np.dot(n, eye - v[0]) < 0:
                n = -n
            shade = 0.45 + 0.55 * max(0.0, float(np.dot(n, SUN)))
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            d = (sy[1] - sy[2]) * (sx[0] - sx[2]) + (sx[2] - sx[1]) * (sy[0] - sy[2])
            if abs(d) < 1e-9:
                continue
            w0 = ((sy[1] - sy[2]) * (xs - sx[2]) + (sx[2] - sx[1]) * (ys - sy[2])) / d
            w1 = ((sy[2] - sy[0]) * (xs - sx[2]) + (sx[0] - sx[2]) * (ys - sy[2])) / d
            w2 = 1 - w0 - w1
            inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
            if not inside.any():
                continue
            depth = 1 / (w0 / z[0] + w1 / z[1] + w2 / z[2])
            region = zbuf[y0:y1 + 1, x0:x1 + 1]
            closer = inside & (depth < region)
            region[closer] = depth[closer]
            img[y0:y1 + 1, x0:x1 + 1][closer] = color * shade
    if a.terrain:
        # Ground plane (the grass terrain) at y = -0.5, behind anything already drawn.
        px, py = np.meshgrid(np.arange(W) + 0.5, np.arange(H) + 0.5)
        dx = (px / W * 2 - 1) * aspect / f
        dy = (1 - py / H * 2) / f
        dirs = fwd[None, None, :] + dx[..., None] * right[None, None, :] + dy[..., None] * up[None, None, :]
        t = (-0.5 - eye[1]) / dirs[..., 1]
        depth = t  # along fwd, since dirs has unit fwd component
        hit = (t > 0) & (depth < zbuf)
        zbuf[hit] = depth[hit]
        img[hit] = np.array([0.33, 0.5, 0.22]) * 0.85
    fog = np.clip((zbuf - 200) / 1500, 0, 0.6)[..., None]
    img = img * (1 - fog) + np.array([0.7, 0.78, 0.88]) * fog * (zbuf < np.inf)[..., None] + img * fog * (zbuf == np.inf)[..., None]
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(a.out)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
