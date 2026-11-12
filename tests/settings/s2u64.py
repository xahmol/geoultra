#!/usr/bin/env python3
"""The mouse pointer's design at boot on the U64 (docs/SETTINGS.md, step
S2; src/kernal/pointer.s, module 86): a test SETTINGS.INI with
[system] pointer=3 gives the crosshair after a reboot: sprite 0's
picture is its design (build/gen/pointers.inc), PosPointer's offsets
24 and 50 less its hot spot (7, 7). The user's own SETTINGS.INI is set
aside first and put back byte for byte at the end.
Usage: tests/settings/s2u64.py [build/geoultra64.crt]
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
TEST_INI = b"[system]\r\npointer=3\r\n"


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
        import re
        t = open(os.path.join(ROOT, "build", "gen", "pointers.inc")).read()
        data = bytes(int(x, 16) for x in re.findall(r"\$([0-9A-F]{2})", t.split("PointerHot:")[0]))
        kern = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            p = line.split()
            kern.setdefault(p[2].lstrip("."), int(p[1], 16))
        check("pointer=3: sprite 0 the crosshair", bytes(u.read(0x8A00, 63)) == data[3 * 63:4 * 63], True)
        check("its hot spot: offsets 17, 43", (u.read(kern["PtrDX"], 1)[0], u.read(kern["PtrDY"], 1)[0]),
              (17, 43))
    finally:
        store(keep)
        check("the user's SETTINGS.INI back as it was", fetch() == keep, True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
