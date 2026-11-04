#!/usr/bin/env python3
"""geoFolder's gush button in VICE (docs/GUSH.md, "Where gush lives"):
geoFolder (a desk accessory) started from gush, its dialog with the gush
button (build/harness/gush/g7-geofolder.png), the button clicked: gush
starts from drive E in the application's place (a fresh screen).
Usage: tests/gush/g7.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, ROOT  # noqa: E402


def main():
    g = Gush("g7", 6569, [os.path.join(ROOT, "build", "tools", "geofolder.cvt")])
    check = g.check
    try:
        g.start()
        g.run("echo before")
        g.run("/b/geoFolder", settle=4)
        g.png("g7-geofolder")
        check("geoFolder's dialog up (gush's prompt not back)", g.lines()[-1], "$ /b/geoFolder")
        g.click(224, 78, settle=5)
        rows = g.lines()
        check("the gush button: gush again, a fresh screen",
              (rows[0].startswith("gush, the GeoUltra shell") if rows else rows, rows[1:]), (True, ["$"]))
        g.png("g7-gush")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
