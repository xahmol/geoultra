#!/usr/bin/env python3
"""GeoUltra Settings on the U64: the Drives page (S5; the user's
decisions of 2026-11-14; pdrives.s, overlay 7). Test copies only, in
/USB0/GEOULTRA/test/s5 (made and removed here): gus5.d64 (the test
D64) and gus5.dnp (build/sysdrive-plain.dnp, 8 tracks). Drive D (empty
in the user's MOUNTS.INI) is the one used:
- "choose" on D: the browser in GEOULTRA, into test, into s5, gus5.d64
  clicked twice: mounted on D;
- "long names on" clicked: off (MOUNTS.INI's D line ",longnames=off");
- "none", Yes: D empty again;
- "new image": the form, type [-] to D71, the name written into the
  form (typing into the text dialog is not driven here), make: gunew.d71
  in test/s5, "Mount it on drive D?" Yes: mounted;
- gus5.dnp on D (FE_MOUNT), its tracks [+] four times, "resize": 12.
The user's MOUNTS.INI and HIBERNAT.BIN are set aside first and put back
at the end; D is emptied. Screens: build/harness/gush/settings-s5-*.png.
Usage: tests/settings/s5u64.py [build/geoultra64.crt]
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

HOME = "/USB0/GEOULTRA"
DIR = HOME + "/test/s5"
UDIR = "/usb0/geoultra/test/s5"
KEY_STUB = 0xC0A0
PAGE_DRIVES, SIDE_TOP, SIDE_ROW = 4, 16, 16      # (SIDE_TOP 16 since 2026-11-19)
ROW0_Y, ROW_DY, LINE2 = 30, 34, 14
CHOOSE_X, NONE_X, NAME_X = 232, 276, 110
TUP_X, RESIZE_X = 262, 278
NEW_Y = 157
LIST_TOP, ROW_H = 42, 11
YES_XY = (90, 110)
FE_MOUNT, FE_UMOUNT, FE_MOUNTINFO = 17, 18, 23
F_NOLONG = 0x10
BUF = 0x5F00
OUT = os.path.join(ROOT, "build", "harness", "gush")


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def overlay_labels(path):
    """The labels inside the page overlays ($5000-$5FFF), which share
    names with the core's."""
    out = {}
    for line in open(path):
        p = line.split()
        a = int(p[1], 16)
        if 0x5000 <= a < 0x6000:
            out.setdefault(p[2].lstrip("."), a)
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    s = labels(os.path.join(ROOT, "build", "settings", "settings.lbl"))
    o = overlay_labels(os.path.join(ROOT, "build", "settings", "settings.lbl"))
    u = U64()
    ok = True
    os.makedirs(OUT, exist_ok=True)

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def get(path):
        f = ftp()
        b = io.BytesIO()
        try:
            f.retrbinary("RETR " + path, b.write)
        except ftplib.error_perm:
            f.quit()
            return None
        f.quit()
        return b.getvalue()

    def put(path, data):
        f = ftp()
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
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(t)

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8),
                      os.path.join(OUT, "settings-s5-%s.png" % name))

    def obyte(name):
        return u.read(o[name], 1)[0]

    def entries():
        n = obyte("count")
        raw = bytes(u.read(s["names"], n * 48))
        return [raw[i * 48:(i + 1) * 48].split(b"\0")[0].decode("latin1") for i in range(n)]

    def open_entry(name):
        """The entry of that name clicked twice (in view: within the first
        rows)."""
        i = [e.lower() for e in entries()].index(name.lower()) - obyte("top")
        y = LIST_TOP + 1 + i * ROW_H + 5
        press(NAME_X + 20, y, t=4)
        press(NAME_X + 20, y, t=8)

    def info():
        x, _, r = u.fe(FE_MOUNTINFO, s0="/d", r1=BUF)
        u.write(s["curOvl"], b"\xff")                     # (feu64's code went to the
        path = bytes(u.read(BUF, 64)).split(b"\0")[0].decode("latin1") if x == 0 else ""
        return x, path, r[3] & 0xFF, r[3] >> 8

    def row(d):
        return ROW0_Y + d * ROW_DY

    ini = get(HOME + "/MOUNTS.INI")
    hib = get(HOME + "/HIBERNAT.BIN")
    f = ftp()
    if hib is not None:
        f.delete(HOME + "/HIBERNAT.BIN")
    try:
        f.mkd(DIR)
    except ftplib.error_perm:
        pass
    f.quit()
    put(DIR + "/gus5.d64", get(HOME + "/test/geopub.d64"))
    put(DIR + "/gus5.dnp", open(os.path.join(ROOT, "build", "sysdrive-plain.dnp"), "rb").read())
    try:
        u.boot(crt)
        time.sleep(20)
        call(k["Settings"])
        press(20, SIDE_TOP + PAGE_DRIVES * SIDE_ROW + 7, t=8)
        shot("rows")
        press(CHOOSE_X + 10, row(3) - 5, t=8)               # D: choose
        check("the browser, in GEOULTRA", (obyte("mode"),
              bytes(u.read(s["bpath"], 40)).split(b"\0")[0].lower()), (1, b"/usb0/geoultra"))
        shot("browser")
        open_entry("test")
        open_entry("s5")
        check("into test/s5: its images", sorted(entries()), ["..", "gus5.d64", "gus5.dnp"])
        open_entry("gus5.d64")
        x, path, _, _ = info()
        check("gus5.d64 mounted on D", (x, path.lower()), (0, UDIR + "/gus5.d64"))
        shot("mounted")
        press(NAME_X + 20, row(3) + LINE2 - 5, t=8)         # long names on -> off
        line = [l for l in get(HOME + "/MOUNTS.INI").split(b"\r\n") if l.startswith(b"D=")]
        check("long names off: F_NOLONG, MOUNTS.INI ,longnames=off",
              (info()[3] & F_NOLONG, [l.lower() for l in line]),
              (F_NOLONG, [b"d=" + (UDIR + "/gus5.d64").encode() + b",longnames=off"]))
        press(NONE_X + 10, row(3) - 5, t=4)                 # none: asked
        press(*YES_XY, t=10)
        check("none, Yes: D empty", info()[0], 13)
        press(NAME_X + 20, NEW_Y + 5, t=6)                  # new image: the form
        check("the form", obyte("mode"), 2)
        press(148 + 7, ROW0_Y + 8 - 3, t=4)                 # type [-]: D71
        u.write(o["fName"], b"gunew\0")
        press(NAME_X + 10, NEW_Y + 5, t=12)                 # make
        shot("made")
        press(*YES_XY, t=15)                                # mount it on D? Yes
        x, path, _, _ = info()
        check("gunew.d71 made in test/s5 and mounted on D",
              (get(DIR + "/gunew.d71") is not None, x, path.lower()), (True, 0, UDIR + "/gunew.d71"))
        u.fe(FE_UMOUNT, s0="/d", timeout=120)
        u.write(s["curOvl"], b"\xff")
        check("FE_MOUNT gus5.dnp on D (8 tracks)",
              u.fe(FE_MOUNT, s0="/d", s1=UDIR + "/gus5.dnp", timeout=120)[0], 0)
        u.write(s["curOvl"], b"\xff")
        press(20, SIDE_TOP + PAGE_DRIVES * SIDE_ROW + 7, t=8)   # the page anew
        for _ in range(4):
            press(TUP_X + 7, row(3) + LINE2 - 5, t=3)
        shot("tracks")
        press(RESIZE_X + 10, row(3) + LINE2 - 5, t=20)
        check("tracks [+] x 4, resize: 12 tracks", info()[2], 12)
    finally:
        try:
            u.fe(FE_UMOUNT, s0="/d", timeout=120)
        except Exception:
            pass
        put(HOME + "/MOUNTS.INI", ini)
        if hib is not None:
            put(HOME + "/HIBERNAT.BIN", hib)
        f = ftp()
        for n in ("gus5.d64", "gus5.dnp", "gunew.d71"):
            for p in (DIR + "/" + n, HOME + "/BACKUP/" + n):
                try:
                    f.delete(p)
                except ftplib.error_perm:
                    pass
        try:
            f.rmd(DIR)
        except ftplib.error_perm:
            pass
        f.quit()
        check("MOUNTS.INI as it was", get(HOME + "/MOUNTS.INI") == ini, True)
    print("s5u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
