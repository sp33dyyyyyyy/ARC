#!/usr/bin/env python3
"""Offline model preview.

Runs the real model-building Luau code under a mock Roblox runtime (real
CFrame/Vector3 maths, records every Part) and renders the result to PNG with a
small z-buffer rasteriser, so models can be inspected without Roblox Studio.

  python3 tools/preview.py bike spatz50 out.png
  python3 tools/preview.py house out.png          (any scene defined in SCENES)

Needs: luau on PATH or LUAU=/path/to/luau, numpy, Pillow.
"""
import math, os, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
PRELUDE = (ROOT / "tools/preview/prelude.lua").read_text()
LUAU = os.environ.get("LUAU", "luau")

MODULE_DIRS = ["ReplicatedStorage/Shared", "ServerScriptService/Services"]


def gather_modules(skip=()):
    out = []
    for d in MODULE_DIRS:
        for p in sorted((SRC / d).glob("*.lua")):
            name = p.name[:-4]
            if name in skip:
                continue
            out.append((name, p.read_text()))
    return out


def run_lua(driver: str, skip=("SoundIds",)):
    body = [PRELUDE]
    for name, src in gather_modules(skip):
        body.append("MODULES[%r] = function(script)\n%s\nend\n" % (name, src))
    body.append("SETUP_TREE()\n" + driver + "\nprint(DUMP('all'))\n")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, dir=str(ROOT / "tools")) as f:
        f.write("\n".join(body))
        path = f.name
    try:
        res = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=300, cwd=str(ROOT / "tools"))
    finally:
        if os.environ.get("KEEP") != "1":
            os.unlink(path)
    if res.returncode != 0:
        sys.stderr.write(res.stdout[-2000:] + res.stderr[-3000:])
        raise SystemExit("lua failed (set KEEP=1 to keep the generated file)")
    for line in res.stdout.splitlines():
        if line.startswith("[") or line.startswith("WARN"):
            print(line)
    return res.stdout


def parse(stdout):
    parts = []
    for line in stdout.splitlines():
        f = line.split("|")
        if len(f) != 11:
            continue
        cls, shape, size, pos, rx, ry, rz, col, mat, tr, name = f
        v = lambda s: [float(x) for x in s.split(",")]
        parts.append(dict(cls=cls, shape=shape, size=v(size), pos=v(pos), R=v(rx), U=v(ry), B=v(rz),
                          color=[int(x) for x in col.split(",")], mat=mat, tr=float(tr), name=name))
    return parts


# ---- geometry ---------------------------------------------------------------
def box_tris(hx, hy, hz):
    c = [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]
    c = [(x*hx, y*hy, z*hz) for x, y, z in c]
    faces = [(0,1,2,3),(5,4,7,6),(4,0,3,7),(1,5,6,2),(3,2,6,7),(4,5,1,0)]
    tris = []
    for a, b, cc, d in faces:
        tris += [(c[a], c[b], c[cc]), (c[a], c[cc], c[d])]
    return tris


def cyl_tris(length, dy, dz, n=16):  # axis = local X
    tris = []
    ring = [(math.cos(2*math.pi*i/n)*dy/2, math.sin(2*math.pi*i/n)*dz/2) for i in range(n)]
    hl = length / 2
    for i in range(n):
        y0, z0 = ring[i]; y1, z1 = ring[(i+1) % n]
        tris += [((-hl,y0,z0),(hl,y0,z0),(hl,y1,z1)), ((-hl,y0,z0),(hl,y1,z1),(-hl,y1,z1))]
        tris += [((hl,0,0),(hl,y1,z1),(hl,y0,z0)), ((-hl,0,0),(-hl,y0,z0),(-hl,y1,z1))]
    return tris


def ball_tris(sx, sy, sz, nu=12, nv=8):
    tris = []
    def p(u, v):
        th = 2*math.pi*u/nu; ph = math.pi*v/nv
        return (math.cos(th)*math.sin(ph)*sx/2, math.cos(ph)*sy/2, math.sin(th)*math.sin(ph)*sz/2)
    for u in range(nu):
        for v in range(nv):
            a, b, c, d = p(u,v), p(u+1,v), p(u+1,v+1), p(u,v+1)
            tris += [(a,b,c),(a,c,d)]
    return tris


def wedge_tris(sx, sy, sz):
    hx, hy, hz = sx/2, sy/2, sz/2
    # tall edge at +Z, slope descends to -Z (Roblox WedgePart)
    a=(-hx,-hy,-hz);b=(hx,-hy,-hz);c=(hx,-hy,hz);d=(-hx,-hy,hz);e=(-hx,hy,hz);f=(hx,hy,hz)
    return [(a,b,c),(a,c,d),(a,e,f),(a,f,b),(d,c,f),(d,f,e),(a,d,e),(b,f,c)]


def world_tris(p):
    s = p["size"]
    if p["shape"].endswith("Cylinder"):
        loc = cyl_tris(s[0], s[1], s[2])
    elif p["shape"].endswith("Ball"):
        loc = ball_tris(*s)
    elif p["cls"] == "WedgePart":
        loc = wedge_tris(*s)
    else:
        loc = box_tris(s[0]/2, s[1]/2, s[2]/2)
    R, U, B, P = p["R"], p["U"], p["B"], p["pos"]
    out = []
    for tri in loc:
        w = []
        for x, y, z in tri:
            w.append((P[0]+R[0]*x+U[0]*y+B[0]*z, P[1]+R[1]*x+U[1]*y+B[1]*z, P[2]+R[2]*x+U[2]*y+B[2]*z))
        out.append(w)
    return out


# ---- rasteriser -------------------------------------------------------------
def render(parts, eye_dir, W=900, H=600, up=(0,1,0), fit=None, bg=(168,196,226), ortho=True, target=None, dist=None, fov=40):
    tris, cols = [], []
    for p in parts:
        if p["tr"] >= 0.95:
            continue
        base = np.array(p["color"], float)
        for t in world_tris(p):
            tris.append(t); cols.append(base)
    T = np.array(tris, float)  # n,3,3
    C = np.array(cols, float)
    if fit is None:
        mn, mx = T.reshape(-1,3).min(0), T.reshape(-1,3).max(0)
    else:
        mn, mx = np.array(fit[0], float), np.array(fit[1], float)
    center = (mn+mx)/2 if target is None else np.array(target, float)
    diag = np.linalg.norm(mx-mn)
    f = np.array(eye_dir, float); f /= np.linalg.norm(f)  # direction camera looks FROM center toward eye
    fwd = -f
    right = np.cross(fwd, up); right /= np.linalg.norm(right)
    upv = np.cross(right, fwd)
    rel = T - center
    x = rel @ right; y = rel @ upv; z = rel @ fwd
    scale = 0.9 * min(W, H) / diag if ortho else None
    if ortho:
        sx = W/2 + x*scale; sy = H/2 - y*scale; sz = z
    else:
        d = (dist or diag*1.6)
        zz = z + d
        k = (H/2)/math.tan(math.radians(fov)/2)
        zz = np.maximum(zz, 0.1)
        sx = W/2 + x*k/zz; sy = H/2 - y*k/zz; sz = zz
    # shading
    n = np.cross(T[:,1]-T[:,0], T[:,2]-T[:,0])
    ln = np.linalg.norm(n, axis=1, keepdims=True); ln[ln==0] = 1; n /= ln
    # make normals face the viewer
    flip = (n @ f) < 0
    n[flip] *= -1
    light = np.array([0.45, 0.85, 0.35]); light /= np.linalg.norm(light)
    diff = np.clip(n @ light, 0, 1)
    shade = 0.45 + 0.65*diff
    img = np.zeros((H, W, 3)); img[:] = np.array(bg, float)
    zbuf = np.full((H, W), 1e18)
    # sky gradient
    for yy in range(H):
        t = yy/H
        img[yy,:,:] = np.array(bg)*(1-0.25*t) + np.array([235,238,240])*0.25*t
    order = np.arange(len(T))
    for i in order:
        px = sx[i]; py = sy[i]; pz = sz[i]
        minx = max(int(math.floor(px.min())), 0); maxx = min(int(math.ceil(px.max())), W-1)
        miny = max(int(math.floor(py.min())), 0); maxy = min(int(math.ceil(py.max())), H-1)
        if minx > maxx or miny > maxy: continue
        den = (py[1]-py[2])*(px[0]-px[2]) + (px[2]-px[1])*(py[0]-py[2])
        if abs(den) < 1e-9: continue
        gx, gy = np.meshgrid(np.arange(minx, maxx+1)+0.5, np.arange(miny, maxy+1)+0.5)
        w0 = ((py[1]-py[2])*(gx-px[2]) + (px[2]-px[1])*(gy-py[2]))/den
        w1 = ((py[2]-py[0])*(gx-px[2]) + (px[0]-px[2])*(gy-py[2]))/den
        w2 = 1-w0-w1
        m = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not m.any(): continue
        zz = w0*pz[0] + w1*pz[1] + w2*pz[2]
        sub = zbuf[miny:maxy+1, minx:maxx+1]
        upd = m & (zz < sub)
        sub[upd] = zz[upd]
        col = np.clip(C[i]*shade[i], 0, 255)
        img[miny:maxy+1, minx:maxx+1][upd] = col
    return Image.fromarray(img.astype(np.uint8))


def sheet(parts, views, out, W=700, H=460, **kw):
    imgs = [render(parts, d, W, H, **kw) for d in views]
    cols = 2
    rows = (len(imgs)+cols-1)//cols
    sh = Image.new("RGB", (W*cols, H*rows), (255,255,255))
    for i, im in enumerate(imgs):
        sh.paste(im, ((i % cols)*W, (i//cols)*H))
    sh.save(out)


BIKE_VIEWS = [(1.0,0.45,0.9), (1,0.0,0), (-1,0.4,-0.8), (0.0,0.15,-1)]

DRIVERS = {
  "bike": lambda vid: f"""
local VD = require('VehicleData')
local BF = require('BikeFactory')
local v = VD.byId['{vid}']
local m = BF.build(v, 1)
m.Parent = workspace
""",
}

SCENES = {
  "houses": """
local B = require('Buildings')
local rng = Random.new(7)
local root = Instance.new('Folder'); root.Parent = workspace
local styles = {'fachwerk','putz','brick','stone'}
for i, st in ipairs(styles) do
  B.house(root, CFrame.new((i-1)*50, 0, 0), {style = st, rng = rng, w = 30, d = 24})
end
""",
  "church": "local B = require('Buildings'); local root = Instance.new('Folder'); root.Parent = workspace; B.church(root, CFrame.new(0,0,0), {})",
  "barn": "local B = require('Buildings'); local root = Instance.new('Folder'); root.Parent = workspace; B.barn(root, CFrame.new(0,0,0), {})",
  "shops": """
local B = require('Buildings'); local root = Instance.new('Folder'); root.Parent = workspace
B.shop(root, CFrame.new(0,0,0), {text='BAECKEREI'})
B.gasthof(root, CFrame.new(70,0,0), {})
B.garage(root, CFrame.new(-60,0,0), {})
""",
  "props": """
local P = require('Props'); local root = Instance.new('Folder'); root.Parent = workspace
local rng = Random.new(3)
P.tree(root, Vector3.new(0,0,0), rng, 'oak'); P.tree(root, Vector3.new(14,0,0), rng, 'birch'); P.tree(root, Vector3.new(28,0,0), rng, 'fir'); P.tree(root, Vector3.new(40,0,0), rng, 'orchard')
P.car(root, CFrame.new(0,0,30), 'estate', Color3.fromRGB(60,110,170)); P.car(root, CFrame.new(14,0,30), 'bubble', Color3.fromRGB(230,200,70))
P.tractor(root, CFrame.new(34,0,32))
P.lamp(root, CFrame.new(-14,0,0)); P.bench(root, CFrame.new(-24,0,0)); P.busStop(root, CFrame.new(-40,0,10), 'Kleindorf Mitte')
P.roadSign(root, CFrame.new(-14,0,-14), 'ortsschild', 'KLEINDORF'); P.roadSign(root, CFrame.new(-4,0,-14), 'limit', '30'); P.roadSign(root, CFrame.new(2,0,-14), 'vorfahrt'); P.roadSign(root, CFrame.new(8,0,-14), 'stop')
P.litfass(root, CFrame.new(-60,0,10)); P.postBox(root, CFrame.new(-70,0,10)); P.wayCross(root, CFrame.new(-80,0,10))
P.fountain(root, CFrame.new(-20,0,-40)); P.maibaum(root, CFrame.new(20,0,-40))
P.powerPole(root, CFrame.new(60,0,0)); P.turbine(root, CFrame.new(90,0,0)); P.haybale(root, CFrame.new(50,0,20))
""",
  "town": """
local TB = require('TownBuilder')
TB.build()
""",
  "petrol": "local B = require('Buildings'); local root = Instance.new('Folder'); root.Parent = workspace; B.petrolStation(root, CFrame.new(0,0,0), {})",
}

if __name__ == "__main__":
    kind = sys.argv[1]
    if kind == "bike":
        vid, out = sys.argv[2], sys.argv[3]
        parts = parse(run_lua(DRIVERS["bike"](vid)))
        print(len(parts), "parts")
        views = BIKE_VIEWS
        if len(sys.argv) > 4:
            views = [BIKE_VIEWS[int(sys.argv[4])]]
            im = render(parts, views[0], 1400, 900)
            im.save(out)
        else:
            sheet(parts, views, out)
    elif kind == "region":
        # python3 tools/preview.py region out.png x1 z1 x2 z2 viewIndex [W H]
        out = sys.argv[2]
        x1, z1, x2, z2 = [float(v) for v in sys.argv[3:7]]
        vi = int(sys.argv[7])
        Wd = int(sys.argv[8]) if len(sys.argv) > 8 else 1400
        Hd = int(sys.argv[9]) if len(sys.argv) > 9 else 900
        parts = parse(run_lua(SCENES["town"]))
        sel = [p for p in parts if x1 <= p["pos"][0] <= x2 and z1 <= p["pos"][2] <= z2 and p["size"][0] < 1500 and p["size"][2] < 1500]
        print(len(parts), "parts total,", len(sel), "in region")
        views = [(0.5,0.6,1.0),(1.0,0.5,0.6),(-0.9,0.5,0.9),(0.0,1.0,0.05),(0.1,0.25,1.0)]
        render(sel, views[vi], Wd, Hd).save(out)
    elif kind == "scene":
        name, out = sys.argv[2], sys.argv[3]
        parts = parse(run_lua(SCENES[name]))
        print(len(parts), "parts")
        views = [(0.5,0.55,1.0),(1.0,0.45,0.6),(-0.9,0.5,0.9),(0.0,1.0,0.05)]
        if len(sys.argv) > 4:
            render(parts, views[int(sys.argv[4])], 1400, 900).save(out)
        else:
            sheet(parts, views, out)
    else:
        raise SystemExit("unknown kind")
