#!/usr/bin/env python3
"""GeoUltra Settings in VICE: the Serials page (pser.s; docs/DESIGN.md
"Serial number", step S3; the user's decisions of 2026-11-19), the
tenth page in the side list (from y 16): "fixed" asks for a number
(typed: 12ab): [system] serial=12AB; "GeoUltra": serial=4755 (GeoUltra's own number); the
bypass switched on: the disclaimer (OK), protection=bypass; add: the
class and the number asked (geoWrite, 4321): [serials] geoWrite=4321
and its line in the list; the line selected and removed: gone; from
disk: drive A's GEOS 2.0 boot disk (GEOS_ORACLE: GEOBOOT, serial 58B5)
found, the class asked (geoCalc): geoCalc=58B5. Screens:
build/harness/gush/settings-s9*.png.
Usage: tests/settings/s9.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_PRINT = 8
PAGE_SERIALS = 9
Y0, DY = 16 + 20, 14            # (pser.s: the rows' baselines)
COL2, COL3 = 196, 240
LIST_X, LIST_TOP = 92, 16 + 20 + 3 * 14 + 4 + 3
BTN_X = 252 + 6
DLG_X, DLG_Y = 64, 32
SIDE_TOP, SIDE_ROW = 16, 16           # (settings.inc; from 16 since 2026-11-19)
ROW_Y = 16 + 20                 # the row's baseline (PAGE_TOP + 20)
MPS_XY = (173 + 3, ROW_Y - 3)   # MPS's box
PDF_XY = (255 + 3, ROW_Y - 3)   # PDF Letter's box
FAST_XY = (208 + 3, ROW_Y + 14 - 3)     # the timing row's "fast"
SYSONLY_XY = (208 + 3, ROW_Y + 28 - 3)  # the fonts row's "system only"


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
    g = Gush("settings-s9", 6744, [])
    check = g.check
    v = g.v

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
        time.sleep(0.5)
        v.ping()
        v.mem_set(0x8505, b"\x80")
        v.resume()
        settle(t)

    def settings_text():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

    try:
        fe = kern["ExtTable"] + 30                          # the desktop, as s6
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
        v.mem_set(0x8465, bytes(17))
        v.mem_set(start, bytes(code))
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)
        call(k["Settings"], 0, t=8)
        press(20, SIDE_TOP + PAGE_SERIALS * SIDE_ROW + 7, t=6)
        check("the Serials page (the tenth)", v.mem_get(s["page"], s["page"])[0], PAGE_SERIALS)
        g.png("settings-s9")
        press(COL2 + 3, Y0 - 3, t=3)                        # fixed: a number asked
        g.png("settings-s9-ask")
        g.queue("12ab\r", settle=3)
        check("fixed: [system] serial=12AB", b"serial=12AB\r\n" in settings_text(), True)
        press(COL3 + 3, Y0 - 3, t=4)                        # GeoUltra
        check("GeoUltra: serial=4755 (its own number)", b"serial=4755\r\n" in settings_text(), True)
        press(COL2 + 3, Y0 + 2 * DY - 3, t=3)               # the bypass on: the disclaimer
        g.png("settings-s9-disc")
        press(DLG_X + 17 * 8 + 20, DLG_Y + 72 + 8, t=3)     # its OK
        check("bypass on: protection=bypass", b"protection=bypass\r\n" in settings_text(), True)
        press(BTN_X + 10, LIST_TOP + 9, t=3)                # add: the class, the number
        g.png("settings-s9-add1")
        g.queue("geoWrite\r", settle=3)
        g.png("settings-s9-add2")
        g.queue("4321\r", settle=3)
        g.png("settings-s9-added")
        check("add: [serials] geoWrite=4321", b"[serials]\r\ngeoWrite=4321\r\n" in settings_text(), True)
        press(LIST_X + 20, LIST_TOP + 6, t=3)               # its line selected, removed
        press(BTN_X + 10, LIST_TOP + 25, t=3)
        check("removed: no geoWrite line", b"geoWrite=" in settings_text(), False)
        press(BTN_X + 10, LIST_TOP + 41, t=12)              # from disk: drive A's GEOBOOT
        g.png("settings-s9-disk")
        g.queue("geoCalc\r", settle=4)
        check("from disk: [serials] geoCalc=58B5 (the GEOS disk on A)",
              b"geoCalc=58B5\r\n" in settings_text(), True)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
