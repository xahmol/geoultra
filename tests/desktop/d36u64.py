#!/usr/bin/env python3
"""geos > GeoUltra on the U64 (the user's decisions of 2026-11-20): the
submenu's hibernate now, reboot and BASIC.
- hibernate now: "GeoUltra is saved. You can switch off now." and
  HIBERNAT.BIN on the stick; OK; a reboot (as a power cycle) resumes the
  session: the desktop again, no message this time.
- reboot: the session kept, the desktop back.
- BASIC (Yes): BASIC's READY. on the screen; a reboot brings GeoUltra.
The user's SETTINGS.INI, MOUNTS.INI, RECENT.INI and HIBERNAT.BIN are kept
first and put back byte for byte; the Cartridge setting is set to the
flash copy for the test and put back (the user's is empty: the .crt is
run from the file browser; d37u64.py tests that way). Screens: build/harness/desktop/d36-*.png.
Usage: tests/desktop/d36u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402

HOME = "/USB0/GEOULTRA/"
KEEP = ("SETTINGS.INI", "MOUNTS.INI", "RECENT.INI", "HIBERNAT.BIN")
OUT = os.path.join(ROOT, "build", "harness", "desktop")
CART = "/v1/configs/C64%20and%20Cartridge%20Settings/Cartridge"
MENU_BOTTOM, ROW = 14, 14
GEOS_XY = (12, 5)
GEOULTRA_XY = (30, MENU_BOTTOM + 7)
SUB_X = 120
HIBERNATE, REBOOT, BASIC = 4, 5, 7               # the submenu's items
DLG_X, DLG_Y = 64, 32
OK_XY = (DLG_X + 17 * 8 + 20, DLG_Y + 72 + 8)
YES_XY = (DLG_X + 1 * 8 + 20, DLG_Y + 72 + 8)


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    desk = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:32]
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

    def press(x, y, t=2):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(t)

    def item(n, t):
        press(*GEOS_XY)
        press(*GEOULTRA_XY)
        press(SUB_X, MENU_BOTTOM + n * ROW + 7, t)

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "d36-%s.png" % name))

    def running():
        return bytes(u.read(0x0400, 32)) == desk

    def message():                                  # the saved message's words
        return b"switch off" in bytes(u.read(0x5000, 0x1000))

    def rest(method, path):
        req = urllib.request.Request("http://%s%s" % (u.ip, path), method=method)
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read()

    cart = json.loads(rest("GET", CART))["C64 and Cartridge Settings"]["Cartridge"]["current"]
    kept = {n: fetch(n) for n in KEEP}
    try:
        rest("PUT", CART + "?value=geoultra64.crt")         # (the flash copy: u.boot)
        store("HIBERNAT.BIN", None)
        u.boot(crt)
        time.sleep(20)
        check("the desktop runs", running(), True)
        item(HIBERNATE, 30)
        shot("saved")
        check("hibernate now: HIBERNAT.BIN written", (fetch("HIBERNAT.BIN") or b"") != b"", True)
        check("the message (overlay 9 with its text in)", message(), True)
        press(*OK_XY, 3)
        check("OK: the desktop carries on", running(), True)
        u.boot()                                    # (as a power cycle)
        time.sleep(35)
        shot("resumed")
        check("the session resumed: the desktop", running(), True)
        check("HIBERNAT.BIN gone after the resume", fetch("HIBERNAT.BIN"), None)
        item(REBOOT, 45)
        shot("rebooted")
        check("reboot: the session back (the desktop)", running(), True)
        item(BASIC, 3)
        shot("basic-ask")
        press(*YES_XY, 15)
        screen = bytes(u.read(0x0400, 1000))
        check("BASIC: READY. on the screen", b"\x12\x05\x01\x04\x19\x2e" in screen, True)
        u.boot()
        time.sleep(35)
        check("a reboot: GeoUltra again", running(), True)
    finally:
        rest("PUT", CART + "?value=" + urllib.parse.quote(cart))   # (the user's: empty)
        for n, d in kept.items():
            store(n, d)
        back = all(fetch(n) == d for n, d in kept.items())
        check("the user's files back as they were", back, True)
        if kept.get("HIBERNAT.BIN"):
            u.boot()
    print("d36u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
