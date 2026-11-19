#!/usr/bin/env python3
"""GU PostScript on the U64 (docs/reference/PSW.md; step P6's hardware test): the
desktop's "make PostScript" on GeoUTools' manual writes GEOULTRA/print/
GeoUTools UK.ps on the stick, read back over FTP and compared with
gwtool ps's byte for byte. MOUNTS.INI for the test: A the test copy of
GEOS64.D81, B a D81 made here with the manual (test/psu64.d81); no
SETTINGS.INI (the options box's defaults: A4, real text; OK). The test
image and the .ps are deleted again; the user's MOUNTS.INI,
SETTINGS.INI, RECENT.INI, HIBERNAT.BIN, FONTS.DNP and gush_history are
set aside and put back as they were. Screens: build/harness/print/
psu64-*.png.
Usage: tests/print/psu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

HOME = "/USB0/GEOULTRA/"
DOC = localcfg.get("GEOUTOOLS_MANUAL", os.path.join(localcfg.GEOUTOOLS, "docs", "geowrite-manual-en.cvt"))
NAME = "GeoUTools UK"
IMAGE = HOME + "test/psu64.d81"
PS = HOME + "print/" + NAME + ".ps"
MOUNTS = ("[drives]\r\nA=/USB0/GEOULTRA/test/GEOS64.D81\r\nB=" + IMAGE + "\r\n").encode()
KEY_STUB = 0xC0A0
OUT = os.path.join(ROOT, "build", "harness", "print")
C1541 = localcfg.C1541
KEEP = ("MOUNTS.INI", "SETTINGS.INI", "RECENT.INI", "HIBERNAT.BIN", "FONTS.DNP", "gush_history")


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

    def get(path):
        b = io.BytesIO()
        f = ftp()
        try:
            f.retrbinary("RETR " + path, b.write)
        except ftplib.error_perm:
            return None
        finally:
            f.quit()
        return b.getvalue()

    def put(path, data):
        f = ftp()
        if data is None:
            try:
                f.delete(path)
            except ftplib.error_perm:
                pass
        else:
            f.storbinary("STOR " + path, io.BytesIO(data))
        f.quit()

    def shot(name):
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "psu64-%s.png" % name))

    def press(x, y, s=4):
        u.write(0x3A, bytes([x & 0xFF, x >> 8, y]))
        u.write(0x8505, b"\x00")
        u.write(0x39, bytes([u.read(0x39, 1)[0] | 0x20]))
        time.sleep(0.5)
        u.write(0x8505, b"\x80")
        time.sleep(s)

    def call(routine, a=0, x=0, s=6):
        tick = k["ClockTick"]
        u.write(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                 0xA9, a, 0xA2, x, 0x4C, routine & 0xFF, routine >> 8]))
        u.write(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        time.sleep(s)

    def names():
        out = []
        n = int.from_bytes(bytes(u.read(k["count"], 2)), "little")
        for i in range(n):
            call(k["Fetch"], i & 0xFF, i >> 8, s=0.7)
            out.append(bytes(u.read(k["entryName"], 17)).split(b"\0")[0].decode("latin1"))
        return out

    local = os.path.join(OUT, "psu64.d81")
    if os.path.exists(local):
        os.remove(local)
    subprocess.run([C1541, "-format", "psu64,pu", "d81", local, "-geoswrite", DOC], check=True, capture_output=True)
    kept = {n: get(HOME + n) for n in KEEP}
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "SETTINGS.INI", None)
        put(PS, None)
        put(IMAGE, open(local, "rb").read())
        put(HOME + "MOUNTS.INI", MOUNTS)
        u.boot(crt)
        time.sleep(25)
        u.write(0x4F00, b"/b\0")
        call(k["Into"], 0x00, 0x4F, s=8)
        lst = names()
        check("the manual in /b", NAME in lst, True)
        u.write(k["cur"], bytes([lst.index(NAME) if NAME in lst else 0, 0]))
        call(k["TaskOrMount"], s=20)                    # make PostScript: the box
        shot("box")
        press(220, 84, 2)                               # OK
        t0 = time.time()
        data = None
        for _ in range(60):                             # written: its end arrives
            time.sleep(10)
            data = get(PS)
            if data and data.endswith(b"%%EOF\n"):
                break
        took = time.time() - t0
        shot("done")
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gwtool.py"), "ps", local,
                        os.path.join(OUT, "psu64-pc.ps"), NAME], check=True, capture_output=True)
        pc = open(os.path.join(OUT, "psu64-pc.ps"), "rb").read()
        if data:
            open(os.path.join(OUT, "psu64-c64.ps"), "wb").write(data)
        check("GEOULTRA/print/%s.ps is gwtool ps's file (%d s)" % (NAME, took),
              (len(data or b""), data == pc), (len(pc), True))
    finally:
        put(PS, None)
        put(IMAGE, None)
        for n, d in kept.items():
            put(HOME + n, d)
        back = all(get(HOME + n) == d for n, d in kept.items())
        check("the user's files back as they were", back, True)
    print("psu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
