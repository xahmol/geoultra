#!/usr/bin/env python3
"""gush's free, turbo and date in VICE (docs/GUSH.md): VICE has
no Ultimate, so turbo finds no turbo registers and date sets GEOS's clock
but not the Ultimate's (on the U64: gu64.py).
Usage: tests/gush/g10.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gushvice import Gush  # noqa: E402


def main():
    g = Gush("g10", 6575)
    check = g.check
    try:
        g.start()
        g.run("free")
        rows = g.lines()
        check("free: the drives' banks", (rows[-4].split()[:2], rows[-3].split()[:2], rows[-2][:8]),
              (["/a", "3"], ["/b", "13"], "drives: "))      # (A: a 1541 image in VICE)
        g.run("turbo")
        check("turbo without turbo registers", g.lines()[-2], "gush: turbo: no turbo (an Ultimate 64 has it)")
        g.run("turbo 16")
        check("turbo 16", g.lines()[-2], "gush: turbo: wrong words (see help)")
        g.run("date 2026-11-05 14:30:15")
        check("date set: no complaint (GEOS's and the CIA's clock only, since 2026-11-13)",
              g.lines()[-2].startswith("gush:"), False)
        g.run("date")
        check("date shown", g.lines()[-2][:16], "2026-11-05 14:30")
        g.run("ntp", settle=3)
        check("ntp without an Ultimate", g.lines()[-2], "gush: ntp: no such drive")
        g.run("date 2026-13-05 14:30")
        check("date: no month 13", g.lines()[-2], "gush: date: bad path")
        g.png("g10")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
