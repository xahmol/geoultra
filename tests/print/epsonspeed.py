#!/usr/bin/env python3
"""How fast GU Epson FX-80 prints on the U64's printer (a measurement,
not a pass/fail test; docs/design/DESIGN.md "Printing"): three pages recorded
through the spooler and timed while they play (FE_SPOOL's percentage
every 5 s; the queue paused while a page is recorded, timed from the
resume): an empty page (only paper feed: the cost per band without
ink), a page of text lines (as geoWrite prints a letter), and a page all
black (the most bytes). The bytes each page sends are counted from the
same bands with tools-free arithmetic (the driver's passes: three per
band, each trimmed after its last ink). The printer is set up as in
prnu64.py (PNG B&W) and put back; the PNGs are deleted again.
Usage: tests/print/epsonspeed.py [build/geoultra64.crt]
"""
import ftplib
import json
import os
import sys
import time
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
sys.path.insert(0, os.path.join(ROOT, "tests", "print"))
from feu64 import U64, APP_MAIN  # noqa: E402
from prnu64 import cards, FONT  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

HOME = "/USB0/GEOULTRA/"
OUTDIR = "/Usb0/GEOULTRA/test/"
CFG, SOFTIEC = "Printer Settings", "SoftIEC Drive Settings"
STUB, BAND, WORK, NAME, RES, DONE = 0x5000, 0x5200, 0x5500, 0x50C0, 0x50E0, 0x50FF
ROWS = 94


def pages():
    blank = Image.new("1", (640, ROWS * 8), 0)
    text = Image.new("1", (640, ROWS * 8), 0)
    d = ImageDraw.Draw(text)
    f = ImageFont.truetype(FONT, 13)
    words = ("The quick brown fox jumps over the lazy dog while GeoUltra prints "
             "this page on the Ultimate's virtual printer. ") * 3
    for y in range(40, ROWS * 8 - 40, 16):
        d.text((80, y), words[(y // 16) % 20:][:78], font=f, fill=1)
    black = Image.new("1", (640, ROWS * 8), 1)
    return [("empty", blank), ("text", text), ("black", black)]


def sent(img):
    """Bytes the driver sends for img: per band three passes, each up to
    its last column with ink (ESC * 4 n: 5 bytes and n), ESC J feeds."""
    total = 0
    for band in range(img.height // 8):
        rows = [[img.getpixel((x, band * 8 + r)) for x in range(640)] for r in range(8)]
        for part in (rows[0:3], rows[3:6], rows[6:8]):
            last = max((x for x in range(640) if any(r[x] for r in part)), default=-1)
            if last >= 0:
                total += 5 + last + 1 + 2
        total += 3
    return total


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    u = U64()

    def ftp():
        f = ftplib.FTP(u.ip, timeout=60)
        f.login()
        return f

    def listing():
        f = ftp()
        try:
            return set(n.split("/")[-1] for n in f.nlst(OUTDIR) if "speed-" in n)
        finally:
            f.quit()

    def setting(key, value, cat=CFG):
        u._req("PUT", "%s/configs/%s/%s?value=%s" % (u.rest, urllib.parse.quote(cat), urllib.parse.quote(key),
                                                    urllib.parse.quote(str(value))))

    def config(cat):
        return json.loads(u._req("GET", "%s/configs/%s" % (u.rest, urllib.parse.quote(cat))))[cat]

    def run(code, timeout=600):
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8,
                0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8] + code
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

    def r(reg, val):
        return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]

    def jsr(a):
        return [0x20, a & 0xFF, a >> 8]

    jt = {}
    names = [l.split("#")[0].split("=")[0].strip() for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
    for i, n in enumerate(x for x in names if x):
        jt[n] = 0xC100 + 3 * i
    before, soft = config(CFG), config(SOFTIEC)
    f = ftp()
    keep_hib = None
    try:
        import io
        b = io.BytesIO()
        f.retrbinary("RETR " + HOME + "HIBERNAT.BIN", b.write)
        keep_hib = b.getvalue()
    except ftplib.error_perm:
        pass
    f.quit()
    try:
        f = ftp()
        try:
            f.delete(HOME + "HIBERNAT.BIN")
        except ftplib.error_perm:
            pass
        f.quit()
        setting("IEC printer", "Enabled")
        setting("Bus ID", 4)
        setting("Output type", "PNG B&W")
        setting("Emulation", "Epson FX-80/JX-80")
        setting("Output file", OUTDIR + "speed")
        setting("IEC Drive", "Enabled", SOFTIEC)
        time.sleep(2)
        u.boot(crt)
        time.sleep(15)
        u.write(NAME, b"GU Epson FX-80\0")
        x = run(r(0x0E, NAME) + [0xA9, 0, 0x85, 0x02] + jsr(jt["GetFile"]), timeout=60)
        print("GetFile X=%02X" % x, flush=True)
        run(jsr(0x7900))
        for name, img in pages():
            have = listing()
            u.fe(33, y=1)                               # paused while recording, so
            run(r(0x04, WORK) + jsr(0x7903))            # the time is the playback's
            for band in range(ROWS):
                u.write(BAND, cards(img, band))
                run(r(0x02, BAND) + r(0x04, WORK) + r(0x06, 0) + jsr(0x7906))
            run(r(0x02, BAND) + r(0x04, WORK) + jsr(0x7909))
            t0 = time.time()
            u.fe(33, y=2)
            marks = []
            while time.time() - t0 < 3600:                # until the queue is empty
                x, a, rr = u.fe(33, y=0)                    # (an empty page writes no
                pct = rr[1] >> 8                            # PNG: the firmware skips a
                marks.append((round(time.time() - t0), pct))    # clean page)
                if a == 0:
                    break
                time.sleep(5)
            t = time.time() - t0
            n = sent(img)
            print("%-5s page: %5.0f s, %6d bytes sent, %5.0f bytes/s; progress %s" % (
                name, t, n, n / t if t else 0, marks[::6]), flush=True)
    finally:
        for k, v in before.items():
            if k in ("IEC printer", "Bus ID", "Output type", "Emulation", "Output file"):
                setting(k, v)
        setting("IEC Drive", soft["IEC Drive"], SOFTIEC)
        f = ftp()
        for n in listing():
            try:
                f.delete(OUTDIR + n)
            except ftplib.error_perm:
                pass
        if keep_hib is not None:
            import io
            f.storbinary("STOR " + HOME + "HIBERNAT.BIN", io.BytesIO(keep_hib))
        f.quit()


if __name__ == "__main__":
    main()
