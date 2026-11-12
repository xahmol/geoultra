#!/usr/bin/env python3
"""GeoUltra's desktop in VICE, step D3b (docs/DESKTOP.md): a document opens
with its application. Drive A is the user's GEOS64.D81 (GEOS_ORACLE81,
only read: the harness uses a copy; never committed), which holds
geoWrite and "ReadMe 1581", a geoWrite 2.1 document. The desktop goes to
/a, the cursor to the document (its place in the directory, read from
the image), RETURN: geoWrite must run (its first record at $0400) with
the document open (its name on geoWrite's title). Screen:
build/harness/gush/desktop-d3doc.png.
Usage: tests/desktop/d3doc.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness  # noqa: E402

KEY_DOWN, KEY_HOME, CR = 17, 18, 13
DOC = "ReadMe 1581"


def entries(path):
    """Names in the D81's directory order, and geoWrite's first record."""
    d = open(path, "rb").read()

    def blk(t, s):
        o = ((t - 1) * 40 + s) * 256
        return d[o:o + 256]
    names, gw = [], None
    t, s = 40, 3
    while t:
        b = blk(t, s)
        for e in range(8):
            x = b[2 + 32 * e:2 + 32 * e + 30]
            if x[0] & 7:
                n = x[3:19].split(b"\xa0")[0].decode("latin1")
                names.append(n)
                if n.lower() == "geowrite":
                    idx = blk(x[1], x[2])
                    gw = blk(idx[2], idx[3])[2:18]
        t, s = b[0], b[1]
    return names, gw


def main():
    harness.use_disk_set("d81")
    names, gw = entries(harness.ORACLE_DISK)
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d3doc", 6638)
    check = g.check
    v = g.v
    try:
        check("the desktop started", g.runsys("GeoUltra Desktop", wait=6), None)
        g.keys([KEY_HOME, CR], settle=1)                   # "/": a first
        time.sleep(4)
        v.ping()
        check("/a", bytes(v.mem_get(k["path"], k["path"] + 2)), b"/a\0")
        def fold(name):                                 # the desktop's sort key
            return "".join(chr(ord(c) & 0xDF) if "a" <= c <= "z" else
                           chr(ord(c) & 0x7F) if "\xc1" <= c <= "\xda" else c
                           for c in name[:7])           # (sort.s: 7 characters)
        i = sorted(names, key=fold).index(DOC)          # (sorted: stable)
        g.keys([KEY_HOME] + [KEY_DOWN] * (i + 1), settle=0.2)    # (".." first)
        g.keys([CR], settle=1)
        time.sleep(20)
        v.ping()
        check("geoWrite runs", bytes(v.mem_get(0x0400, 0x040F)), gw[:16])
        g.png("desktop-d3doc")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
