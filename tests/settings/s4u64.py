#!/usr/bin/env python3
"""GeoUltra Settings on the U64, step S4.3 (docs/SETTINGS.md): the Theme
page with the real theme files. The user's SETTINGS.INI and
THEMES/Custom.ini are kept first and put back byte for byte at the
end. Settings on its Theme page lists the THEMES folder's files; [+]
until Custom; the border's paper set to red; Save writes
THEMES/Custom.ini through Custom.tmp: its border line red, every other
line as before.
Usage: tests/settings/s4u64.py [build/geoultra64.crt]
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
PAGE_THEME, SIDE_TOP, SIDE_ROW = 0, 20, 14
THEME_UP = (242, 36 - 3)
SWATCH_X, PAPER_Y = 152, 99
SAVE_XY = (33 * 8 + 24, 188)


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
        time.sleep(t)

    keep = fetch()
    custom = fetch(CUSTOM)
    try:
        store(b"[desktop]\r\ntheme=GeoUltra\r\n")
        u.boot(crt)
        time.sleep(20)
        call(k["Settings"])
        press(20, SIDE_TOP + PAGE_THEME * SIDE_ROW + 7, t=8)
        count = u.read(s["themeCount"], 1)[0]
        names = [bytes(u.read(s["themeNames"] + 16 * i, 16)).split(b"\0")[0].decode() for i in range(count)]
        check("the Theme page lists the THEMES folder (7 themes)", (count, "Custom" in names), (7, True))
        for _ in range(count):
            if bytes(u.read(s["themeNames"] + 16 * u.read(s["themeNo"], 1)[0], 16)).split(b"\0")[0] == b"Custom":
                break
            press(*THEME_UP, t=4)
        check("[+] to Custom", bytes(u.read(s["themeNames"] + 16 * u.read(s["themeNo"], 1)[0], 16)).split(b"\0")[0],
              b"Custom")
        press(SWATCH_X + 2 * 8 + 3, PAPER_Y, t=3)          # border: red
        press(*SAVE_XY, t=8)
        after = fetch(CUSTOM)
        want = b"\n".join(b"border=red\r" if l.startswith(b"border=") else l for l in custom.split(b"\n"))
        check("Save: THEMES/Custom.ini with border=red, every other line as it was", after, want)
    finally:
        store(custom, CUSTOM)
        store(keep)
        check("Custom.ini and the user's SETTINGS.INI back as they were",
              (fetch(CUSTOM) == custom, fetch() == keep), (True, True))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
