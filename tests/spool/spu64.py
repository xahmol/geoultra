#!/usr/bin/env python3
"""The print spooler's banks on the U64 (docs/design/DESIGN.md "Print spooler"):
SETTINGS.INI [system] spool=2048 (the user's file kept and put
back byte for byte, HIBERNAT.BIN set aside), a boot: the spooler gets the
banks at the top of the drives' area that the mounted drives leave free
(up to 30 more), and no drive overlaps them.
Usage: tests/spool/spu64.py [build/geoultra64.crt]
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
DRIVE_TYPE, RAM_BASE = 0x848E, 0x88C7
TYPE_BANKS = {1: 3, 2: 6, 3: 13}


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
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

    def get(name):
        b = io.BytesIO()
        f = ftp()
        try:
            f.retrbinary("RETR " + HOME + name, b.write)
        except ftplib.error_perm:
            return None
        finally:
            f.quit()
        return b.getvalue()

    def put(name, data):
        f = ftp()
        if data is None:
            try:
                f.delete(HOME + name)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + HOME + name, io.BytesIO(data))
        f.quit()

    keep = {n: get(n) for n in ("SETTINGS.INI", "HIBERNAT.BIN")}
    ini = (keep["SETTINGS.INI"] or b"").replace(b"\r\n", b"\n").split(b"\n")
    ini = [l for l in ini if not l.startswith(b"spool=")]
    if b"[system]" not in ini:
        ini.append(b"[system]")
    ini.insert(ini.index(b"[system]") + 1, b"spool=2048")
    try:
        put("HIBERNAT.BIN", None)
        put("SETTINGS.INI", b"\r\n".join(ini))
        u.boot(crt)
        time.sleep(22)
        extra, base, limit = (u.read(kern[n], 1)[0] for n in ("spoolExtra", "spoolBase", "driveLimit"))
        print("  (spool: %d more banks from %d, drives below %d)" % (extra, base, limit - 1))
        check("spool=2048: banks above 27-28 taken", extra > 0 and base + extra == 188, True)
        types = u.read(DRIVE_TYPE, 4)
        bases = u.read(RAM_BASE, 4)
        overlap = []
        for d in range(4):
            t = types[d] & 0x0F
            if not types[d] & 0x80 or not t:
                continue
            n = TYPE_BANKS.get(t) or u.read(kern["drvTracks"] + d, 1)[0]
            if bases[d] + n > base:
                overlap.append("ABCD"[d])
        check("no mounted drive in the spooler's banks", overlap, [])
    finally:
        for n, d in keep.items():
            put(n, d)
        check("the user's files back as they were", all(get(n) == d for n, d in keep.items()), True)
    print("spu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
