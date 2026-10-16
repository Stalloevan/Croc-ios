#!/usr/bin/env python3
"""Builds the app icon and the in-app logo from the getcroc.com favicon (design/favicon.png).

The favicon is a 128x128 flat-colour image, so instead of stretching pixels it is
rebuilt region by region (green / navy outline / white eye): each colour's mask is
upscaled, smoothed and thresholded, which keeps edges crisp at any size.

Outputs:
  CrocApp/Assets.xcassets/AppIcon.appiconset/icon-1024.png         light icon (opaque 1024x1024)
  CrocApp/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png    dark-mode icon
  CrocApp/Assets.xcassets/AppIcon.appiconset/icon-1024-tinted.png  tinted (monochrome) icon
  CrocApp/Assets.xcassets/CrocMark.imageset/crocmark.png           in-app logo (transparent, 512px)
  CrocApp/Assets.xcassets/CrocMark.imageset/crocmark-dark.png      in-app logo for dark mode (light outline)
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
    split_navy(masks)
    return masks


def split_navy(masks):
    """Split the navy mask into the outer outline (touches transparency) and inner
    details (eye ring, pupil, nostril, mouth line), so the outline can be recoloured."""
    from collections import deque
    w, h = masks["navy"].size
    navy, ink = masks["navy"].load(), masks["ink"].load()
    outline = Image.new("L", (w, h), 0)
    op = outline.load()
    seen = set()
    for y in range(h):
        for x in range(w):
            if not navy[x, y] or (x, y) in seen:
                continue
            comp, touches, dq = [], False, deque([(x, y)])
            seen.add((x, y))
            while dq:
                cx, cy = dq.popleft()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if not (0 <= nx < w and 0 <= ny < h) or not ink[nx, ny]:
                        touches = True
                    elif navy[nx, ny] and (nx, ny) not in seen:
                        seen.add((nx, ny))
                        dq.append((nx, ny))
            if touches:
                for pt in comp:
                    op[pt] = 255
    masks["outline"] = outline
    masks["inner"] = ImageChops.subtract(masks["navy"], outline)


def smooth(mask, size):
    big = mask.resize((size, size), Image.BICUBIC).filter(ImageFilter.GaussianBlur(SCALE * 0.9))
    return big.point(lambda v: 255 if v >= 128 else 0)


def rebuild(size=1024, outline=NAVY, green=GREEN, white=WHITE, inner=NAVY):
    """Rebuild the logo at `size` px. Colours can be swapped for the dark / tinted variants."""
    im = Image.open(SRC).convert("RGBA")
    m = classify(im)
    s = {k: smooth(v, size) for k, v in m.items()}
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (size, size), outline + (255,)), (0, 0), s["ink"])   # silhouette = outline colour
    out.paste(Image.new("RGBA", (size, size), green + (255,)), (0, 0), s["green"])
    out.paste(Image.new("RGBA", (size, size), white + (255,)), (0, 0), s["white"])
    out.paste(Image.new("RGBA", (size, size), inner + (255,)), (0, 0), s["inner"])   # eye ring, pupil, mouth
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


def gradient(S, top, bot):
    bg = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    return bg


def make_icon(logo, path, top, bot, shadow=True):
    S = 2048
    bg = gradient(S, top, bot)
    mark = crop_square(logo).resize((int(S * 0.74), int(S * 0.74)), Image.LANCZOS)
    pos = ((S - mark.width) // 2, (S - mark.height) // 2)
    if shadow:
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sh.paste((0, 40, 20, 70), pos, mark.getchannel("A"))
        sh = sh.filter(ImageFilter.GaussianBlur(28))
        bg.paste(sh, (0, 16), sh)
    bg.paste(mark, pos, mark)
    bg.resize((1024, 1024), Image.LANCZOS).save(path)


if __name__ == "__main__":
    LIGHT_OUTLINE = (244, 246, 238)
    assets = os.path.join(ROOT, "CrocApp", "Assets.xcassets")
    icon_dir = os.path.join(assets, "AppIcon.appiconset")
    mark_dir = os.path.join(assets, "CrocMark.imageset")
    os.makedirs(icon_dir, exist_ok=True)
    os.makedirs(mark_dir, exist_ok=True)

    light = rebuild(1024)
    dark = rebuild(1024, outline=LIGHT_OUTLINE)
    tinted = rebuild(1024, outline=(255, 255, 255), green=(150, 150, 150), white=(255, 255, 255), inner=(0, 0, 0))

    make_icon(light, os.path.join(icon_dir, "icon-1024.png"), (255, 255, 255), (226, 241, 205))
    make_icon(dark, os.path.join(icon_dir, "icon-1024-dark.png"), (40, 44, 42), (9, 11, 10), shadow=False)
    make_icon(tinted, os.path.join(icon_dir, "icon-1024-tinted.png"), (0, 0, 0), (0, 0, 0), shadow=False)

    crop_square(light, 0.02).resize((512, 512), Image.LANCZOS).save(os.path.join(mark_dir, "crocmark.png"))
    crop_square(dark, 0.02).resize((512, 512), Image.LANCZOS).save(os.path.join(mark_dir, "crocmark-dark.png"))

    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        f.write('''{
  "images" : [
    { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "icon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "icon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
''')
    with open(os.path.join(mark_dir, "Contents.json"), "w") as f:
        f.write('''{
  "images" : [
    { "filename" : "crocmark.png", "idiom" : "universal" },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "crocmark-dark.png", "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
''')
    print("ok")
