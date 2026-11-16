#!/usr/bin/env python3
"""GU PDF A4 (src/printer/pdf.s, its scripts pdfa4 on drive E) in VICE:
two pages of ten bands of pseudo-random dots (the rest of each page
blank), printed directly and through the spooler, the driver and its
scripts from drive E (GetFile's fallback; FE_OPEN /e/pdfa4 for real).
VICE has no Ultimate, so the test answers the file engine for the
Ultimate's paths (FE_HOME, FE_MKDIR, FE_OPEN, FE_WRITE, FE_CLOSE on its
own handle) at the engine's entry and keeps what is written. Checks:
the file's path (GEOULTRA/print/<program>-20YYMMDD-HHMMSS.pdf), made for
the first page and appended to for the second, mutool reads the PDF
without a repair (its xref and the update's /Prev right) and finds two
pages, each page's image is the rows as sent (the blank rest included),
and the spooled file is the same. docs/DESIGN.md "Printing".
Usage: tests/print/pdf1.py
"""
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ep1                                       # noqa: E402

ROOT = ep1.ROOT
OUT = ep1.OUT
NAME = b"GU PDF A4"
PAGES = 2
HANDLE = 0x77

HOOK = r'''
import time
from vicemon import RESP_CHECKPOINT
v.mem_set(0x4E00, %(name)r + b"\0")
v.mem_set(0x5000, %(data)r)
v.mem_set(0x02F0, b"\0")
v.mem_set(%(spon)d, bytes([%(on)d]))
v.mem_set(0x033F, b"\x60")                  # rts: the answered calls
v.mem_set(0x0340, open(%(call)r, "rb").read())
v.regs_set({"PC": 0x0340})
ext = v.mem_get(0xC0E4, 0xC0E5)
entry = (ext[0] | ext[1] << 8) + 30
v.checkpoint(entry, temporary=False)
def zp(n):
    b = v.mem_get(n, n + 1)
    return b[0] | b[1] << 8
def string(a):
    return bytes(v.mem_get(a, a + 80)).split(b"\0")[0].decode("latin1")
log, out = [], bytearray()
while True:
    v.events.clear()
    v.resume()
    try:
        v.wait_event(RESP_CHECKPOINT, 25)
    except Exception:
        break
    r = v.regs_get()
    f, y = r["A"], r["Y"]
    answer = None
    if f == 26:                                     # FE_HOME
        v.mem_set(zp(4), b"/USB0/GEOULTRA/\0")
        answer = (0, 0)
    elif f == 8 and string(zp(2)).upper().startswith("/USB0"):
        log.append("mkdir " + string(zp(2)))        # FE_MKDIR
        answer = (0, 0)
    elif f == 13 and string(zp(2)).upper().startswith("/USB0"):
        log.append("open %%s %%d" %% (string(zp(2)), v.mem_get(6, 6)[0]))
        answer = (%(handle)d, 0)
    elif f == 15 and y == %(handle)d:                # FE_WRITE
        n = zp(6)
        if n:
            a = zp(4)
            out += bytes(v.mem_get(a, a + n - 1))
        answer = (0, 0)
    elif f == 4 and y == %(handle)d:                 # FE_CLOSE
        log.append("close")
        answer = (0, 0)
    elif f in (13, 14, 4, 8, 33):
        log.append("engine %%d" %% f)              # (drive E, FE_SPOOL: real)
    if answer:
        v.regs_set({"PC": 0x033F, "A": answer[0], "X": answer[1]})
v.ping()
open(%(raw)r, "wb").write(out)
print("PDF1 " + v.mem_get(0x2EF, 0x2F2).hex())
for l in log:
    print("PDF1LOG " + l)
'''


def run(tag, data, spooled):
    import harness
    jt = harness.jumptab()
    call = os.path.join(OUT, "pdfcall-%s.bin" % tag)
    o = call[:-4] + ".o"
    subprocess.run(["ca65", "-o", o, "-D", "SetDevice=$%04X" % jt["SetDevice"],
                    "-D", "OpenDisk=$%04X" % jt["OpenDisk"], "-D", "GetFile=$%04X" % jt["GetFile"],
                    "-D", "BANDS=%d" % ep1.BANDS, "-D", "COLSTEP=0", "-D", "ASCII=0",
                    "-D", "SPOOLED=%d" % spooled, "-D", "MainLoop=$%04X" % jt["MainLoop"],
                    "-D", "PAGES=%d" % PAGES, os.path.join(ROOT, "tests", "print", "epcall.s")], check=True)
    subprocess.run(["ld65", "-t", "none", "-o", call, o], check=True)
    raw = os.path.join(OUT, "pdf1-%s.pdf" % tag)
    hook = os.path.join(OUT, "hook-pdf1-%s.py" % tag)
    open(hook, "w").write(HOOK % {"name": NAME, "data": data, "call": call, "raw": raw,
                                  "spon": ep1.label("spOn"), "on": 0x80 if spooled else 0,
                                  "handle": HANDLE})
    env = dict(os.environ, GEOS_APPS_DISK=os.path.join(OUT, "apps.d64"),
               PYTHONPATH=os.path.join(ROOT, "tools", "harness"))
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "pdf1-%s.png" % tag), "GEOWRITE",
                        "h:" + hook], env=env, capture_output=True, text=True, timeout=900)
    if r.returncode:
        print(r.stderr[-600:])
    res = next((l.split()[1] for l in r.stdout.splitlines() if l.startswith("PDF1 ")), "")
    log = [l[8:] for l in r.stdout.splitlines() if l.startswith("PDF1LOG ")]
    return res, log, raw


def image(data):
    """A page's expected image: its BANDS bands as rows, then blank rows."""
    rows = bytearray()
    for band in range(ep1.BANDS):
        for r in range(8):
            rows += bytes(data[band * 640 + c * 8 + r] for c in range(80))
    return bytes(rows) + bytes(752 * 80 - len(rows))


def mutool(*args):
    r = subprocess.run(["mutool"] + list(args), capture_output=True)
    return r.returncode, r.stdout, r.stderr.decode("latin1")


def main():
    ep1.disk_with(None)                             # the driver from drive E
    subprocess.run(["make", "-s", "build/printer/pdfa4.cvt", "build/printer/pdfa4data.cvt", "all"],
                   cwd=ROOT, check=True, capture_output=True)
    rnd = random.Random(94)
    data = bytes(rnd.getrandbits(8) for _ in range(ep1.BANDS * 640))
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + str(detail)))

    res, log, pdf = run("direct", data, False)
    print("  " + "\n  ".join(log))
    check("driver from drive E, StartPrint and StopPrint X = 0", res == "00aa0000", res)
    opens = [l.split()[1:] for l in log if l.startswith("open ")]
    path = opens[0][0] if opens else ""
    check("the file: GEOULTRA/print/<program>-20YYMMDD-HHMMSS.pdf",
          re.fullmatch(r"/USB0/GEOULTRA/print/[A-Za-z0-9]+-20\d{6}-\d{6}\.pdf", path) is not None, path)
    check("made for page 1 (write), appended to for every other call",
          [m for _, m in opens][:1] == ["1"] and all(m == "2" for _, m in opens[1:]) and len(opens) == 2 * (2 + ep1.BANDS),
          [m for _, m in opens])
    check("the folder made (FE_MKDIR, there already: not minded)", "mkdir /USB0/GEOULTRA/print" in log, log[:3])
    code, out, err = mutool("info", pdf)
    pages = re.search(r"Pages: (\d+)", out.decode("latin1"))
    check("mutool reads it without repairing (xref, /Prev)", code == 0 and "repair" not in err and "error" not in err,
          err[:300])
    check("two pages", pages and pages.group(1) == "2", out[:200])
    want = image(data)
    for obj, page in ((3, 1), (6, 2)):
        code, got, err = mutool("show", "-b", pdf, str(obj))
        check("page %d's image (object %d): the rows as sent, the rest blank" % (page, obj),
              got == want, "%d bytes, %s" % (len(got), err[:100]))
    direct = open(pdf, "rb").read()
    res, log, pdf2 = run("spooled", data, True)
    check("spooled: the same PDF", res == "00aa0000" and open(pdf2, "rb").read() == direct, res)
    print("pdf1: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
