"""Rasterizes the SoulBound mark (SoulUI/Media/Source/soulbound-mark.svg,
copied from the SoulBound website repo, public/brand/mark.svg) into WoW
textures. No downloads: Pillow draws each layer at 4x and downsamples.

Layers, so the in-game mark can animate them separately:
  LogoSparkles.tga  the star sparkles around the swirl
  LogoSoul.tga      the soul swirl, wisps and the star (rises out of the book)
  LogoBook.tga      the open book
  Logo.tga          everything composited (addon icon)

Run from the repo root:  python tools/build_logo.py
"""
import re
from PIL import Image, ImageDraw, ImageChops

SRC = "SoulUI/Media/Source/soulbound-mark.svg"
OUT = "SoulUI/Media/Textures/"
SIZE = 256
SS = 4  # supersampling

svg = open(SRC, encoding="utf-8").read()
vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
VX, VY, VW, VH = vb

def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

# Vertical linear gradients by id: (y1, y2, [(offset, rgb)])
grads = {}
for m in re.finditer(r'<linearGradient id="(\w+)"[^>]*y1="([\d.]+)"[^>]*y2="([\d.]+)">(.*?)</linearGradient>', svg, re.S):
    stops = [(float(o), hex_rgb(c)) for o, c in re.findall(r'offset="([\d.]+)" stop-color="(#[0-9a-fA-F]{6})"', m.group(4))]
    grads[m.group(1)] = (float(m.group(2)), float(m.group(3)), stops)

paths = re.findall(r'<path d="([^"]+)" fill="([^"]+)"', svg)

def subpaths(d):
    """M/C/L/Z path -> list of polygons (cubics flattened)."""
    tokens = re.findall(r'[MCLZmclz]|-?[\d.]+', d)
    polys, cur, i, cmd = [], [], 0, None
    x = y = 0.0
    while i < len(tokens):
        t = tokens[i]
        if t in "MCLZmclz":
            cmd = t
            i += 1
            if cmd in "Zz":
                if cur:
                    polys.append(cur)
                cur = []
            continue
        if cmd == "M":
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            if cur:
                polys.append(cur)
            cur = [(x, y)]
            cmd = "L"
        elif cmd == "L":
            x, y = float(tokens[i]), float(tokens[i + 1])
            i += 2
            cur.append((x, y))
        elif cmd == "C":
            x1, y1, x2, y2, x3, y3 = (float(tokens[i + k]) for k in range(6))
            i += 6
            for s in range(1, 9):
                u = s / 8.0
                a = (1 - u) ** 3
                b = 3 * (1 - u) ** 2 * u
                c = 3 * (1 - u) * u * u
                e = u ** 3
                cur.append((a * x + b * x1 + c * x2 + e * x3, a * y + b * y1 + c * y2 + e * y3))
            x, y = x3, y3
        else:
            i += 1
    if cur:
        polys.append(cur)
    return polys

BIG = SIZE * SS

def to_px(p):
    return ((p[0] - VX) / VW * BIG, (p[1] - VY) / VH * BIG)

def fill_layer(img, d, fill):
    # Even-odd: XOR each subpath into one mask, so holes stay open.
    mask = Image.new("1", (BIG, BIG), 0)
    for poly in subpaths(d):
        if len(poly) < 3:
            continue
        one = Image.new("1", (BIG, BIG), 0)
        ImageDraw.Draw(one).polygon([to_px(p) for p in poly], fill=1)
        mask = ImageChops.logical_xor(mask, one)
    if fill.startswith("url("):
        y1, y2, stops = grads[re.search(r"#(\w+)", fill).group(1)]
        color = Image.new("RGBA", (BIG, BIG))
        px = color.load()
        rows = []
        for row in range(BIG):
            vy = VY + row / BIG * VH
            t = min(1.0, max(0.0, (vy - y1) / (y2 - y1)))
            for k in range(len(stops) - 1):
                o0, c0 = stops[k]
                o1, c1 = stops[k + 1]
                if t <= o1 or k == len(stops) - 2:
                    f = 0.0 if o1 == o0 else min(1.0, max(0.0, (t - o0) / (o1 - o0)))
                    rows.append(tuple(int(c0[j] + (c1[j] - c0[j]) * f) for j in range(3)) + (255,))
                    break
        draw = ImageDraw.Draw(color)
        for row, rgba in enumerate(rows):
            draw.line([(0, row), (BIG, row)], fill=rgba)
    else:
        color = Image.new("RGBA", (BIG, BIG), hex_rgb(fill) + (255,))
    img.paste(color, (0, 0), mask.convert("L"))

LAYERS = {
    "LogoSparkles": {"#8fd9fb"},
    "LogoSoul": {"#3f9cf0", "url(#s)", "#eaf8ff"},
    "LogoBook": {"#0a4c9c", "url(#c)", "#8ed6fb", "#2484d8", "#84ccf1"},
}

def save_tga(img, name):
    # Uncompressed 32-bit, top-left origin: the same header as the other
    # SoulUI textures, which the client is known to read.
    import struct
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    data = bytearray()
    for r, g, b, a in img.getdata():
        data += bytes((b, g, r, a))
    with open(OUT + name + ".tga", "wb") as f:
        f.write(header + bytes(data))
    print("wrote", OUT + name + ".tga")

full = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
for name, fills in LAYERS.items():
    layer = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    for d, fill in paths:
        if fill in fills:
            fill_layer(layer, d, fill)
    save_tga(layer, name)
for d, fill in paths:
    fill_layer(full, d, fill)
save_tga(full, "Logo")
