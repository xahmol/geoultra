#!/usr/bin/env python3
"""A paused, full print queue in VICE (docs/design/DESIGN.md "Print spooler";
src/kernal/spool.s, modules 107 and 112): the queue paused (FE_SPOOL 1),
then a job of 250 rows (more than the 2-bank queue holds) through
tests/spool/logdrv.s: its StartPrint fits (room for a whole page, X = 0),
the rows past the queue's end are dropped, its StopPrint fits; the next
job's StartPrint finds no room for a page and returns DEV_NOT_FOUND (13),
as without a printer, so the program stops with its own message (before
2026-11-18 X = 0: the print vanished without a word). Paused, the driver
is called not once.
Usage: tests/spool/sp6.py
"""
import os
import shutil
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "spool")
APPS_DISK = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")
ROWS = 250

HOOK = r'''
import time
jt = harness.jumptab()
lbl = {}
for line in open(%(lbl)r):
    p = line.split(); lbl.setdefault(p[2].lstrip("."), int(p[1], 16))
def jsr(a):
    a = jt.get(a, a) if isinstance(a, str) else a
    return [0x20, a & 0xFF, a >> 8]
def r(reg, val):
    return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]
v.ping()
v.mem_set(0x4E00, b"GU Logdrv\0")
v.mem_set(0x0280, bytes(0x70))
v.mem_set(lbl["spOn"], b"\x80")
v.mem_set(0xA000, bytes((i * 7 + 3) & 0xFF for i in range(640)))
v.mem_set(0x02F0, b"\xee\xee\xee")
start = harness.TRAMPOLINE
fe = lbl["FileEngine"]
head = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
        + r(0x0E, 0x4E00) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile")
        + [0xA0, 1, 0xA9, 33] + jsr(fe)                 # FE_SPOOL 1: paused
        + jsr(0x7900) + r(0x04, 0x4000) + jsr(0x7903) + [0x8E, 0xF0, 0x02]
        + [0xA9, %(rows)d, 0x8D, 0xF8, 0x02])           # the rows to go
loop = start + len(head)
body = (r(0x02, 0xA000) + r(0x04, 0x4000) + r(0x06, 0) + jsr(0x7906)
        + [0xCE, 0xF8, 0x02, 0xF0, 0x03, 0x4C, loop & 0xFF, loop >> 8])
tail = (r(0x02, 0x5800) + r(0x04, 0x4000) + jsr(0x7909) + [0x8E, 0xF1, 0x02]
        + jsr(0x7900) + r(0x04, 0x4000) + jsr(0x7903) + [0x8E, 0xF2, 0x02, 0x58, 0x4C, 0xC3, 0xC1])
v.mem_set(start, bytes(head + body + tail))
v.regs_set({"PC": start})
v.resume(); time.sleep(%(wait)d); v.ping()
print("SP6 calls %%d start %%02x stop %%02x next %%02x" %% (v.mem_get(0x0280, 0x0280)[0],
      *v.mem_get(0x02F0, 0x02F2)))
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "apps.d64")
    shutil.copyfile(APPS_DISK, disk)
    o, b, c = (os.path.join(OUT, "logdrv" + x) for x in (".o", ".bin", ".cvt"))
    subprocess.run(["ca65", "-o", o, os.path.join(ROOT, "tests", "spool", "logdrv.s")], check=True)
    subprocess.run(["ld65", "-C", os.path.join(ROOT, "tests", "spool", "logdrv.cfg"), "-o", b, o], check=True)
    subprocess.run([sys.executable, localcfg.GEOSAPP,
                    os.path.join(ROOT, "tests", "spool", "logdrv.toml"), b, c], check=True, capture_output=True)
    subprocess.run([localcfg.C1541, disk, "-geoswrite", c],
                   check=True, capture_output=True)
    hook = os.path.join(OUT, "hook-sp6.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "rows": ROWS, "wait": 60})
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "sp6.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "dev", "harness")),
                       capture_output=True, text=True, timeout=600)
    line = next((l for l in r.stdout.splitlines() if l.startswith("SP6")), "")
    print(line or r.stderr[-600:])
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    f = line.split()
    check("paused: the driver not called", int(f[2]) if len(f) > 2 else None, 0)
    check("StartPrint fitted: X = 0", f[4] if len(f) > 4 else None, "00")
    check("its StopPrint (a few bytes, fits): X = 0", f[6] if len(f) > 6 else None, "00")
    check("the next job's StartPrint: DEV_NOT_FOUND", f[8] if len(f) > 8 else None, "0d")
    print("sp6: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
