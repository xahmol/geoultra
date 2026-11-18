#!/usr/bin/env python3
"""GeoUltra's desktop on the U64 (docs/DESKTOP.md "Recent documents"; the
user's decision of 2026-11-18): a recent document inside a disk image
that is not mounted offers to mount it, then opens. A D64 made for the
test (gu-doctest.d64, in /USB0/GEOULTRA/test) holds "ReadMe 1581", a
geoWrite 2.1 document copied from the user's GEOS64.D81 (GEOS_ORACLE81,
never committed); RECENT.INI names it through the image's path. A click
on the recent entry: "Not mounted. Mount it?", YES, drive D in the mount
dialog: the image mounted on D and geoWrite runs (its first record at
$0400; the newest geoWrite on any drive). geoWrite 2.1 itself then
reports "opening file": it looks for a document on drive A when the
disk names match, else always on drive B (findDocDevice in its source,
mist64/geowrite), so a document on C or D is not found (open, 2026-11-18). The user's
SETTINGS.INI, RECENT.INI, MOUNTS.INI and HIBERNAT.BIN are set aside and
put back (the test starts with a SETTINGS.INI of its own: one pane, the
sidebar shown), the test image deleted; a reboot then resumes the user's
session. Screens: build/harness/gush/d29u64-*.png.
Usage: tests/desktop/d29u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
sys.path.insert(0, os.path.join(ROOT, "tests", "desktop"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402
from d6u64 import fe, labels, DLG_X, DLG_Y  # noqa: E402

HOME = "/USB0/GEOULTRA/"
IMAGE = "gu-doctest.d64"
DOC = "ReadMe 1581"
ORACLE81 = os.environ.get("GEOS_ORACLE81", os.path.expanduser("~/geos-dev/u64-usb/GEOS64.D81"))
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
OUT = os.path.join(ROOT, "build", "harness", "gush")
CODE_REC = 0x90


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels()
    os.makedirs(OUT, exist_ok=True)
    cvt = os.path.join(OUT, "d29-readme.cvt")
    img = os.path.join(OUT, IMAGE)
    for p in (cvt, img):
        if os.path.exists(p):
            os.remove(p)
    subprocess.run([C1541, ORACLE81, "-geosread", DOC, cvt], check=True, capture_output=True)
    subprocess.run([C1541, "-format", "doctest,dt", "d64", img, "-geoswrite", cvt],
                   check=True, capture_output=True)
    from d3doc import entries
    _, gw = entries(ORACLE81)
    u = U64()
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    ftp = ftplib.FTP(u.ip)
    ftp.login()
    names = [n.split("/")[-1] for n in ftp.nlst(HOME)]

    def get(path):
        out = io.BytesIO()
        ftp.retrbinary("RETR " + path, out.write)
        return out.getvalue()
    kept = {n: get(HOME + n) for n in ("SETTINGS.INI", "RECENT.INI", "MOUNTS.INI", "HIBERNAT.BIN")
            if n in names}

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "d29u64-%s.png" % name))

    def press(x, y, s=6):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(s)

    def side():
        n = u.read(k["sideCount"], 1)[0]
        return bytes(u.read(k["sideLetters"], n)), bytes(u.read(k["sideTops"], n))

    try:
        if "HIBERNAT.BIN" in kept:
            ftp.delete(HOME + "HIBERNAT.BIN")       # a cold start, not the user's session
        ftp.storbinary("STOR " + HOME + "SETTINGS.INI",      # the defaults: one pane,
                       io.BytesIO(b"[favourites]\r\n"))           # the sidebar shown
        ftp.storbinary("STOR " + HOME + "RECENT.INI",
                       io.BytesIO(("[recent]\r\n/usb0/geoultra/test/%s/%s\r\n" % (IMAGE, DOC)).encode()))
        with open(img, "rb") as f:
            ftp.storbinary("STOR " + HOME + "test/" + IMAGE, f)
        ftp.quit()
        u.boot(crt)
        time.sleep(15)
        letters, tops = side()
        check("the recent entry in the sidebar", bytes([CODE_REC]) in letters, True)
        x = fe(u, k, 23, s0="/d", r1=0x5F00)[0]
        check("drive D free at the start", x != 0, True)
        press(20, tops[letters.index(bytes([CODE_REC]))] + 4, 6)
        shot("ask")
        press(DLG_X + 8 + 20, DLG_Y + 72 + 8, 6)       # YES
        shot("dialog")
        press(DLG_X + 8 + 20, DLG_Y + 20 + 3 * 18 + 8, 40)   # drive D's button
        shot("opened")
        check("geoWrite runs (its first record at $0400)", bytes(u.read(0x0400, 16)), gw[:16])
    finally:
        ftp = ftplib.FTP(u.ip)
        ftp.login()
        for n, data in kept.items():
            ftp.storbinary("STOR " + HOME + n, io.BytesIO(data))
        for n in ("RECENT.INI", "SETTINGS.INI"):
            if n not in kept:
                ftp.delete(HOME + n)
        try:
            ftp.delete(HOME + "test/" + IMAGE)
        except ftplib.error_perm:
            pass
        back = all(get(HOME + n) == data for n, data in kept.items())
        check("the user's files back as they were", back, True)
        ftp.quit()
        u.boot(crt)                                     # (resumes the user's session)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
