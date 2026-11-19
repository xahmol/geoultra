#!/usr/bin/env python3
"""GeoUltra's desktop in VICE (docs/design/DESIGN.md "Drives"; the user's
decision of 2026-11-18): a document on drive C opens in geoWrite 2.1,
which looks for a document only on drive A (equal disk names) or else on
drive B: the desktop swaps drives B and C while geoWrite runs
(FE_DRVSWAP, drvswap.s). Drive A is the user's GEOS64.D81
(GEOS_ORACLE81, a copy; never committed) with geoWrite 2.1; drive C a
D64 made for the test with a copy of its "ReadMe 1581". The desktop goes
to /c, the cursor to the document, RETURN: geoWrite runs (its first
record at $0400) with the document open: its title and first line as
when it is opened from drive A (tests/desktop/d3doc.py's screen), not
an "opening file" error; drives B and C swapped meanwhile (swapDrv =
10, B's disk name C's). Then EnterDeskTop (as when geoWrite quits):
swapped back, each disk name on its own letter again.
Usage: tests/desktop/d30.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
sys.path.insert(0, os.path.join(ROOT, "tests", "desktop"))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402
C1541 = localcfg.C1541
DOC = "ReadMe 1581"
KEY_DOWN, KEY_HOME, CR = 17, 18, 13


def main():
    import harness
    harness.use_disk_set("d81")
    out = os.path.join(ROOT, "build", "harness", "gush")
    os.makedirs(out, exist_ok=True)
    cvt = os.path.join(out, "d30-readme.cvt")
    img = os.path.join(out, "d30-docs.d64")
    for p in (cvt, img):
        if os.path.exists(p):
            os.remove(p)
    subprocess.run([C1541, harness.ORACLE_DISK, "-geosread", DOC, cvt], check=True, capture_output=True)
    subprocess.run([C1541, "-format", "doctest,dt", "d64", img, "-geoswrite", cvt],
                   check=True, capture_output=True)
    os.environ["APPRUN_DRIVE_C"] = img
    from d3doc import entries
    _, gw = entries(harness.ORACLE_DISK)
    from gushvice import Gush
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    kl = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kl.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d30", 6640)
    check = g.check
    v = g.v
    try:
        check("the desktop started", g.runsys("GeoUltra Desktop", wait=6), None)
        g.keys([KEY_HOME, KEY_DOWN, KEY_DOWN, CR], settle=1)  # "/": a, b, c
        time.sleep(4)
        v.ping()
        check("/c", bytes(v.mem_get(k["path"], k["path"] + 2)), b"/c\0")
        g.keys([KEY_HOME, KEY_DOWN], settle=0.3)            # (".." first)
        g.keys([CR], settle=1)
        time.sleep(25)
        v.ping()
        check("geoWrite runs", bytes(v.mem_get(0x0400, 0x040F)), gw[:16])
        check("drives B and C swapped meanwhile", v.mem_get(kl["swapDrv"], kl["swapDrv"])[0], 10)
        g.png("desktop-d30")
        ref = os.path.join(out, "desktop-d3doc.png")
        if os.path.exists(ref):
            from PIL import Image
            a = Image.open(os.path.join(out, "desktop-d30.png")).convert("1")
            b = Image.open(ref).convert("1")
            same = all(a.crop(box).tobytes() == b.crop(box).tobytes()   # the title and
                       for box in ((0, 0, a.width, 30), (0, 74, a.width, 94)))  # the first line
                                                    # (geoWrite may still be drawing the rest)
            check("the document's first page, as opened from drive A", same, True)
        def name(a):
            return bytes(v.mem_get(a, a + 15)).split(b"\xa0")[0]
        check("B shows C's disk meanwhile", name(0x8430), b"DOCTEST")
        v.regs_set({"PC": 0xC22C})                          # EnterDeskTop
        v.resume()
        time.sleep(10)
        v.ping()
        check("EnterDeskTop: swapped back", v.mem_get(kl["swapDrv"], kl["swapDrv"])[0], 0)
        check("C's disk on C again", name(0x88DC), b"DOCTEST")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
