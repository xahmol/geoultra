#!/usr/bin/env python3
"""GU Epson FX-80 (src/drivers/epson.s) in VICE, its bytes caught at the
C64 ROM's serial routines it calls (LISTEN, SECOND, CIOUT, UNLSN: each
stopped at and returned from as a printer would answer; VICE's own
printer does not answer on GeoUltra's cartridge here) and read back
(epsonstream.py): a page
of ten bands (two of the driver's five-band cycles) of pseudo-random
dots printed directly (spooling off), in black (r2 = 0) and in colour (a
random colour byte per card), and an ASCII page. Every GEOS dot must be
where docs/DESIGN.md "Printing" puts it: column X at 3X/240", row R at
round(R x 2.7)/216" (exactly 80 dpi both ways), and no other; colours as
the driver's inks (the levels and dither patterns below, the spec);
ASCII as text, CR as CR LF, SetNLQ as ESC E, StopPrint as FF. The black
page once more through the spooler (on in MainLoop), and once with the
driver only on drive E (GetFile's fallback): the same bytes. The driver
is written onto a copy of an applications disk (GEOS_APPS_DISK, the
user's own).
Usage: tests/print/ep1.py
"""
import os
import random
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness                                   # noqa: E402
import epsonstream                               # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "print")
APPS_DISK = os.environ.get("GEOS_APPS_DISK", os.path.expanduser(
    "~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
BANDS = 10
TEXT = b"Hello GeoUltra\rsecond line\r"

# The spec of the colours (docs/DESIGN.md "Printing"): per ink (K, C, M, Y,
# their ESC r codes 0, 2, 1, 4) the level of each C64 colour: 0 none,
# 1 a quarter, 2 half, 3 solid; the patterns of even and odd rows.
LEVEL = {0: [3, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 3, 2, 0, 0, 1],
         2: [0, 0, 0, 3, 2, 3, 3, 0, 0, 0, 0, 0, 0, 2, 2, 0],
         1: [0, 0, 3, 0, 3, 0, 3, 0, 2, 2, 2, 0, 0, 0, 1, 0],
         4: [0, 0, 3, 0, 0, 3, 0, 3, 3, 3, 1, 0, 0, 2, 0, 0]}
PAT_EVEN = [0x00, 0x88, 0xAA, 0xFF]
PAT_ODD = [0x00, 0x22, 0x55, 0xFF]

HOOK = r'''
import time
from vicemon import RESP_CHECKPOINT
v.mem_set(0x4E00, %(name)r + b"\0")
v.mem_set(0x4E80, %(text)r + b"\0")
v.mem_set(0x5000, %(data)r)
v.mem_set(0x6A00, %(colr)r)
v.mem_set(0x02F0, b"\0")
v.mem_set(%(spon)d, bytes([%(on)d]))
v.mem_set(0x033F, b"\x60")                  # rts: the ROM's routines skipped
v.mem_set(0x0340, open(%(call)r, "rb").read())
v.regs_set({"PC": 0x0340})
ROM = {0xFFB1: "L", 0xFF93: "S", 0xFFA8: "B", 0xFFAE: "U"}
for a in ROM:
    v.checkpoint(a, temporary=False)
out, bus = bytearray(), []
while True:
    v.events.clear()
    v.resume()
    try:
        v.wait_event(RESP_CHECKPOINT, 20)  # (the run, or the spooler, done: none)
    except Exception:
        break
    r = v.regs_get()
    kind = ROM.get(r["PC"])
    if kind == "B":
        out.append(r["A"])
    elif kind:
        bus.append("%%s%%02X" %% (kind, r["A"]))
    v.regs_set({"PC": 0x033F})
v.ping()
open(%(raw)r, "wb").write(out)
print("EP1 " + v.mem_get(0x2EF, 0x2F2).hex() + " " + " ".join(bus[:6]))
'''


def expected(data, colr, colour):
    """{ink: set of (x, y)}: where every dot of the page belongs."""
    want = {}
    for band in range(BANDS):
        for c in range(80):
            cb = colr[band * 80 + c] if colour else 0x01
            for r in range(8):
                row = band * 8 + r
                y = (row * 27 + 5) // 10
                byte = data[band * 640 + c * 8 + r]
                for k in range(8):
                    on = byte & (0x80 >> k)
                    x = (c * 8 + k) * 3
                    if not colour:
                        if on:
                            want.setdefault(0, set()).add((x, y))
                        continue
                    shade = cb >> 4 if on else cb & 15
                    for ink, levels in LEVEL.items():
                        pat = (PAT_EVEN if r % 2 == 0 else PAT_ODD)[levels[shade]]
                        if pat & (0x80 >> k):
                            want.setdefault(ink, set()).add((x, y))
    return want


def label(name):
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        if p[2].lstrip(".") == name:
            return int(p[1], 16)
    raise KeyError(name)


def run(tag, colour, ascii_, data, colr, spooled=False, name=b"GU Epson FX-80"):
    call = os.path.join(OUT, "epcall-%s.bin" % tag)
    o = call[:-4] + ".o"
    jt = harness.jumptab()
    subprocess.run(["ca65", "-o", o, "-D", "SetDevice=$%04X" % jt["SetDevice"],
                    "-D", "OpenDisk=$%04X" % jt["OpenDisk"], "-D", "GetFile=$%04X" % jt["GetFile"],
                    "-D", "BANDS=%d" % BANDS, "-D", "COLSTEP=%d" % (80 if colour else 0),
                    "-D", "ASCII=%d" % ascii_, "-D", "SPOOLED=%d" % spooled,
                    "-D", "MainLoop=$%04X" % jt["MainLoop"], os.path.join(ROOT, "tests", "print", "epcall.s")],
                   check=True)
    subprocess.run(["ld65", "-t", "none", "-o", call, o], check=True)
    raw = os.path.join(OUT, "printer-%s-%s.raw" % (name.decode().split()[1].lower(), tag))
    if os.path.exists(raw):
        os.remove(raw)
    hook = os.path.join(OUT, "hook-ep1-%s.py" % tag)
    open(hook, "w").write(HOOK % {"text": TEXT, "data": data, "colr": colr, "call": call, "raw": raw,
                                 "spon": label("spOn"), "on": 0x80 if spooled else 0,
                                 "name": name})
    env = dict(os.environ, GEOS_APPS_DISK=os.path.join(OUT, "apps.d64"),
               PYTHONPATH=os.path.join(ROOT, "tools", "harness"),
               )
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "ep1-%s.png" % tag), "GEOWRITE",
                        "h:" + hook], env=env, capture_output=True, text=True, timeout=600)
    if r.returncode:
        print(r.stderr[-600:])
    line = next((l for l in r.stdout.splitlines() if l.startswith("EP1")), "EP1 - -")
    res = line.split()[1]
    print("  %s: bus %s" % (tag, " ".join(line.split()[2:])))
    stream = open(raw, "rb").read() if os.path.exists(raw) else b""
    return res, stream


def disk_with(driver):
    """A copy of the applications disk with build/printer/DRIVER.cvt on it
    (None: without, so GetFile finds the driver on drive E)."""
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "apps.d64")
    shutil.copyfile(APPS_DISK, disk)
    if driver is None:
        return
    subprocess.run(["make", "-s", "build/printer/%s.cvt" % driver], cwd=ROOT, check=True)
    subprocess.run([os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541"), disk, "-geoswrite",
                    os.path.join(ROOT, "build", "printer", driver + ".cvt")], check=True, capture_output=True)


def main():
    disk_with("epson")
    rnd = random.Random(80)
    data = bytes(rnd.getrandbits(8) for _ in range(BANDS * 640))
    colr = bytes(rnd.getrandbits(8) for _ in range(BANDS * 80))
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + detail))

    for tag, colour in (("black", False), ("colour", True)):
        res, stream = run(tag, colour, 0, data, colr)
        check("%s: driver loaded, StartPrint and StopPrint X = 0" % tag, res == "00aa0000", res)
        got = epsonstream.parse(stream)
        pages = got["pages"]
        check("%s: one page, ended by FF, nothing unexpected" % tag,
              len(pages) == 1 and stream.endswith(b"\x0c") and not got["unknown"],
              "%d pages, %d bytes, unknown %s" % (len(pages), len(stream), got["unknown"][:5]))
        want = expected(data, colr, colour)
        have = pages[0] if pages else {}
        for ink in sorted(set(want) | set(have)):
            w, h = want.get(ink, set()), have.get(ink, set())
            check("%s: ink %d, every dot at exactly 80 dpi (%d dots)" % (tag, ink, len(w)), w == h,
                  "%d missing (e.g. %s), %d extra (e.g. %s)" % (
                      len(w - h), sorted(w - h)[:3], len(h - w), sorted(h - w)[:3]))
        if tag == "black":
            direct = stream
    res, stream = run("spooled", False, 0, data, colr, spooled=True)
    check("spooled (played from MainLoop): the same bytes as printed directly (%d)" % len(direct),
          stream == direct and res == "00aa0000", "%s, %d bytes" % (res, len(stream)))
    disk_with(None)
    res, stream = run("frome", False, 0, data, colr)
    check("not on the current drive: loaded from drive E (FindFile's fallback), the same bytes",
          stream == direct and res == "00aa0000", "%s, %d bytes" % (res, len(stream)))
    disk_with("epson")
    res, stream = run("ascii", False, 1, data, colr)
    got = epsonstream.parse(stream)
    check("ascii: StartASCII and StopPrint X = 0", res == "00aa0000", res)
    check("ascii: the text, CR as CR LF, FF at the end",
          got["text"] == "Hello GeoUltra\r\nsecond line\r\n\f", repr(got["text"]))
    check("ascii: SetNLQ as emphasised (ESC E)", got["emphasised"] and not got["unknown"],
          str(got["unknown"]))
    print("ep1: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
