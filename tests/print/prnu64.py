#!/usr/bin/env python3
"""GeoUltra's printer drivers on the U64 with the Ultimate's own IEC
printer, and GU PDF A4 into GEOULTRA/print (docs/DESIGN.md "Printing";
the PDF read back with mutool and taken away again): a test page through GU Epson FX-80
(the printer's Epson emulation, colour PNG) and GU Commodore MPS (its
Commodore emulation, black and white PNG), each loaded from drive E and
printed from the desktop through the spooler (recorded a band at a time,
played from MainLoop), the PNGs into /USB0/GEOULTRA/test. The page: a
frame, an inch grid, a circle (round when both directions are right),
text, and on the Epson page the 16 C64 colours as bars. Checks: the
calls' results, a PNG per page, and the Epson page's circle measured
(as wide as high, 8" across). The Ultimate's printer settings, the
user's SETTINGS.INI and HIBERNAT.BIN are kept and put back (a reboot at
the end resumes the user's session); the PNGs are left for a look.
Usage: tests/print/prnu64.py [build/geoultra64.crt]
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
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

HOME = "/USB0/GEOULTRA/"
OUTDIR = "/Usb0/GEOULTRA/test/"
CFG = "Printer Settings"
SOFTIEC = "SoftIEC Drive Settings"     # (3.15a: its change reconfigures the bus)
STUB, BAND, COLR, WORK, NAME, RES, DONE = 0x5000, 0x5200, 0x5480, 0x5500, 0x50C0, 0x50E0, 0x50FF
FONT = os.path.join(ROOT, "tools", "fonts", "src", "texgyre", "texgyreheros-regular.otf")


def page(width, rows, title, colours):
    """The test page as 1-bit rows (PIL, 1 = ink) and per band 80 colour
    bytes (None: black only)."""
    img = Image.new("1", (width, rows * 8), 0)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, width - 1, rows * 8 - 1], outline=1, width=2)
    for x in range(80, width, 80):                      # an inch grid (80 dpi)
        for y in range(0, rows * 8, 4):
            d.point((x, y), 1)
    for y in range(80, rows * 8, 80):
        for x in range(0, width, 4):
            d.point((x, y), 1)
    r = 200
    cx, cy = width // 2 - 20, 370                     # (off the grid lines)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=1, width=3)
    font = ImageFont.truetype(FONT, 28)
    d.text((24, 20), title, font=font, fill=1)
    d.text((24, 600), "GeoUltra printer test", font=ImageFont.truetype(FONT, 20), fill=1)
    cols = None
    if colours:
        cols = [bytes([0x01] * 80) for _ in range(rows)]
        for band in range(rows - 8, rows - 3):           # 16 bars of 5 cards
            cols[band] = bytes([(c // 5) << 4 | 0x01 for c in range(80)])
            for y in range(band * 8, band * 8 + 8):
                for x in range(0, 640):
                    img.putpixel((x, y), 1)
    return img, cols


def cards(img, band):
    """Band (8 rows) of IMG as 640 bytes of 80 cards (narrower: padded)."""
    out = bytearray(640)
    for c in range(img.width // 8):
        for r in range(8):
            b = 0
            for k in range(8):
                b = b << 1 | (1 if img.getpixel((c * 8 + k, band * 8 + r)) else 0)
            out[c * 8 + r] = b
    return bytes(out)


def main():
    crt = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "geoultra64.crt")
    u = U64()
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + str(detail)))

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

    def listing(prefix):
        f = ftp()
        try:
            return sorted(n.split("/")[-1] for n in f.nlst(OUTDIR) if n.split("/")[-1].startswith(prefix))
        finally:
            f.quit()

    def setting(key, value, cat=CFG):
        u._req("PUT", "%s/configs/%s/%s?value=%s" % (u.rest, urllib.parse.quote(cat), urllib.parse.quote(key),
                                                    urllib.parse.quote(str(value))))

    def config(cat):
        return json.loads(u._req("GET", "%s/configs/%s" % (u.rest, urllib.parse.quote(cat))))[cat]

    def bus(on):
        """The printer works inside the Ultimate's software IEC (its manual:
        "IEC Drive and Printer"): with firmware 3.15a only while the SoftIEC
        drive is on (found 2026-11-16: off, the C64 saw a device but no page
        was ever written). On for the test, then as the user had it."""
        setting("IEC Drive", "Enabled" if on else soft["IEC Drive"], SOFTIEC)
        time.sleep(2)

    def clear():
        """Old test pages away (the firmware never overwrites a PNG: the
        page would be lost)."""
        f = ftp()
        for n in f.nlst(OUTDIR):
            n = n.split("/")[-1]
            if n.startswith("prn-") and n.endswith(".png"):
                f.delete(OUTDIR + n)
        f.quit()

    def run(code, timeout=60):
        """CODE once from MainLoop (appMain), then the done flag; X at RES."""
        code = [0xA9, 0x00, 0x8D, APP_MAIN & 0xFF, APP_MAIN >> 8,
                0x8D, (APP_MAIN + 1) & 0xFF, APP_MAIN >> 8] + code
        code += [0x8E, RES & 0xFF, RES >> 8, 0xA9, 0x01, 0x8D, DONE & 0xFF, DONE >> 8, 0x60]
        assert STUB + len(code) <= NAME
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

    def job(driver, img, cols, prefix):
        before = set(listing(prefix))
        u.write(NAME, driver + b"\0")
        x = run(r(0x0E, NAME) + [0xA9, 0, 0x85, 0x02] + jsr(jt["GetFile"]))
        check("%s: loaded from drive E" % driver.decode(), x == 0, "X=%02X" % x)
        run(jsr(0x7900))
        x = run(r(0x04, WORK) + jsr(0x7903))
        check("%s: StartPrint" % driver.decode(), x == 0, "X=%02X" % x)
        for band in range(img.height // 8):
            u.write(BAND, cards(img, band))
            if cols:
                u.write(COLR, cols[band])
            t1 = time.time()                    # (a full queue: the call waits for
            run(r(0x02, BAND) + r(0x04, WORK) + r(0x06, COLR if cols else 0) + jsr(0x7906),
                timeout=int(os.environ.get("PRNU64_BAND", "1200")))  # (minutes on the Epson)
            if time.time() - t1 > 20:
                print("  band %d: %ds (the queue full, played meanwhile)" % (band, time.time() - t1), flush=True)
        x = run(r(0x02, BAND) + r(0x04, WORK) + jsr(0x7909))
        check("%s: StopPrint" % driver.decode(), x == 0, "X=%02X" % x)
        end = time.time() + int(os.environ.get("PRNU64_WAIT", "900"))   # the spooler plays it
        t0 = time.time()
        while time.time() < end:
            new = sorted(set(listing(prefix)) - before)
            if new:
                time.sleep(5)
                break
            time.sleep(30)
            x2, a2, rr = u.fe(33, y=0)
            print("  %4ds: queue job %d of %d%s" % (time.time() - t0, a2, rr[0] & 0xFF,
                  ", paused" if rr[0] & 0x8000 else ""), flush=True)
        new = sorted(set(listing(prefix)) - before)
        check("%s: a PNG page from the Ultimate's printer" % driver.decode(), len(new) == 1, new)
        return new[0] if new else None

    def pdf_job():
        """GU PDF A4: a page into GEOULTRA/print on the Ultimate, read
        back (mutool), then taken away again."""
        f = ftp()
        try:
            old = set(f.nlst(HOME + "print"))
        except ftplib.error_perm:
            old = set()
        f.quit()
        img, _ = page(640, 94, "GU PDF A4 on the Ultimate", False)
        u.write(NAME, b"GU PDF A4\0")
        x = run(r(0x0E, NAME) + [0xA9, 0, 0x85, 0x02] + jsr(jt["GetFile"]))
        check("GU PDF A4: loaded from drive E", x == 0, "X=%02X" % x)
        run(jsr(0x7900))
        x = run(r(0x04, WORK) + jsr(0x7903))
        check("GU PDF A4: StartPrint", x == 0, "X=%02X" % x)
        for band in range(img.height // 8):
            u.write(BAND, cards(img, band))
            run(r(0x02, BAND) + r(0x04, WORK) + r(0x06, 0) + jsr(0x7906))
        x = run(r(0x02, BAND) + r(0x04, WORK) + jsr(0x7909))
        check("GU PDF A4: StopPrint", x == 0, "X=%02X" % x)
        new = []
        end = time.time() + 600                          # the spooler plays it
        while time.time() < end and not new:
            time.sleep(10)
            f = ftp()
            try:
                new = sorted(set(f.nlst(HOME + "print")) - old)
            except ftplib.error_perm:
                new = []
            f.quit()
        time.sleep(15)
        check("GU PDF A4: a PDF in GEOULTRA/print", len(new) == 1, new)
        if new:
            local = os.path.join(shots, "u64-" + new[0].split("/")[-1])
            data = get(new[0] if new[0].startswith("/") else HOME + "print/" + new[0])
            open(local, "wb").write(data or b"")
            import subprocess
            r2 = subprocess.run(["mutool", "info", local], capture_output=True)
            check("GU PDF A4: mutool reads it, one page, no repair",
                  r2.returncode == 0 and b"Pages: 1" in r2.stdout and b"repair" not in r2.stderr,
                  r2.stderr[:200])
            print("  " + local)
            put(new[0] if new[0].startswith("/") else HOME + "print/" + new[0], None)

    before = config(CFG)
    soft = config(SOFTIEC)
    keep = {n: get(HOME + n) for n in ("SETTINGS.INI", "HIBERNAT.BIN")}
    shots = os.path.join(ROOT, "build", "harness", "print")
    os.makedirs(shots, exist_ok=True)
    try:
        put(HOME + "HIBERNAT.BIN", None)                 # a fresh start, not the user's session
        setting("IEC printer", "Enabled")
        setting("Bus ID", 4)
        setting("Output type", os.environ.get("PRNU64_EPSON_TYPE", "PNG COLOR"))
        setting("Emulation", "Epson FX-80/JX-80")
        setting("Output file", OUTDIR + "prn-epson")
        clear()
        bus(True)
        u.boot(crt)
        time.sleep(15)
        img, cols = page(640, 94, "GU Epson FX-80 on the Ultimate", True)
        png = job(b"GU Epson FX-80", img, cols, "prn-epson")
        if png:
            local = os.path.join(shots, "u64-" + png)
            u.ftp_get(OUTDIR + png, local)
            im = Image.open(local).convert("L")
            print("  %s: %d x %d" % (png, im.width, im.height))
            # the circle's four extremes where 80 dpi both ways puts them: x
            # 32 + 3X (240 dpi, the printer's left offset), y 180 + round(2.7 Y)
            # (216 dpi, its 5-line top margin); ink within 6 pixels of each
            want = {"left": (32 + 3 * 100, 180 + 999), "right": (32 + 3 * 500, 180 + 999),
                    "top": (32 + 3 * 300, 180 + 459), "bottom": (32 + 3 * 300, 180 + 1539)}
            found = {}
            for side, (x, y) in want.items():
                found[side] = any(im.getpixel((x + dx, y + dy)) < 128
                                  for dx in range(-6, 7) for dy in range(-6, 7)
                                  if 0 <= x + dx < im.width and 0 <= y + dy < im.height)
            check("the circle's edges where exact 80 dpi puts them (round, 5\" across)",
                  all(found.values()), found)
        if os.environ.get("PRNU64_ONLY") == "epson":
            return
        setting("Output type", "PNG B&W")
        setting("Emulation", "Commodore MPS")
        setting("Output file", OUTDIR + "prn-mps")
        img, _ = page(480, 90, "GU Commodore MPS on the Ultimate", False)
        png = job(b"GU Commodore MPS", img, None, "prn-mps")
        if png:
            u.ftp_get(OUTDIR + png, os.path.join(shots, "u64-" + png))
        pdf_job()
    finally:
        for key, value in before.items():
            try:
                setting(key, value)
            except OSError:
                pass
        for n, d in keep.items():
            put(HOME + n, d)
        check("the user's files back as they were", all(get(HOME + n) == d for n, d in keep.items()), True)
        try:
            bus(False)
        except OSError:
            pass
        now = config(CFG)
        check("the Ultimate's printer settings back", now == before, now)
        check("its SoftIEC settings back", config(SOFTIEC) == soft, config(SOFTIEC))
        u._req("PUT", u.rest + "/machine:reboot")       # the user's session resumes
    print("prnu64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
