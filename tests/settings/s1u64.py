#!/usr/bin/env python3
"""GeoUltra Settings on the U64, step S1 (docs/SETTINGS.md): the Desktop
page writing SETTINGS.INI. The user's own SETTINGS.INI is set aside
first and put back byte for byte at the end. A test SETTINGS.INI (with
a comment, a [favourites] section and [desktop] view=icons) is read at
the start; the clock set to 12 hours and the view to list by clicks;
Save writes the file: the two keys changed, every other line kept as it
was; then OK leaves for the desktop, which starts with the list view.
Usage: tests/settings/s1u64.py [build/geoultra64.crt]
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
TEST_INI = (b"; a test file of tests/settings/s1u64.py\r\n"
            b"[favourites]\r\n/usb0/geoultra\r\n\r\n"
            b"[desktop]\r\nview=icons\r\nclock=24\r\n")
WANT_INI = (b"; a test file of tests/settings/s1u64.py\r\n"
            b"[favourites]\r\n/usb0/geoultra\r\n\r\n"
            b"[desktop]\r\nview=list\r\nclock=12\r\n")
Y0, DY, X1, X2 = 16 + 20, 18, 137, 191         # pdesk.s COL1, COL2
SAVE_XY = (33 * 8 + 24, 188)
OK_XY = (21 * 8 + 24, 188)


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
        check("settings started: its Desktop page, a file to write",
              (u.read(s["page"], 1)[0], u.read(s["noFile"], 1)[0]), (1, 0))
        press(X2 + 3, Y0 + 3 * DY - 3)                      # clock: 12 hours
        press(X1 + 3, Y0 + DY - 3)                          # view: list
        check("two options chosen: marked changed", u.read(s["dirty"], 1)[0], 1)
        press(*SAVE_XY, t=8)
        check("Save: written, no longer marked", u.read(s["dirty"], 1)[0], 0)
        check("SETTINGS.INI: the two keys changed, the rest as it was", fetch(), WANT_INI)
        press(*OK_XY, t=15)
        check("OK: the desktop again, with the list view", u.read(k["viewMode"], 1)[0], 0)
    finally:
        store(keep)
        check("the user's SETTINGS.INI back as it was", fetch() == keep, True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
