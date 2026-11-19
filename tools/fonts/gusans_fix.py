# GU Sans (GeoUltra's Helvetica look-alike, font ID 28): hand-drawn
# glyphs for tools/mkgeosfont.py --fix (docs/design/DESIGN.md "Fonts"): the
# characters whose shape from the Adobe 75-dpi bitmaps is wider than the
# cell the LW-compatible widths give, redrawn narrower in the same style
# (Adobe's drawings as the model; X11 font-adobe-75dpi, permissive
# licence, its notices in the README). Rows: "#" ink, "." paper; the
# size's full height, the cell's width. Own drawings, 2026-11-16.

FIXES = {
    10: {                       # baseline row 7
        "f": """
.##
#..
###
#..
#..
#..
#..
#..
...
...
""",
    },
    12: {                       # baseline row 8
        "f": """
.##
#..
###
#..
#..
#..
#..
#..
#..
...
...
...
""",
        "/": """
..#
..#
..#
.#.
.#.
.#.
#..
#..
#..
...
...
...
""",
        "\\": """
#..
#..
#..
.#.
.#.
.#.
..#
..#
..#
...
...
...
""",
    },
}
