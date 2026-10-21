#!/usr/bin/env python3
"""Finds free models on the Roblox Creator Store for the asset library (AssetLibrary.luau).

    python3 tools/world/scout.py "potted plant" sheet.png [--limit 16] [--endorsed]

Searches the store, keeps models without scripts, and saves a contact sheet of their
thumbnails labelled with id, name, creator, votes and triangle count, to pick from.
"""
import argparse
import io
import json
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw

UA = {"User-Agent": "Mozilla/5.0 (asset-scout)"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return r.read()


def search(keyword, limit, endorsed):
    params = {"keyword": keyword, "limit": 30}
    if endorsed:
        params["includeOnlyVerifiedCreators"] = "true"
    data = json.loads(get("https://apis.roblox.com/toolbox-service/v1/marketplace/10?" + urllib.parse.urlencode(params)))
    ids = [str(x["id"]) for x in data.get("data", [])]
    if not ids:
        return []
    details = json.loads(get("https://apis.roblox.com/toolbox-service/v1/items/details?assetIds=" + ",".join(ids)))["data"]
    found = []
    for d in details:
        a = d["asset"]
        tech = a.get("modelTechnicalDetails") or {}
        found.append({
            "id": a["id"],
            "name": a["name"],
            "creator": d["creator"]["name"],
            "verified": d["creator"].get("isVerifiedCreator", False),
            "endorsed": a.get("isEndorsed", False),
            "scripts": a.get("scriptCount", 0),
            "up": d.get("voting", {}).get("upVotePercent", 0),
            "votes": d.get("voting", {}).get("voteCount", 0),
            "tris": (tech.get("objectMeshSummary") or {}).get("triangles", 0),
        })
    found = [f for f in found if f["scripts"] == 0]
    found.sort(key=lambda f: (not f["endorsed"], -f["votes"] * f["up"]))
    return found[:limit]


def sheet(items, out):
    ids = ",".join(str(i["id"]) for i in items)
    thumbs = {}
    if ids:
        data = json.loads(get(f"https://thumbnails.roblox.com/v1/assets?assetIds={ids}&size=250x250&format=Png"))["data"]
        for t in data:
            if t.get("imageUrl"):
                try:
                    thumbs[t["targetId"]] = Image.open(io.BytesIO(get(t["imageUrl"]))).convert("RGB")
                except Exception:
                    pass
    cols = 4
    rows = (len(items) + cols - 1) // cols
    cell_w, cell_h = 250, 300
    img = Image.new("RGB", (cols * cell_w, max(1, rows) * cell_h), (30, 30, 34))
    draw = ImageDraw.Draw(img)
    for n, item in enumerate(items):
        x, y = (n % cols) * cell_w, (n // cols) * cell_h
        if item["id"] in thumbs:
            img.paste(thumbs[item["id"]].resize((250, 250)), (x, y))
        tag = "E " if item["endorsed"] else ""
        draw.text((x + 4, y + 252), f"{tag}{item['id']}", fill=(255, 200, 80))
        draw.text((x + 4, y + 266), item["name"][:34], fill=(255, 255, 255))
        draw.text((x + 4, y + 280), f"{item['creator'][:16]} {item['up']}%/{item['votes']} {item['tris']}t", fill=(170, 180, 200))
    img.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keyword")
    ap.add_argument("out")
    ap.add_argument("--limit", type=int, default=16)
    ap.add_argument("--endorsed", action="store_true")
    a = ap.parse_args()
    items = search(a.keyword, a.limit, a.endorsed)
    json.dump(items, sys.stdout, indent=1)
    print()
    sheet(items, a.out)


if __name__ == "__main__":
    main()
