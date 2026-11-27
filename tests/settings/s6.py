#!/usr/bin/env python3
"""GeoUltra Settings in VICE: the REU page (S6; the user's decisions of
2026-11-14; preu.s): the 16 x 16 grid of banks (system dark grey, the
engine orange, the legacy area yellow, the part not in use hatched:
dark grey on yellow, free white), the steppers from the defaults (4
slots, 512 KB, a 1 MB print queue in the legacy area the slots leave,
since 0.9.1): Legacy [+] to 1 MB (legacy=1024) and back (legacy= out),
Tasks [+] to 8 (the legacy area full: the queue at its two banks), back
to 4 (the queue at 242-255), the queue to 2 MB and back (spool= out).
VICE's drives are no REU drives: none on the map. Screens:
build/harness/gush/settings-s6*.png.
Usage: tests/settings/s6.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_THEME, PAGE_REU = 0, 5
GRID_ROW, GRID_CARD = 2, 12
STEP_Y = 156
SIZE_DN, SIZE_UP = (140 + 7, STEP_Y - 3), (200 + 7, STEP_Y - 3)
TASKS_UP = (286 + 7, 170 - 3)          # (the second row)
TASKS_DN = (256 + 7, 170 - 3)          # (TASKS_MINUS_X, preu.s)
STEP2_Y = 170
SPOOL_DN, SPOOL_UP = (140 + 7, STEP2_Y - 3), (200 + 7, STEP2_Y - 3)
SIDE_TOP, SIDE_ROW = 16, 16           # (settings.inc; from 16 since 2026-11-19)
THEME_Y, PART_Y, STYLE_Y = 36, 54, 72
SWATCH_X, INK_Y, PAPER_Y = 152, 83, 99
USE_XY, COPY_XY = (268, THEME_Y - 3), (302, THEME_Y - 3)
THEME_DN, PART_UP = (156, THEME_Y - 3), (242, PART_Y - 3)
NO_XY = (160 + 64, 110)
OK_XY = (90, 110)
COLOR_MATRIX = 0x8C00


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
    g = Gush("settings-s6", 6732, [])
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
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
        v.resume()
        settle(t)

    def ini():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

    def theme_text():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["themeText"], s["themeText"] + n - 1)) if n else b""

    def settings_text():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)       # (SETTINGS.INI's text in use)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["iniText"], s["iniText"] + n - 1)) if n else b""

    def cell(row, col):
        return v.mem_get(COLOR_MATRIX + row * 40 + col, COLOR_MATRIX + row * 40 + col)[0]

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
        call(k["Settings"], 0, t=8)
        press(20, SIDE_TOP + PAGE_REU * SIDE_ROW + 7, t=6)

        def bank(n):
            return cell(GRID_ROW + n // 16, GRID_CARD + n % 16)
        check("the REU page", sbyte("page"), PAGE_REU)
        check("banks: system, free, engine, legacy in use, not in use (512 KB x 4: 224-255 hatched)",
              (bank(0), bank(100), bank(188), bank(223), bank(224)), (0xBB, 0x11, 0x88, 0x77, 0xB7))
        g.png("settings-s6")
        press(*SIZE_UP, t=4)
        check("Legacy [+]: 1 MB, still 4 slots (legacy=1024; tasks= the default, out)", settings_text(),
              b"[system]\r\nlegacy=1024\r\n")
        press(*SIZE_DN, t=4)
        check("Legacy [-]: 512 KB again (legacy= out), 4 slots: banks 224-255 not in use (hatched)",
              (settings_text(), bank(223), bank(224)), (b"[system]\r\n", 0x77, 0xB7))
        g.png("settings-s6-hatched")
        for _ in range(4):
            press(*TASKS_UP, t=3)
        check("Tasks [+] to 8: tasks=8, all of the legacy area in use", (settings_text(), bank(255)),
              (b"[system]\r\ntasks=8\r\n", 0x77))
        check("8 tasks fill the legacy area: the queue only 27-28 (no room left); 179 a drive's",
              (bank(27), bank(28), bank(179), bank(255)), (0xEE, 0xEE, 0x11, 0x77))
        for _ in range(4):                                          # back to 4 tasks
            press(*TASKS_DN, t=3)
        check("4 tasks: the default 1 MB queue in the legacy area they leave (242-255)",
              (settings_text(), bank(223), bank(241), bank(242), bank(255), bank(179)),
              (b"[system]\r\n", 0x77, 0xB7, 0xEE, 0xEE, 0x11))
        press(*SPOOL_UP, t=3)
        check("Spooler [+]: 2 MB (spool=2048), banks 226-255, the drives' banks untouched",
              (settings_text(), bank(225), bank(226), bank(179)),
              (b"[system]\r\nspool=2048\r\n", 0xB7, 0xEE, 0x11))
        g.png("settings-s6-spool")
        press(*SPOOL_DN, t=3)
        check("Spooler [-]: 1 MB, the default (spool= out)", settings_text(), b"[system]\r\n")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
