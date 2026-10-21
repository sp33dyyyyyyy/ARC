#!/usr/bin/env python3
"""Lays out the GUI trees from dump.luau like Roblox does (UDim2 sizes, anchors,
AutomaticSize, UIListLayout / UIGridLayout / UIPadding, scrolling frames), measures every
text with the real fonts, renders each scene to PNG, and reports problems:

  overflow   text wider (or, wrapped, taller) than the box it's in
  clipped    text cut off by TextTruncate
  spill      a box sticking out past its parent (that doesn't clip it)
  collide    two texts whose letters overlap
  offscreen  something partly off the screen

    python3 tools/ui/layout.py ui.json out_dir [--fonts dir] [--scene name]

Fonts (--fonts, default /tmp/claude-0/fonts): Michroma, Sarpanch, Roboto Mono, and Inter
standing in for Builder Sans (a touch wider, so the check errs on the safe side).
"""
import argparse
import json
import os
import re

from PIL import Image, ImageDraw, ImageFont

FONT_FILES = {
    "Michroma": "Michroma-Regular.ttf.ttf",
    "Sarpanch": "Sarpanch-Regular.ttf.ttf",
    "RobotoMono": "RobotoMono.ttf",
    "BuilderSans": "Inter.ttf",
    "BuilderSansMedium": "Inter.ttf",
    "BuilderSansBold": "Inter.ttf",
    "Legacy": "Inter.ttf",
    "SourceSans": "Inter.ttf",
    "Gotham": "Inter.ttf",
    "GothamBold": "Inter.ttf",
}
_fonts = {}
FONT_DIR = "/tmp/claude-0/fonts"


def font(name, size):
    key = (name, int(round(size)))
    if key not in _fonts:
        path = os.path.join(FONT_DIR, FONT_FILES.get(name, "Inter.ttf"))
        _fonts[key] = ImageFont.truetype(path, max(1, int(round(size))))
    return _fonts[key]


TAG = re.compile(r"<[^>]+>")


def plain(text, rich):
    if not rich:
        return text
    text = TAG.sub("", text)
    return text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&").replace("&quot;", '"')


def text_width(t, fname, size):
    return font(fname, size).getlength(t) if t else 0


def wrap(text, fname, size, width):
    lines = []
    for para in text.split("\n"):
        words = para.split(" ")
        line = ""
        for w in words:
            trial = w if not line else line + " " + w
            if text_width(trial, fname, size) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = w
        lines.append(line)
    return lines


def udim2(v):
    return v if v else [0, 0, 0, 0]


GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "CanvasGroup", "ViewportFrame"}
TEXT = {"TextLabel", "TextButton", "TextBox"}


def child_of(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def padding_of(node, w, h):
    p = child_of(node, "UIPadding")
    if not p:
        return 0, 0, 0, 0
    def px(u, ref):
        return (u[0] * ref + u[1]) if u else 0
    return px(p.get("PaddingLeft"), w), px(p.get("PaddingTop"), h), px(p.get("PaddingRight"), w), px(p.get("PaddingBottom"), h)


def text_metrics(node, box_w):
    """Natural (width, height) of a text node's text; wrapped to box_w if TextWrapped."""
    fname = node.get("Font", "Legacy")
    size = node.get("TextSize", 14)
    t = plain(node.get("Text", ""), node.get("RichText"))
    lh = size * (node.get("LineHeight") or 1)
    if node.get("TextWrapped") and box_w is not None and box_w > 0:
        lines = wrap(t, fname, size, box_w)
    else:
        lines = t.split("\n")
    w = max((text_width(l, fname, size) for l in lines), default=0)
    return w, lh * len(lines), lines


class Box:
    __slots__ = ("node", "x", "y", "w", "h", "parent", "kids", "clip", "lines", "ink", "scale")

    def __init__(self, node, parent):
        self.node, self.parent = node, parent
        self.x = self.y = self.w = self.h = 0
        self.kids = []
        self.clip = None
        self.lines = None
        self.ink = None
        self.scale = 1.0


def visible_gui_children(node):
    return [c for c in node["children"] if c["class"] in GUI and c.get("Visible", True)]


def resolve_size(node, pw, ph):
    s = udim2(node.get("Size"))
    w = s[0] * pw + s[1]
    h = s[2] * ph + s[3]
    con = child_of(node, "UISizeConstraint")
    if con:
        mn, mx = con.get("MinSize", [0, 0]), con.get("MaxSize", [1e9, 1e9])
        w = min(max(w, mn[0]), mx[0])
        h = min(max(h, mn[1]), mx[1])
    return w, h


def auto_size(node, w, h, pw, ph):
    """Grow (w, h) for AutomaticSize from the text and the children's natural extents."""
    mode = node.get("AutomaticSize", "None")
    if mode == "None":
        return w, h
    l, t, r, b = padding_of(node, w, h)
    cw, ch = 0, 0
    if node["class"] in TEXT:
        tw, th, _ = text_metrics(node, None if mode in ("X", "XY") else w - l - r)
        cw, ch = tw, th
    kids = visible_gui_children(node)
    layout = child_of(node, "UIListLayout")
    if kids:
        sizes = []
        for k in kids:
            kw, kh = resolve_size(k, 0 if mode in ("X", "XY") else w - l - r, 0 if mode in ("Y", "XY") else h - t - b)
            kw, kh = auto_size(k, kw, kh, w, h)
            sizes.append((k, kw, kh))
        if layout:
            pad = layout.get("Padding") or [0, 0]
            gap = pad[1]
            if layout.get("FillDirection", "Vertical") == "Horizontal":
                cw = max(cw, sum(s[1] for s in sizes) + gap * (len(sizes) - 1))
                ch = max(ch, max(s[2] for s in sizes))
            else:
                ch = max(ch, sum(s[2] for s in sizes) + gap * (len(sizes) - 1))
                cw = max(cw, max(s[1] for s in sizes))
        else:
            for k, kw, kh in sizes:
                p = udim2(k.get("Position"))
                cw = max(cw, p[1] + kw)
                ch = max(ch, p[3] + kh)
    if mode in ("X", "XY"):
        w = max(w, cw + l + r)
    if mode in ("Y", "XY"):
        h = max(h, ch + t + b)
    return w, h


def layout(node, parent, px, py, pw, ph, clip):
    box = Box(node, parent)
    w, h = resolve_size(node, pw, ph)
    w, h = auto_size(node, w, h, pw, ph)
    box.w, box.h = w, h
    box.x, box.y = px, py
    if node.get("ClipsDescendants") or node["class"] == "ScrollingFrame":
        clip = intersect(clip, (px, py, px + w, py + h))
    box.clip = clip
    l, t, r, b = padding_of(node, w, h)
    cx, cy, cw, ch = px + l, py + t, w - l - r, h - t - b
    if node["class"] == "ScrollingFrame":
        canvas = udim2(node.get("CanvasSize"))
        cw = canvas[0] * w + canvas[1] or cw
        ch_canvas = canvas[2] * h + canvas[3]
        ch = max(ch_canvas, ch) if node.get("AutomaticCanvasSize", "None") in ("Y", "XY") else (ch_canvas or ch)
    kids = visible_gui_children(node)
    lay = child_of(node, "UIListLayout")
    grid = child_of(node, "UIGridLayout")
    if lay or grid:
        kids.sort(key=lambda k: (k.get("LayoutOrder", 0), k.get("Name", "")))
    if grid:
        cell = udim2(grid.get("CellSize")) or [0, 100, 0, 100]
        gap = udim2(grid.get("CellPadding")) or [0, 5, 0, 5]
        cwid, chei = cell[0] * cw + cell[1], cell[2] * ch + cell[3]
        gx, gy = gap[0] * cw + gap[1], gap[2] * ch + gap[3]
        per = max(1, int((cw + gx) // (cwid + gx))) if cwid + gx > 0 else 1
        for i, k in enumerate(kids):
            kb = layout_fixed(k, box, cx + (i % per) * (cwid + gx), cy + (i // per) * (chei + gy), cwid, chei, clip)
            box.kids.append(kb)
    elif lay:
        horizontal = lay.get("FillDirection", "Vertical") == "Horizontal"
        gap = (lay.get("Padding") or [0, 0])
        gap = gap[0] * (cw if horizontal else ch) + gap[1]
        placed = []
        for k in kids:
            kw, kh = resolve_size(k, cw, ch)
            kw, kh = auto_size(k, kw, kh, cw, ch)
            placed.append((k, kw, kh))
        total = sum((p[1] if horizontal else p[2]) for p in placed) + gap * max(0, len(placed) - 1)
        ha, va = lay.get("HorizontalAlignment", "Left"), lay.get("VerticalAlignment", "Top")
        if horizontal:
            off = cx + {"Left": 0, "Center": (cw - total) / 2, "Right": cw - total}.get(ha, 0)
        else:
            off = cy + {"Top": 0, "Center": (ch - total) / 2, "Bottom": ch - total}.get(va, 0)
        for k, kw, kh in placed:
            if horizontal:
                y = cy + {"Top": 0, "Center": (ch - kh) / 2, "Bottom": ch - kh}.get(va, 0)
                box.kids.append(place(k, box, off, y, kw, kh, cw, ch, clip))
                off += kw + gap
            else:
                x = cx + {"Left": 0, "Center": (cw - kw) / 2, "Right": cw - kw}.get(ha, 0)
                box.kids.append(place(k, box, x, off, kw, kh, cw, ch, clip))
                off += kh + gap
    else:
        for k in kids:
            kw, kh = resolve_size(k, cw, ch)
            kw, kh = auto_size(k, kw, kh, cw, ch)
            p = udim2(k.get("Position"))
            a = k.get("AnchorPoint") or [0, 0]
            x = cx + p[0] * cw + p[1] - a[0] * kw
            y = cy + p[2] * ch + p[3] - a[1] * kh
            box.kids.append(place(k, box, x, y, kw, kh, cw, ch, clip))
    if node["class"] in TEXT:
        measure_text(box)
    uiscale = child_of(node, "UIScale")
    if uiscale and abs(uiscale.get("Scale", 1) - 1) > 1e-3:
        a = node.get("AnchorPoint") or [0, 0]
        scale_subtree(box, box.x + a[0] * box.w, box.y + a[1] * box.h, uiscale["Scale"])
    return box


def scale_subtree(box, ox, oy, s):
    """UIScale: shrink a laid-out subtree about its anchor point."""
    for b in walk(box):
        b.x, b.y = ox + (b.x - ox) * s, oy + (b.y - oy) * s
        b.w, b.h = b.w * s, b.h * s
        b.scale *= s
        if b.ink:
            b.ink = (ox + (b.ink[0] - ox) * s, oy + (b.ink[1] - oy) * s, ox + (b.ink[2] - ox) * s, oy + (b.ink[3] - oy) * s)
        if b.clip and b is not box:
            b.clip = (ox + (b.clip[0] - ox) * s, oy + (b.clip[1] - oy) * s, ox + (b.clip[2] - ox) * s, oy + (b.clip[3] - oy) * s)


def place(node, parent, x, y, w, h, pw, ph, clip):
    return layout_fixed(node, parent, x, y, w, h, clip)


def layout_fixed(node, parent, x, y, w, h, clip):
    saved = node.get("Size"), node.get("AutomaticSize")
    node["Size"], node["AutomaticSize"] = [0, w, 0, h], "None"
    b = layout(node, parent, x, y, w, h, clip)
    node["Size"], node["AutomaticSize"] = saved
    return b


def intersect(a, b):
    if a is None:
        return b
    return (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))


def measure_text(box):
    n = box.node
    l, t, r, b = padding_of(n, box.w, box.h)
    cw, ch = box.w - l - r, box.h - t - b
    if n.get("TextScaled"):
        size = n.get("TextSize", 14)
        con = child_of(n, "UITextSizeConstraint")
        size = con.get("MaxTextSize", 100) if con else 100
        fname = n.get("Font", "Legacy")
        t_ = plain(n.get("Text", ""), n.get("RichText"))
        while size > 1:
            tw, th, lines = text_metrics(dict(n, TextSize=size), cw)
            if tw <= cw and th <= ch:
                break
            size -= 1
        n["_scaled"] = size
    tw, th, lines = text_metrics(n if not n.get("TextScaled") else dict(n, TextSize=n["_scaled"]), cw)
    box.lines = lines
    xa, ya = n.get("TextXAlignment", "Center"), n.get("TextYAlignment", "Center")
    ix = box.x + l + {"Left": 0, "Center": (cw - tw) / 2, "Right": cw - tw}.get(xa, (cw - tw) / 2)
    iy = box.y + t + {"Top": 0, "Center": (ch - th) / 2, "Bottom": ch - th}.get(ya, (ch - th) / 2)
    box.ink = (ix, iy, ix + tw, iy + th) if tw > 0 else None


def walk(box):
    yield box
    for k in box.kids:
        yield from walk(k)


def path(box):
    names = []
    b = box
    while b is not None:
        names.append(b.node.get("Name", b.node["class"]))
        b = b.parent
    return ".".join(reversed(names))


def check(scene_boxes, view):
    problems = []
    texts = []
    for root in scene_boxes:
        for b in walk(root):
            n = b.node
            if n["class"] in TEXT and b.ink and n.get("TextTransparency", 0) < 0.99 and plain(n.get("Text", ""), n.get("RichText")).strip():
                l, t, r, bt = (v * b.scale for v in padding_of(n, b.w / b.scale, b.h / b.scale))
                cw, ch = b.w - l - r, b.h - t - bt
                tw, th = b.ink[2] - b.ink[0], b.ink[3] - b.ink[1]
                label = plain(n.get("Text", ""), n.get("RichText"))[:50].replace("\n", " | ")
                if not n.get("TextScaled"):
                    if tw > cw + 1.5:
                        kind = "clipped" if n.get("TextTruncate", "None") != "None" else "overflow"
                        problems.append((kind, path(b), f"text {tw:.0f}px wide in {cw:.0f}px: \"{label}\""))
                    if th > ch + 2:
                        problems.append(("overflow", path(b), f"text {th:.0f}px tall in {ch:.0f}px: \"{label}\""))
                elif n.get("_scaled", 99) < 9:
                    problems.append(("overflow", path(b), f"scaled down to {n['_scaled']}px: \"{label}\""))
                ink = b.ink if not b.clip else intersect(b.clip, b.ink)
                if ink[2] > ink[0] and ink[3] > ink[1]:
                    texts.append((b, ink, label))
            p = b.parent
            if p is not None and p.node["class"] in GUI and n["class"] in GUI and p.node["class"] != "ScrollingFrame" and not p.node.get("ClipsDescendants"):
                if b.x < p.x - 1.5 or b.y < p.y - 1.5 or b.x + b.w > p.x + p.w + 1.5 or b.y + b.h > p.y + p.h + 1.5:
                    if p.w > 0 and p.h > 0:
                        problems.append(("spill", path(b), f"box {b.x:.0f},{b.y:.0f} {b.w:.0f}x{b.h:.0f} outside parent {p.x:.0f},{p.y:.0f} {p.w:.0f}x{p.h:.0f}"))
            hidden = b.clip is not None and (b.clip[2] <= b.x or b.clip[3] <= b.y or b.clip[0] >= b.x + b.w or b.clip[1] >= b.y + b.h or (b.clip[1] >= 0 and b.clip[3] <= view[1] and b.clip[0] >= 0 and b.clip[2] <= view[0]))
            if not hidden and n["class"] in GUI and b.w > 0 and b.h > 0 and (b.x < -1 or b.y < -1 or b.x + b.w > view[0] + 1 or b.y + b.h > view[1] + 1):
                problems.append(("offscreen", path(b), f"{b.x:.0f},{b.y:.0f} {b.w:.0f}x{b.h:.0f}"))
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            a, ia, la = texts[i]
            c, ic, lc = texts[j]
            if is_ancestor(a, c) or is_ancestor(c, a):
                continue
            ox = min(ia[2], ic[2]) - max(ia[0], ic[0])
            oy = min(ia[3], ic[3]) - max(ia[1], ic[1])
            if ox > 2 and oy > 3:
                problems.append(("collide", path(a), f"\"{la}\" overlaps \"{lc}\" ({path(c)})"))
    return problems


def is_ancestor(a, b):
    p = b.parent
    while p is not None:
        if p is a:
            return True
        p = p.parent
    return False


def rgba(c, transparency):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(255 * (1 - transparency)))


def render(scene_boxes, view, out):
    img = Image.new("RGBA", (int(view[0]), int(view[1])), (92, 104, 96, 255))
    # A rough "game" backdrop so dark panels read.
    d = ImageDraw.Draw(img)
    for y in range(int(view[1])):
        k = y / view[1]
        d.line([(0, y), (view[0], y)], fill=(int(120 - 50 * k), int(140 - 40 * k), int(150 - 70 * k), 255))
    for root in scene_boxes:
        draw_box(img, root)
    img.convert("RGB").save(out)


def draw_box(img, b):
    n = b.node
    if n["class"] not in GUI and n["class"] not in ("ScreenGui", "SurfaceGui"):
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rect = [b.x, b.y, b.x + b.w - 1, b.y + b.h - 1]
    corner = child_of(n, "UICorner")
    radius = 0
    if corner:
        cr = corner.get("CornerRadius") or [0, 8]
        radius = cr[0] * min(b.w, b.h) + cr[1]
    if n["class"] in GUI and b.w > 0 and b.h > 0:
        bt = n.get("BackgroundTransparency", 0)
        if bt < 1:
            d.rounded_rectangle(rect, radius=max(0, radius), fill=rgba(n.get("BackgroundColor3", [0.64, 0.64, 0.65]), bt))
        if n["class"] in ("ImageLabel", "ImageButton") and n.get("Image"):
            d.rounded_rectangle(rect, radius=max(0, radius), outline=(200, 200, 200, 120))
            d.line([rect[0], rect[1], rect[2], rect[3]], fill=(200, 200, 200, 60))
        stroke = child_of(n, "UIStroke")
        if stroke and n["class"] not in TEXT or (stroke and stroke.get("ApplyStrokeMode") == "Border"):
            if stroke.get("Enabled", True):
                d.rounded_rectangle(rect, radius=max(0, radius), outline=rgba(stroke.get("Color", [0, 0, 0]), stroke.get("Transparency", 0)), width=max(1, int(stroke.get("Thickness", 1))))
        if n["class"] in TEXT and b.lines is not None and b.ink:
            size = (n.get("_scaled") if n.get("TextScaled") else n.get("TextSize", 14)) * b.scale
            f = font(n.get("Font", "Legacy"), size)
            lh = size * (n.get("LineHeight") or 1)
            xa = n.get("TextXAlignment", "Center")
            l, t, r, bt2 = (v * b.scale for v in padding_of(n, b.w / b.scale, b.h / b.scale))
            for i, line in enumerate(b.lines):
                lw = f.getlength(line)
                if xa == "Left":
                    x = b.x + l
                elif xa == "Right":
                    x = b.x + b.w - r - lw
                else:
                    x = b.x + l + (b.w - l - r - lw) / 2
                y = b.ink[1] + i * lh + (lh - size) / 2 - size * 0.08
                d.text((x, y), line, font=f, fill=rgba(n.get("TextColor3", [0, 0, 0]), n.get("TextTransparency", 0)))
    if b.clip:
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rectangle([b.clip[0], b.clip[1], b.clip[2], b.clip[3]], fill=255)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
    img.alpha_composite(layer)
    kids = sorted(b.kids, key=lambda k: k.node.get("ZIndex", 1))
    for k in kids:
        draw_box(img, k)


def scene_layout(scene, view, inset):
    boxes = []
    guis = sorted(scene["guis"], key=lambda g: g.get("DisplayOrder", 0))
    for g in guis:
        if g.get("Enabled") is False:
            continue
        top = 0 if g.get("IgnoreGuiInset") else inset
        # The gui itself is the screen-sized root (its UIListLayout / UIPadding apply).
        boxes.append(layout_fixed(g, None, 0, top, view[0], view[1] - top, None))
    return boxes


def main():
    global FONT_DIR
    ap = argparse.ArgumentParser()
    ap.add_argument("ui")
    ap.add_argument("out")
    ap.add_argument("--fonts", default=FONT_DIR)
    ap.add_argument("--scene", default=None)
    args = ap.parse_args()
    FONT_DIR = args.fonts
    data = json.load(open(args.ui))
    if "surfaces" in data:
        # World signs (tools/world/build.luau): each SurfaceGui is a screen of its own.
        data = {"viewport": None, "scenes": [{"name": s["name"].replace("Workspace.", "").replace(".", "_"), "view": s["canvas"], "guis": [s["gui"]]} for s in data["surfaces"]]}
    view, inset = data["viewport"], data.get("inset", 58)
    os.makedirs(args.out, exist_ok=True)
    total = 0
    for scene in data["scenes"]:
        if args.scene and scene["name"] != args.scene:
            continue
        sview, sinset = (scene["view"], 0) if scene.get("view") else (view, inset)
        boxes = scene_layout(scene, sview, sinset)
        render(boxes, sview, os.path.join(args.out, scene["name"] + ".png"))
        problems = check(boxes, sview)
        seen = set()
        print(f"== {scene['name']}: {len(problems)} problems")
        for kind, where, what in problems:
            key = (kind, re.sub(r"\d+", "#", where))
            if key in seen:
                continue
            seen.add(key)
            print(f"  {kind:9} {where}: {what}")
        total += len(problems)
    print(f"total {total}")


if __name__ == "__main__":
    main()
