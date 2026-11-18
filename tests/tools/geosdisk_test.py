#!/usr/bin/env python3
"""tools/geosdisk.py (docs/GWTOOL_MANUAL.md; the user's request of
2026-11-18): new GEOS disks in D64, D71 and D81 (free blocks as c1541
counts them, the GEOS signature and a border block), files added from
CVTs (GeoUltra's own: the desktop, a printer driver, gush) and from
another image, listed, extracted again (the same bytes), deleted (the
blocks back), renamed; CVTs exchanged with VICE's c1541 both ways
(c1541 -geoswrite of ours, ours of c1541 -geosread), the content the
same. Run after `make`.
Usage: tests/tools/geosdisk_test.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import geosdisk  # noqa: E402
from mkappsdnp import Image, read_cvt  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "tools")
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
TOOL = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]
CVTS = [os.path.join(ROOT, "build", p) for p in ("desktop/desktop.cvt", "printer/epson.cvt", "gush/gush.cvt")]


def run(*args):
    r = subprocess.run(TOOL + list(args), capture_output=True, text=True)
    if r.returncode:
        raise SystemExit("geosdisk %s: %s" % (" ".join(args), r.stderr))
    return r.stdout


def content(img, name):
    g = img.gfile(img.find(name))
    return g.header[2:] if g.header else None, \
        [r for r in g.records if r not in (None, "end")] if g.records else g.data


def main():
    os.makedirs(OUT, exist_ok=True)
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    names = [read_cvt(p).name for p in CVTS]
    for kind, empty in (("d64", 663), ("d71", 1327), ("d81", 3159)):
        path = os.path.join(OUT, "t." + kind)
        if os.path.exists(path):
            os.remove(path)
        run("new", path, "--name=Test", "--id=GT")
        d = geosdisk.Disk(path)
        c = subprocess.run([C1541, path, "-list"], capture_output=True, text=True).stdout
        check("%s: empty, %d blocks free (c1541 too), GEOS disk" % (kind, empty),
              d.blocks_free() == empty and "%d blocks free" % empty in c and d.border() is not None,
              (d.blocks_free(), c[-60:]))
        run("add", path, *CVTS)
        listed = run("list", path)
        check("%s: three files added and listed" % kind, all(n in listed for n in names), listed)
        xdir = os.path.join(OUT, "x-" + kind)
        run("extract", path, "--out=" + xdir)
        back = all(read_cvt(os.path.join(xdir, n + ".cvt")).records == read_cvt(p).records
                   and read_cvt(os.path.join(xdir, n + ".cvt")).header[2:] == read_cvt(p).header[2:]
                   for p, n in zip(CVTS, names))
        check("%s: extracted again, header and records the same" % kind, back)
        before = geosdisk.Disk(path).blocks_free()
        run("delete", path, names[1])
        run("rename", path, names[2], "Renamed")
        d = geosdisk.Disk(path)
        check("%s: deleted (blocks back) and renamed" % kind,
              d.blocks_free() > before and d.find(names[1]) is None and d.find("Renamed") is not None)
    cdisk = os.path.join(OUT, "c.d81")
    if os.path.exists(cdisk):
        os.remove(cdisk)
    cmd = [C1541, "-format", "cross,cc", "d81", cdisk]
    for n in names:
        cmd += ["-geoswrite", os.path.join(OUT, "x-d81", n + ".cvt")]
    subprocess.run(cmd, capture_output=True)
    ours = Image(os.path.join(OUT, "t.d64"))
    theirs = Image(cdisk)
    check("c1541 reads our CVTs: the same content", content(theirs, names[0]) == content(ours, names[0]))
    vc = os.path.join(OUT, "vc.cvt")
    subprocess.run([C1541, cdisk, "-geosread", names[0], vc], capture_output=True)
    m = os.path.join(OUT, "m.d64")
    if os.path.exists(m):
        os.remove(m)
    run("new", m)
    run("add", m, vc)
    check("we read c1541's CVT: the same content", content(Image(m), names[0]) == content(ours, names[0]))
    print("geosdisk_test: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
