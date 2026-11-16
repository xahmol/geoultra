#!/usr/bin/env python3
"""GeoUltra Settings in VICE: the Printing page (S8; docs/DESIGN.md
"Printing", the user's decisions of 2026-11-16; pprint.s): its name the
ninth in the side list; the printer row with GU Epson FX-80 in force
(no printer= yet), the note, "In use:" and the printer the desktop set
(PrntFilename); a click on Commodore MPS: [desktop] printer=GU Commodore
MPS in the settings' text, the row following. Screens:
build/harness/gush/settings-s8*.png.
Usage: tests/settings/s8.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_PRINT = 8
SIDE_TOP, SIDE_ROW = 24, 16
ROW_Y = 16 + 20                 # the row's baseline (PAGE_TOP + 20)
MPS_XY = (205 + 3, ROW_Y - 3)   # Commodore MPS's box


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
    g = Gush("settings-s8", 6743, [])
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
        press(20, SIDE_TOP + PAGE_PRINT * SIDE_ROW + 7, t=6)
        check("the Printing page", v.mem_get(s["page"], s["page"])[0], PAGE_PRINT)
        check("the printer in force: Epson FX-80 (none in the settings)", v.mem_get(s["sel"], s["sel"])[0], 0)
        check("in use: what the desktop set", bytes(v.mem_get(0x8465, 0x8472)), b"GU Epson FX-80")
        g.png("settings-s8")
        press(*MPS_XY, t=4)
        check("Commodore MPS: [desktop] printer=GU Commodore MPS", settings_text(),
              b"[desktop]\r\nprinter=GU Commodore MPS\r\n")
        check("the row follows", v.mem_get(s["sel"], s["sel"])[0], 1)
        g.png("settings-s8-mps")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
