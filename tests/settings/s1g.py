#!/usr/bin/env python3
"""GeoUltra Settings started from gush (docs/SETTINGS.md): the
command line "/e/GU Settings" (quotes keep the space) starts it from
drive E: its code at $0400 and its Desktop page. Screen:
build/harness/gush/settings-s1g.png.
Usage: tests/settings/s1g.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush  # noqa: E402

PAGE_DESKTOP = 1


def main():
    lbl = {}
    for line in open(os.path.join(ROOT, "build", "settings", "settings.lbl")):
        p = line.split()
        lbl.setdefault(p[2].lstrip("."), int(p[1], 16))
    code = open(os.path.join(ROOT, "build", "settings", "settings.bin"), "rb").read()[:16]
    g = Gush("settings-s1g", 6689, [])
    try:
        g.start()
        g.run('"/e/GU Settings"', settle=8)
        g.check("gush: \"/e/GU Settings\" runs it", bytes(g.v.mem_get(0x0400, 0x040F)) == code, True)
        g.check("on its Desktop page", g.v.mem_get(lbl["page"], lbl["page"])[0], PAGE_DESKTOP)
        g.png("settings-s1g")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
