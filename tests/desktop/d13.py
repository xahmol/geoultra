#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: two panes (docs/DESKTOP.md, "Two panes",
step P4). From /a: two panes switched on (TwoPanes, as view > two panes
runs it): the left pane /a active, the right one "/"; the list view;
a click in the right pane makes it active (its cursor on the entry
clicked); C=SPACE back to the left; RETURN on drive b in the right
pane opens /b there while the left keeps /a; two panes off: the view
from before back. Screens: build/harness/gush/desktop-d13*.png.
Usage: tests/desktop/d13.py
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
    files = []
    for name in ("f1", "f2"):
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"pane %s\r" % name.encode())
        files.append(path)
    g = Gush("desktop-d13", 6665, files)
    check = g.check
    v = g.v

    def byte(name):
        return v.mem_get(k[name], k[name])[0]

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):
        time.sleep(s)
        v.ping()

    def call(routine, a, s=6):
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84, 0xA9, a, 0x4C, routine & 0xFF, routine >> 8]))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def press(x, y, s=4):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(s)

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
        call(k["TwoPanes"], 0, s=8)
        check("two panes on: the left pane active, /a, the list view",
              (byte("panes"), byte("active"), here(), byte("viewMode")), (1, 0, "/a", VIEW_LIST))
        g.png("desktop-d13")
        row = byte("listTop") + 2 * byte("rowH") + 3              # the 3rd row
        press(240, row)
        check("a click in the right pane: active, / there, its cursor on row 2",
              (byte("active"), here(), word("cur")), (1, "/", 2))
        g.keys([0x80 | ord(" ")], settle=1)
        settle(3)
        check("C=SPACE: the left pane active again, /a", (byte("active"), here()), (0, "/a"))
        g.keys([0x80 | ord(" ")], settle=1)
        settle(3)
        g.keys([KEY_HOME, KEY_DOWN, 13], settle=0.5)                 # "/": a, b, e (no "..")
        settle(5)
        check("RETURN on b in the right pane: /b there", (byte("active"), here()), (1, "/b"))
        g.keys([0x80 | ord(" ")], settle=1)
        settle(3)
        check("the left pane kept /a", here(), "/a")
        free = bytes(v.mem_get(k["stBuf"], k["stBuf"] + 30))
        check("the status line: drive A's free space (the active pane's)",
              b"A:" in free or b"A: " in free, True)
        g.png("desktop-d13-b")
        # P5: copy and move to the other pane. The right pane into a new
        # folder /b/dst, the left to /b; F1 copied (C=T), F2 moved (C=M).
        g.keys([0x80 | ord(" ")], settle=1)                        # right
        settle(3)
        g.keys([0x80 | ord("n")], settle=2)
        settle(2)
        g.keys("dst\r", settle=0.3)
        settle(5)
        g.keys([KEY_HOME, KEY_DOWN, 13], settle=0.5)               # .., dst
        settle(5)
        check("the right pane in /b/dst", here(), "/b/dst")
        g.keys([0x80 | ord(" ")], settle=1)                        # left
        settle(3)
        g.keys([8], settle=0.5)                                    # up: /
        settle(4)
        g.keys([KEY_HOME, KEY_DOWN, 13], settle=0.5)               # b
        settle(5)
        n = word("count")                                          # .., dst, F1, F2, gush
        check("the left pane in /b", (here(), n), ("/b", 5))
        g.keys([KEY_HOME, KEY_DOWN, KEY_DOWN], settle=0.5)         # F1
        g.keys([0x80 | ord("t")], settle=1)
        settle(30)
        g.keys([KEY_HOME, KEY_DOWN, KEY_DOWN, KEY_DOWN], settle=0.5)   # F2
        g.keys([0x80 | ord("m")], settle=1)
        settle(30)
        check("after the move: the left pane one entry less", word("count"), n - 1)
        g.keys([0x80 | ord(" ")], settle=1)
        settle(3)
        check("the right pane: F1 copied, F2 moved in", (here(), word("count")), ("/b/dst", 3))
        g.png("desktop-d13-copy")
        call(k["TwoPanes"], 0, s=8)
        check("two panes off: the icon view back", (byte("panes"), byte("viewMode")), (0, VIEW_ICONS))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
