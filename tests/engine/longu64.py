#!/usr/bin/env python3
"""File engine on the Ultimate 64: long names off per drive (F_NOLONG;
the user, 2026-11-14, Settings' Drives page; enginemount.s OvInfo,
enginelong.s OvShort, mount.s SizeOption).

A fresh copy of the test D64 (test/img/gulong.d64) is mounted on /d.
FE_MOUNTINFO with r1 = 0 switches long names off: MOUNTS.INI's D line
ends in ",longnames=off" and FE_MOUNTINFO's r3H has F_NOLONG; a file
with a long name copied from the stick onto /d gets its name cut to 16
characters and no GU.LONGNAMES record; switched on again, the next long
name is kept (GU.LONGNAMES). After a reboot the cold start reads
",longnames=off" again (MOUNTS.INI written so). The user's MOUNTS.INI
and HIBERNAT.BIN are set aside first and put back at the end; the
image and its backup are removed.
Usage: tests/engine/longu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402

FE_STAT, FE_COPY, FE_MOUNT, FE_UMOUNT, FE_MOUNTINFO = 1, 5, 17, 18, 23
F_NOLONG = 0x10
INFO, BUF, NAME = 0x5300, 0x5400, 0x5320
HOME = "/USB0/GEOULTRA"
DIR = HOME + "/test/img"
IMG = DIR + "/gulong.d64"
UIMG = "/usb0/geoultra/test/img/gulong.d64"
LONG1 = "A long name for the first test.txt"
LONG2 = "Another long name, kept this time.txt"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
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

    def get(path):
        f = ftp()
        b = io.BytesIO()
        try:
            f.retrbinary("RETR " + path, b.write)
        except ftplib.error_perm:
            f.quit()
            return None
        f.quit()
        return b.getvalue()

    def put(path, data):
        f = ftp()
        f.storbinary("STOR " + path, io.BytesIO(data))
        f.quit()

    def delete(path):
        f = ftp()
        try:
            f.delete(path)
        except ftplib.error_perm:
            pass
        f.quit()

    def flags():
        x, _, r = u.fe(FE_MOUNTINFO, s0="/d", r1=BUF)
        return x, r[3] >> 8

    def longnames(off):
        return u.fe(FE_MOUNTINFO, s0="/d", r1=0, r3=1 if off else 0, timeout=60)[0]

    ini = get(HOME + "/MOUNTS.INI")
    hib = get(HOME + "/HIBERNAT.BIN")
    delete(HOME + "/HIBERNAT.BIN")
    orig = get(HOME + "/test/geopub.d64")
    f = ftp()
    try:
        f.mkd(DIR)
    except ftplib.error_perm:
        pass
    f.quit()
    put(IMG, orig)
    put(DIR + "/" + LONG1, b"first\r")
    put(DIR + "/" + LONG2, b"second\r")
    try:
        u.boot(crt)
        time.sleep(18)
        check("FE_MOUNT the copy on /d", u.fe(FE_MOUNT, s0="/d", s1=UIMG, timeout=120)[0], 0)
        check("long names on at first", flags(), (0, 0))
        check("long names off (FE_MOUNTINFO, r1 = 0)", longnames(True), 0)
        check("r3H: F_NOLONG", flags()[1] & F_NOLONG, F_NOLONG)
        line = [l for l in get(HOME + "/MOUNTS.INI").split(b"\r\n") if l.startswith(b"D=")]
        check("MOUNTS.INI: D=...,longnames=off", line, [b"D=" + UIMG.encode() + b",longnames=off"])
        x = u.fe(FE_COPY, s0="/usb0/geoultra/test/img/" + LONG1, s1="/d", timeout=120)[0]
        check("a long name copied onto /d: cut to 16, no GU.LONGNAMES",
              (x, u.fe(FE_STAT, s0="/d/" + LONG1[:16], r1=INFO)[0],
               u.fe(FE_STAT, s0="/d/GU.LONGNAMES", r1=INFO)[0] != 0), (0, 0, True))
        check("long names on again", longnames(False), 0)
        x = u.fe(FE_COPY, s0="/usb0/geoultra/test/img/" + LONG2, s1="/d", timeout=120)[0]
        check("then a long name is kept (GU.LONGNAMES)",
              (x, u.fe(FE_STAT, s0="/d/" + LONG2, r1=INFO)[0],
               u.fe(FE_STAT, s0="/d/GU.LONGNAMES", r1=INFO)[0]), (0, 0, 0))
        check("long names off again", longnames(True), 0)
        u.boot(crt)
        time.sleep(20)
        check("after a reboot: read from MOUNTS.INI", flags()[1] & F_NOLONG, F_NOLONG)
        check("FE_UMOUNT /d", u.fe(FE_UMOUNT, s0="/d", timeout=120)[0], 0)
    finally:
        put(HOME + "/MOUNTS.INI", ini)
        if hib is not None:
            put(HOME + "/HIBERNAT.BIN", hib)
        for p in (IMG, DIR + "/" + LONG1, DIR + "/" + LONG2, HOME + "/BACKUP/gulong.d64"):
            delete(p)
        f = ftp()
        try:
            f.rmd(DIR)
        except ftplib.error_perm:
            pass
        f.quit()
        check("MOUNTS.INI as it was", get(HOME + "/MOUNTS.INI") == ini, True)
    print("longu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
