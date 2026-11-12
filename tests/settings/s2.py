#!/usr/bin/env python3
"""GeoUltra Settings in VICE, step S2 (docs/SETTINGS.md): the Pointer
page. Started from the desktop as in s1.py; a click on a design sets
[system] pointer= in the INI text and applies it at once (FE_POINTER,
the kernal's module 86): sprite 0's picture is the design's
(build/gen/pointers.inc) and PosPointer's offsets are 24 and 50 less its
hot spot; DrawSprite on sprite 0 (an application's own pointer) puts
the offsets back to 24 and 50; the classic arrow again. Screens:
build/harness/gush/settings-s2*.png.
Usage: tests/settings/s2.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_DESKTOP, PAGE_POINTER = 1, 5
X0, STEP = 90 + 10, 56
SIDE_TOP, SIDE_ROW = 20, 14
Y0, DY, X1, X2 = 16 + 20, 18, 150, 212
CANCEL_XY = (27 * 8 + 24, 188)
YES_XY = (90, 110)


def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    k = labels(os.path.join(ROOT, "build", "desktop", "desktop.lbl"))
    s = labels(os.path.join(ROOT, "build", "settings", "settings.lbl"))
    kern = labels(os.path.join(ROOT, "build", "kernal64.lbl"))
    g = Gush("settings-s2", 6691, [])
    check = g.check
    v = g.v

    def sbyte(name, off=0):
        return v.mem_get(s[name] + off, s[name] + off)[0]

    def settle(t=3):
        time.sleep(t)
        v.ping()

    def call(routine, a, t=6):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(t)

    def press(x, y, t=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(t)

    def ini():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

    def designs():
        import re
        t = open(os.path.join(ROOT, "build", "gen", "pointers.inc")).read()
        data = bytes(int(v, 16) for v in re.findall(r"\$([0-9A-F]{2})", t.split("PointerHot:")[0]))
        hots = [tuple(map(int, m)) for m in re.findall(r"\.byte (\d+), (\d+)", t.split("PointerHot:")[1])]
        return [data[i * 63:i * 63 + 63] for i in range(4)], hots

    pics, hots = designs()

    def sprite():
        return bytes(v.mem_get(0x8A00, 0x8A00 + 62))

    def offsets():
        return (v.mem_get(kern["PtrDX"], kern["PtrDX"])[0], v.mem_get(kern["PtrDY"], kern["PtrDY"])[0])

    try:
        fe = kern["ExtTable"] + 30                          # the desktop, as d13
        start = harness.TRAMPOLINE
        desk = 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
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
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)
        check("at the start: the classic arrow, offsets 24, 50", (sprite() == pics[0], offsets()), (True, (24, 50)))
        call(k["Settings"], 0, t=8)
        press(20, SIDE_TOP + PAGE_POINTER * SIDE_ROW + 7)
        check("the Pointer page", sbyte("page"), PAGE_POINTER)
        g.png("settings-s2")
        press(X0 + 2 * STEP + 3, Y0 - 3, t=5)              # hand
        check("hand: [system] pointer=2", ini(), b"[system]\r\npointer=2\r\n")
        check("hand: sprite 0 its picture, offsets less its hot spot",
              (sprite() == pics[2], offsets()), (True, (24 - hots[2][0], 50 - hots[2][1])))
        press(X0 + 3 * STEP + 3, Y0 - 3, t=5)              # crosshair
        check("crosshair: pointer=3, its picture and hot spot 7, 7",
              (ini(), sprite() == pics[3], offsets()),
              (b"[system]\r\npointer=3\r\n", True, (24 - 7, 50 - 7)))
        g.png("settings-s2-cross")
        start2 = 0x4F40                                     # an application's own
        ds = [0x78, 0xA9, 0x30, 0x85, 0x01,                 # pointer: DrawSprite
              0xA9, 0, 0x85, 0x08,                          # (sprite 0, its own
              0xA9, 0x00, 0x85, 0x0A, 0xA9, 0x8A, 0x85, 0x0B,   # picture again)
              0x20, 0xC6, 0xC1]
        end2 = start2 + len(ds)
        ds += [0x4C, end2 & 0xFF, end2 >> 8]
        regs = v.regs_get()
        v.mem_set(start2, bytes(ds))
        v.regs_set({"PC": start2})
        v.checkpoint(end2)
        v.resume()
        v.wait_event(RESP_CHECKPOINT, timeout=30)
        check("DrawSprite on sprite 0: the offsets back to 24, 50", offsets(), (24, 50))
        v.regs_set({"PC": regs["PC"], "SP": regs["SP"], "A": regs["A"], "X": regs["X"], "Y": regs["Y"],
                    "FL": regs["FL"]})
        press(X0 + 3, Y0 - 3, t=5)                          # classic
        check("classic again: its picture, offsets 24, 50, pointer=0",
              (sprite() == pics[0], offsets(), ini()), (True, (24, 50), b"[system]\r\npointer=0\r\n"))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
