#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: folders on the Ultimate's own file
system copied, deleted and moved with everything in them (src/desktop/
tree.s; the engine's modules 83 and 84). A scratch folder
/USB0/GEOULTRA/test/d8 made over FTP (SRC with one.txt, two.txt and
SUB/three.txt; OUT and MOVED empty) and removed at the end; a favourite
(SETTINGS.INI, made and deleted) takes the desktop there. SRC copied
into OUT (the tree and a file's bytes checked over FTP); OUT deleted
("Delete everything in it?": Yes); SRC cut and pasted into MOVED (one
rename on the Ultimate).
Usage: tests/desktop/d8u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402

HOME = "/USB0/GEOULTRA/"
BASE = HOME + "test/d8"
KEY_STUB = 0xC0A0
KEY_DOWN, KEY_HOME, KEY_LEFT, CR, DEL = 17, 18, 8, 13, 29
C = 0x80
YES_XY = (90, 110)


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    u = U64()
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))
    ftp = ftplib.FTP(u.ip)
    ftp.login()

    def ls(path):
        """The names in a folder (lower case); None when it is not there
        (the Ultimate lists a missing folder as empty: its parent asked)."""
        parent, name = path.rsplit("/", 1)
        try:
            if name.lower() not in [n.split("/")[-1].lower() for n in ftp.nlst(parent)]:
                return None
            return sorted(n.split("/")[-1].lower() for n in ftp.nlst(path))
        except ftplib.error_perm:
            return None

    def rmtree(path):
        for n in ftp.nlst(path):
            full = path + "/" + n.split("/")[-1]
            try:
                ftp.delete(full)
            except ftplib.error_perm:
                rmtree(full)
        ftp.rmd(path)

    def key(c, s=2):
        old = u.read(0x849B, 2)
        u.write(KEY_STUB, bytes([0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                                 0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def press(xy, s=4):
        u.write(0x3A, bytes([xy[0], 0, xy[1]]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(s)

    def path():
        return bytes(u.read(k["path"], 40)).split(b"\0")[0].decode("latin1")

    def names():
        out = []
        for i in range(u.read(k["count"], 1)[0]):
            for c in [KEY_HOME] + [KEY_DOWN] * i + [C | ord("c")]:
                key(c, 1)
            out.append(bytes(u.read(k["entryName"], 20)).split(b"\0")[0].decode("latin1").lower())
        return out

    def cursor(name, listed):
        for c in [KEY_HOME] + [KEY_DOWN] * listed.index(name):
            key(c, 1)
    if ls(BASE) is not None:
        rmtree(BASE)
    ftp.mkd(BASE)
    for d in ("SRC", "SRC/SUB", "OUT", "MOVED"):
        ftp.mkd(BASE + "/" + d)
    for name, data in (("one.txt", b"first\r"), ("two.txt", b"second\r"),
                       ("SUB/three.txt", b"third\r")):
        ftp.storbinary("STOR " + BASE + "/SRC/" + name, io.BytesIO(data))
    try:                                                # (the user's own: kept,
        users = _get(ftp, HOME + "SETTINGS.INI")        # put back at the end)
    except ftplib.error_perm:
        users = None
    ftp.storbinary("STOR " + HOME + "SETTINGS.INI",
                   io.BytesIO(b"[favourites]\r\n/usb0/geoultra/test/d8\r\n"))
    try:
        u.boot(crt)
        time.sleep(15)
        n = u.read(k["sideCount"], 1)[0]
        letters = bytes(u.read(k["sideLetters"], n))
        press((20, u.read(k["sideTops"] + letters.index(b"\x80"), 1)[0] + 4), 6)
        check("the favourite: the scratch folder", path().lower(), "/usb0/geoultra/test/d8")
        here = names()
        cursor("src", here)                                  # copy SRC into OUT
        key(C | ord("c"))
        cursor("out", here)
        key(CR, 5)
        key(C | ord("v"), 25)
        check("SRC copied into OUT", (ls(BASE + "/OUT/SRC"), ls(BASE + "/OUT/SRC/SUB")),
              (["one.txt", "sub", "two.txt"], ["three.txt"]))
        check("the copy's bytes", _get(ftp, BASE + "/OUT/SRC/SUB/three.txt"), b"third\r")
        key(KEY_LEFT, 5)
        here = names()                                       # delete OUT
        cursor("out", here)
        key(DEL, 3)
        press(YES_XY, 4)                                     # Delete the selection?
        press(YES_XY, 20)                                    # Delete everything in it?
        check("OUT deleted with its tree", "out" in (ls(BASE) or []), False)
        here = names()
        cursor("src", here)                                  # cut SRC, paste in MOVED
        key(C | ord("x"))
        cursor("moved", here)
        key(CR, 5)
        key(C | ord("v"), 25)
        check("SRC moved into MOVED", (ls(BASE + "/MOVED/SRC/SUB"), "src" in (ls(BASE) or [])),
              (["three.txt"], False))
        # A GEOS application onto the Ultimate: named as gush's cp names it
        # (GEOWRITE.cvt, CVT: 35992 bytes), not under its bare name.
        n = u.read(k["sideCount"], 1)[0]
        letters = bytes(u.read(k["sideLetters"], n))
        press((20, u.read(k["sideTops"] + letters.index(b"a"), 1)[0] + 4), 6)
        key(KEY_HOME, 1)
        for _ in range(40):
            key(C | ord("c"), 1)
            if bytes(u.read(k["entryName"], 20)).split(b"\0")[0].lower() == b"geowrite":
                break
            key(KEY_DOWN, 1)
        press((20, u.read(k["sideTops"] + letters.index(b"\x80"), 1)[0] + 4), 6)
        key(C | ord("v"), 30)
        names_now = ls(BASE) or []
        check("GEOWRITE pasted onto the Ultimate: GEOWRITE.cvt",
              ("geowrite.cvt" in names_now, "geowrite" in names_now), (True, False))
        check("its size (CVT)", ftp.size(BASE + "/GEOWRITE.cvt") if "geowrite.cvt" in names_now else None, 35992)
    finally:
        if users is None:
            ftp.delete(HOME + "SETTINGS.INI")
        else:
            ftp.storbinary("STOR " + HOME + "SETTINGS.INI", io.BytesIO(users))
        if ls(BASE) is not None:
            rmtree(BASE)
        ftp.quit()
    sys.exit(0 if ok else 1)


def _get(ftp, path):
    out = io.BytesIO()
    ftp.retrbinary("RETR " + path, out.write)
    return out.getvalue()


if __name__ == "__main__":
    main()
