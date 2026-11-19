#!/usr/bin/env python3
"""The file engine's /f (the system fonts) in VICE (docs/DESIGN.md
"System font folder", docs/FILE_ENGINE.md; enginepath.s, sysenter.s
modules 81 and 125): FONTS.DNP with "F Roma" (Roma from GEOS_APPS_DISK,
the user's own, renamed) relocated and put into REU banks 180-187 as in
f2search.py, fontsOn set. Checks: FE_OPENDIR /f and FE_READDIR in
separate calls (the handle shows /f again: HDrive) give "F Roma", then
the end; FE_STAT /f/F Roma: a font; FE_DF /f and /e each their own
free blocks (the BAM working copy shared one count, 2026-11-19); after the calls drive E is shown
again for programs (sysShow 4: FindFile still finds E's "GU Sans"
through its fallback); with fontsOn 0, /f is not there.
Usage: tests/fonts/f4path.py
"""
import os
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "fonts")
APPS = localcfg.disk("GEOS_APPS_DISK", "neos-mouse-driver-for-geos.d64")
GD = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]

HOOK = r'''
from vicemon import RESP_CHECKPOINT
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
fe = lbl["FileEngine"]
def fecall(code):
    run(code)
v.mem_set(0x4E40, b"/f\0")
fecall(r(0x02, 0x4E40) + [0xA9, 2, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF0, 0x02, 0x8D, 0xF1, 0x02])
x, h = v.mem_get(0x2F0, 0x2F1)
names = []
for k in range(4):
    v.mem_set(0x6100, bytes(61))
    fecall([0xAC, 0xF1, 0x02] + r(0x04, 0x6000) + r(0x06, 0x6100) + r(0x08, 0)
           + [0xA9, 3, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF2, 0x02])
    xr = v.mem_get(0x2F2, 0x2F2)[0]
    if xr:
        names.append("end:%%02x" %% xr)
        break
    names.append(bytes(v.mem_get(0x6100, 0x613C)).split(b"\0")[0].decode("latin1"))
fecall([0xAC, 0xF1, 0x02, 0xA9, 4, 0x20, fe & 0xFF, fe >> 8])
print("F4 dir %%02x %%s" %% (x, "|".join(names)))
v.mem_set(0x4E60, b"/f/F Roma\0")
fecall(r(0x02, 0x4E60) + r(0x04, 0x6200) + r(0x06, 0) + [0xA9, 1, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF3, 0x02])
print("F4 stat %%02x" %% v.mem_get(0x2F3, 0x2F3)[0])
for pth in (b"/f\0", b"/e\0"):
    v.mem_set(0x4E80, pth)
    fecall(r(0x02, 0x4E80) + [0xA9, 16, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF4, 0x02,
                              0xA5, 0x04, 0x8D, 0xF5, 0x02, 0xA5, 0x05, 0x8D, 0xF6, 0x02])
    fr = v.mem_get(0x2F5, 0x2F6)
    print("F4 df%%s %%02x %%d" %% (pth[1:2].decode(), v.mem_get(0x2F4, 0x2F4)[0], fr[0] | fr[1] << 8))
print("F4 show %%d" %% v.mem_get(lbl["sysShow"], lbl["sysShow"])[0])
xe, de = find(b"GU Sans")
print("F4 efind %%02x track %%d" %% (xe, de[1]))
v.mem_set(lbl["fontsOn"], b"\x00")
fecall(r(0x02, 0x4E60) + r(0x04, 0x6200) + r(0x06, 0) + [0xA9, 1, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF3, 0x02])
print("F4 off %%02x" %% v.mem_get(0x2F3, 0x2F3)[0])
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    img = os.path.join(OUT, "F4FONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    subprocess.run(GD + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(GD + ["add", img, APPS + ":Roma"], check=True, capture_output=True)
    subprocess.run(GD + ["rename", img, "Roma", "F Roma"], check=True, capture_output=True)
    rel = os.path.join(OUT, "F4FONTS-reloc.dnp")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sysreloc.py"), img, rel, "237", "8"],
                   check=True, capture_output=True)
    hook = os.path.join(OUT, "hook-f4.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "img": rel})
    sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
    import apprun
    for p in (apprun.REU_IMAGE, apprun.REU_IMAGE + ".src"):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "10",
                        "--out", os.path.join(OUT, "f4.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=1200)
    lines = {l.split()[1]: l for l in r.stdout.splitlines() if l.startswith("F4 ")}
    for l in lines.values():
        print(l)
    if not lines:
        print(r.stderr[-600:])
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    d = lines.get("dir", "").split(" ", 3)
    check("FE_OPENDIR /f: X = 0; FE_READDIR: F Roma, then the end",
          len(d) > 3 and d[2] == "00" and d[3].split("|")[0] == "F Roma" and d[3].split("|")[-1].startswith("end:"),
          d)
    check("FE_STAT /f/F Roma: X = 0", lines.get("stat", "").endswith("00"), lines.get("stat"))
    check("E's bank again after the calls (sysShow 4)", lines.get("show", "").endswith(" 4"), lines.get("show"))
    e = lines.get("efind", "").split()
    check("FindFile: E's GU Sans still found (tracks 248-255)", len(e) > 4 and e[2] == "00" and int(e[4]) >= 248, e)
    check("fontsOn 0: /f not there", not lines.get("off", "").endswith("00"), lines.get("off"))
    df = (lines.get("dff", "").split()[-1:], lines.get("dfe", "").split()[-1:])
    check("FE_DF: /f and /e each their own free blocks (not one shared count)",
          df[0] and df[1] and df[0] != df[1] and int(df[0][0]) > int(df[1][0]), df)
    print("f4path: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
