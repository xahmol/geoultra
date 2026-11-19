#!/usr/bin/env python3
"""A restart that keeps the session, on the U64 (docs/DESIGN.md "System
font folder"; enginesys.s FE_REBOOT with Y = 1, hibernate.s Resumed,
mount.s module 122 Keep): GeoUltra started without FONTS.DNP (fontsOn
0), a marker put into RAM, then a FONTS.DNP with "F Roma" (Roma from
GEOS_APPS_DISK, the user's own, renamed) put into GEOULTRA and FE_REBOOT
called with Y = 1 from appMain. Checks: after the reboot the session is
back (the marker, the call returned X = 0 into the same routine),
fontsOn is this boot's ($80: the new FONTS.DNP, not the saved
session's 0), and FindFile finds "F Roma". The user's SETTINGS.INI,
HIBERNAT.BIN and FONTS.DNP are put back.
Usage: tests/fonts/restartu64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64, APP_MAIN  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

HOME = "/USB0/GEOULTRA/"
APPS = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")
STUB, NAME, RES, DONE, MARK = 0x5000, 0x50C0, 0x50E0, 0x50FF, 0x5F00


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    fe = kern["ExtTable"] + 30
    u = U64()
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + str(detail)), flush=True)

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

    def start(code):
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8, 0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8] + code
        code += [0x8E, RES & 0xFF, RES >> 8, 0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        u.write(STUB, code)
        u.write(DONE, [0])
        u.write(APP_MAIN, [STUB & 0xFF, STUB >> 8])

    def wait_done(timeout=60):
        end = time.time() + timeout
        while time.time() < end:
            try:
                if u.read(DONE, 1)[0] == 1:
                    return u.read(RES, 1)[0]
            except Exception:
                pass                                        # (the U64 rebooting)
            time.sleep(1)
        return None

    out = os.path.join(ROOT, "build", "harness", "fonts")
    os.makedirs(out, exist_ok=True)
    img = os.path.join(out, "RSFONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    gd = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]
    subprocess.run(gd + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(gd + ["add", img, APPS + ":Roma"], check=True, capture_output=True)
    subprocess.run(gd + ["rename", img, "Roma", "F Roma"], check=True, capture_output=True)
    keep = {n: get(HOME + n) for n in ("SETTINGS.INI", "HIBERNAT.BIN", "FONTS.DNP")}
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "FONTS.DNP", None)
        u.boot(crt)
        time.sleep(20)
        check("started without FONTS.DNP: fontsOn 0", u.read(kern["fontsOn"], 1)[0] & 0x80 == 0)
        u.write(MARK, b"SESSION MARK")
        put(HOME + "FONTS.DNP", open(img, "rb").read())
        start([0xA9, 28, 0xA0, 1, 0x20, fe & 0xFF, fe >> 8])     # FE_REBOOT, Y = 1
        x = wait_done(120)
        time.sleep(10)
        check("the call came back after the restart: X = 0", x == 0, x)
        check("the session resumed (the marker in RAM)", bytes(u.read(MARK, 12)) == b"SESSION MARK")
        check("fontsOn: this boot's ($80, the new FONTS.DNP)", u.read(kern["fontsOn"], 1)[0] & 0x80 == 0x80,
              hex(u.read(kern["fontsOn"], 1)[0]))
        u.write(NAME, b"F Roma\0")
        jtn = [l.split("#")[0].split("=")[0].strip() for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
        ff = 0xC100 + 3 * [n for n in jtn if n].index("FindFile")
        start([0xA9, NAME & 0xFF, 0x85, 0x0E, 0xA9, NAME >> 8, 0x85, 0x0F, 0x20, ff & 0xFF, ff >> 8])
        x = wait_done(30)
        check("FindFile \"F Roma\": found (track 238-245)", x == 0 and 238 <= u.read(0x8401, 1)[0] <= 245,
              (x, u.read(0x8401, 1)[0]))
    finally:
        for n, d in keep.items():
            put(HOME + n, d)
        check("the user's SETTINGS.INI, HIBERNAT.BIN and FONTS.DNP back as they were",
              all(get(HOME + n) == d for n, d in keep.items()))
    print("restartu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
