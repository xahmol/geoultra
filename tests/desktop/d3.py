#!/usr/bin/env python3
"""GeoUltra's desktop in VICE, step D3a (docs/DESKTOP.md): opening. From
"/": RETURN on b enters /b, cursor left goes back to "/"; a click on
drive B's sidebar line goes to /b; a double click on gush there starts
it (gush's code at $0400; the double-click count set again before the
second press: VICE runs in warp, real time would let it run out); in a
second run from /e, a double click on
gush starts it from drive E (FE_RUNSYS).
Usage: tests/desktop/d3.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush  # noqa: E402

KEY_DOWN, KEY_LEFT, CR = 17, 8, 13
DBL = 0x8515                    # dblClickCount


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    k = labels()
    gush = open(os.path.join(ROOT, "build", "gush", "gush.bin"), "rb").read()[:16]
    ok = True
    for run in ("b", "e"):
        g = Gush("desktop-d3" + run, 6636 if run == "b" else 6637)
        check = g.check
        v = g.v

        def path():
            return bytes(v.mem_get(k["path"], k["path"] + 15)).split(b"\0")[0].decode("latin1")

        def press(x, y, wait=2):
            v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
            v.mem_set(0x8505, b"\x00")
            pf = v.mem_get(0x39, 0x39)[0]
            v.mem_set(0x39, bytes([pf | 0x20]))
            v.resume()
            time.sleep(0.5)                             # (released, as a real
            v.ping()                                    # click: Drag waits
            v.mem_set(0x8505, b"\x80")                # for it)
            v.resume()
            time.sleep(wait)
            v.ping()

        try:
            check("the desktop started", g.runsys("GeoUltra Desktop", wait=6), None)
            LIST_TOP, ROW_H = (v.mem_get(k[n], k[n])[0] for n in ("listTop", "rowH"))
            if run == "b":
                g.keys([KEY_DOWN, CR], settle=0.5)          # "/": a, b, e
                time.sleep(3)
                v.ping()
                check("RETURN on b: /b", path(), "/b")
                g.keys([KEY_LEFT], settle=1)
                time.sleep(2)
                v.ping()
                check("cursor left: / again", path(), "/")
                n = v.mem_get(k["sideCount"], k["sideCount"])[0]   # B's sidebar line
                codes = bytes(v.mem_get(k["sideLetters"], k["sideLetters"] + n - 1))
                top = v.mem_get(k["sideTops"] + codes.index(b"b"), k["sideTops"] + codes.index(b"b"))[0]
                press(30, top + 4, wait=3)
                check("a click on drive B's line: /b", path(), "/b")
                press(150, LIST_TOP + ROW_H + 4, wait=0.3)  # gush: after "..",
                v.mem_set(DBL, bytes([30]))                 # (VICE runs in warp: the
                press(150, LIST_TOP + ROW_H + 4, wait=10)   # count kept for the second)
                check("a double click on gush: it runs", bytes(v.mem_get(0x0400, 0x040F)), gush)
            else:
                g.keys([KEY_DOWN, KEY_DOWN, CR], settle=0.5)    # "/": a, b, e
                time.sleep(3)
                v.ping()
                check("RETURN on e: /e", path(), "/e")
                gpos = 5                                    # (sorted: "..", the folder bin,
                                                            # geoFolder, GeoUltra Desktop,
                                                            # GU Settings, gush)
                press(150, LIST_TOP + gpos * ROW_H + 4, wait=0.3)
                v.mem_set(DBL, bytes([30]))
                press(150, LIST_TOP + gpos * ROW_H + 4, wait=10)
                check("a double click on /e's gush: it runs (FE_RUNSYS)",
                      bytes(v.mem_get(0x0400, 0x040F)), gush)
        finally:
            g.stop()
        ok = ok and g.ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
