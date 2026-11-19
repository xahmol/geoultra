#!/usr/bin/env python3
"""The system fonts and the cold start's settings keys on the U64
(docs/DESIGN.md "System font folder"; mount.s modules 121-122,
sysdrive.s module 123): a FONTS.DNP with "F Roma" (a copy of Roma from
an applications disk, GEOS_APPS_DISK, the user's own) put into GEOULTRA,
SETTINGS.INI given "fastbus=on" and "diskfonts=hide" for the test; after
a reboot: fontsOn $C0 (loaded, drive fonts hidden), guPrnFast ($C0FC)
$80, and FindFile finds "F Roma" on track 238 (loaded, relocated,
searched). The user's SETTINGS.INI and HIBERNAT.BIN are put back and the
test's FONTS.DNP taken away (the user's own kept when there was one).
Usage: tests/fonts/fu64.py [build/geoultra64.crt]
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

HOME = "/USB0/GEOULTRA/"
APPS = os.environ.get("GEOS_APPS_DISK", os.path.expanduser("~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
STUB, NAME, RES, DONE = 0x5000, 0x50C0, 0x50E0, 0x50FF


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
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

    def run(code, timeout=60):
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8, 0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8] + code
        code += [0x8E, RES & 0xFF, RES >> 8, 0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        u.write(STUB, code)
        u.write(DONE, [0])
        u.write(APP_MAIN, [STUB & 0xFF, STUB >> 8])
        end = time.time() + timeout
        while u.read(DONE, 1)[0] != 1:
            if time.time() > end:
                raise TimeoutError("the call did not return")
            time.sleep(0.2)
        return u.read(RES, 1)[0]

    out = os.path.join(ROOT, "build", "harness", "fonts")
    os.makedirs(out, exist_ok=True)
    img = os.path.join(out, "FU64FONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    gd = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]
    subprocess.run(gd + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(gd + ["add", img, APPS + ":Roma"], check=True, capture_output=True)
    subprocess.run(gd + ["rename", img, "Roma", "F Roma"], check=True, capture_output=True)
    keep = {n: get(HOME + n) for n in ("SETTINGS.INI", "HIBERNAT.BIN", "FONTS.DNP")}
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(HOME + "FONTS.DNP", open(img, "rb").read())
        ini = (keep["SETTINGS.INI"] or b"").rstrip(b"\r\n") + b"\r\n[print]\r\nfastbus=on\r\ndiskfonts=hide\r\n"
        put(HOME + "SETTINGS.INI", ini)
        u.boot(crt)
        time.sleep(20)
        f_on = u.read(kern["fontsOn"], 1)[0]
        fast = u.read(0xC0FC, 1)[0]
        check("fontsOn: loaded and the drive fonts hidden ($C0)", f_on == 0xC0, hex(f_on))
        check("guPrnFast ($C0FC): fast bus timing ($80)", fast == 0x80, hex(fast))
        u.write(NAME, b"F Roma\0")
        jt_findfile = 0xC100 + 3 * [l.split("#")[0].split("=")[0].strip() for l in
                                    open(os.path.join(ROOT, "src", "kernal", "jumptab.txt")) if
                                    l.split("#")[0].split("=")[0].strip()].index("FindFile")
        x = run([0xA9, NAME & 0xFF, 0x85, 0x0E, 0xA9, NAME >> 8, 0x85, 0x0F, 0x20, jt_findfile & 0xFF,
                 jt_findfile >> 8])
        track = u.read(0x8401, 1)[0]
        check("FindFile \"F Roma\": found in the system fonts (track 238-245)", x == 0 and 238 <= track <= 245,
              "X=%02X track %d" % (x, track))
    finally:
        for n, d in keep.items():
            put(HOME + n, d)
        check("the user's SETTINGS.INI, HIBERNAT.BIN and FONTS.DNP back as they were",
              all(get(HOME + n) == d for n, d in keep.items()))
    print("fu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
