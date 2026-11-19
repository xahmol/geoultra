# GU Book (GeoUltra's Bookman look-alike, font ID 32, after TeX Gyre
# Bonum): hand-drawn glyphs for tools/mkgeosfont.py --fix (docs/design/DESIGN.md
# "Fonts"): at 9 and 10 points FreeType's rendering loses the crossbars
# of f and t and a serif of T. Rows: "#" ink, "." paper; the size's full
# height, the cell's width. Own drawings, 2026-11-16.


def rows(*r):
    return "\n".join(r)


FIXES = {
    9: {                        # baseline row 6, x-height rows 2-6
        "f": rows(".##", "#..", "##.", "#..", "#..", "#..", "#..", "...", "..."),
        "t": rows("...", "#..", "##.", "#..", "#..", "#..", ".#.", "...", "..."),
        "T": rows("#####.", "..#...", "..#...", "..#...", "..#...", "..#...", "..#...",
                  "......", "......"),
    },
    10: {                       # baseline row 7, x-height rows 3-7
        "f": rows(".##", "#..", "#..", "##.", "#..", "#..", "#..", "#..", "...", "..."),
        "t": rows("....", "....", ".#..", "###.", ".#..", ".#..", ".#..", "..##", "....", "...."),
        "T": rows("......", "#####.", "..#...", "..#...", "..#...", "..#...", "..#...", "..#...",
                  "......", "......"),
    },
}
