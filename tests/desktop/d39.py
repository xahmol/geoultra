#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: a file dragged onto the toolbar's delete
button (the user's hand test 2026-11-21: "drag to trash: where should I
drag to? Drag to the trash icon does not work"; listin.s Drag, desktop.s
DropDo, DROP_TRASH). Drive B with F1, F2, F3 (and gush): F1 dragged onto
the delete button: the delete question; No: F1 still there; F2 dragged
there, Yes: F2 gone; F3 dragged onto another toolbar button (refresh):
nothing. Screens: build/harness/gush/desktop-d39*.png.
Usage: tests/desktop/d39.py
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
    for name in ("f1", "f2", "f3"):
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"pane %s\r" % name.encode())
        files.append(path)
    g = Gush("desktop-d39", 6665, files)
    check = g.check
    v = g.v

    def byte(name):
        return v.mem_get(k[name], k[name])[0]

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):                                # (a monitor command stops
        v.resume()                                  # VICE until the next resume)
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
        time.sleep(0.5)                             # (released, as a real
        v.ping()                                    # click: Drag waits
        v.mem_set(0x8505, b"\x80")                # for it)
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
        def names():
            out = []
            for i in range(word("count")):
                call(k["Fetch"], i, s=0.7)
                out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0].decode("latin1"))
            return out

        def row_y(n):
            return byte("listTop") + n * byte("rowH") + 3

        def button_x(i):
            return v.mem_get(k["Cards"] + i, k["Cards"] + i)[0] * 8 + 6

        def drag(x0, y0, x1, y1, shot=None):
            v.mem_set(0x8515, b"\x00")                            # (no double click)
            press(x0, y0, s=2)                                     # select
            v.mem_set(0x8515, b"\x00")
            v.mem_set(0x3A, bytes([x0 & 0xFF, x0 >> 8, y0]))
            v.mem_set(0x8505, b"\x00")                            # held:
            pf = v.mem_get(0x39, 0x39)[0]
            v.mem_set(0x39, bytes([pf | 0x20]))
            v.checkpoint(k["Drag"])
            v.resume()
            v.wait_event(RESP_CHECKPOINT)
            v.mem_set(0x3A, bytes([x1 & 0xFF, x1 >> 8, y1]))
            v.resume()
            settle(0.5)
            v.mem_set(0x8505, b"\x80")                            # released
            v.resume()
            settle(6)
            if shot:
                g.png(shot)

        YES, NO = (64 + 8 + 20, 32 + 72 + 8), (64 + 17 * 8 + 20, 32 + 72 + 8)
        call(k["Drive"], ord("b"))
        settle(5)
        lst = names()
        check("drive B: F1, F2, F3", all(n in lst for n in ("F1", "F2", "F3")), True)
        bin_x, bar_y = button_x(k["TB_DELETE"]), 22
        drag(200, row_y(lst.index("F1")), bin_x, bar_y, "desktop-d39-ask")
        press(*NO, s=6)
        after = names()
        check("F1 dropped on delete, No: still there", ("F1" in after, after), (True, after))
        lst = names()
        drag(200, row_y(lst.index("F2")), bin_x, bar_y)
        press(*YES, s=15)
        g.png("desktop-d39-deleted")
        lst = names()
        check("F2 dropped on delete, Yes: gone (F1, F3 kept)", ("F2" in lst, "F1" in lst, "F3" in lst),
              (False, True, True))
        refresh_x = button_x(8)
        drag(200, row_y(lst.index("F3")), refresh_x, bar_y)
        check("F3 dropped on another button: nothing", ("F3" in names(), byte("count")), (True, len(lst)))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
