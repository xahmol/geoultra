#!/usr/bin/env python3
"""FE_RUNSYS in VICE (docs/GUSH.md, "Where gush lives"): gush started from
drive E (the system drive in the cartridge) by the file engine, as the
boot setting and geoFolder's button do; then a name not on E, and one
that is no application (geoFolder, a desk accessory) come back with
their errors.
Usage: tests/gush/g6.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    ok = True
    for name, want in (("nope", 5), ("geoFolder", 10)):
        g = Gush("g6" + name, 6568)
        try:
            g.check("FE_RUNSYS %s: back with its error" % name, g.runsys(name, wait=3), want)
        finally:
            g.stop()
        ok = ok and g.ok
    g = Gush("g6", 6568)
    try:
        g.check("FE_RUNSYS gush: no return", g.runsys("gush"), None)
        rows = g.lines()
        g.check("gush from drive E: its greeting", rows[0].startswith("gush, the GeoUltra shell") if rows else rows,
                True)
        g.png("g6-runsys")
    finally:
        g.stop()
    sys.exit(0 if ok and g.ok else 1)


if __name__ == "__main__":
    main()
