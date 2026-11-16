#!/usr/bin/env python3
"""mkprnicon.py - the file icon of GeoUltra's printer drivers (24 x 21,
the GEOS file icon's 63 bytes), drawn here; a letter in the paper says
which printer (E: Epson, C: Commodore).

    mkprnicon.py LETTER OUT.bin

Own drawing (no Berkeley artwork), 2026-11-16.
"""
import sys

PRINTER = """
........................
.....##############.....
.....#............#.....
.....#............#.....
.....#............#.....
.....#............#.....
.....#............#.....
..####............####..
.##..#............#..##.
#....##############....#
#......................#
#......................#
#..................###.#
#......................#
#......................#
########################
#......................#
#.....############.....#
#......................#
.######################.
........................
"""

LETTERS = {
    "E": ["#####", "#....", "####.", "#....", "#####"],
    "C": [".####", "#....", "#....", "#....", ".####"],
}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in LETTERS:
        sys.exit(__doc__.strip().split("\n\n")[1].strip())
    rows = [list(r) for r in PRINTER.strip("\n").split("\n")]
    assert len(rows) == 21 and all(len(r) == 24 for r in rows)
    for y, line in enumerate(LETTERS[sys.argv[1]]):
        for x, ch in enumerate(line):
            rows[2 + y][10 + x] = ch
    out = bytearray()
    for r in rows:
        bits = int("".join("1" if c == "#" else "0" for c in r), 2)
        out += bits.to_bytes(3, "big")
    open(sys.argv[2], "wb").write(out)


if __name__ == "__main__":
    main()
