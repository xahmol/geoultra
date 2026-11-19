#!/usr/bin/env python3
"""GeoUltra Settings on the U64 (docs/SETTINGS.md): the Time
page's "now" with a real time server. A test SETTINGS.INI with [time]
ntp=pool.ntp.org, offset=3600 and summer=eu; settings started, the Time
page, "now" (the settings written, then FE_NTP): GEOS's clock against
this computer's UTC time plus the offset, plus an hour more when the
EU's summer time is in force on that date (the kernal's rule, module
79). The user's own SETTINGS.INI set aside first and put back byte for
byte at the end.
Usage: tests/settings/s3bu64.py [build/geoultra64.crt]
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
KEY_STUB = 0xC0A0
TEST_INI = b"[time]\r\nntp=pool.ntp.org\r\noffset=3600\r\nsummer=eu\r\n"
PAGE_TIME, SIDE_TOP, SIDE_ROW = 3, 16, 16      # (SIDE_TOP 16 since 2026-11-19)
NOW_XY = (160, 45 + 5)


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    s = labels(os.path.join(ROOT, "build", "settings", "settings.lbl"))
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

    def fetch():
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + SETTINGS, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def store(data):
        f = ftp()
        if data is None:
            try:
                f.delete(SETTINGS)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + SETTINGS, io.BytesIO(data))
        f.quit()

    def call(routine, t=10):
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(t)

    def press(x, y, t=4):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)                             # (released, as a real
        u.write(0x8505, b"\x80")                  # click: Drag waits)
        time.sleep(t)

    keep = fetch()
    try:
        store(TEST_INI)
        u.boot(crt)
        time.sleep(20)
        call(k["Settings"])
        press(20, SIDE_TOP + PAGE_TIME * SIDE_ROW + 7)
        check("settings on its Time page", u.read(s["page"], 1)[0], PAGE_TIME)
        press(*NOW_XY, t=15)
        import datetime
        utc = datetime.datetime.now(datetime.timezone.utc)
        last = lambda m: max(d for d in range(25, 32)               # noqa: E731
                             if datetime.date(utc.year, m, d).weekday() == 6)
        start = datetime.datetime(utc.year, 3, last(3), 1, tzinfo=datetime.timezone.utc)
        end = datetime.datetime(utc.year, 10, last(10), 1, tzinfo=datetime.timezone.utc)
        local = utc + datetime.timedelta(hours=2 if start <= utc < end else 1)
        c = u.read(0x8516, 5)
        got = datetime.datetime(2000 + c[0], c[1], c[2], c[3], c[4])
        diff = abs((got - local.replace(tzinfo=None, second=0, microsecond=0)).total_seconds())
        check("now: GEOS's clock is UTC + 1 h (+ 1 h in EU summer time), within 2 minutes",
              diff <= 120, True)
        print("  GEOS %s, expected about %s" % (got, local.strftime("%Y-%m-%d %H:%M")))
    finally:
        store(keep)
        check("the user's SETTINGS.INI back as it was", fetch() == keep, True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
