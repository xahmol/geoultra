#!/usr/bin/env python3
"""mkappicon.py - the file icons of GeoUltra's own programs (24 x 21, the
GEOS file icon's 63 bytes): a picture of what the program does with a
small U, the logo's, in the bottom right corner (the user's choice of
2026-11-20, design B); splash, the start picture, is the logo's U itself.

    mkappicon.py NAME OUT.icon       NAME: desktop, settings, gush,
                                     postscript, folder, splash
    mkappicon.py --sheet OUT.png     all of them enlarged, to look at

Own drawing (no Berkeley artwork), 2026-11-20.
"""
import sys

W, H = 24, 21

# The pictures (W x H at most; "#" set). The bottom right corner (7 x 7)
# is cleared for the badge.
ART = {
    "desktop": """
######################
######################
######################
#....................#
#....................#
#.......##...........#
#.......#.#..........#
#.......#..#.........#
#.......#...#........#
#.......#....#.......#
#.......#.##.........#
#.......##..#........#
#............#.......#
#....................#
#....................#
#....................#
#....................#
######################
""",
    "settings": """
......................
.##...................
######################
.##...................
......................
............##........
######################
............##........
......................
......##..............
######################
......##..............
......................
..................##..
######################
..................##..
""",
    "gush": """
######################
#....................#
#.#..................#
#..#.................#
#...#................#
#..#.................#
#.#....######........#
#....................#
#....................#
#....................#
#....................#
#....................#
#....................#
######################
""",
    "postscript": """
##############
#............##
#............#.#
#............#..#
#..##..##....####
#..#.#.#.........#
#..##..##........#
#..#.....#.......#
#..#...##........#
#................#
#..###########...#
#................#
#..###########...#
#................#
#..#######.......#
#................#
#................#
#################
""",
    "folder": """
#######
#.....#
######################
#....................#
#....................#
#....................#
#....................#
#....................#
#....................#
#....................#
#....................#
#....................#
#....................#
######################
""",
}

# The badge: a small solid U (6 x 6), set in a cleared 7 x 7 corner.
BADGE = """
##..##
##..##
##..##
##..##
######
.####.
"""


def logo_u():
    """The logo's U at full size: strokes 5 wide, a rounded bottom and a
    checkered shadow down and to the left, as in the start picture."""
    def solid(x, y):
        if not (3 <= x <= 20 and 0 <= y <= 17):
            return False
        if 8 <= x <= 15 and y <= 12 and not (y == 12 and x in (8, 15)):
            return False
        if (y == 17 and (x <= 4 or x >= 19)) or (y == 16 and x in (3, 20)):
            return False
        return True
    g = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if solid(x, y):
                g[y][x] = 1
            elif solid(x + 2, y - 2) and (x + y) % 2 == 0:
                g[y][x] = 1
    return g


def icon(name):
    """NAME's icon as H rows of W bits."""
    if name == "splash":
        return logo_u()
    g = [[0] * W for _ in range(H)]
    for y, row in enumerate(ART[name].strip("\n").split("\n")):
        for x, c in enumerate(row):
            if c == "#":
                g[y][x] = 1
    bx, by = W - 7, H - 7                       # the corner cleared, the U in it
    for y in range(by - 1, H):
        for x in range(bx - 1, W):
            g[y][x] = 0
    for y, row in enumerate(BADGE.strip("\n").split("\n")):
        for x, c in enumerate(row):
            if c == "#":
                g[by + y][bx + x] = 1
    return g


def to_bytes(g):
    out = bytearray()
    for r in g:
        out += int("".join("1" if c else "0" for c in r), 2).to_bytes(3, "big")
    return bytes(out)


def sheet(path, scale=8):
    from PIL import Image, ImageDraw
    names = ["desktop", "settings", "gush", "postscript", "folder", "splash"]
    im = Image.new("RGB", (len(names) * (W * scale + 16) + 16, H * scale + 32), (178, 178, 178))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        x0 = 16 + i * (W * scale + 16)
        for y, row in enumerate(icon(n)):
            for x, c in enumerate(row):
                if c:
                    d.rectangle([x0 + x * scale, 8 + y * scale, x0 + x * scale + scale - 1,
                                 8 + y * scale + scale - 1], fill=(0, 0, 0))
        d.text((x0, 12 + H * scale), n, fill=(0, 0, 0))
    im.save(path)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--sheet":
        sheet(sys.argv[2])
    elif len(sys.argv) == 3 and (sys.argv[1] in ART or sys.argv[1] == "splash"):
        open(sys.argv[2], "wb").write(to_bytes(icon(sys.argv[1])))
    else:
        sys.exit(__doc__.strip().split("\n\n")[1].strip())


if __name__ == "__main__":
    main()
