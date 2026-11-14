#!/usr/bin/env python3
"""File engine on the Ultimate 64: a DNP mounted at another size
(FE_MOUNT's path with ",tracks=N"; the user, 2026-11-14, Settings'
Drives page; enginesize.s, module 91).

build/sysdrive-plain.dnp (8 tracks) is copied to test/img/gusize.dnp
and mounted on /d with ",tracks=12": 12 tracks, F_RESIZED, MOUNTS.INI's
D line keeps ",tracks=12", its files listed; unmounted, the file is 12
tracks long (written anew, whole). Then ",tracks=4": smaller (its
files lie in the first tracks), 4 tracks long after FE_UMOUNT. The
user's MOUNTS.INI and HIBERNAT.BIN are set aside and put back; the copy
and its backup removed.
Usage: tests/engine/sizeu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402

FE_OPENDIR, FE_CLOSE, FE_MOUNT, FE_UMOUNT, FE_MOUNTINFO = 2, 4, 17, 18, 23
F_RESIZED, FE_NOT_SUPPORTED, DEV_NOT_FOUND = 0x08, 0x4E, 13
BUF = 0x5400
HOME = "/USB0/GEOULTRA"
DIR = HOME + "/test/img"
IMG = DIR + "/gusize.dnp"
UIMG = "/usb0/geoultra/test/img/gusize.dnp"
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

    def info():
        x, _, r = u.fe(FE_MOUNTINFO, s0="/d", r1=BUF)
        return x, r[3] & 0xFF, r[3] >> 8

    ini = get(HOME + "/MOUNTS.INI")
    hib = get(HOME + "/HIBERNAT.BIN")
    delete(HOME + "/HIBERNAT.BIN")
    f = ftp()
    try:
        f.mkd(DIR)
    except ftplib.error_perm:
        pass
    f.quit()
    put(IMG, open(os.path.join(ROOT, "build", "sysdrive-plain.dnp"), "rb").read())
    try:
        u.boot(crt)
        time.sleep(18)
        x = u.fe(FE_MOUNT, s0="/d", s1=UIMG + ",tracks=12", timeout=300)[0]
        x2, tracks, flags = info()
        check("FE_MOUNT ...,tracks=12: 12 tracks, F_RESIZED", (x, x2, tracks, flags & F_RESIZED),
              (0, 0, 12, F_RESIZED))
        line = [l for l in get(HOME + "/MOUNTS.INI").split(b"\r\n") if l.startswith(b"D=")]
        check("MOUNTS.INI: D=...,tracks=12", line, [b"D=" + UIMG.encode() + b",tracks=12"])
        x, h, _ = u.fe(FE_OPENDIR, s0="/d")
        u.fe(FE_CLOSE, y=h)
        check("its files listed", x, 0)
        check("FE_UMOUNT /d", u.fe(FE_UMOUNT, s0="/d", timeout=300)[0], 0)
        check("the file 12 tracks long now", len(get(IMG) or b""), 12 * 65536)
        x = u.fe(FE_MOUNT, s0="/d", s1=UIMG + ",tracks=4", timeout=300)[0]
        x2, tracks, flags = info()
        check("...,tracks=4: smaller (its files in the first tracks)",
              (x, x2, tracks, flags & F_RESIZED), (0, 0, 4, F_RESIZED))
        check("FE_UMOUNT /d again: the file 4 tracks long",
              (u.fe(FE_UMOUNT, s0="/d", timeout=300)[0], len(get(IMG) or b"")), (0, 4 * 65536))
    finally:
        put(HOME + "/MOUNTS.INI", ini)
        if hib is not None:
            put(HOME + "/HIBERNAT.BIN", hib)
        for p in (IMG, HOME + "/BACKUP/gusize.dnp"):
            delete(p)
        f = ftp()
        try:
            f.rmd(DIR)
        except ftplib.error_perm:
            pass
        f.quit()
        check("MOUNTS.INI as it was", get(HOME + "/MOUNTS.INI") == ini, True)
    print("sizeu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
