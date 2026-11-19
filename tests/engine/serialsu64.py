#!/usr/bin/env python3
"""[serials] at the cold start on the U64 (src/kernal/serials.s, mount.s
module 122; docs/design/DESIGN.md "Serial number", step S1): a SETTINGS.INI
for the test lists the desktop's own class ("GU Desktop", any case)
with 4321; after the boot, GetSerialNumber called from the desktop
(MainLoop, through appMain as tests/engine/feu64.py does) gives 4321,
and the running application's class is the desktop's. The user's
SETTINGS.INI and HIBERNAT.BIN are set aside and put back.
Usage: tests/engine/serialsu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64, STUB, RES, DONE, APP_MAIN  # noqa: E402

HOME = "/USB0/GEOULTRA/"
INI = b"[system]\r\n[serials]\r\ngu desktop=4321\r\n"
GET_SERIAL = 0xC196
KEEP = ("SETTINGS.INI", "HIBERNAT.BIN")


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    k = labels()
    u = U64()
    ok = True

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

    kept = {n: get(HOME + n) for n in KEEP}
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "SETTINGS.INI", INI)
        u.boot(crt)
        time.sleep(35)
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8, 0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8,
                0x20, GET_SERIAL & 0xFF, GET_SERIAL >> 8,
                0xA5, 0x02, 0x8D, RES & 0xFF, RES >> 8, 0xA5, 0x03, 0x8D, (RES + 1) & 0xFF, RES >> 8,
                0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        u.write(STUB, code)
        u.write(DONE, [0])
        u.write(APP_MAIN, [STUB & 0xFF, STUB >> 8])
        end = time.time() + 30
        while u.read(DONE, 1)[0] != 1 and time.time() < end:
            time.sleep(0.3)
        r = u.read(RES, 2)
        name = bytes(u.read(k["taskName"], 13)).split(b"\0")[0]
        check("the running application: the desktop", name.rstrip(), b"GU Desktop")
        check("GetSerialNumber: [serials]' 4321 (read at the cold start)", "%04X" % (r[0] | r[1] << 8), "4321")
    finally:
        for n, d in kept.items():
            put(HOME + n, d)
        back = all(get(HOME + n) == d for n, d in kept.items())
        check("the user's files back as they were", back, True)
        u.boot(crt)                                     # (the user's session again)
    print("serialsu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
