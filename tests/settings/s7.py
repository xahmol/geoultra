#!/usr/bin/env python3
"""GeoUltra Settings in VICE: the Start page (the cold start's auto-exec
files; the user's decisions of 2026-11-14; pstart.s, overlay 8). Two
AUTO_EXEC files (GUAUTO1, GUAUTO2, tests/engine/autou64.py's) on drive
B. add: the browser at "/" (the drives), into b, GUAUTO2 chosen twice:
autoexec=/b/GUAUTO2 in SETTINGS.INI; add GUAUTO1 the same way: a second
line; the second selected, up: the order swapped (the selection follows it); removed: one line
left. Screens: build/harness/gush/settings-s7*.png.
Usage: tests/settings/s7.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_THEME, PAGE_REU, PAGE_START = 0, 5, 7
LIST_TOP, ROW_H, BTN_Y = 42, 11, 157
ADD_XY, REMOVE_XY, UP_XY = (106, BTN_Y + 5), (142, BTN_Y + 5), (192, BTN_Y + 5)
GRID_ROW, GRID_CARD = 3, 12
STEP_Y = 156
SIZE_DN, SIZE_UP = (140 + 7, STEP_Y - 3), (200 + 7, STEP_Y - 3)
TASKS_UP = (286 + 7, 170 - 3)          # (the second row)
SIDE_TOP, SIDE_ROW = 24, 16
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
    import subprocess
    sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
    import autou64
    files = [autou64.make_cvt(1), autou64.make_cvt(2)]
    o = {}
    for line in open(os.path.join(ROOT, "build", "settings", "settings.lbl")):
        p = line.split()
        a = int(p[1], 16)
        if 0x5000 <= a < 0x6000:
            o.setdefault(p[2].lstrip("."), a)
    g = Gush("settings-s7", 6734, files)
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
        press(20, SIDE_TOP + PAGE_START * SIDE_ROW + 7, t=6)
        check("the Start page: an empty list", (sbyte("page"), settings_text()), (PAGE_START, b""))
        g.png("settings-s7")

        def entries():
            n = v.mem_get(o["bcount"], o["bcount"])[0]
            raw = bytes(v.mem_get(s["names"], s["names"] + n * 48 - 1)) if n else b""
            return [raw[i * 48:(i + 1) * 48].split(b"\0")[0].decode("latin1") for i in range(n)]

        def choose(name):
            i = [e.lower() for e in entries()].index(name.lower())
            y = LIST_TOP + 1 + i * ROW_H + 5
            press(120, y, t=3)
            press(120, y, t=5)

        def add(name):
            press(*ADD_XY, t=5)
            choose("b")
            choose(name)
        add("GUAUTO2")
        check("added: autoexec=/b/GUAUTO2", settings_text(), b"[system]\r\nautoexec=/b/GUAUTO2\r\n")
        add("GUAUTO1")
        check("a second one after it", settings_text(),
              b"[system]\r\nautoexec=/b/GUAUTO2\r\nautoexec=/b/GUAUTO1\r\n")
        g.png("settings-s7-list")
        press(120, LIST_TOP + 1 + ROW_H + 5, t=3)           # the second selected
        press(*UP_XY, t=5)
        check("up: the order swapped", settings_text(),
              b"[system]\r\nautoexec=/b/GUAUTO1\r\nautoexec=/b/GUAUTO2\r\n")
        press(*REMOVE_XY, t=5)                              # (the selection followed it)
        check("remove: one line left", settings_text(), b"[system]\r\nautoexec=/b/GUAUTO2\r\n")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
