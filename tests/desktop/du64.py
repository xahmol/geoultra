#!/usr/bin/env python3
"""GeoUltra's desktop on the U64 (docs/design/DESKTOP.md, D1): SETTINGS.INI
[system] desktop=geoultra makes EnterDeskTop start it from drive E. The
test stick has no SETTINGS.INI (it is made and deleted again; an
existing one stops the test). Boots the cartridge, calls EnterDeskTop
(appMain), and checks that the desktop runs (its code at $0400, the
path and the entries of the start folder in its memory); the sidebar's
Ultimate roots (D5a): usb0 listed, a click on it goes there. D5b: the
favourites from SETTINGS.INI and the recent documents from RECENT.INI
(made for the test, deleted again; an existing RECENT.INI stops it too)
in the sidebar; C=F in /a adds it, SETTINGS.INI rewritten with its other
lines kept; a click on the recent "ReadMe 1581" (in the test copy's
image, mounted on drive A; recent entries name a document by its image's
path since 2026-11-18, imgpath.s) opens it in geoWrite and moves it to
the top of RECENT.INI.
Usage: tests/desktop/du64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402

SETTINGS = "/USB0/GEOULTRA/SETTINGS.INI"
RECENT = "/USB0/GEOULTRA/RECENT.INI"
INI = b"[system]\r\ndesktop=geoultra\r\n\r\n[favourites]\r\n/usb0\r\n"
KEY_STUB = 0xC0A0


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels()
    u = U64()
    u.require_test_drives("A")                  # (it writes onto drive A)
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))
    ftp = ftplib.FTP(u.ip)
    ftp.login()
    there = [n.split("/")[-1] for n in ftp.nlst("/USB0/GEOULTRA")]
    if "SETTINGS.INI" in there or "RECENT.INI" in there:
        sys.exit("du64.py: the stick has a SETTINGS.INI or RECENT.INI; not touched")

    def get(path):
        out = io.BytesIO()
        ftp.retrbinary("RETR " + path, out.write)
        return out.getvalue()

    def press(x, y, s=6):
        u.write(0x3A, bytes([x, 0, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)                             # (released, as a real
        u.write(0x8505, b"\x80")                  # click: Drag waits)
        time.sleep(s)

    def side(code, s=6):
        n = u.read(k["sideCount"], 1)[0]
        codes = bytes(u.read(k["sideLetters"], n))
        press(20, u.read(k["sideTops"] + codes.index(bytes([code])), 1)[0] + 4, s)

    def key(c, s=4):
        old = u.read(0x849B, 2)                         # (gush's gu64.py)
        u.write(KEY_STUB, bytes([0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                                 0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def paths(at, n):
        return [bytes(u.read(at + 64 * i, 64)).split(b"\0")[0].decode("latin1") for i in range(n)]
    ftp.storbinary("STOR " + SETTINGS, io.BytesIO(INI))
    ftp.storbinary("STOR " + RECENT, io.BytesIO(b"[recent]\r\n/usb0/none.doc\r\n/USB0/GEOULTRA/test/GEOS64.D81/ReadMe 1581\r\n"))
    try:
        u.boot(crt)
        u.write(0x849B, b"\x2C\xC2")                    # appMain = EnterDeskTop
        time.sleep(15)
        code = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:32]
        check("EnterDeskTop started GeoUltra's desktop", bytes(u.read(0x0400, 32)), code)
        path = bytes(u.read(k["path"], 16)).split(b"\0")[0].decode("latin1")
        check("its path line", path.startswith("/"), True)
        check("entries listed", u.read(k["count"], 1)[0] > 0, True)
        n = u.read(k["sideCount"], 1)[0]                # D5: the Ultimate's roots
        codes = bytes(u.read(k["sideLetters"], n))
        check("the sidebar lists usb0", b"0" in codes, True)
        i = codes.index(b"0")
        top = u.read(k["sideTops"] + i, 1)[0]
        press(20, top + 4)                              # a press on its line
        path = bytes(u.read(k["path"], 16)).split(b"\0")[0].decode("latin1")
        check("a click on usb0: there", path.lower(), "/usb0")
        counts = u.read(k["counts"], 2)                 # D5b
        check("favourites from SETTINGS.INI", paths(k["favs"], counts[0]), ["/usb0"])
        check("recent documents from RECENT.INI", paths(k["recents"], counts[1]),
              ["/usb0/none.doc", "/USB0/GEOULTRA/test/GEOS64.D81/ReadMe 1581"])
        n = u.read(k["sideCount"], 1)[0]
        check("their sidebar lines", [c for c in u.read(k["sideLetters"], n) if c & 0x80], [0x80, 0x90, 0x91])
        side(ord("a"))
        key(0x80 | ord("f"))                            # C=F in /a
        counts = u.read(k["counts"], 2)
        check("C=F in /a", paths(k["favs"], counts[0]), ["/usb0", "/a"])
        check("SETTINGS.INI: its other lines kept", get(SETTINGS), INI + b"/a\r\n")
        side(0x91, s=25)                                # the recent ReadMe 1581
        check("RECENT.INI: ReadMe 1581 on top", get(RECENT),
              b"[recent]\r\n/USB0/GEOULTRA/test/GEOS64.D81/ReadMe 1581\r\n/usb0/none.doc\r\n")
        check("geoWrite started in the desktop's place", bytes(u.read(0x0400, 32)) != code, True)
    finally:
        names = [n.split("/")[-1] for n in ftp.nlst("/USB0/GEOULTRA")]
        for name in ("SETTINGS.INI", "RECENT.INI", "SETTINGS.TMP", "RECENT.TMP"):
            if name in names:
                ftp.delete("/USB0/GEOULTRA/" + name)
        ftp.quit()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
