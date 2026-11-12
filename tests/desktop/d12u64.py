#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: Info (src/desktop/ctxmenu.s, overlay 7)
on a file on the Ultimate, whose size its listing leaves out: FE_STAT
gives it (the dialog's size line read from memory, against the size the
FTP listing gives). The file is MOUNTS.INI in GEOULTRA, only read. Info
is called once through appMain, as the toolbar's info button runs it.
Usage: tests/desktop/d12u64.py [build/geoultra64.crt]
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

    size = ftp.size(HOME + "MOUNTS.INI")
    ftp.quit()
    u.boot(crt)
    time.sleep(18)
    into("/usb0/geoultra")
    check("MOUNTS.INI found", cursor("mounts.ini"), True)
    tick, routine = k["ClockTick"], k["Info"]
    u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                             0x4C, routine & 0xFF, routine >> 8]))
    u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
    time.sleep(6)
    line = lambda name: bytes(u.read(k[name], 40)).split(b"\0")[0].decode("latin1")
    check("Info: a file on the Ultimate", line("line2"), "Kind: file on the Ultimate")
    check("Info: its size (FE_STAT)", line("line3"), "Size: %d bytes" % size)
    press((220, 112), 3)                                    # OK
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
