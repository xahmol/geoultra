#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the context menu on a font (ctxmenu.s,
fontact.s; docs/DESIGN.md "System font folder"). Drive B gets a GU font
(build/fonts/guserif.cvt); the desktop in /b, the cursor on it, the
context menu: IsPrinter marks it a font (isFont $80, outside /f: item 1
"install as system font"; the screen shows the box wide enough for
it, BOX_W 112). Screen: build/harness/gush/desktop-d33-ctx.png.
Usage: tests/desktop/d33.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

FONT = os.path.join(ROOT, "build", "fonts", "guserif.cvt")


def main():
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d33", 6733, [FONT])
    check, v = g.check, g.v

    def settle(s):
        time.sleep(s)
        v.ping()

    def call(routine, a=0, x=0, s=3):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0xA2, x, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    try:
        fe = kern["ExtTable"] + 30                          # FE_CD /b, the desktop
        start = harness.TRAMPOLINE
        nm, desk = 0x4F00, 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, nm & 0xFF, 0x85, 0x02, 0xA9, nm >> 8, 0x85, 0x03,
                0xA9, 11, 0x20, fe & 0xFF, fe >> 8,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8]
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.resume()
        settle(5)
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        v.mem_set(start, bytes(code))
        v.mem_set(nm, b"/b\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)
        at = None
        for i in range(word("count")):
            call(k["Fetch"], i & 0xFF, i >> 8, s=0.6)
            if bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0] == b"GU Serif":
                at = i
        check("the font in /b", at is not None, True)
        v.mem_set(k["cur"], bytes([at or 0, 0]))
        v.mem_set(0x3A, bytes([200, 0, 60]))
        call(k["Popup"], 0, s=3)
        g.png("desktop-d33-ctx")
        check("IsPrinter: a font, outside /f", v.mem_get(k["isFont"], k["isFont"])[0], 0x80)
    finally:
        g.stop()
    print("d33: %s" % ("all passed" if g.ok else "FAILED"))
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
