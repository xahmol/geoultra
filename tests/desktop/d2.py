#!/usr/bin/env python3
"""GeoUltra's desktop in VICE, step D2 (docs/DESKTOP.md): the list. Drive
B holds 40 files more than gush's test disk; the engine's current folder
is set to /b before the desktop starts. Checked from its memory: all
entries read (count), the cursor keys move the cursor and the window
(top), C= with a cursor key extends the selection, a click selects the
entry under it alone, a click in the strip below the thumb pages down.
Screens: build/harness/gush/desktop-d2*.png.
Usage: tests/desktop/d2.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

KEY_DOWN, KEY_UP, KEY_HOME = 17, 16, 18
FILES = 40
ROWS, LIST_TOP, ROW_H = 17, 28, 9


def labels(name):
    out = {}
    for line in open(os.path.join(ROOT, "build", name)):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for i in range(FILES):
        path = os.path.join(OUT, "f%02d" % i)
        open(path, "wb").write(b"x\r")
        files.append(path)
    k = labels("desktop/desktop.lbl")
    kern = labels("kernal64.lbl")
    g = Gush("desktop-d2", 6635, files)
    check = g.check
    v = g.v

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def press(x, y):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        time.sleep(2)
        v.ping()
    try:
        v.resume()                                          # up to MainLoop
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        fe = kern["ExtTable"] + 30                          # FE_CD /b, then
        start = harness.TRAMPOLINE                          # FE_RUNSYS the desktop
        name, desk = 0x4F00, 0x4F10
        code = [0x78, 0xA9, 0x30, 0x85, 0x01,
                0xA9, name & 0xFF, 0x85, 0x02, 0xA9, name >> 8, 0x85, 0x03,
                0xA9, 11, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF0, 0x02,
                0xA9, desk & 0xFF, 0x85, 0x02, 0xA9, desk >> 8, 0x85, 0x03,
                0xA9, 22, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF1, 0x02]
        end = start + len(code)
        code += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(start, bytes(code))
        v.mem_set(name, b"/b\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.mem_set(0x02F0, b"\xEE\xEE")
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(8)
        v.ping()
        check("FE_CD /b, then the desktop started (FE_RUNSYS no return)",
              bytes(v.mem_get(0x02F0, 0x02F1)), b"\x00\xEE")
        check("all entries of /b read (gush and the files)", word("count"), FILES + 1)
        g.png("desktop-d2")
        g.keys([KEY_DOWN] * 20, settle=0.3)
        time.sleep(2)
        v.ping()
        check("20 times down: the cursor at 20, the window follows",
              (word("cur"), word("top")), (20, 20 - ROWS + 1))
        g.keys([0x80 | KEY_DOWN] * 2, settle=0.5)           # C= + down: extend
        time.sleep(1)
        v.ping()
        sel = bytes(v.mem_get(k["sel"], k["sel"] + 3))
        check("C= + down twice: entries 20-22 selected", sel[2] & 0x70, 0x70)
        g.keys([KEY_HOME], settle=1)
        press(150, LIST_TOP + 3 * ROW_H + 4)                # row 3
        sel = bytes(v.mem_get(k["sel"], k["sel"] + 5))
        check("a click on row 3: entry 3 alone selected, the cursor there",
              (sel, word("cur")), (bytes([0x08, 0, 0, 0, 0, 0]), 3))
        press(315, LIST_TOP + ROWS * ROW_H - 4)             # strip, at its bottom
        check("a click in the strip below the thumb: a page down", word("top"), ROWS)
        g.png("desktop-d2-paged")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
