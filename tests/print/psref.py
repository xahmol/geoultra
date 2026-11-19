#!/usr/bin/env python3
"""gwtool ps (tools/gwps.py) against geoWrite's own printout (docs/
DESIGN.md "PostScript writer": the PC writer is the C64 writer's
reference, so it must lay a page out as geoWrite does). geoWrite 2.1
(the user's, from GEOS_ORACLE81 onto a native image; its key through
apprun --bypass, as [system] protection=bypass) prints GeoUTools'
manual (GEOUTOOLS_MANUAL, default ~/git/GeoUTools/docs/geowrite-
manual-en.cvt: 11 pages, pictures, BSW and BSW128, bold, underline,
outline, tabs) on GeoUltra in VICE with GU Epson FX-80 to VICE's
printer; the stream (tests/print/epsonstream.py) gives every page's
GEOS dots (column X at 3X/240", row R at round(2.7R)/216"). gwps writes
the same document with paper "page" (one dot a pixel at 80 dpi), which
ghostscript renders; each page is compared dot for dot after the one
offset that lines the two up (the printer's margins). Outline is drawn
plain by GeoUltra's kernal, so the comparison holds for it too.
The printout is kept (build/harness/print/psref.raw) and made again
only with --print.
Usage: tests/print/psref.py [--print] [--pages=N]
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import epsonstream                               # noqa: E402
import gwps                                      # noqa: E402
from mkappsdnp import read_cvt                   # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "print")
D81 = os.environ.get("GEOS_ORACLE81", os.path.expanduser("~/geos-dev/u64-usb/GEOS64.D81"))
DOC = os.environ.get("GEOUTOOLS_MANUAL", os.path.expanduser("~/git/GeoUTools/docs/geowrite-manual-en.cvt"))
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")


def printout(raw):
    """geoWrite prints DOC from drive A (a D81 with the document alone)."""
    docdisk = os.path.join(OUT, "psref-doc.d81")
    if os.path.exists(docdisk):
        os.remove(docdisk)
    subprocess.run([C1541, "-format", "psref,pr", "d81", docdisk, "-geoswrite", DOC],
                   check=True, capture_output=True)
    toml = os.path.join(OUT, "psref.toml")
    open(toml, "w").write('[dnp]\nout = "psref.dnp"\nname = "Apps test"\nid = "AT"\ntracks = 8\n'
                          'strict = true\n\n[sources]\ng = "%s"\n\n[[folder]]\npath = "Writing"\n'
                          'files = ["g:GEOWRITE"]\n' % D81)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=OUT,
                   check=True, capture_output=True)
    pre = os.path.join(OUT, "psref-pre.py")
    open(pre, "w").write('v.mem_set(0x8465, b"GU Epson FX-80\\0")\n')
    if os.path.exists(raw):
        os.remove(raw)
    env = dict(os.environ, APPRUN_DRIVE_A=docdisk, APPRUN_PREHOOK=pre,
               GEOS_APPS_DISK=os.path.join(OUT, "psref.dnp"), PYTHONPATH=os.path.join(ROOT, "tools", "harness"),
               APPRUN_VICE_ARGS="-devicebackend4 1 -busdevice4 -pr4drv raw -pr4output text -pr4txtdev 1 -prtxtdev2 " + raw)
    clicks = ["103,86,p", "w:1", "103,86,r", "w:4",          # Open
              "223,98,p", "w:1", "223,98,r", "w:4",          # Drive: A
              "223,63,p", "w:1", "223,63,r", "w:15",         # the document
              "35,6,p", "w:2", "45,92,p", "w:3",             # file > print
              "111,120,p", "w:1", "111,120,r", "w:1500",     # OK
              "s:" + os.path.join(OUT, "psref-after.png")]
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "15",
                    "--select", "/b/Writing/GEOWRITE", "--bypass", "--out", os.path.join(OUT, "psref.png"),
                    "GEOWRITE"]
                   + clicks, env=env, capture_output=True, text=True, timeout=3000)


def oracle_pages(raw):
    got = epsonstream.parse(open(raw, "rb").read())
    pages = []
    for p in got["pages"]:
        dots = set()
        for s in p.values():
            for x, y in s:
                dots.add((x // 3, round(y / 2.7)))
        pages.append(dots)
    return pages


def ours(pages_n):
    gf = read_cvt(DOC)
    recs = gf.records + [None] * (127 - len(gf.records))
    pg = [r for r in recs[:61] if r not in (None, "end")][:pages_n]
    pics = {r: recs[r] for r in range(64, 127) if recs[r] not in (None, "end")}
    h = gf.header
    ps = os.path.join(OUT, "psref.ps")
    gwps.write(ps, pg, None, None, pics, gwps.Fonts([]), paper="page",
               page_height=h[0x90] | h[0x91] << 8)
    for f in os.listdir(OUT):
        if f.startswith("psref-our-"):
            os.remove(os.path.join(OUT, f))
    subprocess.run(["gs", "-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pbmraw", "-r80",
                    "-dGraphicsAlphaBits=1", "-dTextAlphaBits=1",
                    "-sOutputFile=" + os.path.join(OUT, "psref-our-%02d.pbm"), ps], check=True)
    pages = []
    for f in sorted(os.listdir(OUT)):
        if f.startswith("psref-our-"):
            data = open(os.path.join(OUT, f), "rb").read()
            m = re.match(rb"P4\s+(?:#[^\n]*\n\s*)*(\d+)\s+(\d+)\s", data)
            w, h = int(m.group(1)), int(m.group(2))
            stride = (w + 7) // 8
            body = data[m.end():]
            dots = set()
            for y in range(h):
                row = body[y * stride:(y + 1) * stride]
                for bx, b in enumerate(row):
                    if b:
                        for k in range(8):
                            if b >> (7 - k) & 1:
                                dots.add((bx * 8 + k, y))
            pages.append(dots)
    return pages


def best_offset(a, b):
    """The shift (dx, dy), within a few dots, that leaves the fewest dots
    apart (the printout's margins put the page 2 rows down)."""
    best = None
    for dx in range(-3, 4):
        for dy in range(-3, 8):
            moved = {(x + dx, y + dy) for x, y in b}
            n = len(a ^ moved)
            if best is None or n < best[0]:
                best = (n, dx, dy)
    return best[1], best[2]


def main():
    os.makedirs(OUT, exist_ok=True)
    raw = os.path.join(OUT, "psref.raw")
    if "--print" in sys.argv or not os.path.exists(raw):
        printout(raw)
    n = next((int(a[8:]) for a in sys.argv if a.startswith("--pages=")), 99)
    theirs = oracle_pages(raw)[:n]
    mine = ours(len(theirs))
    ok = len(theirs) == len(mine) and len(theirs) > 0
    print("%s pages: geoWrite printed %d, gwps wrote %d" % ("pass" if ok else "FAIL", len(theirs), len(mine)))
    for k, (t, m) in enumerate(zip(theirs, mine), 1):
        dx, dy = best_offset(t, m)
        moved = {(x + dx, y + dy) for x, y in m}
        miss, extra = len(t - moved), len(moved - t)
        good = miss == 0 and extra == 0
        ok = ok and good
        print("%s page %d: %d dots, offset (%d, %d), %d not drawn by gwps, %d drawn only by gwps"
              % ("pass" if good else "FAIL", k, len(t), dx, dy, miss, extra))
    print("psref: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
