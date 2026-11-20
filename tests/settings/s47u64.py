#!/usr/bin/env python3
"""GeoUltra Settings on the U64: a theme chosen on the Theme page and
used (the user's hand test, 2026-11-20: Night chosen in Settings, OK,
the desktop not in it). Twice from SETTINGS.INI theme=GeoUltra: Settings,
the Theme page, [+] until Night, then (1) "use" and OK, (2) only OK:
Settings asks "Use the theme Night for the desktop?" (the user's
decision), Yes. Each time SETTINGS.INI must say theme=Night and the
desktop, started again, must be in it (its curName). The user's
SETTINGS.INI and HIBERNAT.BIN are kept first and put back byte for byte.
Screens: build/harness/settings/s47-*.png.
Usage: tests/settings/s47u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402

HOME = "/USB0/GEOULTRA/"
KEY_STUB = 0xC0A0
PAGE_THEME, SIDE_TOP, SIDE_ROW = 0, 16, 16
THEME_UP = (242, 36 - 3)
USE_XY = (254 + 6, 36 - 3)                  # (ptheme.s USE_X, THEME_Y)
OK_XY = (190, 186)
YES_XY = (64 + 8 + 20, 32 + 72 + 8)        # (DEF_DB_POS at 64, 32; YES at card 1)
WANT = b"Night"
OUT = os.path.join(ROOT, "build", "harness", "settings")


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
    os.makedirs(OUT, exist_ok=True)

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)),
              flush=True)

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def fetch(name):
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + HOME + name, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def store(name, data):
        f = ftp()
        if data is None:
            try:
                f.delete(HOME + name)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + HOME + name, io.BytesIO(data))
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
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(t)

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "s47-%s.png" % name))

    def shown():
        return bytes(u.read(s["themeNames"] + 16 * u.read(s["themeNo"], 1)[0], 16)).split(b"\0")[0]

    def desk_theme():
        return bytes(u.read(k["curName"], 16)).split(b"\0")[0]

    def run(use):
        tag = "use" if use else "ask"
        store("SETTINGS.INI", b"[desktop]\r\ntheme=GeoUltra\r\n")
        u.boot(crt)
        time.sleep(20)
        check(tag + ": the desktop starts in GeoUltra", desk_theme(), b"GeoUltra")
        call(k["Settings"])
        press(20, SIDE_TOP + PAGE_THEME * SIDE_ROW + 7, t=8)
        shot(tag + "-page")
        for _ in range(u.read(s["themeCount"], 1)[0]):
            if shown() == WANT:
                break
            press(*THEME_UP, t=3)
        check(tag + ": [+] to Night", shown(), WANT)
        if use:
            press(*USE_XY, t=6)
            shot("used")
            press(*OK_XY, t=20)
        else:
            press(*OK_XY, t=4)                  # the question
            shot("asked")
            press(*YES_XY, t=20)
        shot(tag + "-desktop")
        text = fetch("SETTINGS.INI") or b""
        check(tag + ": SETTINGS.INI theme=Night", b"theme=Night\r\n" in text, True)
        check(tag + ": the desktop started again in Night", desk_theme(), WANT)

    kept = {n: fetch(n) for n in ("SETTINGS.INI", "HIBERNAT.BIN")}
    try:
        store("HIBERNAT.BIN", None)
        run(True)
        run(False)
    finally:
        for n, d in kept.items():
            store(n, d)
        back = all(fetch(n) == d for n, d in kept.items())
        check("the user's files back as they were", back, True)
    print("s47u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
