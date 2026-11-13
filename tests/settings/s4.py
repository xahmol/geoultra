#!/usr/bin/env python3
"""GeoUltra Settings in VICE, step S4.3 (docs/SETTINGS.md): the Theme
page, the theme editor. VICE has no theme files: the page edits an
empty text named after SETTINGS.INI's theme (none: GeoUltra). The
border's paper, the desk's ink and paper, the menu bar's style set by
clicks, each line checked in the theme's text in the file's words; the
preview's colour cells; "use" (SETTINGS.INI theme=); "copy" to a new
name (name= in its text, two themes listed); going back to the first
theme asks to save the changes (No: dropped); the palette part (S4.4):
a colour chosen, its red a step up (palette= with all 16), none.
Screens: build/harness/gush/settings-s4*.png.
Usage: tests/settings/s4.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

PAGE_THEME = 0
SIDE_TOP, SIDE_ROW = 20, 14
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
    g = Gush("settings-s4", 6701, [])
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

    def theme_text():
        n = v.mem_get(s["iniLen"], s["iniLen"] + 1)
        n = n[0] | n[1] << 8
        return bytes(v.mem_get(s["themeText"], s["themeText"] + n - 1)) if n else b""

    def settings_text():
        n = sbyte("textLenLo") | sbyte("textLenHi") << 8
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
        press(20, SIDE_TOP + PAGE_THEME * SIDE_ROW + 7, t=6)
        names = bytes(v.mem_get(s["themeNames"], s["themeNames"] + 15)).split(b"\0")[0]
        check("the Theme page: one theme, GeoUltra, the first part (border)",
              (sbyte("page"), sbyte("themeCount"), names, sbyte("themePart")), (PAGE_THEME, 1, b"GeoUltra", 0))
        g.png("settings-s4")
        press(SWATCH_X + 6 * 8 + 3, PAPER_Y, t=3)          # border: blue paper
        check("border: blue (paper only)", theme_text(), b"[theme]\r\nborder=blue\r\n")
        press(*PART_UP, t=3)                                # desk
        press(SWATCH_X + 1 * 8 + 3, INK_Y, t=3)            # ink white
        press(SWATCH_X + 6 * 8 + 3, PAPER_Y, t=3)          # paper blue
        check("desk: white on blue", theme_text(), b"[theme]\r\nborder=blue\r\ndesk=white on blue\r\n")
        press(*PART_UP, t=3)                                # menubar: plain, clock
        x = sbyte("styleXLo", 1) | sbyte("styleXHi", 1) << 8
        press(x + 3, STYLE_Y - 3, t=3)
        check("menubar: clock (the style word before the colours)", theme_text(),
              b"[theme]\r\nborder=blue\r\ndesk=white on blue\r\nmenubar=clock, dark grey on light grey\r\n")
        check("the preview: the menu bar's cells dark grey on light grey, the desk's white on blue",
              (cell(15, 20), cell(19, 30)), (0xBF, 0x16))
        g.png("settings-s4-menubar")
        press(*USE_XY, t=3)
        check("use: SETTINGS.INI [desktop] theme=GeoUltra", settings_text(),
              b"[desktop]\r\ntheme=GeoUltra\r\n")
        press(*COPY_XY, t=4)
        g.keys("Night2\r", settle=0.3)
        settle(3)
        names = bytes(v.mem_get(s["themeNames"] + 16, s["themeNames"] + 31)).split(b"\0")[0]
        check("copy: Night2 listed and shown, name= in its text",
              (sbyte("themeCount"), sbyte("themeNo"), names, theme_text().endswith(b"name=Night2\r\n")),
              (2, 1, b"Night2", True))
        g.png("settings-s4-copy")
        press(*THEME_DN, t=4)                               # back: save first?
        g.png("settings-s4-ask")
        press(*NO_XY, t=4)                                  # No: dropped
        check("back to GeoUltra, the changes dropped (no file: empty)",
              (sbyte("themeNo"), theme_text(), sbyte("themeDirty")), (0, b"", 0))
        # S4.4: the palette part (after the lines; from the first part,
        # [-] wraps to it). VICE: no Ultimate 64, the default palette.
        default = ("000000 F7F7F7 8D2F34 6AD4CD 9835A4 4CB442 2C29B1 EFEF5D "
                   "984E20 5B3800 D1676D 4A4A4A 7B7B7B 9FEF93 6D6AEF B2B2B2").split()
        for _ in range(3):                                  # menubar -> palette
            press(156, PART_Y - 3, t=3)
        check("the palette part", sbyte("themePart"), 14)
        press(SWATCH_X + 6 * 8 + 3, PAPER_Y, t=3)          # blue
        press(118 + 40 + 7, STYLE_Y - 3, t=3)              # R +
        want = default[:]
        want[6] = "3029B1"
        check("blue's red one step up: palette= the 16, blue 3029B1", theme_text(),
              ("[theme]\r\npalette=" + " ".join(want) + "\r\n").encode())
        g.png("settings-s4-palette")
        press(118 + 168 + 16, STYLE_Y - 3, t=3)            # none
        check("none: palette= taken out", theme_text(), b"[theme]\r\n")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
