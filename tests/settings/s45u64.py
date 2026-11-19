#!/usr/bin/env python3
"""The theme's programs= on the U64 (docs/design/SETTINGS.md): a test
Custom.ini with programs=white on blue and SETTINGS.INI theme=Custom;
after a boot the desktop has given the kernal's progColours (info.s,
$C0F4, which FirstInit gives every program) and GEOS's screencolors
white on blue. The user's SETTINGS.INI and Custom.ini are kept first
and put back byte for byte at the end.
Usage: tests/settings/s45u64.py [build/geoultra64.crt]
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
CUSTOM = "/USB0/GEOULTRA/THEMES/Custom.ini"
PAGE_THEME, SIDE_TOP, SIDE_ROW = 0, 16, 16      # (SIDE_TOP 16 since 2026-11-19)
THEME_UP = (242, 36 - 3)
SWATCH_X, PAPER_Y = 152, 99
SAVE_XY = (33 * 8 + 24, 188)
CMD, REPLY = 0x7F40, 0x7F50               # (GEOS: free above the background screen)


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

    def fetch(path=SETTINGS):
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + path, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def store(data, path=SETTINGS):
        f = ftp()
        if data is None:
            try:
                f.delete(path)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + path, io.BytesIO(data))
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
    custom = fetch(CUSTOM)
    try:
        store(custom.rstrip(b"\r\n") + b"\r\nprograms=white on blue\r\n", CUSTOM)
        store(b"[desktop]\r\ntheme=Custom\r\n")
        u.boot(crt)
        time.sleep(20)
        check("programs=white on blue: progColours and screencolors $16",
              (u.read(0xC0F4, 1)[0], u.read(0x851E, 1)[0]), (0x16, 0x16))
    finally:
        store(custom, CUSTOM)
        store(keep)
        check("Custom.ini and the user's SETTINGS.INI back as they were",
              (fetch(CUSTOM) == custom, fetch() == keep), (True, True))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
