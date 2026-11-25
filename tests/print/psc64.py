#!/usr/bin/env python3
"""GU PostScript (src/psw, docs/design/DESIGN.md "PostScript writer") in VICE
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
--doc=features: tests/print/psref.py's test document instead (GU
Serif, Sans and Mono at 10-24 points, from drive E; a header and a
footer; the alignments and spacings; the GU fonts as real text, IDs
27-37: step P3), compared with gwtool ps.
The application's options box: OK (A4, real text: the defaults without
a SETTINGS.INI); --letter clicks Letter, --c64 clicks C64 look first
(gwtool ps then --letter, --bitmap).
Usage: tests/print/psc64.py [DOCUMENT.cvt] [--doc=features] [--letter] [--c64]
"""
import os
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "print")
C1541 = localcfg.C1541
DOC = localcfg.get("GEOUTOOLS_MANUAL", os.path.join(localcfg.GEOUTOOLS, "docs", "geowrite-manual-en.cvt"))
HANDLE = 0x66

HOOK = r'''
from vicemon import RESP_CHECKPOINT
ext = v.mem_get(0xC0E4, 0xC0E5)
entry = (ext[0] | ext[1] << 8) + 30
v.mem_set(0x033F, b"\x60")                  # rts: the answered calls
v.checkpoint(entry, temporary=False)
import time
def press(x, y):                            # a press (GEOS's icons act on it)
    v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
    v.mem_set(0x8505, b"\x00")
    v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
def run(t):
    v.resume()
    time.sleep(t)
    v.ping()
def release():
    v.mem_set(0x8505, b"\x80")
    v.mem_set(0x39, bytes([v.mem_get(0x39, 0x39)[0] | 0x20]))
    run(0.5)
press(220, 44)                              # Open in the file box
run(1.5)
release()
for x, y in %(clicks)r:                     # the options box's buttons
    press(x, y)
    run(0.7)
    release()
press(220, 84)                              # its OK: run by the loop below, so
                                            # the first engine call is caught
def zp(n):
    b = v.mem_get(n, n + 1)
    return b[0] | b[1] << 8
def string(a):
    return bytes(v.mem_get(a, a + 80)).split(b"\0")[0].decode("latin1")
log, out, busy = [], bytearray(), []
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
        if len(out) > 30000 and not busy:           # the progress box (psw.s
            busy.append(1)                          # Busy, ShowPage): its frame
            import apprun
            apprun.render(bytes(v.mem_get(0xA000, 0xBF3F)), bytes(v.mem_get(0x8C00, 0x8FE7)),
                          %(busyshot)r)
            row = bytes(v.mem_get(0xA000 + 8 * 320 + 9 * 8, 0xA000 + 8 * 320 + 30 * 8))   # line 64
            print("PSC64 busy %%d" %% sum(row[i] == 0xFF for i in range(0, len(row), 8)), flush=True)
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
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    feat = "--doc=features" in sys.argv
    if feat:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import psref
        doc = psref.features_doc()
    else:
        doc = args[0] if args else DOC
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
    clicks = []
    if "--letter" in sys.argv:
        clicks.append((150, 84))            # Letter (A4 at 90, OK at 220)
    if "--c64" in sys.argv:
        clicks.append((150, 104))           # C64 look (real text at 90)
    open(hook, "w").write(HOOK % {"raw": raw, "handle": HANDLE, "clicks": clicks,
                                  "busyshot": os.path.join(OUT, "psc64-busy.png")})
    env = dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "dev", "harness"))
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"),
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
                    name or "GeoUTools UK"] + (["--letter"] if "--letter" in sys.argv else [])
                   + (["--bitmap"] if "--c64" in sys.argv else []), check=True, capture_output=True)
    a = open(raw, "rb").read() if os.path.exists(raw) else b""
    b = open(pc, "rb").read()
    same = a == b
    print("%s GU PostScript's file and gwtool ps's: %d and %d bytes%s" % (
        "pass" if same else "FAIL", len(a), len(b), "" if same else first_diff(a, b)))
    busy = next((int(l.split()[2]) for l in r.stdout.splitlines() if l.startswith("PSC64 busy")), 0)
    shown = busy >= 20                              # (the frame's top line, line 64:
    print("%s the progress box while it writes (psc64-busy.png): %d of 22 cards of its"
          " frame" % ("pass" if shown else "FAIL", busy))   # x 72-247)
    ok = same and shown
    print("psc64: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


def first_diff(a, b):
    la, lb = a.split(b"\n"), b.split(b"\n")
    for k, (x, y) in enumerate(zip(la, lb)):
        if x != y:
            return "; first different line %d:\n  C64: %r\n  PC:  %r" % (k + 1, x[:160], y[:160])
    return "; one is a prefix of the other (line %d)" % (min(len(la), len(lb)) + 1)


if __name__ == "__main__":
    main()
