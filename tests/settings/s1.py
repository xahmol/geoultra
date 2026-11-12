#!/usr/bin/env python3
"""GeoUltra Settings in VICE, step S1 (docs/SETTINGS.md): started from
the desktop's Settings routine (as geos > settings and the toolbar run
it), the frame on the Desktop page; a page name switches pages; clicks
on the Desktop page's options set keys in the INI text (VICE has no
Ultimate: the text starts empty and nothing is written), checked byte
for byte; Cancel asks first when something changed, and Yes goes back
to the desktop. Screens: build/harness/gush/settings-s1*.png.
Usage: tests/settings/s1.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_DESKTOP, PAGE_SYSTEM = 1, 2
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
    g = Gush("settings-s1", 6683, [])
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
        desk_start = bytes(v.mem_get(0x0400, 0x040F))
        call(k["Settings"], 0, t=8)
        check("started from the desktop: the Desktop page", sbyte("page"), PAGE_DESKTOP)
        check("no Ultimate: nothing to write, an empty text", (sbyte("noFile"), ini()), (1, b""))
        g.png("settings-s1")
        press(20, SIDE_TOP + PAGE_SYSTEM * SIDE_ROW + 7)
        check("a click on System: that page", sbyte("page"), PAGE_SYSTEM)
        g.png("settings-s1-system")
        press(20, SIDE_TOP + PAGE_DESKTOP * SIDE_ROW + 7)
        check("and back on Desktop", sbyte("page"), PAGE_DESKTOP)
        press(X2 + 3, Y0 + DY - 3)                          # view: icons
        check("view: icons chosen, marked changed", (sbyte("sel", 1), sbyte("dirty")), (1, 1))
        check("the INI text: [desktop] view=icons", ini(), b"[desktop]\r\nview=icons\r\n")
        press(X2 + 14 + 3, Y0 - 3)                          # start with: GEOS 2.0's
        check("start with GEOS 2.0's: [system] desktop=geos added", ini(),
              b"[desktop]\r\nview=icons\r\n[system]\r\ndesktop=geos\r\n")
        press(X1 + 3, Y0 + 4 * DY - 3)                      # panes: one list (in force)
        check("a click on the option in force: no change", ini(),
              b"[desktop]\r\nview=icons\r\n[system]\r\ndesktop=geos\r\n")
        press(X1 + 3, Y0 + DY - 3)                          # view: list again
        check("view: list again (replaced)", ini(), b"[desktop]\r\nview=list\r\n[system]\r\ndesktop=geos\r\n")
        g.png("settings-s1-chosen")
        press(*CANCEL_XY)
        g.png("settings-s1-cancel")
        press(*YES_XY, t=10)
        check("Cancel, Yes: back in the desktop", bytes(v.mem_get(0x0400, 0x040F)), desk_start)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
