#!/usr/bin/env python3
"""GeoUltra's desktop on the U64: CVT files dropped into GEOULTRA/fonts
installed at the desktop's start (docs/DESIGN.md "System font folder",
step F4; fontact.s Import). Two CVT files from the user's library
(fonts/English: Roma, Mykonos) copied to the top of GEOULTRA/fonts, no
FONTS.DNP, MOUNTS.INI with A and B only: at the cold start the desktop
makes FONTS.DNP with both (read back from the stick) and asks "Done.
Restart now?"; NO. A fresh start then has them in /f and leaves
FONTS.DNP alone (no second question: the same bytes). The two CVT
files are deleted again; the user's MOUNTS.INI, SETTINGS.INI,
RECENT.INI, HIBERNAT.BIN, FONTS.DNP and gush_history put back as they
were. Screens: build/harness/gush/d34u64-*.png.
Usage: tests/desktop/d34u64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
from feu64 import U64  # noqa: E402
import apprun  # noqa: E402

HOME = "/USB0/GEOULTRA/"
MOUNTS = b"[drives]\r\nA=/USB0/GEOULTRA/test/GEOS64.D81\r\nB=/USB0/GEOULTRA/test/neos.d64\r\n"
FONTS = ("Roma", "Mykonos")
KEY_STUB = 0xC0A0
DLG_X, DLG_Y = 64, 32
OUT = os.path.join(ROOT, "build", "harness", "gush")
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
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "d34u64-%s.png" % name))

    def press(x, y, s=6):
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

    def path():
        return bytes(u.read(k["path"], 32)).split(b"\0")[0].decode("latin1")

    def stored(data):
        if data is None:
            return None
        local = os.path.join(OUT, "d34-FONTS.DNP")
        open(local, "wb").write(data)
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "geosdisk.py"), "list", local],
                           capture_output=True, text=True)
        return sorted(l.split()[1] for l in r.stdout.splitlines()
                      if len(l.split()) > 2 and l.split()[0].isdigit() and "blocks free" not in l)

    kept = {n: get(HOME + n) for n in KEEP}
    cvts = {n: get(HOME + "fonts/English/%s.cvt" % n) for n in FONTS}
    check("the library's CVT files there", all(cvts.values()), True)
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "FONTS.DNP", None)
        put(HOME + "MOUNTS.INI", MOUNTS)
        u.boot(crt)                                         # an earlier session's queue,
        time.sleep(35)                                      # paused (spool.s module 105;
                                                            # after the desktop's first tick:
                                                            # its pickup and import, 2026-11-19)
        x = u.fe(33, y=1)[0]                                # FE_SPOOL: pause, state
        r = u.fe(33, y=0)
        check("a session's print queue paused", (x, r[2][0] >> 8), (0, 0x80))
        for n, d in cvts.items():
            put(HOME + "fonts/%s.cvt" % n, d)
        put(HOME + "HIBERNAT.BIN", None)                    # (a cold start, not that session)
        u.boot(crt)
        time.sleep(40)                                      # the start; the import at the first tick
        shot("asked")
        dnp = get(HOME + "FONTS.DNP")
        check("FONTS.DNP made with both", stored(dnp), sorted(FONTS))
        press(DLG_X + 17 * 8 + 20, DLG_Y + 72 + 8, 8)       # NO
        shot("after")
        check("the list after the question", int.from_bytes(bytes(u.read(k["count"], 2)), "little") > 0, True)
        r = u.fe(33, y=0)
        check("the cold start: the old queue forgotten (empty, not paused)", (r[0], r[1], r[2][0] >> 8), (0, 0, 0))
        put(HOME + "HIBERNAT.BIN", None)                    # (a fresh start, not the session)
        u.boot(crt)
        time.sleep(30)
        shot("second")
        check("the second start: FONTS.DNP left alone", get(HOME + "FONTS.DNP") == dnp, True)
        u.write(0x4F00, b"/f\0")
        call(k["Into"], 0x00, 0x4F, s=8)
        check("/f lists both", (path(), sorted(n for n in names() if n in FONTS)), ("/f", sorted(FONTS)))
    finally:
        for n in FONTS:
            put(HOME + "fonts/%s.cvt" % n, None)
        for n, d in kept.items():
            put(HOME + n, d)
        back = all(get(HOME + n) == d for n, d in kept.items())
        check("the user's files back as they were", back, True)
        f = ftp()
        top = [x.split("/")[-1] for x in f.nlst(HOME + "fonts")]
        f.quit()
        check("the test CVT files gone again", any(x.endswith(".cvt") for x in top), False)
    print("d34u64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
