#!/usr/bin/env python3
"""Auto-exec files at the cold start on the U64 (the user's decisions of
2026-11-14; src/kernal/autoexec.s, modules 92-93; docs/design/DESIGN.md).

Two tiny AUTO_EXEC files (GUAUTO1, GUAUTO2, made here: each appends its
number and firstBoot to the unused bytes of GeoUltra's information block
at $C0A0, then ends with EnterDeskTop) are copied onto drive A's test
copy through GeoUltra (their CVTs in a scratch folder, FE_COPY).
SETTINGS.INI gets [system] autoexec=/a/GUAUTO2 and /a/GUAUTO1 (the
other way round from the directory), a third line naming a file that is
not there; a fresh cold start (no HIBERNAT.BIN) then shows both run in
the list's order, with firstBoot FALSE, the missing one skipped,
firstBoot TRUE afterwards and the desktop running. The user's
SETTINGS.INI and HIBERNAT.BIN are set aside first and put back; the two
files are deleted from drive A again.
Usage: tests/engine/autou64.py [build/geoultra64.crt]
"""
import ftplib
import io
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feu64 import U64  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "engine")
GEOSAPP = localcfg.GEOSAPP
HOME = "/USB0/GEOULTRA"
CVTS = HOME + "/test/guauto"
FE_COPY, FE_DELETE = 5, 7
MARK = 0xC0A0                   # count, the numbers (4), firstBoot (4)
FIRST_BOOT = 0x88C5


def program(n):
    """LDX $C0A0; LDA #n; STA $C0A1,X; LDA firstBoot; STA $C0A5,X;
    INC $C0A0; JMP EnterDeskTop."""
    return bytes([0xAE, 0xA0, 0xC0, 0xA9, n, 0x9D, 0xA1, 0xC0, 0xAD, FIRST_BOOT & 0xFF, FIRST_BOOT >> 8,
                  0x9D, 0xA5, 0xC0, 0xEE, 0xA0, 0xC0, 0x4C, 0x2C, 0xC2])


def make_cvt(n):
    os.makedirs(OUT, exist_ok=True)
    spec = os.path.join(OUT, "guauto%d.toml" % n)
    open(spec, "w").write('[file]\nname = "GUAUTO%d"\ntype = "AUTO_EXEC"\nload = 0x0400\n'
                          'author = "GeoUltra test"\ninfo = "An auto-exec test."\n' % n)
    binp = os.path.join(OUT, "guauto%d.bin" % n)
    open(binp, "wb").write(program(n))
    cvt = os.path.join(OUT, "guauto%d.cvt" % n)
    subprocess.run([sys.executable, GEOSAPP, spec, binp, cvt], check=True, capture_output=True)
    return cvt


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    u = U64()
    u.require_test_drives("A")                  # (it writes onto drive A)
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

    def get(path):
        f = ftp()
        b = io.BytesIO()
        try:
            f.retrbinary("RETR " + path, b.write)
        except ftplib.error_perm:
            f.quit()
            return None
        f.quit()
        return b.getvalue()

    def put(path, data):
        f = ftp()
        f.storbinary("STOR " + path, io.BytesIO(data))
        f.quit()

    def delete(path):
        f = ftp()
        try:
            f.delete(path)
        except ftplib.error_perm:
            pass
        f.quit()

    ini = get(HOME + "/SETTINGS.INI")
    hib = get(HOME + "/HIBERNAT.BIN")
    delete(HOME + "/HIBERNAT.BIN")
    f = ftp()
    try:
        f.mkd(CVTS)
    except ftplib.error_perm:
        pass
    f.quit()
    for n in (1, 2):
        put(CVTS + "/guauto%d.cvt" % n, open(make_cvt(n), "rb").read())
    try:
        u.boot(crt)
        time.sleep(18)
        for n in (1, 2):
            u.fe(FE_DELETE, s0="/a/GUAUTO%d" % n)
            x = u.fe(FE_COPY, s0="/usb0/geoultra/test/guauto/guauto%d.cvt" % n, s1="/a/GUAUTO%d" % n,
                     timeout=120)[0]
            check("GUAUTO%d copied onto drive A" % n, x, 0)
        time.sleep(8)                                   # (written back)
        text = ini.replace(b"[system]\r\n", b"[system]\r\nautoexec=/a/GUAUTO2\r\n"
                           b"autoexec=/a/NOT THERE\r\nautoexec=/a/GUAUTO1\r\n")
        put(HOME + "/SETTINGS.INI", text)
        delete(HOME + "/HIBERNAT.BIN")
        u.boot(crt)
        time.sleep(25)
        m = u.read(MARK, 9)
        check("both run, in the list's order (the missing one skipped)", (m[0], list(m[1:3])), (2, [2, 1]))
        check("firstBoot FALSE while they ran", list(m[5:7]), [0, 0])
        check("firstBoot TRUE afterwards", u.read(FIRST_BOOT, 1)[0], 0xFF)
    finally:
        put(HOME + "/SETTINGS.INI", ini)
        try:
            u.boot(crt)
            time.sleep(18)
            for n in (1, 2):
                u.fe(FE_DELETE, s0="/a/GUAUTO%d" % n)
            time.sleep(8)
        except Exception:
            pass
        delete(HOME + "/HIBERNAT.BIN")
        if hib is not None:
            put(HOME + "/HIBERNAT.BIN", hib)
        for n in (1, 2):
            delete(CVTS + "/guauto%d.cvt" % n)
        f = ftp()
        try:
            f.rmd(CVTS)
        except ftplib.error_perm:
            pass
        f.quit()
        check("SETTINGS.INI as it was", get(HOME + "/SETTINGS.INI") == ini, True)
    print("autou64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
