#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the icon view (docs/design/DESKTOP.md, "Icon
view"). In /a (GEOS's own files): the grid's layout (5 columns beside
the wide sidebar, 4 rows under the toolbar: 20 cells a page, scrolling
a row of 5), the GEOS files' header icons kept in the REU (their bits
set), a click on a cell selecting its entry, a double click on ".."
opening it; in /b (gush and 30 files: more than a page) the cursor's
row followed a row at a time and the scroll strip's arrow moving a row
of cells; with the narrow sidebar (theme Detailed, then the icon view
again) 6 columns. Screens: build/harness/gush/desktop-d9*.png.
Usage: tests/desktop/d9.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

KEY_DOWN, KEY_HOME = 17, 18
VIEW_LIST, VIEW_ICONS = 0, 1
CELL_W, CELL_H, STRIP_LEFT = 40, 32, 312


def main():
    os.makedirs(OUT, exist_ok=True)
    files = []
    for i in range(30):
        path = os.path.join(OUT, "i%02d" % i)
        open(path, "wb").write(b"file %d\r" % i)
        files.append(path)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d9", 6659, files)
    check = g.check
    v = g.v

    def byte(name):
        return v.mem_get(k[name], k[name])[0]

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):                                # (VICE kept running while
        v.resume()                                  # waiting, as in d13: a
        time.sleep(s)                               # stopped one failed the
        v.ping()                                    # paging checks at times)

    def call(routine, a, s=6):
        """routine(A) once through appMain, as a menu click runs it."""
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def press(x, y, s=3):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
        v.resume()
        settle(s)

    def cell(n):
        """The middle of cell n's icon."""
        cols = byte("gridCols")
        x = byte("gridCard") * 8 + (n % cols) * CELL_W + CELL_W // 2
        y = byte("listTop") + (n // cols) * CELL_H + 11
        return x, y

    def here():
        return bytes(v.mem_get(k["path"], k["path"] + 15)).split(b"\0")[0].decode("latin1")
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
        call(k["Drive"], ord("a"))
        call(k["View"], VIEW_ICONS)
        check("icon view: 5 columns, 20 cells, a row of 5",
              (byte("viewMode"), byte("gridCols"), byte("rows"), byte("step")), (VIEW_ICONS, 5, 20, 5))
        bits = bytes(v.mem_get(k["cached"], k["cached"] + 2))
        check("the GEOS files' icons kept in the REU (entries 1-16)",
              (bits[0] & 0xFE, bits[1]), (0xFE, 0xFF))
        g.png("desktop-d9")
        x, y = cell(7)
        press(x, y)
        check("a click on cell 7: its entry the cursor, selected", (word("cur"), v.mem_get(k["sel"], k["sel"])[0] >> 7), (7, 1))
        x, y = cell(0)
        press(x, y, s=1)
        v.mem_set(0x8515, b"\x1e")                          # (dblClickCount: warp
        press(x, y, s=4)                                    # makes 0.3 s too long)
        check("a double click on \"..\": /", here(), "/")
        call(k["Drive"], ord("b"))
        n = word("count")
        check("/b: more than a page", n > 20, True)
        g.keys([KEY_HOME] + [KEY_DOWN] * 22, settle=0.2)
        settle(3)
        check("the cursor on entry 22: the page a row on (top 5)", (word("cur"), word("top")), (22, 5))
        press(STRIP_LEFT + 3, byte("stY0") + 3)               # the strip's up arrow
        check("the strip's arrow: a row of cells back (top 0)", word("top"), 0)
        call(k["Theme"], 3, s=8)                            # Detailed: narrow
        call(k["View"], VIEW_ICONS)
        check("narrow sidebar: 6 columns, 24 cells, a row of 6",
              (byte("gridCols"), byte("rows"), byte("step")), (6, 24, 6))
        g.png("desktop-d9-narrow")
        call(k["View"], VIEW_LIST)
        check("back to the list: a row at a time", (byte("viewMode"), byte("step")), (VIEW_LIST, 1))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
