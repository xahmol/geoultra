#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: SETTINGS.INI's [desktop] read and written
with the shared INI code (inifile.s DeskText, KeyVal, SetLine; found by
the user's test 2026-11-13: the desktop kept only four [desktop] lines,
read no more and wrote only those back, so Settings' copy=, delete=,
panes= ... were lost). A test SETTINGS.INI with nine [desktop] lines and
a [system] section; after a fresh boot the desktop has copy=skip and
delete=now (deskPrefs); its own save (ViewSave) leaves the file as it
was. The user's SETTINGS.INI, RECENT.INI and HIBERNAT.BIN are kept
first and put back byte for byte at the end.
Usage: tests/desktop/d16u64.py [build/geoultra64.crt]
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
KEY_STUB = 0xC0A0
PREF_SKIP, PREF_NOASK = 2, 4
TEST = (b"[desktop]\r\ntheme=GeoUltra\r\nview=list\r\ntoolbar=16\r\nclock=24\r\npanes=1\r\nsort=name\r\n"
        b"copy=skip\r\ndelete=now\r\n[system]\r\npointercolour=6\r\n")


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
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

    def get(name):
        out = io.BytesIO()
        try:
            f = ftp()
            f.retrbinary("RETR " + HOME + name, out.write)
            f.quit()
        except ftplib.error_perm:
            return None
        return out.getvalue()

    def put(name, data):
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

    keep = {n: get(n) for n in ("SETTINGS.INI", "RECENT.INI", "HIBERNAT.BIN")}
    try:
        put("HIBERNAT.BIN", None)                       # (a fresh start)
        put("SETTINGS.INI", TEST)
        u.boot(crt)
        time.sleep(25)
        check("all nine [desktop] lines read: copy=skip, delete=now",
              u.read(k["deskPrefs"], 1)[0], PREF_SKIP | PREF_NOASK)
        call(k["ViewSave"])
        check("the desktop's own save: the file as it was", get("SETTINGS.INI"), TEST)
    finally:
        for n, d in keep.items():
            put(n, d)
        check("the user's files back as they were", all(get(n) == d for n, d in keep.items()), True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
