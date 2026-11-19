#!/usr/bin/env python3
"""How long the print spooler takes per record, in VICE (a measurement;
docs/design/DESIGN.md "Print spooler"): a page of 94 empty rows recorded with
the queue paused through tests/spool/logdrv.s (a driver that only logs),
then resumed and timed in emulated time (GEOS's clock, $8519-$851B)
until the driver has had every call. No printer, no serial bus: what is
left is the spooler's own cost per record.
Usage: tests/spool/sptime.py
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
ROWS = 94

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
v.mem_set(0xA000, bytes(640))
start = harness.TRAMPOLINE
fe = lbl["FileEngine"]
head = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
        + r(0x0E, 0x4E00) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile")
        + [0xA0, 1, 0xA9, 33] + jsr(fe)                 # FE_SPOOL 1: paused
        + jsr(0x7900) + r(0x04, 0x4000) + jsr(0x7903)
        + [0xA9, %(rows)d, 0x8D, 0xF8, 0x02])           # the rows to go
loop = start + len(head)
body = (r(0x02, 0xA000) + r(0x04, 0x4000) + r(0x06, 0) + jsr(0x7906)
        + [0xCE, 0xF8, 0x02, 0xF0, 0x03, 0x4C, loop & 0xFF, loop >> 8])
tail = (r(0x02, 0x5800) + r(0x04, 0x4000) + jsr(0x7909)
        + [0xAD, 0x19, 0x85, 0x8D, 0xF0, 0x02, 0xAD, 0x1A, 0x85, 0x8D, 0xF1, 0x02,
           0xAD, 0x1B, 0x85, 0x8D, 0xF2, 0x02]           # the clock at the resume
        + [0xA0, 2, 0xA9, 33] + jsr(fe)                 # FE_SPOOL 2: played
        + ([0xA9, 0, 0x8D, 0x9B, 0x84, 0x8D, 0x9C, 0x84] if %(noapp)d else [])   # appMain 0
        + [0x58, 0x4C, 0xC3, 0xC1])
v.mem_set(start, bytes(head + body + tail))
v.regs_set({"PC": start})
v.resume()
t0 = time.time()
while time.time() - t0 < %(wait)d:
    time.sleep(2); v.ping()
    calls = v.mem_get(0x0280, 0x0280)[0]
    if calls >= %(rows)d + 3:
        break
    v.resume()
c = v.mem_get(0x8519, 0x851B); s0 = v.mem_get(0x02F0, 0x02F2)
el = ((c[0] - s0[0]) * 3600 + (c[1] - s0[1]) * 60 + (c[2] - s0[2])) %% 86400
print("SPT calls %%d emulated %%d s, %%.2f s a record; wall %%.0f s" %% (calls, el, el / max(1, calls), time.time() - t0))
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
    hook = os.path.join(OUT, "hook-sptime.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "rows": ROWS, "wait": 300,
                                    "noapp": int(os.environ.get("SPTIME_NOAPP", "0"))})
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "dev", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "sptime.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "dev", "harness")),
                       capture_output=True, text=True, timeout=600)
    line = next((l for l in r.stdout.splitlines() if l.startswith("SPT")), "")
    print(line or r.stderr[-600:])
    sys.exit(0 if line else 1)
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
