#!/usr/bin/env python3
"""The file engine reads from drive E with all four drives A-D in use
(docs/FILE_ENGINE.md; the user's U64, 2026-11-18: GU PDF's script on
drive E gave FE_NO_SLOT, "printer error" $50, the print queue paused):
a slot is borrowed for the call (sysenter.s module 119) and put back.
In VICE with images on A, B, C and D: FE_OPEN /e/pdfa4, FE_READ (the
same bytes as build/printer/pdfa4data.bin), FE_CLOSE: X = 0 each;
drive D's type and disk name the same after.
Usage: tests/engine/e5noslot.py   (E5_D= : drive D left empty, the plain
path; the first check then fails by design)
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "engine")
HOOK = r'''
from vicemon import RESP_CHECKPOINT
lbl = {}
for line in open(%(lbl)r):
    p = line.split(); lbl.setdefault(p[2].lstrip("."), int(p[1], 16))
fe = lbl["FileEngine"]
def call(code):
    code = [0x78, 0xA9, 0x30, 0x85, 0x01] + code    # (RAM in view, as GEOS runs)
    start = harness.TRAMPOLINE
    end = start + len(code)
    v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
    cp = v.checkpoint(end, temporary=False)
    v.regs_set({"PC": start})
    v.events.clear(); v.resume()
    try:
        v.wait_event(RESP_CHECKPOINT, 60)   # (the call back in the trampoline)
    except Exception:
        v.ping()
        print("E5HANG PC=%%04X SP=%%02X port=%%02X" %% (v.regs_get()["PC"], v.regs_get()["SP"], v.mem_get(1, 1)[0]))
        raise
    v.delete_checkpoint(cp)
def r(reg, val):
    return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]
jt = v.mem_get(0xC1C3, 0xC1C5)                     # (a clean point: MainLoop,
cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)    # as the desktop tests)
v.events.clear(); v.resume()
v.wait_event(RESP_CHECKPOINT, 30)
v.delete_checkpoint(cid)
v.mem_set(0x4E00, b"/e/pdfa4\0")
before = (bytes(v.mem_get(0x848E, 0x8491)), bytes(v.mem_get(0x88EE, 0x88FF)))
call([0x78] + r(0x02, 0x4E00) + [0xA9, 0, 0x85, 0x06, 0xA9, 13, 0x20, fe & 0xFF, fe >> 8,
     0x8E, 0xF0, 0x02, 0x8D, 0xF1, 0x02])
x, h = v.mem_get(0x2F0, 0x2F1)
call([0x78, 0xAC, 0xF1, 0x02] + r(0x04, 0x5000) + r(0x06, 600) + [0xA9, 14, 0x20, fe & 0xFF, fe >> 8,
     0x8E, 0xF2, 0x02, 0xA5, 0x06, 0x8D, 0xF3, 0x02, 0xA5, 0x07, 0x8D, 0xF4, 0x02])
xr = v.mem_get(0x2F2, 0x2F2)[0]
n = v.mem_get(0x2F3, 0x2F3)[0] | v.mem_get(0x2F4, 0x2F4)[0] << 8
data = bytes(v.mem_get(0x5000, 0x5000 + 599))
call([0x78, 0xAC, 0xF1, 0x02, 0xA9, 4, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF5, 0x02])
xc = v.mem_get(0x2F5, 0x2F5)[0]
after = (bytes(v.mem_get(0x848E, 0x8491)), bytes(v.mem_get(0x88EE, 0x88FF)))
print("E5 types %%s open X=%%02x read X=%%02x n=%%d close X=%%02x same=%%s data %%s" %% (
    before[0].hex(), x, xr, n, xc, before == after, data.hex()))
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
    import harness
    import apprun
    d = os.path.join(OUT, "e5")
    imgs = []
    for k in ("c", "d"):
        p = os.path.join(OUT, "e5-%s.d64" % k)
        subprocess.run([os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541"), "-format",
                        "drive %s,%s%s" % (k, k, k), "d64", p], capture_output=True)
        imgs.append(p)
    hook = os.path.join(OUT, "hook-e5.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl")})
    env = dict(os.environ, APPRUN_DRIVE_C=imgs[0], APPRUN_DRIVE_D=os.environ.get("E5_D", imgs[1]),
               PYTHONPATH=os.path.join(ROOT, "tools", "harness"))
    rimg = apprun.REU_IMAGE
    for p in (rimg, rimg + ".src"):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "12",
                        "--out", os.path.join(OUT, "e5.png"), "GEOWRITE", "h:" + hook],
                       env=env, capture_output=True, text=True, timeout=600)
    line = next((l for l in r.stdout.splitlines() if l.startswith("E5 ")), "")
    print(line[:200])
    if not line:
        print("\n".join(l for l in r.stdout.splitlines() if l.startswith("E5HANG")))
    want = open(os.path.join(ROOT, "build", "printer", "pdfa4data.bin"), "rb").read()
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    types = line.split()[2] if line else ""
    check("all four drives in use", line and all(t != "00" for t in (types[0:2], types[2:4], types[4:6], types[6:8])), types)
    check("FE_OPEN /e/pdfa4: X = 0 (a slot borrowed)", "open X=00" in line, line[:80])
    data = bytes.fromhex(line.rsplit(" ", 1)[1]) if line else b""
    n = int(line.split("n=")[1].split()[0]) if "n=" in line else 0
    check("FE_READ: X = 0, the script's bytes (all %d)" % len(want),
          "read X=00" in line and n == len(want) and data[:n] == want, (n, line[60:120]))
    check("FE_CLOSE: X = 0", "close X=00" in line)
    check("drive D as before (type, disk name)", "same=True" in line)
    for p in (rimg, rimg + ".src"):
        if os.path.exists(p):
            os.remove(p)
    print("e5noslot: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
