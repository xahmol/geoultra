#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: two panes kept in SETTINGS.INI
(src/desktop/inifile.s, "panes="). The user's own SETTINGS.INI is set
aside first and put back byte for byte at the end. A test SETTINGS.INI
with "panes=2" makes the desktop start in two panes; TwoPanes (run
once through appMain, as the toolbar runs it) switches them off and
writes "panes=1"; the other [desktop] lines stay.
Usage: tests/desktop/d14u64.py [build/geoultra64.crt]
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
KEY_STUB = 0xC0A0               # the info block's unused bytes (gushvice.py)
TEST_INI = b"[desktop]\r\nview=icons\r\npanes=2\r\n"


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

    def call(routine, s=10):
        """routine once through appMain (ClockTick back first)."""
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def byte(name):
        return u.read(k[name], 1)[0]

    keep = fetch()
    try:
        store(TEST_INI)
        u.boot(crt)
        time.sleep(20)
        check("panes=2: the desktop starts in two panes, the list view",
              (byte("panes"), byte("viewMode")), (1, 0))
        call(k["TwoPanes"])
        check("two panes off: one list, the icon view from view=", (byte("panes"), byte("viewMode")), (0, 1))
        lines = (fetch() or b"").replace(b"\r", b"").split(b"\n")
        check("SETTINGS.INI: panes=1 written", b"panes=1" in lines, True)
        check("and view=icons kept", b"view=icons" in lines, True)
    finally:
        store(keep)
        check("the user's SETTINGS.INI back as it was", fetch() == keep, True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
