#!/usr/bin/env python3
"""GeoUltra on the U64: [time] adjust= after a cold start (the user's
decision 2026-11-13: GeoUltra no longer writes the Ultimate's clock, a
time set in GeoUltra persists as a difference to it). Two cold starts
without a hibernation file: without adjust= and with adjust=90; GEOS's
clock must differ by 90 minutes plus the time between the two readings,
and the kernal's mark ($C0FB, the clock fresh from the Ultimate) must be
cleared by then. The user's SETTINGS.INI and HIBERNAT.BIN are kept first
and put back byte for byte at the end.
Usage: tests/settings/s3cu64.py [build/geoultra64.crt]
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
BASE = b"[desktop]\r\ntheme=GeoUltra\r\n"


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
        f = ftplib.FTP(u.ip)
        f.login()
        return f

    def get(name):
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + HOME + name, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

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

    def minutes(c):
        return ((c[2] * 24 + c[3]) * 60 + c[4]) + c[5] / 60

    keep = {n: get(n) for n in ("SETTINGS.INI", "HIBERNAT.BIN")}
    try:
        put("HIBERNAT.BIN", None)
        put("SETTINGS.INI", BASE)
        u.boot(crt)
        time.sleep(25)
        t0, h0 = list(u.read(0x8516, 6)), time.time()
        put("HIBERNAT.BIN", None)
        put("SETTINGS.INI", BASE + b"[time]\r\nadjust=90\r\n")
        u._req("PUT", u.rest + "/machine:reboot")
        time.sleep(40)
        t1, h1 = list(u.read(0x8516, 6)), time.time()
        diff = minutes(t1) - minutes(t0) - (h1 - h0) / 60
        check("adjust=90: GEOS's clock 90 minutes on from the Ultimate's (within 1)",
              abs(diff - 90) < 1, True)
        check("the mark cleared after it", u.read(0xC0FB, 1)[0], 0)
    finally:
        for n, d in keep.items():
            put(n, d)
        check("the user's files back as they were", all(get(n) == d for n, d in keep.items()), True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
