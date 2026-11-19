#!/usr/bin/env python3
"""GeoUltra's desktop in VICE (docs/design/DESKTOP.md "Opening"; the user's
decision of 2026-11-18): a document opens in the newest version of its
application on any drive. Drive A is a geoWrite 1.x work disk with its
own geoWrite and old documents (GEOS_OLDWRITE_DISK, the user's own, a
copy; never committed); drive B holds geoWrite 2.1 in a folder, /b/Writing (taken
from the user's GEOS64.D81, GEOS_ORACLE81), as the user keeps it on C. The desktop goes
to /a, the cursor to the document, RETURN: geoWrite 2.1 must run (its
first record at $0400), not the 1.x beside the document. Skipped when
the work disk is missing.
Usage: tests/desktop/d28.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
OLD = os.environ.get("GEOS_OLDWRITE_DISK", os.path.join(ROOT, "build", "harness", "bb", "g03.d64"))
DOC = "Big Brother 1"
KEY_DOWN, KEY_HOME, CR = 17, 18, 13


def d64_entries(path):
    """Names in directory order, and the first 16 bytes of GEOWRITE's
    record 0."""
    d = open(path, "rb").read()
    starts = [0]
    for t in range(1, 36):
        starts.append(starts[-1] + (21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17))

    def blk(t, s):
        o = (starts[t - 1] + s) * 256
        return d[o:o + 256]
    names, first = [], None
    t, s = 18, 1
    while t:
        b = blk(t, s)
        for i in range(8):
            e = b[i * 32 + 2:i * 32 + 32]
            if e[0] & 7:
                name = e[3:19].split(b"\xa0")[0].decode("latin1")
                names.append(name)
                if name == "GEOWRITE":
                    idx = blk(e[1], e[2])
                    first = blk(idx[2], idx[3])[2:18]
        t, s = b[0], b[1]
    return names, first


def main():
    if not os.path.exists(OLD):
        print("d28: skipped (no geoWrite 1.x work disk: GEOS_OLDWRITE_DISK)")
        sys.exit(0)
    import harness
    harness.use_disk_set("d81")
    out = os.path.join(ROOT, "build", "harness", "gush")
    os.makedirs(out, exist_ok=True)
    old = os.path.join(out, "d28-old.d64")
    with open(OLD, "rb") as f, open(old, "wb") as g:
        g.write(f.read())
    os.environ["APPRUN_DRIVE_A"] = old
    toml = os.path.join(out, "d28.toml")                 # drive B: /Writing/GEOWRITE
    open(toml, "w").write('[dnp]\nout = "d28-apps.dnp"\nname = "Apps test"\nid = "AT"\ntracks = 8\n'
                          'strict = true\n\n[sources]\ng = "%s"\n\n[[folder]]\npath = "Writing"\n'
                          'files = ["g:GEOWRITE"]\n' % harness.ORACLE_DISK)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=out,
                   check=True, capture_output=True)
    sys.path.insert(0, os.path.join(ROOT, "tests", "desktop"))
    from d3doc import entries
    _, new_first = entries(harness.ORACLE_DISK)
    names, old_first = d64_entries(old)
    from gushvice import Gush
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d28", 6639, disk=os.path.join(out, "d28-apps.dnp"))
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
        time.sleep(25)
        v.ping()
        got = bytes(v.mem_get(0x0400, 0x040F))
        check("geoWrite 2.1 from /b/Writing runs, not the 1.x beside the document",
              (got == new_first, got == old_first), (True, False))
        g.png("desktop-d28")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
