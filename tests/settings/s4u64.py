#!/usr/bin/env python3
"""GeoUltra Settings on the U64, step S4.3 (docs/SETTINGS.md): the Theme
page with the real theme files. The user's SETTINGS.INI and
THEMES/Custom.ini are kept first and put back byte for byte at the
end. Settings on its Theme page lists the THEMES folder's files; [+]
until Custom; the border's paper set to red; Save writes
THEMES/Custom.ini through Custom.tmp: its border line red, every other
line as before. Then the palette (S4.4): from the Ultimate's own (Custom
has none), blue's red a step up, seen at once with GET_PALETTE; Save
writes palette=; none gives the Ultimate's palette back and Save takes
the line out.
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
        # S4.4: the palette, live on the U64. Custom has no palette=: the
        # editor starts from the Ultimate's palette now (its default).
        def u64_palette():
            u.write(CMD, bytes([0x04, 0x51]))
            u.fe(30, r0=CMD, r1=2, r2=REPLY, r3=48)
            u.write(s["curOvl"], b"\xff")                  # (u.fe's code went to
            return bytes(u.read(REPLY, 48)).hex().upper()   # $5000: the page's
                                                            # overlay fetched anew)
        before = u64_palette()
        press(156, 54 - 3, t=4)                             # part [-]: the palette
        press(SWATCH_X + 6 * 8 + 3, PAPER_Y, t=3)          # blue
        press(118 + 38 + 7, 72 - 3, t=4)                   # R +
        now = u64_palette()
        blue = int(before[36:38], 16)
        check("R +: blue's red a step up on the Ultimate at once",
              now, before[:36] + "%02X" % min(255, blue + 4) + before[38:])
        press(*SAVE_XY, t=8)
        pal = [l for l in fetch(CUSTOM).split(b"\r\n") if l.startswith(b"palette=")]
        want = " ".join(now[i:i + 6] for i in range(0, 96, 6)).encode()
        check("Save: Custom.ini's palette= the 16 colours", pal, [b"palette=" + want])
        press(118 + 3 * 56 + 4 + 14, 72 - 3, t=4)        # none
        check("none: the Ultimate's own palette back", u64_palette(), before)
        press(*SAVE_XY, t=8)
        check("Save: palette= gone again",
              [l for l in fetch(CUSTOM).split(b"\r\n") if l.startswith(b"palette=")], [])
    finally:
        store(custom, CUSTOM)
        store(keep)
        check("Custom.ini and the user's SETTINGS.INI back as they were",
              (fetch(CUSTOM) == custom, fetch() == keep), (True, True))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
