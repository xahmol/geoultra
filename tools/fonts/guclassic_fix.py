# GU Classic (GeoUltra's Palatino look-alike, font ID 35, after TeX Gyre
# Pagella): hand-drawn glyphs for tools/mkgeosfont.py --fix
# (docs/DESIGN.md "Fonts"): at 9 points FreeType's rendering loses the
# crossbars of f and t, at 9 and 10 the top of T. Rows: "#" ink, "."
# paper; the size's full height, the cell's width. Own drawings,
# 2026-11-16.


def rows(*r):
    return "\n".join(r)


FIXES = {
    9: {                        # baseline row 6, x-height rows 2-6
        "f": rows(".##", "#..", "##.", "#..", "#..", "#..", "#..", "...", "..."),
        "t": rows("...", "#..", "##.", "#..", "#..", "#..", ".#.", "...", "..."),
        "T": rows("#####.", "..#...", "..#...", "..#...", "..#...", "..#...", "..#...",
                  "......", "......"),
    },
    10: {                       # baseline row 7
        "T": rows("#####.", "..#...", "..#...", "..#...", "..#...", "..#...", "..#...", "..#...",
                  "......", "......"),
    },
}
