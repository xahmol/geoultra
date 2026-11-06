#!/usr/bin/env python3
"""GeoUltra's desktop on the U64 (docs/DESKTOP.md, D1): SETTINGS.INI
[system] desktop=geoultra makes EnterDeskTop start it from drive E. The
test stick has no SETTINGS.INI (it is made and deleted again; an
existing one stops the test). Boots the cartridge, calls EnterDeskTop
(appMain), and checks that the desktop runs (its code at $0400, the
path and the entries of the start folder in its memory).
Usage: tests/desktop/du64.py [build/geoultra64.crt]
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


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
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
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))
    ftp = ftplib.FTP(u.ip)
    ftp.login()
    if "SETTINGS.INI" in [n.split("/")[-1] for n in ftp.nlst("/USB0/GEOULTRA")]:
        sys.exit("du64.py: the stick has a SETTINGS.INI; not touched")
    ftp.storbinary("STOR " + SETTINGS, io.BytesIO(b"[system]\r\ndesktop=geoultra\r\n"))
    try:
        u.boot(crt)
        u.write(0x849B, b"\x2C\xC2")                    # appMain = EnterDeskTop
        time.sleep(15)
        code = open(os.path.join(ROOT, "build", "desktop", "desktop.bin"), "rb").read()[:32]
        check("EnterDeskTop started GeoUltra's desktop", bytes(u.read(0x0400, 32)), code)
        path = bytes(u.read(k["path"], 16)).split(b"\0")[0].decode("latin1")
        check("its path line", path.startswith("/"), True)
        check("entries listed", u.read(k["count"], 1)[0] > 0, True)
    finally:
        ftp.delete(SETTINGS)
        ftp.quit()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
