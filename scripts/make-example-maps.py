#!/usr/bin/env python3
# Makes the tileset and the two maps of the example game (game/content): a 16x16 tileset drawn here (no third-party
# graphics, MIT like the rest of the repository), the meadow and the cellar as Tiled maps (CSV layers ground, decor,
# objects, over, collision). Needs Pillow. The maps can be edited in Tiled or Amber Studio afterwards; running this again
# overwrites them.
#
#   python3 scripts/make-example-maps.py
import os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "content", "maps")
T = 16
NAMES = ["grass", "flowers", "path", "water", "floor", "wall", "tree", "roof",
         "door", "crate", "sign", "stairs_down", "stairs_up", "bush", "fence", "rock"]
GID = {name: i + 1 for i, name in enumerate(NAMES)}
COLLISION = 17


def tile(draw, index, name):
    x0, y0 = index % 8 * T, index // 8 * T
    box = lambda x, y, w, h, c: draw.rectangle([x0 + x, y0 + y, x0 + x + w - 1, y0 + y + h - 1], fill=c)
    grass = (86, 150, 72, 255)
    if name in ("grass", "flowers", "tree", "sign", "bush", "fence", "rock"):
        box(0, 0, T, T, grass)
        for i in range(6):
            box((i * 7 + 3) % T, (i * 5 + 2) % T, 1, 2, (70, 128, 60, 255))
    if name == "flowers":
        for x, y, c in ((3, 4, (240, 220, 90, 255)), (11, 6, (230, 110, 130, 255)), (6, 11, (250, 250, 250, 255)), (12, 12, (240, 220, 90, 255))):
            box(x, y, 2, 2, c)
    elif name == "path":
        box(0, 0, T, T, (186, 160, 112, 255))
        for i in range(5):
            box((i * 5 + 1) % T, (i * 7 + 3) % T, 2, 1, (160, 136, 94, 255))
    elif name == "water":
        box(0, 0, T, T, (58, 104, 176, 255))
        box(2, 4, 5, 1, (110, 160, 220, 255))
        box(9, 10, 5, 1, (110, 160, 220, 255))
    elif name == "floor":
        box(0, 0, T, T, (120, 112, 104, 255))
        box(0, 7, T, 1, (96, 90, 84, 255))
        box(7, 0, 1, 7, (96, 90, 84, 255))
        box(3, 8, 1, 8, (96, 90, 84, 255))
    elif name == "wall":
        box(0, 0, T, T, (80, 72, 70, 255))
        for y in range(0, T, 4):
            box(0, y, T, 1, (60, 54, 52, 255))
            box((y * 3) % 8 + 2, y, 1, 4, (60, 54, 52, 255))
    elif name == "tree":
        box(7, 10, 3, 6, (98, 66, 40, 255))
        draw.ellipse([x0 + 1, y0 + 0, x0 + 14, y0 + 12], fill=(44, 102, 50, 255))
        draw.ellipse([x0 + 4, y0 + 2, x0 + 9, y0 + 6], fill=(70, 136, 70, 255))
    elif name == "roof":
        box(0, 0, T, T, (156, 70, 56, 255))
        for y in range(2, T, 4):
            box(0, y, T, 1, (120, 52, 42, 255))
    elif name == "door":
        box(0, 0, T, T, (200, 176, 132, 255))
        box(4, 3, 8, 13, (110, 72, 44, 255))
        box(9, 9, 1, 1, (230, 200, 90, 255))
    elif name == "crate":
        box(0, 0, T, T, (120, 112, 104, 255))
        box(2, 3, 12, 11, (150, 104, 60, 255))
        box(2, 3, 12, 1, (110, 74, 40, 255))
        box(2, 8, 12, 1, (110, 74, 40, 255))
        box(7, 7, 2, 3, (230, 200, 90, 255))
    elif name == "sign":
        box(7, 8, 2, 8, (110, 72, 44, 255))
        box(2, 2, 12, 7, (176, 130, 80, 255))
        box(4, 4, 8, 1, (90, 60, 36, 255))
        box(4, 6, 6, 1, (90, 60, 36, 255))
    elif name in ("stairs_down", "stairs_up"):
        box(0, 0, T, T, (90, 84, 78, 255) if name == "stairs_up" else (186, 160, 112, 255))
        for i in range(4):
            shade = 40 + i * 25 if name == "stairs_down" else 140 - i * 25
            box(2, 2 + i * 3, 12, 3, (shade, shade - 6, shade - 10, 255))
    elif name == "bush":
        draw.ellipse([x0 + 1, y0 + 4, x0 + 14, y0 + 15], fill=(54, 120, 58, 255))
        box(5, 8, 2, 2, (200, 60, 60, 255))
    elif name == "fence":
        box(0, 6, T, 2, (150, 110, 70, 255))
        box(0, 11, T, 2, (150, 110, 70, 255))
        box(2, 3, 2, 12, (130, 92, 56, 255))
        box(12, 3, 2, 12, (130, 92, 56, 255))
    elif name == "rock":
        draw.ellipse([x0 + 2, y0 + 5, x0 + 14, y0 + 15], fill=(132, 130, 126, 255))
        box(5, 8, 3, 2, (170, 168, 164, 255))


def write_tileset():
    image = Image.new("RGBA", (8 * T, 2 * T), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for i, name in enumerate(NAMES):
        tile(draw, i, name)
    image.save(os.path.join(ROOT, "example tiles.png"))
    marker = Image.new("RGBA", (T, T), (220, 40, 40, 110))
    marker.save(os.path.join(ROOT, "collision.png"))
    with open(os.path.join(ROOT, "example tiles.tsx"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<tileset version="1.9" tiledversion="1.9.1" name="example tiles" tilewidth="16" tileheight="16" tilecount="16" columns="8">\n'
                ' <image source="example tiles.png" width="128" height="32"/>\n</tileset>\n')
    with open(os.path.join(ROOT, "collision.tsx"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                '<tileset version="1.9" tiledversion="1.9.1" name="collision" tilewidth="16" tileheight="16" tilecount="1" columns="1">\n'
                ' <image source="collision.png" width="16" height="16"/>\n</tileset>\n')


class Map:
    def __init__(self, width, height):
        self.width, self.height = width, height
        self.layers = {name: [0] * (width * height) for name in ("ground", "decor", "objects", "over", "collision")}

    def set(self, layer, x, y, name, blocked=False):
        self.layers[layer][y * self.width + x] = GID[name] if name else 0
        if blocked:
            self.layers["collision"][y * self.width + x] = COLLISION

    def fill(self, layer, x, y, w, h, name, blocked=False):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(layer, xx, yy, name, blocked)

    def write(self, path):
        with open(path, "w") as f:
            f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            f.write(f'<map version="1.9" tiledversion="1.9.1" orientation="orthogonal" renderorder="right-down" width="{self.width}" '
                    f'height="{self.height}" tilewidth="16" tileheight="16" infinite="0" nextlayerid="6" nextobjectid="1">\n')
            f.write(' <tileset firstgid="1" source="example tiles.tsx"/>\n')
            f.write(f' <tileset firstgid="{COLLISION}" source="collision.tsx"/>\n')
            for i, (name, data) in enumerate(self.layers.items()):
                visible = ' visible="0"' if name == "collision" else ""
                f.write(f' <layer id="{i + 1}" name="{name}" width="{self.width}" height="{self.height}"{visible}>\n  <data encoding="csv">\n')
                rows = [",".join(str(v) for v in data[y * self.width:(y + 1) * self.width]) for y in range(self.height)]
                f.write(",\n".join(rows) + "\n  </data>\n </layer>\n")
            f.write('</map>\n')


def meadow():
    m = Map(24, 16)
    m.fill("ground", 0, 0, 24, 16, "grass")
    for i in range(14):
        m.set("ground", (i * 7 + 3) % 22 + 1, (i * 5 + 2) % 14 + 1, "flowers")
    m.fill("ground", 12, 4, 1, 11, "path")
    m.fill("ground", 4, 9, 16, 1, "path")
    m.fill("ground", 13, 4, 7, 1, "path")
    m.fill("ground", 2, 11, 4, 3, "water", True)
    for x in range(24):
        for y in (0, 15):
            m.set("objects", x, y, "tree", True)
    for y in range(16):
        for x in (0, 23):
            m.set("objects", x, y, "tree", True)
    m.fill("objects", 2, 1, 5, 2, "roof", True)
    m.fill("objects", 2, 3, 5, 1, "wall", True)
    m.set("objects", 4, 3, "door", True)
    m.set("objects", 13, 8, "sign", True)
    m.set("objects", 19, 4, "stairs_down")
    m.fill("objects", 15, 11, 5, 1, "fence", True)
    for x, y in ((9, 2), (16, 6), (20, 12), (7, 13)):
        m.set("objects", x, y, "bush", True)
    for x, y in ((17, 2), (21, 7)):
        m.set("objects", x, y, "rock", True)
    m.write(os.path.join(ROOT, "meadow.tmx"))


def cellar():
    m = Map(14, 10)
    m.fill("ground", 0, 0, 14, 10, "floor")
    for x in range(14):
        m.set("objects", x, 0, "wall", True)
        m.set("objects", x, 9, "wall", True)
    for y in range(10):
        m.set("objects", 0, y, "wall", True)
        m.set("objects", 13, y, "wall", True)
    m.set("objects", 6, 8, "stairs_up")
    m.set("objects", 11, 2, "crate", True)
    m.fill("objects", 3, 3, 1, 3, "wall", True)
    m.write(os.path.join(ROOT, "cellar.tmx"))


os.makedirs(ROOT, exist_ok=True)
write_tileset()
meadow()
cellar()
print("written:", ", ".join(sorted(os.listdir(ROOT))))
