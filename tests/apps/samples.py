#!/usr/bin/env python3
"""The sample documents (make samples) in geoWrite 2.1 on GeoUltra in VICE.

Drive A is build/samples/geoultra-samples.d81 (a copy), drive B a native
image with geoWrite 2.1 in /Writing, taken from the user's GEOS 2.0 disk
(GEOS_ORACLE81, never committed; skipped without it). The serial that
disk's GEOBOOT holds goes to the kernal as [serials] geoWrite=... (as
Settings does on Save, FE_SERIALS), then the desktop opens each document
with RETURN: geoWrite must run with it as its document (dataFileName).
Without the serial geoWrite refuses ("Please reboot your system ...");
after its OK the desktop asks "geoWrite refused to run ... Set it in
Settings?" (serials.s module 127, pickup.s Refused). Screens:
build/harness/gush/samples-*.png; look at them for the layout.
Usage: tests/apps/samples.py
"""
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import harness  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

SAMPLES = os.path.join(ROOT, "build", "samples", "geoultra-samples.d81")
OUT = os.path.join(ROOT, "build", "harness", "gush")
DOCS = (("Brochure", 1), ("Letter", 3), ("Quick start", 4))   # rows after ".."
KEY_DOWN, KEY_HOME, CR = 17, 18, 13
DATA_FILE_NAME = 0x8442          # dataFileName (geos.inc)
SERIAL_AT = (82, 183)           # GEOBOOT: its 83rd block, offset (mount.s)


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def boot_serial(d81):
    """The serial in GEOBOOT of a D81 (the kernal's way)."""
    d = open(d81, "rb").read()
    blk = lambda t, s: d[((t - 1) * 40 + s) * 256:((t - 1) * 40 + s) * 256 + 256]
    t, s = 40, 3
    while t:
        b = blk(t, s)
        for i in range(8):
            e = b[i * 32:i * 32 + 32]
            if e[5:21].rstrip(b"\xa0") == b"GEOBOOT":
                ft, fs = e[3], e[4]
                for _ in range(SERIAL_AT[0]):
                    x = blk(ft, fs)
                    ft, fs = x[0], x[1]
                x = blk(ft, fs)
                return x[SERIAL_AT[1]] | x[SERIAL_AT[1] + 1] << 8
        t, s = b[0], b[1]
    return None


def main():
    harness.use_disk_set("d81")
    if not os.path.exists(harness.ORACLE_DISK) or not os.path.exists(SAMPLES):
        print("samples: skipped (needs GEOS_ORACLE81 and make samples)")
        sys.exit(0)
    serial = boot_serial(harness.ORACLE_DISK)
    os.makedirs(OUT, exist_ok=True)
    a = os.path.join(OUT, "samples-a.d81")
    toml = os.path.join(OUT, "samples-b.toml")
    open(toml, "w").write('[dnp]\nout = "samples-b.dnp"\nname = "Writing"\nid = "WR"\ntracks = 8\n'
                          'strict = true\n\n[sources]\ng = "%s"\n\n[[folder]]\npath = "Writing"\n'
                          'files = ["g:GEOWRITE"]\n' % harness.ORACLE_DISK)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "mkappsdnp.py"), toml], cwd=OUT,
                   check=True, capture_output=True)
    k = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    from gushvice import Gush
    ok = True
    for name, row in DOCS + (("Brochure", None),):
        keyed = row is not None
        row = row if keyed else DOCS[0][1]
        shutil.copy(SAMPLES, a)
        os.environ["APPRUN_DRIVE_A"] = a
        tag = name.lower().replace(" ", "") + ("" if keyed else "-nokey")
        g = Gush("samples-" + tag, 6643, disk=os.path.join(OUT, "samples-b.dnp"))
        v = g.v
        try:
            if keyed:                               # up to MainLoop, [serials], back
                v.resume()
                time.sleep(6)
                v.ping()
                jt = v.mem_get(0xC1C3, 0xC1C5)
                cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
                v.resume()
                v.wait_event(RESP_CHECKPOINT)
                v.delete_checkpoint(cid)
                before, port = v.regs_get(), v.mem_get(1, 1)
                text = b"[serials]\r\ngeoWrite=%04X\r\n" % serial
                at, fe = 0x4E00, k["ExtTable"] + 30
                v.mem_set(at, text)
                code = [0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, at & 0xFF, 0x85, 0x02, 0xA9, at >> 8, 0x85, 0x03,
                        0xA9, len(text), 0x85, 0x04, 0xA9, 0, 0x85, 0x05, 0xA9, 36, 0x20, fe & 0xFF, fe >> 8]
                start = harness.TRAMPOLINE
                end = start + len(code)
                v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
                cid = v.checkpoint(end, temporary=False)
                v.regs_set({"PC": start})
                v.resume()
                v.wait_event(RESP_CHECKPOINT)
                v.delete_checkpoint(cid)
                v.mem_set(1, bytes(port))
                v.regs_set({r: before[r] for r in ("PC", "A", "X", "Y", "SP", "FL") if r in before})
            g.check("the desktop started", g.runsys("GeoUltra Desktop", wait=6), None)
            g.keys([KEY_HOME, CR], settle=1)        # "/": a first
            time.sleep(4)
            g.keys([KEY_HOME] + [KEY_DOWN] * row, settle=0.2)
            g.keys([CR], settle=1)
            time.sleep(30)
            v.ping()
            g.png("samples-" + tag)
            if keyed:
                got = bytes(v.mem_get(DATA_FILE_NAME, DATA_FILE_NAME + 16)).split(b"\0")[0]
                g.check("geoWrite runs with " + name, got.decode("latin1"), name)
            else:
                g.keys([CR], settle=1)              # geoWrite's refusal: OK
                time.sleep(12)
                v.ping()
                g.png("samples-refusal")
                d = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
                cls = bytes(v.mem_get(d["refCls"], d["refCls"] + 12)).split(b"\0")[0].rstrip()
                g.check("refused: the desktop asks about geoWrite (samples-refusal.png)", cls, b"geoWrite")
        finally:
            g.stop()
        ok = ok and g.ok
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
