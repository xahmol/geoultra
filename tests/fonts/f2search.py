#!/usr/bin/env python3
"""The system fonts found by programs in VICE (docs/DESIGN.md "System
font folder"; sysdrive.s modules 15 and 123): a FONTS.DNP holding a font
named "F Roma" (Roma from an applications disk, GEOS_APPS_DISK, the
user's own, renamed so no drive has it), relocated with
tools/sysreloc.py as the cold start does (tests/fonts/f1reloc.py checks
that the two agree) and put into REU banks 180-187, fontsOn set. Checks:
FindFTypes for fonts lists it after the drive's and E's; FindFile finds
it on tracks 238-245 (X = 0); an unknown name stays FILE_NOT_FOUND;
module 81 shows E's bank again after (sysShow); with fontsOn 0 the font
is not found.
Usage: tests/fonts/f2search.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "fonts")
APPS = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")
GD = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]

HOOK = r'''
from vicemon import RESP_CHECKPOINT
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402
lbl = {}
for line in open(%(lbl)r):
    p = line.split(); lbl.setdefault(p[2].lstrip("."), int(p[1], 16))
jt = harness.jumptab()
sysop = lbl["SysRAMOp"]
def run(code):
    code = [0x78, 0xA9, 0x30, 0x85, 0x01] + code
    start = harness.TRAMPOLINE; end = start + len(code)
    v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
    cp = v.checkpoint(end, temporary=False)
    v.regs_set({"PC": start}); v.events.clear(); v.resume()
    v.wait_event(RESP_CHECKPOINT, 120); v.delete_checkpoint(cp)
def r(reg, val):
    return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]
def jsr(a):
    return [0x20, a & 0xFF, a >> 8]
def stash(c64, bank, page, length):
    return (r(0x02, c64) + [0xA9, 0, 0x85, 0x04, 0xA9, page, 0x85, 0x05] + r(0x06, length)
            + [0xA9, bank, 0x85, 0x08, 0xA0, 0x90] + jsr(sysop))
t = v.mem_get(0xC1C3, 0xC1C5)
cid = v.checkpoint(t[1] | t[2] << 8, temporary=False)
v.events.clear(); v.resume(); v.wait_event(RESP_CHECKPOINT, 30); v.delete_checkpoint(cid)
img = open(%(img)r, "rb").read()
for k in range(len(img) // 4096):
    v.mem_set(0x5000, img[k * 4096:(k + 1) * 4096])
    run(stash(0x5000, 180 + k // 16, (k %% 16) * 16, 4096))
v.mem_set(lbl["fontsOn"], b"\x80")
def ftypes():
    v.mem_set(0x6000, bytes(17 * 21))
    run(r(0x0E, 0x6000) + [0xA9, 8, 0x85, 0x10, 0xA9, 20, 0x85, 0x11] + r(0x16, 0)
        + jsr(jt["FindFTypes"]) + [0x8E, 0xF0, 0x02])
    raw = bytes(v.mem_get(0x6000, 0x6000 + 17 * 20))
    return [raw[i * 17:i * 17 + 16].split(b"\0")[0].decode("latin1") for i in range(20) if raw[i * 17]]
def find(name):
    v.mem_set(0x4E00, name + b"\0")
    run(r(0x0E, 0x4E00) + jsr(jt["FindFile"]) + [0x8E, 0xF1, 0x02])
    return v.mem_get(0x2F1, 0x2F1)[0], v.mem_get(0x8400, 0x841D)
names = ftypes()
print("F2 list", "|".join(names))
x, de = find(b"F Roma")
print("F2 find %%02x track %%d" %% (x, de[1]))
x2, _ = find(b"No such font")
print("F2 none %%02x" %% x2)
print("F2 show %%d" %% v.mem_get(lbl["sysShow"], lbl["sysShow"])[0])
v.mem_set(lbl["fontsOn"], b"\x00")
x3, _ = find(b"F Roma")
print("F2 off %%02x" %% x3)
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    img = os.path.join(OUT, "F2FONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    subprocess.run(GD + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(GD + ["add", img, APPS + ":Roma"], check=True, capture_output=True)
    subprocess.run(GD + ["rename", img, "Roma", "F Roma"], check=True, capture_output=True)
    rel = os.path.join(OUT, "F2FONTS-reloc.dnp")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sysreloc.py"), img, rel, "237", "8"],
                   check=True, capture_output=True)
    hook = os.path.join(OUT, "hook-f2.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "img": rel})
    sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
    import apprun
    for p in (apprun.REU_IMAGE, apprun.REU_IMAGE + ".src"):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "10",
                        "--out", os.path.join(OUT, "f2.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=1200)
    lines = {l.split()[1]: l for l in r.stdout.splitlines() if l.startswith("F2 ")}
    for l in lines.values():
        print(l)
    if not lines:
        print(r.stderr[-600:])
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    lst = lines.get("list", "").split(" ", 2)[-1].split("|")
    check("FindFTypes: the system font listed, after the drive's and E's fonts",
          "F Roma" in lst and lst.index("F Roma") > 0, lst)
    f = lines.get("find", "").split()
    check("FindFile: found (X = 0) on tracks 238-245", len(f) > 4 and f[2] == "00" and 238 <= int(f[4]) <= 245, f)
    check("an unknown name: FILE_NOT_FOUND", lines.get("none", "").endswith("05"), lines.get("none"))
    check("E's bank shown again after (sysShow 4)", lines.get("show", "").endswith(" 4"), lines.get("show"))
    check("fontsOn 0: not found", lines.get("off", "").endswith("05"), lines.get("off"))
    print("f2search: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
