#!/usr/bin/env python3
"""geoLaser's PostScript picked up on the U64 (src/desktop/pickup.s;
docs/design/DESIGN.md "Printing", the user's decisions of 2026-11-19): drive B a
test D81 (GEOULTRA/test/pickup.d81) with a CBM SEQ file "PS.TEST" as
geoLaser writes one (made with c1541; its bytes a PostScript-like text);
at the desktop's start it is copied to GEOULTRA/print/TEST.ps (the same
bytes) and deleted from the image (read back over FTP, listed with
c1541), and a note says so. The test image and file are deleted again;
the user's MOUNTS.INI, SETTINGS.INI, RECENT.INI, HIBERNAT.BIN,
FONTS.DNP and gush_history put back as they were. Screen:
build/harness/print/pickupu64.png.
Usage: tests/print/pickupu64.py [build/geoultra64.crt]
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
IMAGE = HOME + "test/pickup.d81"
PS = HOME + "print/TEST.ps"
MOUNTS = ("[drives]\r\nA=/USB0/GEOULTRA/test/GEOS64.D81\r\nB=" + IMAGE + "\r\n").encode()
OUT = os.path.join(ROOT, "build", "harness", "print")
C1541 = localcfg.C1541
KEEP = ("MOUNTS.INI", "SETTINGS.INI", "RECENT.INI", "HIBERNAT.BIN", "FONTS.DNP", "gush_history")


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
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

    body = b"%!PS-Adobe-3.0\n%%Title: a geoLaser test\n" + b"".join(
        b"%d %d moveto (line %d) show\n" % (72, 700 - i * 12, i) for i in range(200)) + b"showpage\n"
    local = os.path.join(OUT, "pickup.d81")
    seq = os.path.join(OUT, "pickup-ps.bin")
    open(seq, "wb").write(body)
    if os.path.exists(local):
        os.remove(local)
    subprocess.run([C1541, "-format", "pickup,pk", "d81", local, "-write", seq, "ps.test,s"],
                   check=True, capture_output=True)
    kept = {n: get(HOME + n) for n in KEEP}
    try:
        put(HOME + "HIBERNAT.BIN", None)
        put(PS, None)
        put(IMAGE, open(local, "rb").read())
        put(HOME + "MOUNTS.INI", MOUNTS)
        u.boot(crt)
        time.sleep(40)
        apprun.render(u.read(0xA000, 0x1F40), u.read(0x8C00, 0x3E8), os.path.join(OUT, "pickupu64.png"))
        got = get(PS)
        check("GEOULTRA/print/TEST.ps: the file's bytes", (len(got or b""), got == body), (len(body), True))
        u.boot(crt)                                     # (written back: the image read again)
        time.sleep(25)
        img = get(IMAGE)
        back = os.path.join(OUT, "pickup-back.d81")
        open(back, "wb").write(img)
        r = subprocess.run([C1541, "-attach", back, "-list"], capture_output=True, text=True)
        check("deleted from the image", "ps.test" in r.stdout.lower(), False)
    finally:
        put(PS, None)
        put(IMAGE, None)
        for n, d in kept.items():
            put(HOME + n, d)
        back_ok = all(get(HOME + n) == d for n, d in kept.items())
        check("the user's files back as they were", back_ok, True)
    print("pickupu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
