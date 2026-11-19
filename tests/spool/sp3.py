#!/usr/bin/env python3
"""The print spooler's playback in VICE (docs/DESIGN.md "Print spooler";
src/kernal/spool.s): the same page (InitForPrint, StartPrint,
two rows, StopPrint) printed twice through tests/spool/logdrv.s, a
printer driver that logs its calls and each row's sum at $0280 (VICE's
printer 4 does not answer GEOS drivers here): once directly (spooling
off), once spooled (spOn: the calls recorded and returned at once, then
played from MainLoop, a record a pass, with the driver swapped in). The
logs the same and as expected. The driver is written onto a copy of an
applications disk (GEOS_APPS_DISK, the user's own).
Usage: tests/spool/sp3.py
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
v.mem_set(lbl["spOn"], bytes([%(on)d]))
v.mem_set(0xA000, bytes((i * 7 + 3) & 0xFF for i in range(1280)))
mark = bytes((i * 13 + 5) & 0xFF for i in range(0xB50))
v.mem_set(0x6000, mark)                     # the program's bytes there
code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
        + r(0x0E, 0x4E00) + [0xA9, 0x00, 0x85, 0x02] + jsr("GetFile")
        + jsr(0x7900)
        + r(0x04, 0x4000) + jsr(0x7903) + [0x8E, 0xF1, 0x02]
        + r(0x02, 0xA000) + r(0x04, 0x4000) + r(0x06, 0) + jsr(0x7906)
        + r(0x02, 0xA280) + r(0x04, 0x4000) + r(0x06, 0) + jsr(0x7906)
        + r(0x02, 0x5800) + r(0x04, 0x4000) + jsr(0x7909) + [0x8E, 0xF2, 0x02]
        + [0x58, 0x4C, 0xC3, 0xC1])             # cli, on in MainLoop (the playback)
start = harness.TRAMPOLINE
v.mem_set(start, bytes(code))
v.regs_set({"PC": start})
v.resume(); time.sleep(%(wait)d); v.ping()
print("SP3 start X=%%02x stop X=%%02x" %% tuple(v.mem_get(0x2F1, 0x2F2)))
print("SP3 log " + v.mem_get(0x0280, 0x028F).hex() + " " + v.mem_get(0x02BF, 0x02C3).hex())
print("SP3 own %%02x" %% v.mem_get(0x02EF, 0x02EF)[0])
print("SP3 area %%s driver %%s" %% (bytes(v.mem_get(0x6000, 0x6B4F)) == mark, v.mem_get(0x7903, 0x7905).hex()))
fetch = ([0x78] + r(0x02, 0x4F00) + r(0x04, 0xE700) + r(0x06, 22) + [0xA9, 1, 0x85, 0x08, 0xA0, 0x91]
         + jsr(lbl["SysRAMOp"]))            # the queue's header (QHEAD, bank 1)
fend = start + len(fetch)
v.mem_set(start, bytes(fetch + [0x4C, fend & 0xFF, fend >> 8]))
v.regs_set({"PC": start})
v.resume(); time.sleep(2); v.ping()
print("SP3 progress " + v.mem_get(0x4F13, 0x4F15).hex())
'''


def run(tag, on, wait):
    hook = os.path.join(OUT, "hook-sp3-%s.py" % tag)
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "on": on, "wait": wait})
    env = dict(os.environ, GEOS_APPS_DISK=os.path.join(OUT, "apps.d64"),
               PYTHONPATH=os.path.join(ROOT, "tools", "harness"))
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"),
                        "--wait", "10", "--out", os.path.join(OUT, "sp3-%s.png" % tag), "GEOWRITE",
                        "h:" + hook], env=env, capture_output=True, text=True, timeout=500)
    if r.returncode:
        print(r.stderr[-600:])
    lines = [l for l in r.stdout.splitlines() if "SP3" in l]
    print("\n".join(lines))
    area = next((l for l in lines if l.startswith("SP3 area")), "")
    own = next((l.split()[2] for l in lines if l.startswith("SP3 own")), "")
    global progress
    progress = next((l.split()[2] for l in lines if l.startswith("SP3 progress")), "")
    return next((l.split(None, 2)[2] for l in lines if l.startswith("SP3 log")), ""), area, own


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
    direct, _, own_direct = run("direct", 0, 20)
    spooled, area, own_spooled = run("spooled", 0x80, 40)
    pattern = bytes((i * 7 + 3) & 0xFF for i in range(1280))
    sums = [sum(pattern[:640]) & 0xFFFF, sum(pattern[640:]) & 0xFFFF]   # (the driver: 16 bits)
    want = (bytes([5, 1, 2, 3, 3, 4]).hex() + "00" * 10 + " "
            + bytes([2, sums[0] & 0xFF, sums[0] >> 8, sums[1] & 0xFF, sums[1] >> 8]).hex())
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    check("printed directly: the calls and rows' sums logged", direct, want)
    check("spooled and played: the same log", spooled, want)
    check("the progress after the played page (FE_SPOOL 0 r1H): page 1, all 94 rows, 100%",
          progress, "015e64")
    check("the program's memory given back ($6000 area; its caught driver at $7900)",
          area.split()[2:4] if area else None, ["True", "driver"])
    check("the caught driver's entry kept (jsr SpoolEnt)", area.split()[-1][:2] if area else None, "20")
    check("the driver's own memory kept from call to call (its count: 5 calls)",
          (own_direct, own_spooled), ("05", "05"))
    print("sp3: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
