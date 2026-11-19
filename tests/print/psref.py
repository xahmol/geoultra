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
--doc=features: a document made here instead (features_doc: a header
and a footer; left, centred, right and justified paragraphs; 1.5 and 2
line spacing; GU Serif, Sans and Mono at several sizes, mixed on a
line; bold, underline, reverse, italic, outline; regular and decimal
tab stops; a hanging indent; BSW128), with GeoUltra's GU fonts (drive E
for geoWrite, build/fonts for gwps) drawn from their bitmaps on both
sides (gwps real=False), so the layout is compared dot for dot.
The printout is kept (build/harness/print/psref[-features].raw) and
made again only with --print.
--doc=FILE.cvt: any geoWrite document (gwgen's brochure and quick start
guide, samples/), its GU fonts from their bitmaps as for features.
Usage: tests/print/psref.py [--print] [--pages=N] [--doc=features|FILE.cvt]
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import epsonstream                               # noqa: E402
import gwps                                      # noqa: E402
from mkappsdnp import read_cvt                   # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "print")
D81 = localcfg.disk("GEOS_ORACLE81", "GEOS64.D81")
DOC = localcfg.get("GEOUTOOLS_MANUAL", os.path.join(localcfg.GEOUTOOLS, "docs", "geowrite-manual-en.cvt"))
C1541 = localcfg.C1541


def ruler(left, right, para=None, align=0, spacing=0, tabs=()):
    """A ruler escape (27 bytes; $10 in the flags as geoWrite 2.1 writes it)."""
    t = list(tabs) + [right] * (8 - len(tabs))
    b = bytearray([0x11]) + left.to_bytes(2, "little") + right.to_bytes(2, "little")
    for x in t:
        b += x.to_bytes(2, "little")
    b += (left if para is None else para).to_bytes(2, "little") + bytes([0x10 | align | spacing << 2, 0, 0, 0])
    return bytes(b)


def card(fid=9, style=0):
    return bytes([0x17, fid & 0xFF, fid >> 8, style])


def features_doc():
    """The test document's CVT (build/harness/print/psfeat/PS features.cvt)."""
    import gwtool
    serif, sans, mono = 27 << 6, 28 << 6, 30 << 6
    lorem = (b"The quick brown fox jumps over the lazy dog while the five boxing wizards jump "
             b"quickly, and a wizard's job is to vex chumps quickly in fog.")
    p1 = (ruler(80, 560) + card() + b"Left aligned: " + lorem + b"\r"
          + ruler(80, 560, align=1) + card() + b"Centred: " + lorem + b"\r"
          + ruler(80, 560, align=2) + card() + b"Right aligned: " + lorem + b"\r"
          + ruler(80, 560, align=3) + card() + b"Justified: " + lorem + b" " + lorem + b"\r"
          + ruler(80, 560, spacing=1) + card() + b"Spacing 1.5: " + lorem + b"\r"
          + ruler(80, 560, spacing=2) + card() + b"Spacing 2: " + lorem + b"\r"
          + ruler(80, 560) + card() + b"\r")
    p2 = (ruler(80, 560) + card(serif | 12) + b"GU Serif 12: " + lorem + b"\r"
          + card(sans | 10) + b"GU Sans 10: " + lorem + b"\r"
          + card(mono | 12) + b"GU Mono 12: the quick brown fox\r"
          + card(serif | 24, 0x40) + b"Serif 24 bold\r"
          + card(sans | 10) + b"small " + card(serif | 24) + b"BIG" + card(sans | 10) + b" small again\r"
          + card(serif | 12, 0x40) + b"bold " + card(serif | 12, 0x80) + b"underline "
          + card(serif | 12, 0x20) + b"reverse " + card(serif | 12, 0x10) + b"italic "
          + card(serif | 12, 0x08) + b"outline " + card(serif | 12, 0xC0) + b"bold underline"
          + card(serif | 12) + b"\r" + card() + b"\r")
    p3 = (ruler(80, 560, tabs=(200, 320 | 0x8000, 440)) + card() + b"Item\t12.5\tend\r"
          + b"A longer item\t1234.75\tx\r" + b"\t\t.5\tdecimal only\r"
          + ruler(120, 560, para=80) + card() + b"Hanging indent: " + lorem + b"\r"
          + ruler(80, 560) + card(128 << 6 | 9) + b"BSW128: the system font of GEOS 128.\r")
    head = ruler(80, 560, align=1) + card(9, 0x40) + b"GeoUltra PostScript test\r"
    foot = ruler(80, 560, align=2) + card() + b"the footer, right aligned\r"
    out = os.path.join(OUT, "psfeat")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    gwtool.save_new(out, "PS features", [p1, p2, p3], head, foot, {}, "GeoUltra's psref test document.")
    return os.path.join(out, os.listdir(out)[0])   # (V2.1: gwtool marks a wide
                                                    # document so; V2.0 is placed differently)


def printout(raw, doc, wait=1500):
    """geoWrite prints doc from drive A (a D81 with the document alone)."""
    docdisk = os.path.join(OUT, "psref-doc.d81")
    if os.path.exists(docdisk):
        os.remove(docdisk)
    subprocess.run([C1541, "-format", "psref,pr", "d81", docdisk, "-geoswrite", doc],
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
              "111,120,p", "w:1", "111,120,r", "w:%d" % wait,  # OK
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


def ours(pages_n, doc=DOC, real=True):
    gf = read_cvt(doc)
    recs = gf.records + [None] * (127 - len(gf.records))
    pg = [r for r in recs[:61] if r not in (None, "end")][:pages_n]
    pics = {r: recs[r] for r in range(64, 127) if recs[r] not in (None, "end")}
    h = gf.header
    ps = os.path.join(OUT, "psref.ps")
    files = [read_cvt(os.path.join(ROOT, "build", "fonts", f))
             for f in sorted(os.listdir(os.path.join(ROOT, "build", "fonts"))) if f.endswith(".cvt")]
    gwps.write(ps, pg, recs[61] if recs[61] not in (None, "end") else None,
               recs[62] if recs[62] not in (None, "end") else None, pics, gwps.Fonts(files), paper="page",
               page_height=h[0x90] | h[0x91] << 8, title_page=bool(h[0x8B] & 0x80), real=real,
               head_h=h[0x8C] | h[0x8D] << 8, foot_h=h[0x8E] | h[0x8F] << 8, version=bytes(h[0x59:0x5D]))
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
    feat = "--doc=features" in sys.argv
    other = next((a[6:] for a in sys.argv if a.startswith("--doc=") and a != "--doc=features"), None)
    doc = features_doc() if feat else os.path.abspath(other) if other else DOC
    raw = os.path.join(OUT, "psref-features.raw" if feat else
                       "psref-%s.raw" % re.sub(r"\W", "_", os.path.basename(other)) if other else "psref.raw")
    feat = feat or bool(other)          # (another document: its fonts drawn from bitmaps,
                                        # as the features document's GU fonts)
    if "--print" in sys.argv or not os.path.exists(raw):
        printout(raw, doc, 3000 if other else 600 if feat else 1500)   # (pictures print
                                                    # slowly: the brochure's seven take long)
    n = next((int(a[8:]) for a in sys.argv if a.startswith("--pages=")), 99)
    theirs = oracle_pages(raw)[:n]
    mine = ours(len(theirs), doc, real=not feat)
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
