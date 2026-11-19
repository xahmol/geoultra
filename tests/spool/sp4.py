#!/usr/bin/env python3
"""The print spooler with a full queue in VICE (docs/DESIGN.md "Print
spooler"; src/kernal/spool.s, module 112): 250 rows (641 bytes each
queued, more than the 2-bank queue holds) printed spooled through
tests/spool/logdrv.s: a call that does not fit waits while records are
played, nothing is dropped: the driver sees all 250 rows, in order
(the first rows' sums as given).
Usage: tests/spool/sp4.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "spool")
APPS_DISK = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")
ROWS = 250

HOOK = r'''
import time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402
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
start = harness.TRAMPOLINE
head = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
        + r(0x0E, 0x4E00) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile")
        + jsr(0x7900) + r(0x04, 0x4000) + jsr(0x7903)
        + [0xA9, %(rows)d, 0x8D, 0xF8, 0x02])           # the rows to go
loop = start + len(head)
body = (r(0x02, 0xA000) + r(0x04, 0x4000) + r(0x06, 0) + jsr(0x7906)
        + [0xCE, 0xF8, 0x02, 0xF0, 0x03, 0x4C, loop & 0xFF, loop >> 8])
tail = r(0x02, 0x5800) + r(0x04, 0x4000) + jsr(0x7909) + [0x58, 0x4C, 0xC3, 0xC1]
v.mem_set(start, bytes(head + body + tail))
v.regs_set({"PC": start})
v.resume(); time.sleep(%(wait)d); v.ping()
print("SP4 rows %%d calls %%d first %%s sums %%s" %% (v.mem_get(0x02BF, 0x02BF)[0], v.mem_get(0x0280, 0x0280)[0],
      v.mem_get(0x0281, 0x0284).hex(), v.mem_get(0x02C0, 0x02C3).hex()))
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
    hook = os.path.join(OUT, "hook-sp4.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "rows": ROWS, "wait": 120})
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "sp4.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=600)
    line = next((l for l in r.stdout.splitlines() if l.startswith("SP4")), "")
    print(line or r.stderr[-600:])
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    f = line.split()
    s = sum(bytes((i * 7 + 3) & 0xFF for i in range(640))) & 0xFFFF
    check("all rows reached the driver", int(f[2]) if len(f) > 2 else None, ROWS)
    check("every call: init, start, the rows, stop", int(f[4]) if len(f) > 4 else None, ROWS + 3)
    check("in order: init, start, rows", f[6] if len(f) > 6 else None, "01020303")
    check("the rows as given", f[8] if len(f) > 8 else None, bytes([s & 0xFF, s >> 8] * 2).hex())
    print("sp4: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
