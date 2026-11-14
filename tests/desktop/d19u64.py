#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: a disk image gone into like a folder
(the user's decision 2026-11-13; open.s Open, the engine's engineimg.s).
A scratch folder /USB0/GEOULTRA/test/d19 made over FTP with a copy of the
test D64 (gutest.d64), removed at the end. Through the desktop: RETURN
on the image goes into it (the path ends in its name, its 8 files
listed after ".."); a file copied out of it (C=C) and pasted into the folder (a
GEOS file onto the Ultimate: as .cvt); ".." leaves it; RETURN on its
application inside says the image must be mounted to open it. The image
itself is only read. The desktop is moved around with its own Into
routine, called once through appMain as a menu would run it.
Usage: tests/desktop/d19u64.py [build/geoultra64.crt]
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
BASE = HOME + "test/d19"
UBASE = "/usb0/geoultra/test/d19"
KEY_STUB = 0xC0A0               # the info block's unused bytes (gushvice.py)
PATH_STR = 0xC0B8               # a path for Into, up to $C0DF
KEY_DOWN, KEY_HOME, CR = 17, 18, 13
C = 0x80
OK_XY = (90, 110)               # (DEF_DB_POS: OK where Yes is)


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

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def names(path):
        f = ftp()
        out = [n.split("/")[-1] for n in f.nlst(path)]
        f.quit()
        return out

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
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(s)

    def into(path, s=8):
        """The desktop's Into(path), once through appMain."""
        u.write(PATH_STR, path.encode() + b"\0")
        tick, routine = k["ClockTick"], k["Into"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0xA9, PATH_STR & 0xFF, 0xA2, PATH_STR >> 8,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def here():
        return bytes(u.read(k["path"], 60)).split(b"\0")[0].decode("latin1")

    def count():
        return int.from_bytes(bytes(u.read(k["count"], 2)), "little")

    def cursor(name):
        """The cursor (and the selection) on the entry of that name; C=C
        reads each entry's name on the way. True when found."""
        key(KEY_HOME, 1)
        for _ in range(count()):
            key(C | ord("c"), 1)
            if bytes(u.read(k["entryName"], 20)).split(b"\0")[0].lower() == name.lower().encode():
                return True
            key(KEY_DOWN, 1)
        return False

    orig = io.BytesIO()
    f = ftp()
    f.retrbinary("RETR " + HOME + "test/geopub.d64", orig.write)
    try:
        f.mkd(BASE)
    except ftplib.error_perm:
        pass
    orig.seek(0)
    f.storbinary("STOR " + BASE + "/gutest.d64", orig)
    f.quit()
    try:
        u.boot(crt)
        time.sleep(18)
        into(UBASE)
        check("in the scratch folder", here().lower(), UBASE)
        check("the image found", cursor("gutest.d64"), True)
        key(CR, 10)
        check("RETURN goes into the image: its path, its 8 files and \"..\"",
              (here().lower(), count()), (UBASE + "/gutest.d64", 9))
        check("Text 1 found inside", cursor("text 1"), True)
        key(C | ord("c"))
        into(UBASE)
        key(C | ord("v"), 20)
        check("copied out of the image onto the Ultimate (as .cvt)",
              "Text 1.cvt".lower() in [n.lower() for n in names(BASE)], True)
        into(UBASE + "/gutest.d64")
        into("..")
        check("'..' leaves the image", here().lower(), UBASE)
        into(UBASE + "/gutest.d64")
        check("GEOPUBLISH found inside", cursor("geopublish"), True)
        key(CR, 6)
        line = int.from_bytes(bytes(u.read(k["errLine"], 2)), "little")
        check("its application: 'Mount the disk image to open it.'", line, k["EInImg"])
        press(OK_XY, 4)
    finally:
        f = ftp()
        for n in names(BASE):
            try:
                f.delete(BASE + "/" + n)
            except ftplib.error_perm:
                pass
        try:
            f.rmd(BASE)
        except ftplib.error_perm:
            pass
        f.quit()
    print("d19u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
