#!/usr/bin/env python3
"""GU Folder's gush button in VICE (docs/design/GUSH.md, "Where gush lives"):
GU Folder (a desk accessory) started from gush, its dialog with the gush
button (build/harness/gush/g7-gufolder.png), the button clicked: gush
starts from drive E in the application's place (a fresh screen).
Usage: tests/gush/g7.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush, ROOT  # noqa: E402


def main():
    g = Gush("g7", 6569, [os.path.join(ROOT, "build", "tools", "gufolder.cvt")])
    check = g.check
    try:
        g.start()
        g.run("echo before")
        g.run('"/b/GU Folder"', settle=4)   # (quoted: a space)
        g.png("g7-gufolder")
        check("GU Folder's dialog up (gush's prompt not back)", g.lines()[-1], '$ "/b/GU Folder"')
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
