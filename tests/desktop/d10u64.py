#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: copy, paste, move and delete onto drive
C, the native REU drive with the user's own applications DNP (the
user, 2026-11-11; MOUNTS.INI C=, a test copy made by make deploy). A
scratch folder /USB0/GEOULTRA/test/d10 made over FTP (SRC with one.txt,
two.txt and SUB/three.txt) and removed at the end. Through the desktop:
SRC copied from the Ultimate into /c (its folders made on the native
drive, a file read back); GEOWRITE copied from drive A into /c (a GEOS
application onto a native drive: its size and type); a new folder
MOVED made in /c (C=N) and SRC cut and pasted into it (moved: gone from
/c); MOVED (with everything in it) and GEOWRITE deleted, so /c ends as
it started. The desktop is moved around with its own Into routine,
called once through appMain as a menu would run it.
Usage: tests/desktop/d10u64.py [build/geoultra64.crt]
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
BASE = HOME + "test/d10"
KEY_STUB = 0xC0A0               # the info block's unused bytes (gushvice.py)
PATH_STR = 0xC0B8               # a path for Into, up to $C0DF
INFO = 0x5F00                   # FE_STAT's info (the overlay area; curOvl reset)
KEY_DOWN, KEY_HOME, CR, DEL = 17, 18, 13, 29
C = 0x80
YES_XY = (90, 110)
K_FOLDER, K_GEOS = 2, 3
FE_STAT, FE_OPEN, FE_READ, FE_CLOSE = 1, 13, 14, 4


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

    def exists(path):
        nonlocal ftp
        parent, name = path.rsplit("/", 1)
        try:
            return name.lower() in [n.split("/")[-1].lower() for n in ftp.nlst(parent)]
        except ftplib.error_perm:
            return False

    def rmtree(path):
        nonlocal ftp
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

    def into(path, s=6):
        """The desktop's Into(path), once through appMain."""
        u.write(PATH_STR, path.encode() + b"\0")
        tick, routine = k["ClockTick"], k["Into"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0xA9, PATH_STR & 0xFF, 0xA2, PATH_STR >> 8,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def here():
        return bytes(u.read(k["path"], 40)).split(b"\0")[0].decode("latin1")

    def cursor(name):
        """The cursor (and the selection) on the entry of that name; C=C
        reads each entry's name on the way. True when found."""
        key(KEY_HOME, 1)
        for _ in range(int.from_bytes(bytes(u.read(k["count"], 2)), "little")):
            key(C | ord("c"), 1)
            if bytes(u.read(k["entryName"], 20)).split(b"\0")[0].lower() == name.lower().encode():
                return True
            key(KEY_DOWN, 1)
        return False

    def stat(path):
        """(error, kind, size) of a path on the U64 (FE_STAT)."""
        r = u.fe(FE_STAT, s0=path, r1=INFO)[0]
        u.write(k["curOvl"], b"\xff")
        info = bytes(u.read(INFO, 16))
        return r, info[0], int.from_bytes(info[4:8], "little")

    if exists(BASE):
        rmtree(BASE)
    ftp.mkd(BASE)
    for d in ("SRC", "SRC/SUB"):
        ftp.mkd(BASE + "/" + d)
    for name, data in (("one.txt", b"first\r"), ("two.txt", b"second\r"),
                       ("SUB/three.txt", b"third\r")):
        ftp.storbinary("STOR " + BASE + "/SRC/" + name, io.BytesIO(data))
    try:
        u.boot(crt)
        time.sleep(18)
        check("drive C mounted (the apps DNP, native)", stat("/c")[:2], (0, 1))
        into("/usb0/geoultra/test/d10")
        check("in the scratch folder", here().lower(), "/usb0/geoultra/test/d10")
        check("SRC found", cursor("src"), True)
        key(C | ord("c"))                                    # copy SRC
        into("/c")
        key(C | ord("v"), 40)                                # paste into /c
        check("SRC copied into /c: its folders",
              (stat("/c/SRC")[:2], stat("/c/SRC/SUB")[:2]), ((0, K_FOLDER), (0, K_FOLDER)))
        check("and its files", (stat("/c/SRC/one.txt")[0], stat("/c/SRC/SUB/three.txt")[0]), (0, 0))
        into("/a")
        check("GEOWRITE found on drive A", cursor("geowrite"), True)
        key(C | ord("c"))
        into("/c")
        key(C | ord("v"), 40)
        check("GEOWRITE copied into /c (a GEOS application, 141 blocks)",
              stat("/c/GEOWRITE"), (0, K_GEOS, 141))
        key(C | ord("n"), 3)                                 # a new folder MOVED
        for ch in "MOVED":
            key(ord(ch), 0.5)
        key(CR, 5)
        check("folder MOVED made in /c", stat("/c/MOVED")[:2], (0, K_FOLDER))
        into("/c")
        check("SRC found in /c", cursor("src"), True)
        key(C | ord("x"))                                    # cut SRC
        into("/c/MOVED")
        key(C | ord("v"), 40)                                # paste: moved
        check("SRC moved into MOVED", (stat("/c/MOVED/SRC/SUB")[:2], stat("/c/SRC")[0] != 0),
              ((0, K_FOLDER), True))
        into("/c")
        check("MOVED found", cursor("moved"), True)
        key(DEL, 3)
        press(YES_XY, 4)                                     # Delete the selection?
        press(YES_XY, 30)                                    # Delete everything in it?
        check("MOVED deleted with its tree", stat("/c/MOVED")[0] != 0, True)
        into("/c")
        check("GEOWRITE found in /c", cursor("geowrite"), True)
        key(DEL, 3)
        press(YES_XY, 10)
        check("GEOWRITE deleted: /c as it started", stat("/c/GEOWRITE")[0] != 0, True)
    finally:
        ftp = ftplib.FTP(u.ip)                          # (a fresh connection:
        ftp.login()                                     # the U64 closes an idle one)
        if exists(BASE):
            rmtree(BASE)
        ftp.quit()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
