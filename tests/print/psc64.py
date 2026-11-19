#!/usr/bin/env python3
"""GU PostScript (src/psw, docs/DESIGN.md "PostScript writer") in VICE
against gwtool ps (tools/gwps.py), byte for byte. A D81 with the
application and a geoWrite document (GEOUTOOLS_MANUAL by default:
GeoUTools' manual, 11 pages, the system fonts, pictures) as the apps
disk (drive B); the application starts, its file box lists the
document, a click on Open writes it. VICE has no Ultimate, so the test
answers the file engine's calls for the Ultimate's paths at its entry
(FE_HOME, FE_MKDIR, FE_OPEN, FE_WRITE, FE_CLOSE, as tests/print/pdf1.py)
and keeps what is written; gwtool ps writes the same document (A4) and
the two must be the same. Files: build/harness/print/psc64-c64.ps,
psc64-pc.ps; the screen psc64.png.
Usage: tests/print/psc64.py [DOCUMENT.cvt]
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "print")
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
DOC = os.environ.get("GEOUTOOLS_MANUAL", os.path.expanduser("~/git/GeoUTools/docs/geowrite-manual-en.cvt"))
HANDLE = 0x66

HOOK = r'''
from vicemon import RESP_CHECKPOINT
ext = v.mem_get(0xC0E4, 0xC0E5)
entry = (ext[0] | ext[1] << 8) + 30
v.mem_set(0x033F, b"\x60")                  # rts: the answered calls
v.checkpoint(entry, temporary=False)
import time
def click(x, y):                            # (as apprun's x,y,p and r)
    v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
    for data in (0x00, 0x80):
        v.mem_set(0x8505, bytes([data]))
        v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
        v.resume()
        time.sleep(0.5)
        v.ping()
click(220, 44)                              # Open in the file box
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
        v.wait_event(RESP_CHECKPOINT, 60)
    except Exception:
        break
    r = v.regs_get()
    f, y = r["A"], r["Y"]
    answer = None
    if f == 26:                                     # FE_HOME
        v.mem_set(zp(4), b"/USB0/GEOULTRA/\0")
        answer = (0, 0)
    elif f == 8 and string(zp(2)).upper().startswith("/USB0"):
        log.append("mkdir " + string(zp(2)))
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
    else:
        log.append("engine %%d" %% f)
    if answer:
        v.regs_set({"PC": 0x033F, "A": answer[0], "X": answer[1]})
    if f == 4 and y == %(handle)d:
        break
v.ping()
open(%(raw)r, "wb").write(out)
for l in log:
    print("PSC64LOG " + l)
'''


def main():
    doc = sys.argv[1] if len(sys.argv) > 1 else DOC
    os.makedirs(OUT, exist_ok=True)
    subprocess.run(["make", "-s", "build/psw/psw.cvt", "all"], cwd=ROOT, check=True, capture_output=True)
    disk = os.path.join(OUT, "psc64.d81")
    if os.path.exists(disk):
        os.remove(disk)
    subprocess.run([C1541, "-format", "psc64,pc", "d81", disk, "-geoswrite",
                    os.path.join(ROOT, "build", "psw", "psw.cvt"), "-geoswrite", doc],
                   check=True, capture_output=True)
    raw = os.path.join(OUT, "psc64-c64.ps")
    if os.path.exists(raw):
        os.remove(raw)
    hook = os.path.join(OUT, "hook-psc64.py")
    open(hook, "w").write(HOOK % {"raw": raw, "handle": HANDLE})
    env = dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness"))
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "8", "--out", os.path.join(OUT, "psc64.png"), "GU PostScript",
                        "h:" + hook],
                       env=env, capture_output=True, text=True, timeout=3000)
    log = [l[9:] for l in r.stdout.splitlines() if l.startswith("PSC64LOG ")]
    for l in log:
        print("  " + l)
    if r.returncode:
        print(r.stderr[-800:])
    name = None
    for l in log:
        if l.startswith("open "):
            name = l[5:].rsplit(" ", 1)[0].rsplit("/", 1)[-1][:-3]
    pc = os.path.join(OUT, "psc64-pc.ps")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gwtool.py"), "ps", disk, pc,
                    name or "GeoUTools UK"], check=True, capture_output=True)
    a = open(raw, "rb").read() if os.path.exists(raw) else b""
    b = open(pc, "rb").read()
    same = a == b
    print("%s GU PostScript's file and gwtool ps's: %d and %d bytes%s" % (
        "pass" if same else "FAIL", len(a), len(b), "" if same else first_diff(a, b)))
    print("psc64: %s" % ("all passed" if same else "FAILED"))
    sys.exit(0 if same else 1)


def first_diff(a, b):
    la, lb = a.split(b"\n"), b.split(b"\n")
    for k, (x, y) in enumerate(zip(la, lb)):
        if x != y:
            return "; first different line %d:\n  C64: %r\n  PC:  %r" % (k + 1, x[:160], y[:160])
    return "; one is a prefix of the other (line %d)" % (min(len(la), len(lb)) + 1)


if __name__ == "__main__":
    main()
