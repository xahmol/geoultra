#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: two panes keep their folders
(src/desktop/inifile.s PanesKeep, DeskRead; the user, 2026-11-12, after
GeoDesk64's two-window mode). The user's own SETTINGS.INI is set aside
first and put back byte for byte at the end. A test SETTINGS.INI with
panes=2 and pane2=/b: the desktop starts in two panes with the other
pane in /b (seen by switching to it); back to the first, which goes to
/a; Leave (as before a program) writes pane2= with the other pane's
folder (/b) only when it changed: unchanged here, the file the same;
then the other pane to /e and Leave: pane2=/e written.
Usage: tests/desktop/d15u64.py [build/geoultra64.crt]
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
KEY_STUB = 0xC0A0               # the info block's unused bytes (gushvice.py)
TEST_INI = b"[desktop]\r\npanes=2\r\npane2=/b\r\n"
PATH_STR = 0xC0B8


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    u = U64()
    u.require_test_drives("A")                  # (it writes onto drive A)
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

    def fetch():
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + SETTINGS, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def store(data):
        f = ftp()
        if data is None:
            try:
                f.delete(SETTINGS)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + SETTINGS, io.BytesIO(data))
        f.quit()

    def call(routine, s=10):
        """routine once through appMain (ClockTick back first)."""
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def byte(name):
        return u.read(k[name], 1)[0]

    keep = fetch()
    try:
        store(TEST_INI)
        u.boot(crt)
        time.sleep(20)
        def path():
            return bytes(u.read(k["path"], 40)).split(b"\0")[0].decode("latin1")

        def into(p, t=6):
            u.write(PATH_STR, p.encode() + b"\0")
            tick, routine = k["ClockTick"], k["Into"]
            u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                     0xA9, PATH_STR & 0xFF, 0xA2, PATH_STR >> 8,
                                     0x4C, routine & 0xFF, routine >> 8]))
            u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            time.sleep(t)

        check("panes=2: two panes at the start", byte("panes"), 1)
        call(k["PaneSwitch"], 6)
        check("pane2=/b: the other pane in /b", path().lower(), "/b")
        call(k["PaneSwitch"], 6)
        into("/a")
        check("the first pane to /a", path().lower(), "/a")
        before = fetch()
        call(k["Leave"], 8)
        check("Leave with the other pane unchanged: the file the same", fetch() == before, True)
        call(k["PaneSwitch"], 6)
        into("/e")
        call(k["PaneSwitch"], 6)
        call(k["Leave"], 8)
        lines = (fetch() or b"").replace(b"\r", b"").split(b"\n")
        check("the other pane to /e, Leave: pane2=/e written", b"pane2=/e" in lines, True)
    finally:
        store(keep)
        check("the user's SETTINGS.INI back as it was", fetch() == keep, True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
