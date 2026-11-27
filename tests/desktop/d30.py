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
            a = Image.open(os.path.join(out, "desktop-d30.png")).convert("RGB")   # (not "1":
            b = Image.open(ref).convert("RGB")   # its dithering carries the rows above along)
            line = a.crop((0, 74, a.width, 94))             # the title as from
            same = (a.crop((0, 0, a.width, 14)).tobytes()    # drive A, and text on
                    == b.crop((0, 0, a.width, 14)).tobytes()   # the first line (not
                    and len(set(line.getdata())) > 1)        # compared: d3doc's
                                                    # screen can be taken while geoWrite is
                                                    # still drawing it, "Thi" only; the
                                                    # 2026-11-26 regression failed so)
            check("the document's first page, as opened from drive A", same, True)
        # The task list over geoWrite, close task, No (the user's hand test
        # 2026-11-27: the question's box stayed and GeoUltra was unstable,
        # as DoDlgBox recovered through geoWrite's RecoverVector): the screen
        # under the box as before, geoWrite still running.
        rows = (0xA000 + 4 * 320, 0xA000 + 17 * 320 - 1)
        colours = (0x8C00 + 4 * 40, 0x8C00 + 17 * 40 - 1)
        before = (bytes(v.mem_get(*rows)), bytes(v.mem_get(*colours)))
        v.mem_set(kl["taskReq"], b"\x80")                  # as C= + RUN/STOP
        v.resume()
        time.sleep(2)
        v.ping()
        g.queue([KEY_DOWN, KEY_DOWN, CR], settle=3)         # geoWrite, new, close
        g.png("desktop-d30-ask")
        x, y = 64 + 17 * 8 + 20, 32 + 72 + 8                 # NO
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        for data in (0x00, 0x80):
            v.mem_set(0x8505, bytes([data]))
            v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
            v.resume()
            time.sleep(0.5)
            v.ping()
        v.resume()
        time.sleep(4)
        v.ping()
        g.png("desktop-d30-no")
        after = (bytes(v.mem_get(*rows)), bytes(v.mem_get(*colours)))
        check("close task over geoWrite, No: the screen under the box as before",
              after == before, True)
        check("and geoWrite still runs", bytes(v.mem_get(0x0400, 0x040F)), gw[:16])

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
