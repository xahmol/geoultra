#!/usr/bin/env python3
"""The system fonts' relocation in VICE (docs/DESIGN.md "System font
folder"; src/kernal/mount.s overlay modules 121-122): a FONTS.DNP of 8
tracks made with tools/geosdisk.py holding fonts from an applications
disk (GEOS_APPS_DISK, the user's own; VLIR) and a sequential file, put
into REU banks 180-187 as the cold start loads it, relocated by module
121 (entry 3, Reloc): the banks then hold, byte for byte, what
tools/sysreloc.py makes of the same image with offset 237 (the proven
relocation of drive E). Module 121's Reloc returns C clear.
Usage: tests/fonts/f1reloc.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "fonts")
APPS = os.environ.get("GEOS_APPS_DISK", os.path.expanduser("~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
GD = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]
FONT_BANK, FONT_TRACK = 180, 237

HOOK = r'''
from vicemon import RESP_CHECKPOINT
lbl = {}
for line in open(%(lbl)r):
    p = line.split(); lbl.setdefault(p[2].lstrip("."), int(p[1], 16))
ovl = lbl["OvlCall"]
def run(code, port=0x30):
    code = [0x78, 0xA9, port, 0x85, 0x01] + code
    start = harness.TRAMPOLINE; end = start + len(code)
    v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
    cp = v.checkpoint(end, temporary=False)
    v.regs_set({"PC": start}); v.events.clear(); v.resume()
    v.wait_event(RESP_CHECKPOINT, 120); v.delete_checkpoint(cp)
sysop = lbl["SysRAMOp"]
def dma(cmd, c64, bank, page, length):
    """SysRAMOp: r0 C64, r1 REU address, r2 length, r3L bank, Y the command."""
    return ([0xA9, c64 & 0xFF, 0x85, 0x02, 0xA9, c64 >> 8, 0x85, 0x03,
             0xA9, 0, 0x85, 0x04, 0xA9, page, 0x85, 0x05,
             0xA9, length & 0xFF, 0x85, 0x06, 0xA9, length >> 8, 0x85, 0x07,
             0xA9, bank, 0x85, 0x08, 0xA0, cmd, 0x20, sysop & 0xFF, sysop >> 8])
t = v.mem_get(0xC1C3, 0xC1C5)
cid = v.checkpoint(t[1] | t[2] << 8, temporary=False)
v.events.clear(); v.resume(); v.wait_event(RESP_CHECKPOINT, 30); v.delete_checkpoint(cid)
img = open(%(img)r, "rb").read()
used = %(used)d
for k in range(used * 16):                      # in: 4 KB at a time
    v.mem_set(0x5000, img[k * 4096:(k + 1) * 4096])
    run(dma(0x90, 0x5000, %(bank)d + k // 16, (k %% 16) * 16, 4096))
v.mem_set(0x4301, bytes([%(tracks)d]))          # fTracks (mount.s FV + 1)
stub = 0x0380
v.mem_set(stub, bytes([0x20, ovl & 0xFF, ovl >> 8, 121, 3]))
run([0x20, stub & 0xFF, stub >> 8, 0x08, 0x68, 0x8D, 0xF0, 0x02], 0x35)   # (I/O in, as at the cold start)
out = bytearray()
for k in range(used * 16):                      # out
    run(dma(0x91, 0x5000, %(bank)d + k // 16, (k %% 16) * 16, 4096))
    out += bytes(v.mem_get(0x5000, 0x5FFF))
open(%(back)r, "wb").write(out)
print("F1 P=%%02x" %% v.mem_get(0x2F0, 0x2F0)[0])
'''


def main():
    os.makedirs(OUT, exist_ok=True)
    img = os.path.join(OUT, "FONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    subprocess.run(GD + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(GD + ["add", img, APPS + ":Roma", APPS + ":California", APPS + ":Cory"],
                   check=True, capture_output=True)
    seq = os.path.join(OUT, "note.seq")
    open(seq, "wb").write(bytes(range(256)) * 3)
    subprocess.run(GD + ["add", img, seq, "--seq"], check=True, capture_output=True)
    want = os.path.join(OUT, "FONTS-reloc.dnp")
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sysreloc.py"), img, want,
                        str(FONT_TRACK), "8"], capture_output=True, text=True)
    print(r.stdout.strip() or r.stderr.strip())
    expect = open(want, "rb").read()
    used = (len(expect) + 65535) // 65536
    back = os.path.join(OUT, "FONTS-vice.bin")
    hook = os.path.join(OUT, "hook-f1.py")
    open(hook, "w").write(HOOK % {"lbl": os.path.join(ROOT, "build", "kernal64.lbl"), "img": img, "used": used,
                                  "bank": FONT_BANK, "tracks": 8, "back": back})
    sys.path.insert(0, os.path.join(ROOT, "tools", "harness"))
    import apprun
    for p in (apprun.REU_IMAGE, apprun.REU_IMAGE + ".src"):
        if os.path.exists(p):
            os.remove(p)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "10",
                        "--out", os.path.join(OUT, "f1.png"), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=1200)
    line = next((l for l in r.stdout.splitlines() if l.startswith("F1")), "")
    print(line or r.stderr[-600:])
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": %s" % (detail,)))
    p = int(line.split("=")[1], 16) if line else 0xFF
    check("Reloc: C clear (the image whole)", line and not p & 1, line)
    got = open(back, "rb").read()[:len(expect)] if os.path.exists(back) else b""
    diff = [i for i in range(min(len(got), len(expect))) if got[i] != expect[i]]
    check("the banks as sysreloc.py relocates the image (%d bytes)" % len(expect),
          len(got) == len(expect) and not diff,
          ["%d/%d+%d: %02x want %02x" % (i // 65536 + 1, i // 256 % 256, i % 256, got[i], expect[i])
           for i in diff[:6]])
    print("f1reloc: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
