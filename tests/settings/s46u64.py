#!/usr/bin/env python3
"""GeoUltra Settings on the U64: the Theme page's delete (the user,
2026-11-13; docs/design/SETTINGS.md). A test theme, THEMES/Ztest.ini (a copy of
the GeoUltra theme with name=Ztest), is written first and is the only
file the test deletes; the user's SETTINGS.INI and theme files are only
read, and checked byte for byte at the end. Settings on its Theme page:
the theme in use (GeoUltra) refuses to go ("This theme is in use.");
[+] to Ztest, delete, No: the file stays; delete, Yes: the file is gone,
the list one shorter, the theme shown the one before it; a copy not
saved yet (no file) goes from the list too. Then Cancel:
nothing was changed, so Settings ends at once. Screens:
build/harness/gush/settings-s46-*.png.
Usage: tests/settings/s46u64.py [build/geoultra64.crt]
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
TEST = HOME + "THEMES/Ztest.ini"
KEY_STUB = 0xC0A0
PAGE_THEME, SIDE_TOP, SIDE_ROW = 0, 16, 16      # (SIDE_TOP 16 since 2026-11-19)
THEME_UP = (242, 36 - 3)
DELETE_XY = (92 + 18, 20 * 8 - 6 + 7)               # ptheme.s BDel
YES_XY, NO_XY = (90, 110), (220, 110)               # (DEF_DB_POS: OK as Yes)
CANCEL_XY = (27 * 8 + 24, 188)
OUT = os.path.join(ROOT, "build", "harness", "gush")


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
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def ftp():
        f = ftplib.FTP(u.ip)
        f.login()
        return f

    def user_files():
        f = ftp()
        out = {}
        for name in ["SETTINGS.INI"] + ["THEMES/" + n for n in f.nlst(HOME + "THEMES")
                                        if n.lower().endswith(".ini")]:
            name = name.split("/USB0/GEOULTRA/")[-1]
            b = io.BytesIO()
            f.retrbinary("RETR " + HOME + name, b.write)
            out[name] = b.getvalue()
        f.quit()
        return out

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

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8),
                      os.path.join(OUT, "settings-s46-%s.png" % name))

    def shown():
        return bytes(u.read(s["themeNames"] + 16 * u.read(s["themeNo"], 1)[0], 16)).split(b"\0")[0]

    def exists():
        f = ftp()
        names = [n.split("/")[-1] for n in f.nlst(HOME + "THEMES")]
        f.quit()
        return "Ztest.ini" in names

    before = user_files()
    used = b"GeoUltra"
    for line in before["SETTINGS.INI"].split(b"\r\n"):
        if line.lower().startswith(b"theme="):
            used = line[6:]
    base = before.get("THEMES/GeoUltra.ini", b"[theme]\r\nname=GeoUltra\r\n")
    f = ftp()
    f.storbinary("STOR " + TEST, io.BytesIO(base.replace(b"name=GeoUltra", b"name=Ztest")))
    f.quit()
    try:
        u.boot(crt)
        time.sleep(20)
        call(k["Settings"])
        press(20, SIDE_TOP + PAGE_THEME * SIDE_ROW + 7, t=8)
        count = u.read(s["themeCount"], 1)[0]
        check("the theme in use shown first", shown(), used)
        press(*DELETE_XY, t=4)
        shot("inuse")
        press(*YES_XY, t=4)                         # (its OK)
        check("the theme in use stays (its file and the list)",
              (u.read(s["themeCount"], 1)[0], shown()), (count, used))
        for _ in range(count):
            if shown() == b"Ztest":
                break
            press(*THEME_UP, t=4)
        check("[+] to Ztest", shown(), b"Ztest")
        before_z = u.read(s["themeNo"], 1)[0]
        press(*DELETE_XY, t=4)
        shot("ask")
        press(*NO_XY, t=4)
        check("delete, No: the file stays", (exists(), shown()), (True, b"Ztest"))
        press(*DELETE_XY, t=4)
        press(*YES_XY, t=6)
        shot("deleted")
        names = [bytes(u.read(s["themeNames"] + 16 * i, 16)).split(b"\0")[0]
                 for i in range(u.read(s["themeCount"], 1)[0])]
        check("delete, Yes: the file gone, out of the list",
              (exists(), len(names), b"Ztest" in names), (False, count - 1, False))
        check("the one before it shown",
              u.read(s["themeNo"], 1)[0], before_z - 1 if before_z == count - 1 else before_z)
        # A copy not saved yet (no file; put in the list as "copy" adds
        # it, as a name cannot be typed here): delete, Yes takes it out.
        n = u.read(s["themeCount"], 1)[0]
        u.write(s["themeNames"] + 16 * n, b"Zghost\0")
        u.write(s["themeCount"], bytes([n + 1]))
        u.write(s["themeNo"], bytes([n]))
        press(*DELETE_XY, t=4)
        press(*YES_XY, t=6)
        names = [bytes(u.read(s["themeNames"] + 16 * i, 16)).split(b"\0")[0]
                 for i in range(u.read(s["themeCount"], 1)[0])]
        check("an unsaved copy (no file): delete, Yes takes it out of the list",
              (len(names), b"Zghost" in names), (n, False))
        press(*CANCEL_XY, t=6)                     # (nothing changed: no question)
        shot("back")
    finally:
        if exists():
            f = ftp()
            f.delete(TEST)
            f.quit()
        after = user_files()
        check("the user's SETTINGS.INI and themes as they were", after == before, True)
    print("s46u64: %s" % ("all passed" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
