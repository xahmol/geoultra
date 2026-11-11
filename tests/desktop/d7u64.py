#!/usr/bin/env python3
"""GeoUltra's desktop on the U64, step D7 (docs/DESKTOP.md): theme files.
GEOULTRA/THEMES holds the six built-in themes and Custom (made by the
desktop when they are not there: this test only checks they are, and
that Night.ini says what the built-in Night is, its palette too); with
theme=Night the U64's palette is Night's (read back with GET_PALETTE),
and the desktop's Theme routine (called through appMain: menu clicks
are not reliable over REST) switching to GeoUltra gives the Ultimate's
own palette back (RESET_PALETTE); then Custom.ini edited
(desk, sidebar, headings) and SETTINGS.INI [desktop] theme=Custom (made
for the test): after a boot the theme record holds the edited values.
Custom.ini and SETTINGS.INI are put back as they were (an existing
SETTINGS.INI stops the test).
Usage: tests/desktop/d7u64.py [build/geoultra64.crt]
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
THEMES = ["Custom", "Detailed", "Flat", "GEOS classic", "GeoUltra", "Mono", "Night"]
NIGHT = ("desk=light grey on dark grey", "headings=band, black on cyan", "rows=8",
         "selection=bar, black on yellow", "status=on, cyan on black")
NIGHT_PAL = ("12151A E8ECF2 8D2F34 4FC7C2 9835A4 4CB442 2C29B1 F2C94C "
             "984E20 5B3800 D1676D 232830 6B7280 9FEF93 6D6AEF C5CAD3")
CMD, REPLY, STUB = 0x5E00, 0x5E80, 0xC0A0


def palette(u):
    """The U64's current palette (GET_PALETTE through FE_UCI), as hex."""
    u.write(CMD, bytes([0x04, 0x51]))
    u.fe(30, r0=CMD, r1=2, r2=REPLY, r3=48)
    return bytes(u.read(REPLY, 48)).hex().upper()


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
    ftp = ftplib.FTP(u.ip)
    ftp.login()
    if "SETTINGS.INI" in [n.split("/")[-1] for n in ftp.nlst(HOME)]:
        sys.exit("d7u64.py: the stick has a SETTINGS.INI; not touched")

    def get(path):
        out = io.BytesIO()
        ftp.retrbinary("RETR " + path, out.write)
        return out.getvalue()
    u.boot(crt)                                         # (THEMES made if missing)
    time.sleep(15)
    names = sorted(n.split("/")[-1][:-4] for n in ftp.nlst(HOME + "THEMES") if n.lower().endswith(".ini"))
    check("THEMES: the six themes and Custom", names, THEMES)
    night = get(HOME + "THEMES/Night.ini").decode("latin1").replace("\r", "").split("\n")
    check("Night.ini in words", all(line in night for line in NIGHT), True)
    check("Night.ini: its palette", "palette=" + NIGHT_PAL in night, True)
    default = palette(u)
    check("the desktop lists them", u.read(k["themeCount"], 1)[0], 7)
    custom = get(HOME + "THEMES/Custom.ini")
    edited = []
    for line in custom.decode("latin1").split("\r\n"):
        key = line.split("=")[0]
        line = {"desk": "desk=white on blue", "sidebar": "sidebar=narrow, light grey on blue",
                "headings": "headings=band, white on red"}.get(key, line)
        edited.append(line)
    try:
        ftp.storbinary("STOR " + HOME + "SETTINGS.INI", io.BytesIO(b"[desktop]\r\ntheme=Night\r\n"))
        u.boot()
        time.sleep(15)
        check("theme=Night: its palette on the U64", palette(u), NIGHT_PAL.replace(" ", ""))
        names = [bytes(u.read(k["themeNames"] + 15 * i, 15)).split(b"\0")[0] for i in range(7)]
        tick = k["ClockTick"]
        u.write(STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                             0xA9, names.index(b"GeoUltra"), 0x4C, k["Theme"] & 0xFF, k["Theme"] >> 8]))
        u.write(0x849B, bytes([STUB & 0xFF, STUB >> 8]))    # appMain: Theme(GeoUltra), once
        time.sleep(8)
        check("to GeoUltra: the Ultimate's own palette back", palette(u), default)
        check("SETTINGS.INI: theme=GeoUltra", b"theme=GeoUltra" in get(HOME + "SETTINGS.INI"), True)
        ftp.storbinary("STOR " + HOME + "THEMES/Custom.ini", io.BytesIO("\r\n".join(edited).encode("latin1")))
        ftp.storbinary("STOR " + HOME + "SETTINGS.INI", io.BytesIO(b"[desktop]\r\ntheme=Custom\r\n"))
        u.boot()
        time.sleep(15)
        check("theme=Custom in use", bytes(u.read(k["curName"], 7)), b"Custom\0")
        check("desk=white on blue", u.read(k["cDesk"], 1)[0], 0x16)
        check("sidebar=narrow", u.read(k["tSide"], 1)[0], 1)
        check("headings=band, white on red", (u.read(k["tHead"], 1)[0], u.read(k["cHead"], 1)[0]), (1, 0x12))
        check("its band painted red, the text white (swapped)", u.read(k["cHeadP"], 1)[0], 0x21)
    finally:
        ftp.storbinary("STOR " + HOME + "THEMES/Custom.ini", io.BytesIO(custom))
        ftp.delete(HOME + "SETTINGS.INI")
        ftp.quit()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
