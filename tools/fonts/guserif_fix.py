# GU Serif (GeoUltra's Times look-alike, font ID 27): hand-drawn glyphs
# for tools/mkgeosfont.py --fix (docs/DESIGN.md "Fonts"):
# - 9 points: the lowercase drawn anew (no Adobe bitmap at 9; FreeType's
#   rendering loses strokes at that size);
# - 10-14 points: the characters whose shape from the Adobe 75-dpi
#   bitmaps is wider than the cell the LW-compatible widths give,
#   redrawn narrower in the same style (Adobe's drawings as the model;
#   X11 font-adobe-75dpi, permissive licence, its notices in the README).
# Rows: "#" ink, "." paper; the size's full height, the cell's width.
# Own drawings, 2026-11-16.


def cell(width, top, rows, height=9):
    """A drawing of HEIGHT rows: ROWS (ink at the left) from row TOP, each
    padded to WIDTH with paper."""
    out = ["." * width] * height
    for i, r in enumerate(rows):
        out[top + i] = r.ljust(width, ".")
    return "\n".join(out)


# 9 points (Adobe has no 9-pixel bitmaps; FreeType's lose strokes): the
# lowercase redrawn. Grid: ascenders from row 0, x-height rows 3-6
# (baseline row 6), descenders rows 7-8; 3 columns of ink and a space.
LOWER9 = {
    "a": (4, 3, ["##", "..#", "#.#", ".##"]),
    "b": (4, 0, ["#", "#", "#", "##", "#.#", "#.#", "##"]),
    "c": (4, 3, [".##", "#", "#", ".##"]),
    "d": (4, 0, ["..#", "..#", "..#", ".##", "#.#", "#.#", ".##"]),
    "e": (4, 3, [".#", "###", "#", ".##"]),
    "f": (3, 0, [".##", "#", "#", "##", "#", "#", "#"]),
    "g": (4, 3, [".##", "#.#", "#.#", ".##", "..#", "##"]),
    "h": (4, 0, ["#", "#", "#", "##", "#.#", "#.#", "#.#"]),
    "i": (3, 1, ["#", "", "#", "#", "#", "#"]),
    "j": (3, 1, [".#", "", ".#", ".#", ".#", ".#", ".#", "#"]),
    "k": (4, 0, ["#", "#", "#", "#.#", "##", "#.#", "#.#"]),
    "l": (3, 0, ["#", "#", "#", "#", "#", "#", "#"]),
    "m": (7, 3, ["#####", "#.#.#", "#.#.#", "#.#.#"]),
    "n": (4, 3, ["##", "#.#", "#.#", "#.#"]),
    "o": (4, 3, [".#", "#.#", "#.#", ".#"]),
    "p": (4, 3, ["##", "#.#", "#.#", "##", "#", "#"]),
    "q": (4, 3, [".##", "#.#", "#.#", ".##", "..#", "..#"]),
    "r": (3, 3, ["##", "#", "#", "#"]),
    "s": (4, 3, [".##", "#", "..#", "##"]),
    "t": (3, 2, ["#", "##", "#", "#", ".#"]),
    "u": (4, 3, ["#.#", "#.#", "#.#", ".##"]),
    "v": (4, 3, ["#.#", "#.#", "#.#", ".#"]),
    "w": (6, 3, ["#...#", "#...#", "#.#.#", ".#.#"]),
    "x": (4, 3, ["#.#", ".#", ".#", "#.#"]),
    "y": (4, 3, ["#.#", "#.#", "#.#", ".##", "..#", "##"]),
    "z": (4, 3, ["###", "..#", "#", "###"]),
}

FIXES = {
    9: {c: cell(w, top, rows) for c, (w, top, rows) in LOWER9.items()},
    10: {                       # baseline row 6, descenders rows 7-9
        "f": """
.##
#..
###
#..
#..
#..
##.
...
...
...
""",
        "t": """
...
.#.
###
.#.
.#.
.#.
.##
...
...
...
""",
        "w": """
.......
.......
#..#..#
#..#..#
.#.#.#.
.#.#.#.
..#.#..
.......
.......
.......
""",
        "y": """
.....
.....
#...#
.#..#
.#.#.
..##.
..#..
.#...
##...
.....
""",
        "W": """
#...#...#
#...#...#
#...#...#
.#.#.#.#.
.#.#.#.#.
..#...#..
..#...#..
.........
.........
.........
""",
    },
    12: {                       # baseline row 8, descenders rows 9-11
        "t": """
...
...
.#.
###
.#.
.#.
.#.
.#.
.##
...
...
...
""",
        "W": """
##..###..##
.#...#...#.
.#...#...#.
.#..#.#..#.
..#.#.#.#..
..#.#.#.#..
..#.#.#.#..
...#...#...
...#...#...
...........
...........
...........
""",
    },
    14: {                       # baseline row 9, descenders rows 10-13
        "w": """
..........
..........
..........
###.###.##
.#...#..#.
.#...#..#.
..#.#.#.#.
..#.#.#.#.
...#...#..
...#...#..
..........
..........
..........
..........
""",
        "/": """
...#
...#
...#
..#.
..#.
..#.
.#..
.#..
.#..
#...
#...
#...
....
....
""",
    },
}
