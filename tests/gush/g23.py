#!/usr/bin/env python3
"""gush in VICE: a PRG on a GEOS drive typed by name runs in BASIC, asked
first (the user's decision 2026-11-26; prog.s RunPrg, src/inc/prgrun.inc,
the kernal's ToBASIC loading it from the drive). Drive B holds BP, a
BASIC program (10 PRINT "PRG OK") written by c1541 as a PRG. "BP": the
question; n: gush stays; "BP" again, y: BASIC loads BP from drive B and
runs it. Screens in build/harness/gush/g23-*.png.
Usage: tests/gush/g23.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, OUT  # noqa: E402


def program():
    line = bytes([0x99]) + b' "PRG OK"' + b"\0"
    nxt = 0x0801 + 4 + len(line)
    return b"\x01\x08" + bytes([nxt & 0xFF, nxt >> 8, 10, 0]) + line + b"\0\0"


def basic_has(v, text):
    codes = bytes((c - 0x40) if 0x41 <= c <= 0x5A else c for c in text.encode())
    return codes in bytes(v.mem_get(0x0400, 0x07E7))


def main():
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "bp")
    open(path, "wb").write(program())
    g = Gush("g23", 6624, [path])
    check = g.check
    v = g.v
    try:
        g.start()
        g.run("BP", settle=2)
        g.png("g23-ask")
        asked = any("leave GeoUltra and run BP?" in line for line in g.lines())
        check("BP: the question", asked, True)
        g.queue("n", settle=2)
        g.run("echo still here", settle=2)
        check("n: gush stays", any(line == "still here" for line in g.lines()), True)
        g.run("BP", settle=2)
        g.queue("y", settle=12)
        check("y: BASIC loads BP from drive B and runs it", basic_has(v, "PRG OK"), True)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
