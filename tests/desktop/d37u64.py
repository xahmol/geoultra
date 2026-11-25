#!/usr/bin/env python3
"""GeoUltra started as the user starts it (the hand test of 2026-11-21:
geos > GeoUltra > reboot went to BASIC): the Ultimate's Cartridge setting
empty and the .crt run from its file browser (REST runners:run_crt), so
an Ultimate reboot would drop it. Two tasks (FE_TASK, a new one in /e);
hibernate now, then the .crt started again (as after a power cycle):
both tasks back; reboot from the menu: GeoUltra must come back (its own
restart through the cartridge's ROM), with both tasks. The user's
SETTINGS.INI, MOUNTS.INI, RECENT.INI, HIBERNAT.BIN and the Cartridge
setting are kept first and put back. Screens: build/harness/desktop/d37-*.png.
Usage: tests/desktop/d37u64.py [build/geoultra64.crt]
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
CRT = HOME + "test/gutest.crt"
KEEP = ("SETTINGS.INI", "MOUNTS.INI", "RECENT.INI", "HIBERNAT.BIN")
OUT = os.path.join(ROOT, "build", "harness", "desktop")
CART = "/v1/configs/C64%20and%20Cartridge%20Settings/Cartridge"
FE_TASK = 32
MENU_BOTTOM, ROW = 14, 14
HIBERNATE, REBOOT = 4, 5
OK_XY = (64 + 17 * 8 + 20, 32 + 72 + 8)


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    desk = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:32]
    u = U64()
    base = "http://%s" % u.ip
    ok = True
    os.makedirs(OUT, exist_ok=True)

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)),
              flush=True)

    def rest(method, path):
        req = urllib.request.Request(base + path, method=method)
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read()

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

    def store(path, data):
        f = ftp()
        if data is None:
            try:
                f.delete(path)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + path, io.BytesIO(data))
        f.quit()

    def press(x, y, t=2):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(t)

    def item(n, t, tag=None):
        for _ in range(3):                              # (a press can come before
            press(12, 5)                                # the desktop listens: again)
            if bytes(u.read(0xA000 + 320 * 3, 8)) != top:
                break
        if tag:
            shot(tag + "-1")
        press(30, MENU_BOTTOM + 7)
        if tag:
            shot(tag + "-2")
        press(120, MENU_BOTTOM + n * ROW + 7, t)
        if tag:
            shot(tag + "-3")

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "d37-%s.png" % name))

    def running():
        return bytes(u.read(0x0400, 32)) == desk

    def tasks():
        return u.fe(FE_TASK, y=0)[1]

    cart = json.loads(rest("GET", CART))["C64 and Cartridge Settings"]["Cartridge"]["current"]
    kept = {n: fetch(n) for n in KEEP}
    safe = os.path.join(OUT, "d37-kept")                    # (a copy on the PC too,
    os.makedirs(safe, exist_ok=True)                        # should the test break off)
    for n, d in kept.items():
        if d is not None:
            open(os.path.join(safe, n), "wb").write(d)
    open(os.path.join(safe, "Cartridge"), "w").write(cart)
    try:
        store(HOME + "HIBERNAT.BIN", None)
        store(CRT, open(crt, "rb").read())
        rest("PUT", CART + "?value=")                       # (no cartridge set)
        rest("PUT", "/v1/runners:run_crt?file=" + urllib.parse.quote(CRT))
        time.sleep(25)
        check("run from the file: the desktop runs", running(), True)
        top = bytes(u.read(0xA000 + 320 * 3, 8))            # card row 3, column 0 closed
        x, a, _ = u.fe(FE_TASK, y=2, s0="/e")               # a second task
        time.sleep(15)
        check("two tasks", tasks(), 2)
        shot("two")
        item(HIBERNATE, 35)
        press(*OK_XY, 3)
        check("hibernate now: HIBERNAT.BIN written", (fetch("HIBERNAT.BIN") or b"") != b"", True)
        rest("PUT", "/v1/runners:run_crt?file=" + urllib.parse.quote(CRT))   # (as after
        time.sleep(40)                                                        # power off, on)
        shot("restarted")
        check("the .crt started again: the desktop", running(), True)
        check("the session back: two tasks", tasks(), 2)
        u.write(0x8505, b"\x80")                           # (the snapshot was taken during
        time.sleep(1)                                       # the menu click: injected press)
        item(REBOOT, 50)
        shot("rebooted")
        check("reboot: GeoUltra again, not BASIC (the desktop)", running(), True)
        check("the session back again: two tasks", tasks(), 2)
    finally:
        rest("PUT", CART + "?value=" + urllib.parse.quote(cart))
        store(CRT, None)
        for n, d in kept.items():
            store(HOME + n, d)
        back = all(fetch(n) == d for n, d in kept.items())
        check("the user's files and Cartridge setting back", back, True)
        try:
            u.boot()
        except OSError:                                     # (the REST call may time
            pass                                            # out while it reboots)
    print("d37u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
