#!/usr/bin/env python3
"""Generate the tvOS App Icon (layered/parallax) + Top Shelf images for
ReversionTV from the brand mark + lockup, and wire the brandassets Contents.json.

Run from the repo root: python3 scripts/gen_tv_icons.py
Sources:
  - brand mark  : ../reversion-tv/assets/brand-mark-square-dark.png (transparent)
  - brand lockup: ../reversion-tv-assets/logo-with-asset-1920x1080.png (transparent)
"""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
BRAND = os.path.join(REPO, "Resources", "Assets.xcassets",
                     "App Icon & Top Shelf Image.brandassets")

MARK = os.path.join(REPO, "..", "reversion-tv", "assets", "brand-mark-square-dark.png")
LOCKUP = os.path.join(REPO, "..", "reversion-tv-assets", "logo-with-asset-1920x1080.png")

# Brand navy gradient (Theme.bg #131A24, lifted slightly at top for depth).
TOP = (26, 34, 48)
BOTTOM = (14, 20, 30)


def gradient(w, h):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = round(TOP[0] + (BOTTOM[0] - TOP[0]) * t)
        g = round(TOP[1] + (BOTTOM[1] - TOP[1]) * t)
        b = round(TOP[2] + (BOTTOM[2] - TOP[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return img


def cropped(path):
    im = Image.open(path).convert("RGBA")
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def fitted(overlay, max_w, max_h):
    o = overlay.copy()
    o.thumbnail((int(max_w), int(max_h)), Image.LANCZOS)
    return o


def centered(base, overlay):
    x = (base.width - overlay.width) // 2
    y = (base.height - overlay.height) // 2
    base.alpha_composite(overlay, (x, y))


def write_json(folder, images):
    path = os.path.join(folder, "Contents.json")
    with open(path, "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
                  f, indent=2)


mark = cropped(MARK)
lockup = cropped(LOCKUP)


def make_icon_back(folder, sizes):
    images = []
    for w, h, scale in sizes:
        name = f"back_{w}x{h}.png"
        gradient(w, h).save(os.path.join(folder, name))
        images.append({"idiom": "tv", "scale": scale, "filename": name})
    write_json(folder, images)


def make_icon_front(folder, sizes):
    images = []
    for w, h, scale in sizes:
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        centered(canvas, fitted(mark, w * 0.60, h * 0.80))
        name = f"front_{w}x{h}.png"
        canvas.save(os.path.join(folder, name))
        images.append({"idiom": "tv", "scale": scale, "filename": name})
    write_json(folder, images)


def make_top_shelf(folder, sizes):
    images = []
    for w, h, scale in sizes:
        canvas = gradient(w, h)
        centered(canvas, fitted(lockup, w * 0.80, h * 0.64))
        name = f"topshelf_{w}x{h}.png"
        canvas.convert("RGB").save(os.path.join(folder, name))
        images.append({"idiom": "tv", "scale": scale, "filename": name})
    write_json(folder, images)


# Home App Icon — 400x240 (1x) + 800x480 (2x), layered.
home = "App Icon.imagestack"
make_icon_back(os.path.join(BRAND, home, "Back.imagestacklayer", "Content.imageset"),
               [(400, 240, "1x"), (800, 480, "2x")])
make_icon_front(os.path.join(BRAND, home, "Front.imagestacklayer", "Content.imageset"),
                [(400, 240, "1x"), (800, 480, "2x")])

# App Store App Icon — 1280x768 (1x only), layered.
store = "App Icon - App Store.imagestack"
make_icon_back(os.path.join(BRAND, store, "Back.imagestacklayer", "Content.imageset"),
               [(1280, 768, "1x")])
make_icon_front(os.path.join(BRAND, store, "Front.imagestacklayer", "Content.imageset"),
                [(1280, 768, "1x")])

# Top Shelf — 1920x720 (1x) + 3840x1440 (2x).
make_top_shelf(os.path.join(BRAND, "Top Shelf Image.imageset"),
               [(1920, 720, "1x"), (3840, 1440, "2x")])

# Top Shelf Wide — 2320x720 (1x) + 4640x1440 (2x).
make_top_shelf(os.path.join(BRAND, "Top Shelf Image Wide.imageset"),
               [(2320, 720, "1x"), (4640, 1440, "2x")])

print("Done.")
