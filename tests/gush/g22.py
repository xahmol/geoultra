#!/usr/bin/env python3
"""gush in VICE: the close button (the user's request 2026-11-13). The
status line ends with an "x" (con.s ConStatus, column CLOSE_COL), the
time two columns left of it; a click on it ends gush as `exit` does
(edit.s EdPress): back to the desktop. Screens in build/harness/gush/
g22-*.png.
Usage: tests/gush/g22.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402

COLS = 53
CLOSE_COL = COLS - 2


def main():
    g = Gush("g22", 6623)
    check = g.check
    v = g.v
    try:
        g.start()
        g.png("g22-start")
        ours = v.mem_get(0x84A3, 0x84A4)
        g.run("echo still here")
        x = CLOSE_COL * 6 + 2
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, 40]))   # on the input line first:
        v.mem_set(0x8505, b"\x00")                         # not a close
        v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
        v.resume()
        time.sleep(1)
        v.ping()
        check("a click elsewhere: gush stays", v.mem_get(0x84A3, 0x84A4) == ours, True)
        v.mem_set(0x8505, b"\x80")
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, 3]))    # the "x"
        v.mem_set(0x8505, b"\x00")
        v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
        v.resume()
        time.sleep(5)
        v.ping()
        check("the x: back to the desktop (gush's keyVector gone)", v.mem_get(0x84A3, 0x84A4) != ours, True)
        g.png("g22-closed")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
