#!/usr/bin/env python3
"""The print spooler recording in VICE (docs/DESIGN.md "Print spooler";
src/kernal/spool.s): a printer driver ("Epson MX-80" from the
applications disk, GEOS_APPS_DISK, the user's own, never committed)
loaded with GetFile (catching switched on: spOn): its entries (not GetDimensions) become `jsr
SpoolEnt`; InitForPrint, StartPrint, two PrintBuffer rows (from the
screen), StopPrint called: each returns at once, the queue's header
(REU bank 1 $E700) has one job open and the records' bytes, the queue
(bank 27, from $2000) holds T_DRIVER, its slot and job number, T_INIT, T_START, the rows as
given, T_STOP. Through tools/harness/apprun.py (an h: hook).
Usage: tests/spool/sp2.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "spool")
APPS_DISK = os.environ.get("GEOS_APPS_DISK", os.path.expanduser(
    "~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
DRIVER = b"Epson MX-80"

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
sys_op = lbl["SysRAMOp"]
v.ping()
v.mem_set(0x4E00, %(drv)r + b"\0")
v.mem_set(0x02F0, b"\xEE" * 4)
v.mem_set(lbl["spOn"], b"\x80")                       # (catching on)
code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
        + r(0x0E, 0x4E00) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile") + [0x8E, 0xF0, 0x02]
        + jsr(0x7900)                                             # InitForPrint
        + r(0x04, 0x5000) + jsr(0x7903) + [0x8E, 0xF1, 0x02]     # StartPrint
        + r(0x02, 0xA000) + r(0x04, 0x5000) + r(0x06, 0) + jsr(0x7906)
        + r(0x02, 0xA280) + r(0x04, 0x5000) + r(0x06, 0) + jsr(0x7906)
        + r(0x02, 0x5800) + r(0x04, 0x5000) + jsr(0x7909) + [0x8E, 0xF2, 0x02]
        + r(0x02, 0x4F00) + r(0x04, 0xE700) + r(0x06, 16) + [0xA9, 1, 0x85, 0x08, 0xA0, 0x91] + jsr(sys_op)
        + r(0x02, 0x4F20) + r(0x04, 0x2000) + r(0x06, 8) + [0xA9, 27, 0x85, 0x08, 0xA0, 0x91] + jsr(sys_op)
        + r(0x02, 0x6000) + r(0x04, 0x2006) + r(0x06, 1290) + [0xA9, 27, 0x85, 0x08, 0xA0, 0x91] + jsr(sys_op))
start = harness.TRAMPOLINE
end = start + len(code)
code += [0x4C, end & 0xFF, end >> 8]
v.mem_set(start, bytes(code))
v.regs_set({"PC": start})
v.resume(); time.sleep(6); v.ping()
x = v.mem_get(0x2F0, 0x2F2)
ent = v.mem_get(0x7900, 0x7917)
hdr = v.mem_get(0x4F00, 0x4F0F)
q = v.mem_get(0x4F20, 0x4F27)
rows = v.mem_get(0x6000, 0x6000 + 1289)
screen = v.mem_get(0xA000, 0xA000 + 1279)
print("SP2 getfile=%%02x start=%%02x stop=%%02x" %% (x[0], x[1], x[2]))
print("SP2 entries " + ent.hex())
print("SP2 header " + hdr.hex())
print("SP2 queue " + q.hex())
print("SP2 rows %%s" %% (rows[0:640] == screen[0:640] and rows[641:1281] == screen[640:1280]))
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "apps.d64")
    shutil.copyfile(APPS_DISK, disk)
    hook = os.path.join(OUT, "hook-sp2.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "drv": DRIVER})
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "sp2.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=400)
    out = {l.split()[1]: l.split(None, 2)[2] for l in r.stdout.splitlines() if l.startswith("SP2")}
    if not out:
        print(r.stdout, r.stderr[-800:])
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    check("GetFile, StartPrint, StopPrint: X = 0", r.stdout.count("getfile=00 start=00 stop=00"), 1)
    ent = bytes.fromhex(out.get("entries", ""))
    caught = [ent[3 * i] == 0x20 for i in range(8)]
    check("its entries caught, GetDimensions not", caught, [True] * 4 + [False] + [True] * 3)
    hdr = bytes.fromhex(out.get("header", ""))
    head = hdr[4] | hdr[5] << 8 | hdr[6] << 16 if len(hdr) > 6 else -1
    check("the header: GUSP, one job open", (hdr[:4], hdr[10], hdr[11]) if len(hdr) > 11 else None,
          (b"GUSP", 1, 0x80))
    check("the head: driver (3), init, start, 2 rows (641 each), stop (the ring from $2000)", head, 0x2000 + 3 + 1 + 1 + 2 * 641 + 1)
    q = bytes.fromhex(out.get("queue", ""))
    check("the queue: T_DRIVER, its slot, its job (0), T_INIT, T_START, T_ROW", q[:6], bytes([1, 0, 0, 2, 3, 4]))
    check("the rows as given (the screen's)", out.get("rows"), "True")
    print("sp2: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
