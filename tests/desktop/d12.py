#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the context menu and Info (src/desktop/
ctxmenu.s, overlay 7). Port 1 as VICE's joyport I/O simulation: its
"up" line is the 1351's right button (guMouse2). In /a: a right press
over an entry selects it and opens the menu at the pointer; "info"
shows its name, kind, size and class (the dialog's lines read from
memory); the right button again closes the menu without an action;
"copy" from the menu puts the entry on the clipboard. Screens:
build/harness/gush/desktop-d12*.png.
Usage: tests/desktop/d12.py
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
JOY_IDLE, JOY_UP = 0xFF, 0xFE   # port 1's lines (active low): "up" is the
                                # 1351's right button
ITEM_H, OK_XY = 14, (220, 112)   # ctxmenu.s; the dialog's OK (DBI_X_2, DBI_Y_2)


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
    g = Gush("desktop-d12", 6663, [], extra=["-controlport1device", "37"])
    check = g.check
    v = g.v
    v.joyport_set(0, JOY_IDLE)

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

    def point(x, y):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))

    def left(x, y, s=3):
        point(x, y)
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(s)

    def right(x, y, s=3):
        point(x, y)
        v.joyport_set(0, JOY_UP)
        v.resume()
        settle(0.5)
        v.joyport_set(0, JOY_IDLE)
        v.resume()
        settle(s)

    def in_menu(want=True, tries=15):
        """Wait until the menu's loop runs (the CPU in overlay 7, $5000-$5FFF)
        or, want False, no longer runs; True when it got there."""
        for _ in range(tries):
            pc = v.regs_get()["PC"]
            if (0x5000 <= pc < 0x6000) == want:
                return True
            v.resume()
            settle(1)
        return False

    def item(n):
        """The middle of the menu's item n (its box at the pointer)."""
        return byte("x0") + 20, byte("y0") + 1 + n * ITEM_H + 7

    def text(name):
        return bytes(v.mem_get(k[name], k[name] + 30)).split(b"\0")[0].decode("latin1")
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
        row = byte("listTop") + 4 * byte("rowH") + 3            # the 5th row
        right(150, row)
        check("the menu's loop runs", in_menu(), True)
        check("a right press: the entry under the pointer the cursor", word("cur"), 4)
        check("the menu open (overlay 7 in)", byte("curOvl"), 7)
        g.png("desktop-d12")
        x, y = item(6)                                          # info
        left(x, y, s=5)
        check("info: the kind line", text("line2").startswith("Kind: "), True)
        check("info: the size in blocks", text("line3").endswith(" blocks"), True)
        g.png("desktop-d12-info")
        left(*OK_XY, s=3)
        right(150, row)
        in_menu()
        right(150, row)                                         # again: closed
        check("the right button again: the menu closed", in_menu(False), True)
        check("the right button again: nothing on the clipboard", word("clipCount"), 0)
        right(150, row)
        check("the menu open again", in_menu(), True)
        x, y = item(1)                                          # copy
        left(x, y, s=4)
        in_menu(False)
        check("copy from the menu: one entry on the clipboard", word("clipCount"), 1)
        # The go menu (the user, 2026-11-12): its items through GoItem, as a
        # menu click runs it (A = the item), and its keys.
        def here():
            return bytes(v.mem_get(k["path"], k["path"] + 15)).split(b"\0")[0].decode("latin1")
        call(k["GoItem"], 3)                                    # root
        check("go > root: /", here(), "/")
        call(k["GoItem"], 0)                                    # back
        check("go > back: /a", here(), "/a")
        g.keys([0x80 | 30], settle=3)                           # C= cursor right
        settle(2)
        check("C=cursor right: forward, /", here(), "/")
        g.keys([0x80 | 8], settle=3)                            # C= cursor left
        settle(2)
        check("C=cursor left: back, /a", here(), "/a")
        left(88, 6, s=3)                                        # the go menu opened
        g.png("desktop-d12-go")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
