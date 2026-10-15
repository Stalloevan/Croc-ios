#!/usr/bin/env python3
"""Builds the app icon and the in-app logo from the getcroc.com favicon (design/favicon.png).

The favicon is a 128x128 flat-colour image, so instead of stretching pixels it is
rebuilt region by region (green / navy outline / white eye): each colour's mask is
upscaled, smoothed and thresholded, which keeps edges crisp at any size.

Outputs:
  CrocApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png   (opaque 1024x1024)
  CrocApp/Assets.xcassets/CrocMark.imageset/crocmark.png     (transparent, 512px)
Run: python3 scripts/make_icon.py   (needs Pillow)
"""
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "design", "favicon.png")

GREEN, NAVY, WHITE = (139, 194, 63), (1, 20, 60), (254, 254, 253)
SCALE = 8


def classify(im):
    """Return masks for green / white / navy / any-ink at source resolution."""
    w, h = im.size
    px = im.load()
    masks = {k: Image.new("L", (w, h), 0) for k in ("green", "white", "navy", "ink")}
    mp = {k: m.load() for k, m in masks.items()}
    palette = {"green": GREEN, "navy": NAVY, "white": WHITE}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            best = min(palette, key=lambda k: sum((c1 - c2) ** 2 for c1, c2 in zip((r, g, b), palette[k])))
            mp[best][x, y] = 255
            mp["ink"][x, y] = 255
    return masks


def smooth(mask, size):
    big = mask.resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(SCALE * 0.9))
    return big.point(lambda v: 255 if v >= 128 else 0)


def rebuild(size=1024):
    im = Image.open(SRC).convert("RGBA")
    m = classify(im)
    s = {k: smooth(v, size) for k, v in m.items()}
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (size, size), NAVY + (255,)), (0, 0), s["ink"])   # outline + dark details
    out.paste(Image.new("RGBA", (size, size), GREEN + (255,)), (0, 0), s["green"])
    out.paste(Image.new("RGBA", (size, size), WHITE + (255,)), (0, 0), s["white"])
    # Clip everything to the smoothed silhouette so edges stay clean.
    alpha = ImageChops.multiply(out.getchannel("A"), s["ink"])
    out.putalpha(alpha)
    return out


def crop_square(img, pad=0.0):
    box = img.getchannel("A").getbbox()
    cropped = img.crop(box)
    side = int(max(cropped.size) * (1 + pad * 2))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    return sq


def make_icon(logo, path):
    S = 2048
    bg = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(bg)
    top, bot = (255, 255, 255), (226, 241, 205)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    mark = crop_square(logo).resize((int(S * 0.74), int(S * 0.74)), Image.LANCZOS)
    pos = ((S - mark.width) // 2, (S - mark.height) // 2)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 40, 20, 70), pos, mark.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    bg.paste(shadow, (0, 16), shadow)
    bg.paste(mark, pos, mark)
    bg.resize((1024, 1024), Image.LANCZOS).save(path)


if __name__ == "__main__":
    logo = rebuild(1024)
    assets = os.path.join(ROOT, "CrocApp", "Assets.xcassets")
    icon_dir = os.path.join(assets, "AppIcon.appiconset")
    mark_dir = os.path.join(assets, "CrocMark.imageset")
    os.makedirs(icon_dir, exist_ok=True)
    os.makedirs(mark_dir, exist_ok=True)
    make_icon(logo, os.path.join(icon_dir, "icon-1024.png"))
    crop_square(logo, 0.02).resize((512, 512), Image.LANCZOS).save(os.path.join(mark_dir, "crocmark.png"))
    with open(os.path.join(mark_dir, "Contents.json"), "w") as f:
        f.write('{\n  "images" : [\n    { "filename" : "crocmark.png", "idiom" : "universal" }\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
    print("ok")
