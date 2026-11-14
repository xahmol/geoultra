#!/usr/bin/env python3
"""GeoUltra's desktop on the U64 (docs/DESKTOP.md): disk images.
A favourite (SETTINGS.INI, made for the test and deleted again) takes the
desktop to /usb0/geoultra/test; the cursor walks to geopub.d64 (its name
read back through the clipboard, C=C) and RETURN opens the mount dialog;
drive D's button (a free letter; C holds the system DNP for testing)
mounts it: the list at /d, FE_MOUNTINFO's
path, the sidebar's line for D with its eject icon. Then a click on that
icon and YES unmount it: D gone from the sidebar. The images are test
copies (/USB0/GEOULTRA/test); MOUNTS.INI is put back as it was at the
end. Screens: build/harness/gush/d6u64-*.png.
Usage: tests/desktop/d6u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402

HOME = "/USB0/GEOULTRA/"
IMAGE = "geopub.d64"
INI = b"[favourites]\r\n/usb0/geoultra/test\r\n"
KEY_STUB = 0xC0A0
KEY_DOWN, KEY_HOME, CR, C = 17, 18, 13, 0x80
DLG_X, DLG_Y = 64, 32           # DEF_DB_POS's top left
OUT = os.path.join(ROOT, "build", "harness", "gush")



def fe(u, k, *args, **kw):
    """An engine call through feu64 (its stub and results at $5000-$50FF,
    the desktop's overlay area): the overlay there then marked as gone
    (curOvl $FF), so the desktop's next stub fetches a clean one."""
    r = u.fe(*args, **kw)
    u.write(k["curOvl"], b"\xff")
    return r

def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels()
    u = U64()
    ok = True
    os.makedirs(OUT, exist_ok=True)

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    ftp = ftplib.FTP(u.ip)
    ftp.login()
    names = [n.split("/")[-1] for n in ftp.nlst(HOME)]
    if "SETTINGS.INI" in names:
        sys.exit("d6u64.py: the stick has a SETTINGS.INI; not touched")

    def get(path):
        out = io.BytesIO()
        ftp.retrbinary("RETR " + path, out.write)
        return out.getvalue()
    mounts = get(HOME + "MOUNTS.INI")

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "d6u64-%s.png" % name))

    def press(x, y, s=6):
        u.write(0x3A, bytes([x, 0, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)                             # (released, as a real
        u.write(0x8505, b"\x80")                  # click: Drag waits)
        time.sleep(s)

    def key(c, s=3):
        old = u.read(0x849B, 2)                         # (gush's gu64.py)
        u.write(KEY_STUB, bytes([0xA9, c, 0x8D, 0x04, 0x85, 0xA9, old[0], 0x8D, 0x9B, 0x84,
                                 0xA9, old[1], 0x8D, 0x9C, 0x84, 0x6C, 0xA3, 0x84]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def path():
        return bytes(u.read(k["path"], 32)).split(b"\0")[0].decode("latin1")

    def side():
        n = u.read(k["sideCount"], 1)[0]
        return bytes(u.read(k["sideLetters"], n)), bytes(u.read(k["sideTops"], n))

    ftp.storbinary("STOR " + HOME + "SETTINGS.INI", io.BytesIO(INI))
    try:
        u.boot(crt)
        time.sleep(15)                                  # the cold start: the desktop
        code = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:32]
        check("the cold start ends in GeoUltra's desktop", bytes(u.read(0x0400, 32)), code)
        letters, tops = side()
        check("drive D free at the start", b"d" in letters, False)
        press(20, tops[letters.index(b"\x80")] + 4)     # the favourite
        check("the favourite: the test folder", path().lower(), "/usb0/geoultra/test")
        key(KEY_HOME)
        found = False
        for _ in range(20):                             # to geopub.d64
            key(C | ord("c"), 2)
            name = bytes(u.read(k["entryName"], 20)).split(b"\0")[0].decode("latin1")
            if name.lower() == IMAGE:
                found = True
                break
            key(KEY_DOWN, 2)
        check("geopub.d64 under the cursor", found, True)
        key(CR, 8)                                      # the mount dialog
        shot("dialog")
        press(DLG_X + 8 + 20, DLG_Y + 20 + 3 * 18 + 8, 25)   # drive D's button
        shot("mounted")
        check("mounted on D: the list at /d", path(), "/d")
        info = 0x5F00
        x = fe(u, k, 23, s0="/d", r1=info)[0]               # FE_MOUNTINFO
        got = bytes(u.read(info, 64)).split(b"\0")[0].decode("latin1").lower()
        check("FE_MOUNTINFO /d: the test image", (x, got), (0, "/usb0/geoultra/test/" + IMAGE))
        letters, tops = side()
        check("the sidebar's line for D", b"d" in letters, True)
        press(67, tops[letters.index(b"d")] + 4, 4)     # its eject icon
        shot("eject")
        press(DLG_X + 8 + 20, DLG_Y + 72 + 8, 20)       # YES
        letters, tops = side()
        check("unmounted: D gone from the sidebar", b"d" in letters, False)
        check("FE_MOUNTINFO /d: nothing", fe(u, k, 23, s0="/d", r1=info)[0], 13)
        shot("after")
    finally:
        ftp.delete(HOME + "SETTINGS.INI")
        ftp.storbinary("STOR " + HOME + "MOUNTS.INI", io.BytesIO(mounts))
        ftp.quit()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
