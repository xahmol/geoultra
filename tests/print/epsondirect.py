#!/usr/bin/env python3
"""GU Epson FX-80's own cost per band on the U64, without the spooler (a
measurement, docs/DESIGN.md "Printing"): spOn 0 (drivers not caught), the
driver loaded from drive E, then one routine on the C64 calls StartPrint,
PrintBuffer 94 times with an empty band (or every MODE band black) and
StopPrint, timed from the PC (start to the done flag). The printer set
up as in prnu64.py and put back; the user's HIBERNAT.BIN kept.
Usage: tests/print/epsondirect.py [empty|black]
"""
import ftplib
import io
import json
import os
import sys
import time
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feu64 import U64, APP_MAIN  # noqa: E402

HOME = "/USB0/GEOULTRA/"
OUTDIR = "/Usb0/GEOULTRA/test/"
CFG, SOFTIEC = "Printer Settings", "SoftIEC Drive Settings"
STUB, BAND, WORK, NAME, DONE = 0x5000, 0x5200, 0x5500, 0x50C0, 0x50FF


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "empty"
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    u = U64()

    def setting(key, value, cat=CFG):
        u._req("PUT", "%s/configs/%s/%s?value=%s" % (u.rest, urllib.parse.quote(cat), urllib.parse.quote(key),
                                                    urllib.parse.quote(str(value))))

    def config(cat):
        return json.loads(u._req("GET", "%s/configs/%s" % (u.rest, urllib.parse.quote(cat))))[cat]

    def run(code, timeout=3600):
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8, 0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8] + code
        code += [0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        u.write(STUB, code)
        u.write(DONE, [0])
        t0 = time.time()
        u.write(APP_MAIN, [STUB & 0xFF, STUB >> 8])
        while u.read(DONE, 1)[0] != 1:
            if time.time() - t0 > timeout:
                raise TimeoutError("not done")
            time.sleep(0.2)
        return time.time() - t0

    def r(reg, val):
        return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]

    def jsr(a):
        return [0x20, a & 0xFF, a >> 8]
    jt = {}
    names = [l.split("#")[0].split("=")[0].strip() for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
    for i, n in enumerate(x for x in names if x):
        jt[n] = 0xC100 + 3 * i
    before, soft = config(CFG), config(SOFTIEC)
    f = ftplib.FTP(u.ip, timeout=60)
    f.login()
    keep = io.BytesIO()
    try:
        f.retrbinary("RETR " + HOME + "HIBERNAT.BIN", keep.write)
        keep = keep.getvalue()
    except ftplib.error_perm:
        keep = None
    f.quit()
    try:
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        try:
            f.delete(HOME + "HIBERNAT.BIN")
        except ftplib.error_perm:
            pass
        f.quit()
        setting("IEC printer", "Enabled")
        setting("Bus ID", 4)
        setting("Output type", "PNG B&W")
        setting("Emulation", "Epson FX-80/JX-80")
        setting("Output file", OUTDIR + "direct")
        setting("IEC Drive", "Enabled", SOFTIEC)
        time.sleep(2)
        u.boot(os.path.join(ROOT, "build", "geoultra64.crt"))
        time.sleep(15)
        u.write(kern["spOn"], [0])                  # not spooled: straight to the driver
        u.write(NAME, b"GU Epson FX-80\0")
        run(r(0x0E, NAME) + [0xA9, 0, 0x85, 0x02] + jsr(jt["GetFile"]) + jsr(0x7900), 60)
        u.write(BAND, bytes([0xFF if mode == "black" else 0] * 640))
        loop = STUB + 8 + 3 + len(r(0x04, WORK)) + 3 + 5     # after StartPrint and the count
        body = (r(0x04, WORK) + jsr(0x7903) + [0xA9, 94, 0x8D, 0xF8, 0x02])
        code_loop_at = STUB + 8 + len(body)
        body += (r(0x02, BAND) + r(0x04, WORK) + r(0x06, 0) + jsr(0x7906)
                 + [0xCE, 0xF8, 0x02, 0xF0, 0x03, 0x4C, code_loop_at & 0xFF, code_loop_at >> 8]
                 + r(0x02, BAND) + r(0x04, WORK) + jsr(0x7909))
        if mode == "io":                            # InitForIO and DoneWithIO alone
            at = STUB + 8 + 5
            body = ([0xA9, 94, 0x8D, 0xF8, 0x02] + jsr(jt["InitForIO"]) + jsr(jt["DoneWithIO"])
                    + [0xCE, 0xF8, 0x02, 0xF0, 0x03, 0x4C, at & 0xFF, at >> 8])
        t = run(body)
        print("direct %s page: %.1f s, %.2f s a band" % (mode, t, t / 94), flush=True)
    finally:
        for k, v in before.items():
            if k in ("IEC printer", "Bus ID", "Output type", "Emulation", "Output file"):
                setting(k, v)
        setting("IEC Drive", soft["IEC Drive"], SOFTIEC)
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        for n in f.nlst(OUTDIR):
            if "direct-" in n:
                f.delete(OUTDIR + n.split("/")[-1])
        if keep is not None:
            f.storbinary("STOR " + HOME + "HIBERNAT.BIN", io.BytesIO(keep))
        f.quit()


if __name__ == "__main__":
    main()
