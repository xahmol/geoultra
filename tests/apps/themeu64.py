#!/usr/bin/env python3
"""Original programs under a desktop theme on the U64 (the user, 2026-11-15:
how do they look with, for example, Night?): SETTINGS.INI's theme set to
THEME (the user's file kept first and put back byte for byte), a boot,
the desktop; geoWrite (/c/Writing/GEOWRITE) and GeoLudo (/c/Games/GeoLudo)
each started in a new task (FE_TASK, as "open in new task"): geoWrite's
start dialog, GeoLudo's board with four AI players. Nothing is written
to the drives. Screens from the VIC stream: build/e2e/theme/*.png, for
looking at; the checks are that each program runs (its task name) and
that the palette is the theme's (Night: colour 0 is not black).
Usage: tests/apps/themeu64.py [build/geoultra64.crt] [THEME]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

OUT = os.path.join(ROOT, "build", "e2e", "theme")
SHOT = localcfg.GEOUTOOLS_SHOT
HOME = "/USB0/GEOULTRA/"
FE_TASK = 32
KEY_DELETE, CR = 29, 13


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    theme = sys.argv[2] if len(sys.argv) > 2 else "Night"
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    os.makedirs(OUT, exist_ok=True)
    u = U64()
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def get(name):
        b = io.BytesIO()
        f = ftp()
        try:
            f.retrbinary("RETR " + HOME + name, b.write)
        except ftplib.error_perm:
            return None
        finally:
            f.quit()
        return b.getvalue()

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

    def shot(name):
        u.write(0x3A, bytes([0x30, 0x01, 196]))
        time.sleep(0.5)
        path = os.path.join(OUT, "%s-%s.png" % (theme.lower(), name))
        subprocess.run([sys.executable, SHOT, "--device", u.ip, path], check=True,
                       capture_output=True, timeout=60)
        print("screen:", path)

    def press(x, y, t=1.0):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        for data in (0x00, 0x80):
            u.write(0x8505, bytes([data]))
            u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
            time.sleep(0.4)
        time.sleep(t)

    def key(c, t=0.6):
        head = u.read(kern["qHead"], 1)[0]
        u.write(kern["keyQueue"] + head, bytes([c]))
        u.write(kern["qHead"], bytes([(head + 1) & 15]))
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x80]))
        time.sleep(t)

    def task(path, t=25):
        x, a, regs = u.fe(FE_TASK, y=2, s0=path)
        time.sleep(t)
        return x

    keep = {n: get(n) for n in ("SETTINGS.INI", "HIBERNAT.BIN")}
    ini = (keep["SETTINGS.INI"] or b"[desktop]\r\n").decode("latin1")
    lines = [l for l in ini.split("\r\n") if not l.startswith("theme=")]
    i = lines.index("[desktop]") if "[desktop]" in lines else -1
    if i < 0:
        lines[:0] = ["[desktop]"]
        i = 0
    lines.insert(i + 1, "theme=" + theme)
    try:
        put("HIBERNAT.BIN", None)
        put("SETTINGS.INI", "\r\n".join(lines).encode("latin1"))
        u.boot(crt)
        time.sleep(25)
        shot("desktop")
        check("geoWrite started in a new task", task("/c/Writing/GEOWRITE"), 0)
        print("  (task name: %r)" % u.read(kern["taskName"], 12))
        shot("geowrite")
        press(102, 111, 8)                          # Quit (to the desktop)
        check("GeoLudo started in a new task", task("/c/Games/GeoLudo"), 0)
        check("GeoLudo running", u.read(kern["taskName"], 7), b"GeoLudo")
        shot("geoludo-title")
        press(44, 6, 2)                             # Game > (Re)Start, 4 AI players
        press(20, 17, 3)
        key(KEY_DELETE)
        key(ord("4"))
        key(CR, 3)
        for _ in range(4):
            key(CR, 2)
        time.sleep(12)
        press(300, 190, 2)
        shot("geoludo-board")
    finally:
        for n, d in keep.items():
            put(n, d)
        u.boot()                                    # (the user's own theme again)
        time.sleep(5)
        check("the user's files back as they were", all(get(n) == d for n, d in keep.items()), True)
    print("themeu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
