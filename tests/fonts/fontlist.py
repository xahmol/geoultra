#!/usr/bin/env python3
"""GeoUltra's fonts on drive E in an application's font list, in VICE
(docs/DESIGN.md "Fonts"; src/kernal/sysdrive.s modules 15 and 116):
FindFTypes for fonts from drive B, with room for 15 and for 7 names (as
geoWrite's menu): without fonts on B, drive E's ten GU fonts; with the
user's LW_Roma (font ID 27) on B, LW_Roma first and GU Serif (also ID 27)
left out: one entry per ID, the user's own. geoWrite and LW_Roma come
from the user's GEOS 2.0 disk (GEOS_FONTS_DISK, default
~/geos-dev/u64-usb/GEOS64.D81; never committed).
Usage: tests/fonts/fontlist.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "harness", "fonts")
C1541 = os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")
SRC = os.environ.get("GEOS_FONTS_DISK", os.path.expanduser("~/geos-dev/u64-usb/GEOS64.D81"))
GU = ["GU Serif", "GU Sans", "GU Symbol", "GU Mono", "GU Geometric", "GU Book", "GU Narrow",
      "GU School", "GU Classic", "GU Script"]

HOOK = r'''
import time
jt = harness.jumptab()
def jsr(a):
    a = jt.get(a, a) if isinstance(a, str) else a
    return [0x20, a & 0xFF, a >> 8]
def r(reg, val):
    return [0xA9, val & 0xFF, 0x85, reg, 0xA9, val >> 8, 0x85, reg + 1]
v.ping()
buf = 0x5000
for maxn in (7, 15):
    code = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 9] + jsr("SetDevice") + jsr("OpenDisk")
            + r(0x0E, buf) + [0xA9, 8, 0x85, 0x10, 0xA9, maxn, 0x85, 0x11]
            + [0xA9, 0, 0x85, 0x16, 0x85, 0x17] + jsr("FindFTypes")
            + [0xA5, 0x11, 0x8D, 0xF0, 0x02, 0x58, 0x4C, 0xC3, 0xC1])
    v.mem_set(buf, bytes(17 * 16))
    v.mem_set(0x2F0, b"\xEE")
    v.mem_set(harness.TRAMPOLINE, bytes(code))
    v.regs_set({"PC": harness.TRAMPOLINE})
    v.resume(); time.sleep(12); v.ping()
    left = v.mem_get(0x2F0, 0x2F0)[0]
    n = maxn - left if left <= maxn else -1
    names = [bytes(v.mem_get(buf + 17 * i, buf + 17 * i + 16)).split(b"\0")[0].decode("latin1")
             for i in range(max(n, 0))]
    print("FONTS %d %s" % (maxn, "|".join(names)))
'''


def run(tag, extra):
    disk = os.path.join(OUT, "fonts-%s.d81" % tag)
    if os.path.exists(disk):
        os.remove(disk)
    cmd = [C1541, "-format", "fonts,ft", "d81", disk, "-geoswrite", os.path.join(OUT, "geowrite.cvt")]
    for f in extra:
        cmd += ["-geoswrite", os.path.join(OUT, f)]
    subprocess.run(cmd, check=True, capture_output=True)
    hook = os.path.join(OUT, "hook-fonts.py")
    open(hook, "w").write(HOOK)
    r = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "harness", "apprun.py"), "--wait", "12",
                        "--out", os.path.join(OUT, "fonts-%s.png" % tag), "GEOWRITE", "h:" + hook],
                       env=dict(os.environ, GEOS_APPS_DISK=disk, PYTHONPATH=os.path.join(ROOT, "tools", "harness")),
                       capture_output=True, text=True, timeout=600)
    out = {}
    for line in r.stdout.splitlines():
        if line.startswith("FONTS "):
            _, n, names = line.split(" ", 2)
            out[int(n)] = names.split("|") if names else []
    return out


def vlir_cvt(d81, name, out):
    """A GEOS VLIR file from a D81 image as a CVT (c1541's geosread stops
    early on a font, whose first records are empty): the directory entry,
    the header, the record table (blocks and the last block's bytes + 1
    per record; 00 FF: empty), the records padded to whole blocks."""
    img = open(d81, "rb").read()

    def blk(tr, se):
        o = ((tr - 1) * 40 + se) * 256
        return img[o:o + 256]

    def chain(tr, se):
        data = b""
        while tr:
            b = blk(tr, se)
            data += b[2:] if b[0] else b[2:b[1] + 1]
            tr, se = b[0], b[1]
        return data
    tr, se = 40, 3
    while tr:
        b = blk(tr, se)
        for i in range(8):
            e = b[i * 32:i * 32 + 32]
            if e[2] and e[5:21].rstrip(b"\xa0") == name.encode("latin1"):
                index = blk(e[3], e[4])
                table, data, last = bytearray(254), b"", 0
                for n in range(127):
                    rt, rs = index[2 + 2 * n], index[3 + 2 * n]
                    if rt == 0:
                        table[2 * n:2 * n + 2] = bytes([0, rs])
                        continue
                    rec = chain(rt, rs)
                    k = (len(rec) + 253) // 254
                    table[2 * n:2 * n + 2] = bytes([k, len(rec) - (k - 1) * 254 + 1])
                    data += rec + bytes(k * 254 - len(rec))
                sig = bytearray(254)
                sig[0:30] = e[2:32]
                sig[30:58] = b"PRG formatted GEOS file V1.0"
                open(out, "wb").write(bytes(sig) + blk(e[0x15], e[0x16])[2:] + bytes(table) + data)
                return
        tr, se = b[0], b[1]
    sys.exit("fontlist.py: %s not on %s" % (name, d81))


def main():
    os.makedirs(OUT, exist_ok=True)
    subprocess.run([C1541, SRC, "-geosread", "GEOWRITE", os.path.join(OUT, "geowrite.cvt")],
                   check=True, capture_output=True)
    vlir_cvt(SRC, "LW_Roma", os.path.join(OUT, "lwroma.cvt"))
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    plain = run("plain", [])
    check("no fonts on B, room for 15: drive E's ten", plain.get(15), GU)
    check("no fonts on B, room for 7: E's first seven", plain.get(7), GU[:7])
    lw = run("lw", ["lwroma.cvt"])
    check("LW_Roma on B, room for 15: LW_Roma, E's without GU Serif", lw.get(15), ["LW_Roma"] + GU[1:])
    check("LW_Roma on B, room for 7: no GU Serif", "GU Serif" in (lw.get(7) or ["GU Serif"]), False)
    print("fontlist: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
