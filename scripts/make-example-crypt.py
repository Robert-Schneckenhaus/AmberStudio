#!/usr/bin/env python3
# Makes the 3D map of the example game (game/content/maps/crypt.tmx) with its textures, all drawn here (no third-party
# graphics, MIT like the rest of the repository). The textures have the formats of Ambermoon: walls 128x80, floor and
# ceiling 64x64, billboards 32x48 (a width in multiples of 16). A game replaces them with its own tilesets of the same
# sizes. Needs Pillow; running this again overwrites the files.
#
#   python3 scripts/make-example-crypt.py
#
# The layers of a 3D map: objects = walls (a wall tile per cell, 0 = free), ground = floor, decor = ceiling,
# over = billboards (barrels, pillars), collision = blocked cells without a wall.
import os
import random
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "content", "maps")
WALLS = ["stone", "brick", "moss", "door", "stairs"]
FLOORS = ["flagstones", "ceiling"]
THINGS = ["pillar", "barrel", "urn", "bones"]
WALL_GID = {name: i + 1 for i, name in enumerate(WALLS)}
FLOOR_GID = {name: i + 101 for i, name in enumerate(FLOORS)}
THING_GID = {name: i + 201 for i, name in enumerate(THINGS)}
COLLISION = 301

# the map: # stone, B brick, M moss, D door, U the stairs up (a wall), p pillar, b barrel, u urn, k bones, x a blocked cell
LAYOUT = [
    "################",
    "#U.....#.......#",
    "#......D...u...#",
    "#......#.......#",
    "##.#####BBDBBBB#",
    "#....p....#....#",
    "#.........#..k.#",
    "#....p....M....#",
    "######.####....#",
    "#b...M.M..######",
    "#....D.D.......#",
    "#b...M.M...u...#",
    "################",
]


def noise(draw, x0, y0, w, h, base, amount, rng, count):
    for _ in range(count):
        x = x0 + rng.randrange(w)
        y = y0 + rng.randrange(h)
        d = rng.randint(-amount, amount)
        draw.point((x, y), fill=tuple(max(0, min(255, c + d)) for c in base) + (255,))


def blocks(draw, x0, rng, base, mortar, rows, cols):
    draw.rectangle([x0, 0, x0 + 127, 79], fill=mortar + (255,))
    h = 80 // rows
    for r in range(rows):
        offset = (r % 2) * (128 // cols // 2)
        for c in range(-1, cols + 1):
            bx = x0 + c * (128 // cols) + offset
            left, right = max(x0, bx + 1), min(x0 + 127, bx + 128 // cols - 2)
            if right <= left:
                continue
            shade = rng.randint(-14, 14)
            color = tuple(max(0, min(255, v + shade)) for v in base)
            draw.rectangle([left, r * h + 1, right, r * h + h - 2], fill=color + (255,))
            noise(draw, left, r * h + 1, right - left + 1, h - 2, color, 18, rng, 40)


def wall(draw, index, name, rng):
    x0 = index * 128
    if name in ("stone", "door", "stairs"):
        blocks(draw, x0, rng, (118, 112, 104), (58, 54, 50), 5, 4)
    elif name == "brick":
        blocks(draw, x0, rng, (146, 72, 52), (70, 50, 44), 10, 8)
    elif name == "moss":
        blocks(draw, x0, rng, (104, 108, 96), (50, 54, 46), 5, 4)
        for _ in range(260):
            x, y = x0 + rng.randrange(128), rng.randrange(80)
            if rng.random() < (y / 80.0):
                draw.point((x, y), fill=(60 + rng.randint(0, 30), 110 + rng.randint(0, 40), 50, 255))
    if name == "door":
        draw.rectangle([x0 + 36, 10, x0 + 91, 79], fill=(60, 44, 30, 255))
        draw.rectangle([x0 + 40, 14, x0 + 87, 79], fill=(122, 84, 50, 255))
        for x in range(46, 88, 10):
            draw.line([x0 + x, 14, x0 + x, 79], fill=(96, 64, 38, 255))
        draw.rectangle([x0 + 40, 30, x0 + 87, 32], fill=(70, 70, 76, 255))
        draw.rectangle([x0 + 40, 60, x0 + 87, 62], fill=(70, 70, 76, 255))
        draw.ellipse([x0 + 78, 44, x0 + 83, 49], fill=(220, 190, 80, 255))
    elif name == "stairs":
        draw.rectangle([x0 + 24, 8, x0 + 103, 79], fill=(30, 28, 30, 255))
        for i in range(6):
            y = 79 - i * 11
            shade = 120 - i * 14
            draw.rectangle([x0 + 24, y - 6, x0 + 103, y], fill=(shade, shade - 6, shade - 10, 255))


def floor(draw, index, name, rng):
    x0 = index * 64
    if name == "flagstones":
        draw.rectangle([x0, 0, x0 + 63, 63], fill=(52, 48, 44, 255))
        for (x, y, w, h) in ((1, 1, 30, 20), (33, 1, 30, 30), (1, 23, 30, 40), (33, 33, 30, 30)):
            shade = rng.randint(-12, 12)
            color = (96 + shade, 90 + shade, 82 + shade)
            draw.rectangle([x0 + x, y, x0 + x + w - 1, y + h - 1], fill=color + (255,))
            noise(draw, x0 + x, y, w, h, color, 16, rng, 90)
    else:
        draw.rectangle([x0, 0, x0 + 63, 63], fill=(70, 62, 56, 255))
        noise(draw, x0, 0, 64, 64, (70, 62, 56), 12, rng, 300)
        for y in (0, 31):
            draw.rectangle([x0, y, x0 + 63, y + 4], fill=(92, 66, 44, 255))
            draw.line([x0, y + 4, x0 + 63, y + 4], fill=(60, 42, 28, 255))


def thing(draw, index, name):
    x0 = index * 32
    if name == "pillar":
        draw.rectangle([x0 + 9, 4, x0 + 22, 44], fill=(150, 144, 134, 255))
        draw.rectangle([x0 + 9, 4, x0 + 11, 44], fill=(176, 170, 160, 255))
        draw.rectangle([x0 + 20, 4, x0 + 22, 44], fill=(112, 106, 98, 255))
        draw.rectangle([x0 + 6, 0, x0 + 25, 4], fill=(130, 124, 116, 255))
        draw.rectangle([x0 + 6, 44, x0 + 25, 47], fill=(130, 124, 116, 255))
    elif name == "barrel":
        draw.ellipse([x0 + 5, 18, x0 + 26, 47], fill=(128, 84, 48, 255))
        draw.rectangle([x0 + 6, 24, x0 + 25, 26], fill=(80, 80, 86, 255))
        draw.rectangle([x0 + 6, 39, x0 + 25, 41], fill=(80, 80, 86, 255))
        draw.line([x0 + 15, 19, x0 + 15, 46], fill=(100, 64, 36, 255))
    elif name == "urn":
        draw.ellipse([x0 + 8, 26, x0 + 23, 47], fill=(170, 110, 70, 255))
        draw.rectangle([x0 + 12, 21, x0 + 19, 28], fill=(150, 96, 60, 255))
        draw.rectangle([x0 + 10, 19, x0 + 21, 21], fill=(184, 124, 80, 255))
        draw.line([x0 + 9, 36, x0 + 22, 36], fill=(110, 70, 44, 255))
    elif name == "bones":
        draw.ellipse([x0 + 11, 32, x0 + 20, 40], fill=(226, 220, 200, 255))
        draw.rectangle([x0 + 13, 36, x0 + 14, 37], fill=(40, 30, 30, 255))
        draw.rectangle([x0 + 17, 36, x0 + 18, 37], fill=(40, 30, 30, 255))
        draw.line([x0 + 4, 45, x0 + 27, 41], fill=(210, 204, 186, 255), width=2)
        draw.line([x0 + 6, 41, x0 + 25, 46], fill=(210, 204, 186, 255), width=2)


def sheet(path, names, w, h, painter, rng=None):
    image = Image.new("RGBA", (w * len(names), h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for i, name in enumerate(names):
        if rng is None:
            painter(draw, i, name)
        else:
            painter(draw, i, name, rng)
    image.save(os.path.join(ROOT, path + ".png"))
    with open(os.path.join(ROOT, path + ".tsx"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<tileset version="1.9" tiledversion="1.9.1" name="{path}" tilewidth="{w}" tileheight="{h}" tilecount="{len(names)}" columns="{len(names)}">\n'
                f' <image source="{path}.png" width="{w * len(names)}" height="{h}"/>\n</tileset>\n')


def crypt():
    height, width = len(LAYOUT), len(LAYOUT[0])
    layers = {name: [0] * (width * height) for name in ("ground", "decor", "objects", "over", "collision")}
    walls = {"#": "stone", "B": "brick", "M": "moss", "D": "door", "U": "stairs"}
    things = {"p": "pillar", "b": "barrel", "u": "urn", "k": "bones"}
    for y, row in enumerate(LAYOUT):
        assert len(row) == width
        for x, c in enumerate(row):
            i = y * width + x
            layers["ground"][i] = FLOOR_GID["flagstones"]
            layers["decor"][i] = FLOOR_GID["ceiling"]
            if c in walls:
                layers["objects"][i] = WALL_GID[walls[c]]
            elif c in things:
                layers["over"][i] = THING_GID[things[c]]
                if c != "k":
                    layers["collision"][i] = COLLISION
            elif c == "x":
                layers["collision"][i] = COLLISION
    with open(os.path.join(ROOT, "crypt.tmx"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write(f'<map version="1.9" tiledversion="1.9.1" orientation="orthogonal" renderorder="right-down" width="{width}" '
                f'height="{height}" tilewidth="16" tileheight="16" infinite="0" nextlayerid="6" nextobjectid="1">\n')
        f.write(' <tileset firstgid="1" source="crypt walls.tsx"/>\n')
        f.write(' <tileset firstgid="101" source="crypt floors.tsx"/>\n')
        f.write(' <tileset firstgid="201" source="crypt things.tsx"/>\n')
        f.write(f' <tileset firstgid="{COLLISION}" source="collision.tsx"/>\n')
        for i, (name, data) in enumerate(layers.items()):
            visible = ' visible="0"' if name == "collision" else ""
            f.write(f' <layer id="{i + 1}" name="{name}" width="{width}" height="{height}"{visible}>\n  <data encoding="csv">\n')
            rows = [",".join(str(v) for v in data[y * width:(y + 1) * width]) for y in range(height)]
            f.write(",\n".join(rows) + "\n  </data>\n </layer>\n")
        f.write('</map>\n')


os.makedirs(ROOT, exist_ok=True)
sheet("crypt walls", WALLS, 128, 80, wall, random.Random(7))
sheet("crypt floors", FLOORS, 64, 64, floor, random.Random(11))
sheet("crypt things", THINGS, 32, 48, thing)
crypt()
print("written: crypt.tmx, crypt walls, crypt floors, crypt things")
