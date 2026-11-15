#!/usr/bin/env python3
"""The print spooler's jobs, cancel, pause and resume in VICE (docs/
DESIGN.md "Print spooler"; src/kernal/spool.s, FE_SPOOL): three
jobs recorded through tests/spool/logdrv.s (a printer driver that logs
its calls) by a program named "testprog", none played yet; FE_SPOOL's
state (job 1 of 3) and job list (three entries: numbers 0-2, a page
each, the program's name). The playback stepped by hand into job 0's
first row, then job 0 cancelled (in the middle of its page) and job 1
cancelled (not begun), the queue paused: MainLoop plays nothing. Then
resumed: job 0's page ended with one StopPrint, job 1 passed over, job
2 printed whole; the queue empty after.
The driver is written onto a copy of an applications disk
(GEOS_APPS_DISK, the user's own).
Usage: tests/spool/sp5.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "spool")
APPS_DISK = os.environ.get("GEOS_APPS_DISK", os.path.expanduser(
    "~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))

HOOK = r'''
import time
jt = harness.jumptab()
lbl = {}
for line in open(%(lbl)r):
    p = line.split(); lbl.setdefault(p[2].lstrip("."), int(p[1], 16))
FE, OVL = lbl["FileEngine"], lbl["OvlCall"]
def jsr(a):
    a = jt.get(a, a) if isinstance(a, str) else a
    return [0x20, a & 0xFF, a >> 8]
def r(reg, val):
    return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]
def fe(sub, at=None, r0=None):              # FE_SPOOL, its A, r0, r1L kept at `at`
    c = (r(0x02, r0) if r0 is not None else []) + [0xA9, 33, 0xA0, sub] + jsr(FE)
    if at is not None:
        c += [0x8D, at & 0xFF, at >> 8, 0xA5, 0x02, 0x8D, (at + 1) & 0xFF, at >> 8,
              0xA5, 0x03, 0x8D, (at + 2) & 0xFF, at >> 8, 0xA5, 0x04, 0x8D, (at + 3) & 0xFF, at >> 8]
    return c
def job(row):
    return (jsr(0x7900) + r(0x04, 0x4000) + jsr(0x7903)
            + r(0x02, row) + r(0x04, 0x4000) + r(0x06, 0) + jsr(0x7906)
            + r(0x02, 0x5800) + r(0x04, 0x4000) + jsr(0x7909))
v.ping()
v.mem_set(0x4E00, b"GU Logdrv\0")
v.mem_set(0x0280, bytes(0x70))
v.mem_set(0x02D0, bytes(0x20))
v.mem_set(lbl["spOn"], b"\x80")
v.mem_set(lbl["taskName"], b"testprog\0\0\0\0\0")
v.mem_set(0xA000, bytes((i * 7 + 3) & 0xFF for i in range(1280)))
start = harness.TRAMPOLINE
STEP = 0x4D00                               # a stub: module 109 (Step)
v.mem_set(STEP, bytes([0x20, OVL & 0xFF, OVL >> 8, 109, 0]))
code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
        + r(0x0E, 0x4E00) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile")
        + job(0xA000) + job(0xA280) + job(0xA000)
        + fe(0, 0x02D0) + fe(4, 0x02D4, 0x5000)
        + jsr(STEP) * 4                                    # driver, init, start, a row
        + fe(3, None, 0) + fe(3, None, 1) + fe(1) + fe(0, 0x02D8)
        + [0x58, 0x4C, 0xC3, 0xC1])
v.mem_set(start, bytes(code))
v.regs_set({"PC": start})
v.resume(); time.sleep(15); v.ping()
paused_log = v.mem_get(0x0280, 0x0280)[0]
res = [0x78] + fe(2) + [0x58, 0x4C, 0xC3, 0xC1]           # resume, on in MainLoop
v.mem_set(0x4C00, bytes(res))
v.regs_set({"PC": 0x4C00})
v.resume(); time.sleep(15); v.ping()
done = [0x78] + fe(0, 0x02DC) + [0x58, 0x4C, 0xC3, 0xC1]
v.mem_set(0x4C80, bytes(done))
v.regs_set({"PC": 0x4C80})
v.resume(); time.sleep(5); v.ping()
print("SP5 st " + v.mem_get(0x02D0, 0x02DF).hex())
print("SP5 list " + v.mem_get(0x5000, 0x502F).hex())
print("SP5 paused %%d" %% paused_log)
print("SP5 log " + v.mem_get(0x0280, 0x0290).hex() + " " + v.mem_get(0x02BF, 0x02C3).hex())
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "apps5.d64")
    shutil.copyfile(APPS_DISK, disk)
    o, b, c = (os.path.join(OUT, "logdrv" + x) for x in (".o", ".bin", ".cvt"))
    subprocess.run(["ca65", "-o", o, os.path.join(ROOT, "tests", "spool", "logdrv.s")], check=True)
    subprocess.run(["ld65", "-C", os.path.join(ROOT, "tests", "spool", "logdrv.cfg"), "-o", b, o], check=True)
    subprocess.run([sys.executable, os.path.expanduser("~/git/geos-oscar64/tools/geosapp.py"),
                    os.path.join(ROOT, "tests", "spool", "logdrv.toml"), b, c], check=True, capture_output=True)
    subprocess.run([os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541"), disk, "-geoswrite", c],
                   check=True, capture_output=True)
    hook = os.path.join(OUT, "hook-sp5.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl")})
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "sp5.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=600)
    out = {l.split()[1]: l.split(None, 2)[2] for l in r.stdout.splitlines() if l.startswith("SP5 ")}
    if not out:
        print(r.stdout[-800:], r.stderr[-800:])
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    st = bytes.fromhex(out.get("st", ""))
    lst = bytes.fromhex(out.get("list", ""))
    check("FE_SPOOL state: job 1 of 3, not paused", st[0:3].hex() if st else None, "010300")
    check("the job list: 3 jobs", st[4] if st else None, 3)
    check("its entries: numbers 0-2, a page each, not cancelled",
          [tuple(lst[16 * i:16 * i + 3]) for i in range(3)] if len(lst) >= 48 else None,
          [(0, 0, 1), (1, 0, 1), (2, 0, 1)])
    check("their program's name", lst[3:12] if lst else None, b"testprog\0")
    check("paused: FE_SPOOL says so", st[8:11].hex() if st else None, "010380")
    check("paused: MainLoop played nothing more (init, start, a row)", int(out.get("paused", -1)), 3)
    pattern = bytes((i * 7 + 3) & 0xFF for i in range(1280))
    sa = sum(pattern[:640]) & 0xFFFF
    want = (bytes([8, 1, 2, 3, 4, 1, 2, 3, 4]).hex() + "00" * 8 + " "
            + bytes([2, sa & 0xFF, sa >> 8, sa & 0xFF, sa >> 8]).hex())
    check("resumed: job 0's page ended (StopPrint), job 1 passed over, job 2 whole", out.get("log"), want)
    check("the queue empty after", st[12] if len(st) > 12 else None, 0)
    print("sp5: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
