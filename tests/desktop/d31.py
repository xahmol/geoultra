#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the system fonts (docs/DESIGN.md "System
font folder", step F; the user's choice of 2026-11-19): a FONTS.DNP with
"F Roma" (Roma from GEOS_APPS_DISK, the user's own, renamed) relocated
with tools/sysreloc.py and put into REU banks 180-187, fontsOn set, the
desktop started in /e. Checks: the list of /e starts "..", "installed
fonts" (list.s FontsEntry, kept there by the sort); opening that entry
goes to /f, which lists F Roma (open.s); go > system fonts (Fonts) does
the same from elsewhere; without the fonts (fontsOn 0) /e has no such
entry.
Usage: tests/desktop/d31.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

APPS = os.environ.get("GEOS_APPS_DISK", os.path.expanduser("~/geos-dev/u64-usb/neos-mouse-driver-for-geos.d64"))
GD = [sys.executable, os.path.join(ROOT, "tools", "geosdisk.py")]


def main():
    os.makedirs(OUT, exist_ok=True)
    img = os.path.join(OUT, "D31FONTS.DNP")
    if os.path.exists(img):
        os.remove(img)
    subprocess.run(GD + ["new", img, "--tracks=8", "--name=System fonts"], check=True, capture_output=True)
    subprocess.run(GD + ["add", img, APPS + ":Roma"], check=True, capture_output=True)
    subprocess.run(GD + ["rename", img, "Roma", "F Roma"], check=True, capture_output=True)
    rel = os.path.join(OUT, "D31FONTS-reloc.dnp")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "sysreloc.py"), img, rel, "237", "8"],
                   check=True, capture_output=True)
    fonts = open(rel, "rb").read()
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d31", 6731)
    check = g.check
    v = g.v

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):
        time.sleep(s)
        v.ping()

    def run(code):
        code = [0x78, 0xA9, 0x30, 0x85, 0x01] + code
        start = harness.TRAMPOLINE
        end = start + len(code)
        v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
        cp = v.checkpoint(end, temporary=False)
        v.regs_set({"PC": start})
        v.events.clear()
        v.resume()
        v.wait_event(RESP_CHECKPOINT, 60)
        v.delete_checkpoint(cp)

    def call(routine, a=0, s=6):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def names():
        out = []
        tick, fetch = k["ClockTick"], k["Fetch"]
        for i in range(min(word("count"), 6)):
            v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                       0x84, 0xA9, i & 0xFF, 0xA2, i >> 8, 0x4C, fetch & 0xFF, fetch >> 8]))
            v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            v.resume()
            settle(0.6)
            out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0].decode("latin1"))
        return out

    def path():
        return bytes(v.mem_get(k["path"], k["path"] + 20)).split(b"\0")[0].decode("latin1")

    try:
        v.resume()
        settle(5)
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        sysop = kern["SysRAMOp"]
        for n in range(len(fonts) // 4096):                 # the fonts into banks 180 on
            v.mem_set(0x5000, fonts[n * 4096:(n + 1) * 4096])
            run([0xA9, 0, 0x85, 0x02, 0xA9, 0x50, 0x85, 0x03, 0xA9, 0, 0x85, 0x04, 0xA9, (n % 16) * 16, 0x85, 0x05,
                 0xA9, 0, 0x85, 0x06, 0xA9, 0x10, 0x85, 0x07, 0xA9, 180 + n // 16, 0x85, 0x08, 0xA0, 0x90,
                 0x20, sysop & 0xFF, sysop >> 8])
        v.mem_set(kern["fontsOn"], b"\x80")
        fe = kern["ExtTable"] + 30                          # FE_CD /e, the desktop
        nm, desk = 0x4F00, 0x4F10
        v.mem_set(nm, b"/e\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        start = harness.TRAMPOLINE
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, nm & 0xFF, 0x85, 0x02, 0xA9, nm >> 8, 0x85, 0x03,
                0xA9, 11, 0x20, fe & 0xFF, fe >> 8,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8]
        end = start + len(code)
        v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
        v.regs_set({"PC": start})
        v.resume()
        settle(10)
        lst = names()
        check("/e: \"..\", then \"installed fonts\"", (path(), lst[:2]), ("/e", ["..", "installed fonts"]))
        g.png("desktop-d31-e")
        v.mem_set(k["cur"], bytes([1, 0]))                  # open it
        call(k["Open"], s=8)
        check("opened: /f, F Roma in it", (path(), "F Roma" in names()), ("/f", True))
        g.png("desktop-d31-f")
        v.mem_set(nm, b"/b\0")                              # go > system fonts from /b
        v.mem_set(k["path"], b"/b\0")
        call(k["Fonts"], s=8)
        check("go > system fonts: /f", path(), "/f")
        v.mem_set(kern["fontsOn"], b"\x00")                 # no fonts: no entry in /e
        call(k["Root"], s=6)
        v.mem_set(k["path"], b"/\0")
        v.mem_set(nm, b"/e\0")
        tick = k["ClockTick"]
        into = k["Into"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C, 0x84,
                                   0xA9, nm & 0xFF, 0xA2, nm >> 8, 0x4C, into & 0xFF, into >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(8)
        check("fontsOn 0: /e without the entry", (path(), "installed fonts" in names()), ("/e", False))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
