#!/usr/bin/env python3
"""One entry per font ID in a program's font list, in VICE (docs/DESIGN.md
"System font folder"; sysdrive.s modules 15, 116, 123, 124; the user's
rules of 2026-11-15 and 2026-11-18): the drive (a copy of an
applications disk, GEOS_APPS_DISK, the user's own) gets "D Serif", a
copy of drive E's GU Serif (font ID 27; University taken off the copy
for room); FONTS.DNP holds "F Roma", a
copy of the disk's Roma (the same ID). A list of 15 (the drive's 5, the
installed one, E's to fill): Roma out (an installed font has its ID), D
Serif in and GU Serif out (a drive's font beats E's), F Roma in, before
E's. With the hide switch (fontsOn bit 6): every drive font out, GU
Serif back.
Usage: tests/fonts/f3rules.py
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
    run(r(0x0E, 0x6000) + [0xA9, 8, 0x85, 0x10, 0xA9, 15, 0x85, 0x11] + r(0x16, 0)
        + jsr(jt["FindFTypes"]) + [0x8E, 0xF0, 0x02])
    n = 15 - v.mem_get(0x11, 0x11)[0]                  # (found: 15 - r7H, as programs count)
    raw = bytes(v.mem_get(0x6000, 0x6000 + 17 * 20))
    return [raw[i * 17:i * 17 + 16].split(b"\0")[0].decode("latin1") for i in range(n)]
def find(name):
    v.mem_set(0x4E00, name + b"\0")
    run(r(0x0E, 0x4E00) + jsr(jt["FindFile"]) + [0x8E, 0xF1, 0x02])
    return v.mem_get(0x2F1, 0x2F1)[0], v.mem_get(0x8400, 0x841D)
print("F3 shown", "|".join(ftypes()))
v.mem_set(lbl["fontsOn"], b"\xC0")
print("F3 hidden", "|".join(ftypes()))
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    disk = os.path.join(OUT, "f3apps.d64")
    import shutil
    shutil.copyfile(APPS, disk)
    subprocess.run(GD + ["delete", disk, "University"], check=True, capture_output=True)   # (room)
    subprocess.run(GD + ["add", disk, os.path.join(ROOT, "build", "sysdrive-plain.dnp") + ":GU Serif"],
                   check=True, capture_output=True)
    subprocess.run(GD + ["rename", disk, "GU Serif", "D Serif"], check=True, capture_output=True)
    img = os.path.join(OUT, "F3FONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    subprocess.run(GD + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(GD + ["add", img, APPS + ":Roma"], check=True, capture_output=True)
    subprocess.run(GD + ["rename", img, "Roma", "F Roma"], check=True, capture_output=True)
    rel = os.path.join(OUT, "F3FONTS-reloc.dnp")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sysreloc.py"), img, rel, "237", "8"],
                   check=True, capture_output=True)
    hook = os.path.join(OUT, "hook-f3.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "img": rel})
    sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
    import apprun
    for p in (apprun.REU_IMAGE, apprun.REU_IMAGE + ".src"):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "10",
                        "--out", os.path.join(OUT, "f3.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=1200)
    lines = {l.split()[1]: l for l in r.stdout.splitlines() if l.startswith("F3 ")}
    for l in lines.values():
        print(l)
    if not lines:
        print(r.stderr[-600:])
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    shown = lines.get("shown", "").split(" ", 2)[-1].split("|")
    hidden = lines.get("hidden", "").split(" ", 2)[-1].split("|")
    check("shown: Roma out (the installed F Roma has its ID), F Roma in, before E's",
          "Roma" not in shown and "F Roma" in shown and "GU Sans" in shown
          and shown.index("F Roma") < shown.index("GU Sans"), shown)
    check("shown: D Serif in, GU Serif out (a drive's font beats E's)",
          "D Serif" in shown and "GU Serif" not in shown, shown)
    check("shown: the drive's other fonts kept", all(n in shown for n in ("California", "Cory", "Dwinelle")),
          shown)
    check("no name twice (one entry per ID)", len(set(shown)) == len(shown) and len(set(hidden)) == len(hidden),
          (shown, hidden))
    check("hidden: no drive font, F Roma and GU Serif in",
          not any(n in hidden for n in ("Roma", "D Serif", "California", "Cory", "Dwinelle"))
          and "F Roma" in hidden and "GU Serif" in hidden, hidden)
    print("f3rules: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
