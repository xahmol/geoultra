#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: geos > GeoUltra info (ctxmenu.s About;
the user's request 2026-11-13). The version line is built from the
kernal's info block (major, minor $C0E2; patch and the build's time
stamp $C0F5) as vMAJOR.MINOR.PATCH-YYYYMMDD-HHMM, the numbers the
Makefile's;
"splash" puts drive E's GU Splash file (src/tools/splash.toml: the boot
splash with its own status line) on the screen, bitmap and colours as
built; a click brings the desktop back. Screens:
build/harness/gush/desktop-d16*.png.
Usage: tests/desktop/d16.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, KEY_STUB  # noqa: E402

SPLASH_XY = (64 + 17 * 8 + 20, 32 + 72 + 8)    # DBI_X_2, DBI_Y_2 of the default box


def main():
    os.makedirs(OUT, exist_ok=True)
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    bitmap = open(os.path.join(ROOT, "build", "gen", "splashinfo.bin"), "rb").read()
    colours = open(os.path.join(ROOT, "build", "gen", "splashinfo_col.bin"), "rb").read()
    g = Gush("desktop-d16", 6716, [])
    check = g.check
    v = g.v

    def settle(s=3):
        time.sleep(s)
        v.ping()

    def call(routine, s=6):
        """ROUTINE from appMain; again when it did not run (the desktop,
        still starting, set its appMain over the stub): the stub marks
        $02FF."""
        tick = k["ClockTick"]
        for _ in range(5):
            v.mem_set(0x02FF, b"\0")
            v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                       0x84, 0xEE, 0xFF, 0x02, 0x4C, routine & 0xFF, routine >> 8]))
            v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            v.resume()
            settle(s)
            if v.mem_get(0x02FF, 0x02FF)[0]:
                return

    def press(x, y, s=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
        v.resume()
        time.sleep(0.5)                                 # (released, as a real click)
        v.ping()
        v.mem_set(0x8505, b"\x80")
        v.resume()
        settle(s)

    def line(at):
        return bytes(v.mem_get(at, at + 39)).split(b"\0")[0]

    try:
        tick = k["ClockTick"]                       # the desktop up: its appMain
        for _ in range(60):                         # (a fixed wait failed now
            settle(0.5)                             # and then)
            if int.from_bytes(bytes(v.mem_get(0x849B, 0x849C)), "little") == tick:
                break
        settle(2)
        ver = bytes(v.mem_get(0xC0E2, 0xC0E3))
        b = bytes(v.mem_get(0xC0F5, 0xC0FA))
        call(k["About"])
        g.png("desktop-d16-box")
        want = b"v%d.%d.%d-20%02d%02d%02d-%02d%02d" % (ver[0], ver[1], b[0], b[1], b[2], b[3], b[4], b[5])
        check("the version: vMAJOR.MINOR.PATCH-YYYYMMDD-HHMM from the info block",
              line(k["about"]), want)
        mk = open(os.path.join(ROOT, "Makefile")).read()
        nums = [int(mk.split("VERSION_%s = " % n)[1].split()[0]) for n in ("MAJOR", "MINOR", "PATCH")]
        check("the info block's numbers: the Makefile's", [ver[0], ver[1], b[0]], nums)
        press(*SPLASH_XY, s=6)
        g.png("desktop-d16-splash")
        check("splash: the bitmap as built", bytes(v.mem_get(0xA000, 0xA000 + 7999)) == bitmap, True)
        check("splash: the colours as built", bytes(v.mem_get(0x8C00, 0x8C00 + 999)) == colours, True)
        press(100, 100, s=6)
        g.png("desktop-d16-back")
        check("a click: the desktop again", bytes(v.mem_get(0xA000, 0xA000 + 7999)) != bitmap, True)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
