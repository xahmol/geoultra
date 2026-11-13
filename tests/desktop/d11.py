#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the list sorted (docs/DESKTOP.md,
"Sorting"): ".." first, then folders, then files, each group by name in
any case. Drive B gets files zz, Mm, aa, BB (and gush; c1541 names them in
PETSCII: AA, \xc2\xc2, \xcdM, ZZ, sorted as AA, BB, MM, ZZ), two folders are
made (zdir, Adir); the list's order is read by stepping the cursor.
Then the order after a new folder (it takes its sorted place), and the
other sort orders: size, type, date, name again. Screen:
build/harness/gush/desktop-d11.png.
Usage: tests/desktop/d11.py
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
    for name in ("zz", "Mm", "aa", "BB"):
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"text\r")
        files.append(path)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d11", 6661, files)
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
        C = 0x80

        def order():
            """The names in list order (cursor stepped, C=C reads each)."""
            out = []
            g.keys([KEY_HOME], settle=0.3)
            for i in range(word("count")):
                g.keys([C | ord("c")], settle=0.3)
                settle(1)
                out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 15)).split(b"\0")[0].decode("latin1"))
                g.keys([KEY_DOWN], settle=0.3)
            return out
        for name in ("zdir", "Adir"):
            g.keys([C | ord("n")], settle=2)
            settle(2)
            g.keys(name + "\r", settle=0.3)
            settle(5)
        check("sorted: .., folders, then files, any case", order(),
              ["..", "Adir", "zdir", "AA", "\xc2\xc2", "gush", "\xcdM", "ZZ"])
        g.keys([C | ord("n")], settle=2)
        settle(2)
        g.keys("Mdir\r", settle=0.3)
        settle(5)
        check("a new folder in its sorted place", order()[1:4], ["Adir", "Mdir", "zdir"])
        g.png("desktop-d11")
        # The sort orders (sortMode, [desktop] sort=; the user, 2026-11-12):
        # gush is the only GEOS file (93 blocks, a date); the rest one block.
        for mode, title, want in (
                (2, "by size: gush (largest) first, then by name", ["gush", "AA", "\xc2\xc2", "\xcdM", "ZZ"]),
                (3, "by type: plain files, then the GEOS application", ["AA", "\xc2\xc2", "\xcdM", "ZZ", "gush"]),
                (1, "by date: gush (dated) first, the undated after", ["gush", "AA", "\xc2\xc2", "\xcdM", "ZZ"]),
                (0, "by name again", ["AA", "\xc2\xc2", "gush", "\xcdM", "ZZ"])):
            v.mem_set(k["sortMode"], bytes([mode]))
            call(k["Refresh"], 0, s=6)
            got = order()
            check(title + "; folders still first", (got[:4], got[4:]), (["..", "Adir", "Mdir", "zdir"], want))
        # Two panes, step P3: the other pane's state swapped in and back.
        def state():
            return (bytes(v.mem_get(k["path"], k["path"] + 7)).split(b"\0")[0].decode("latin1"),
                    word("count"), v.mem_get(k["entryBank"], k["entryBank"])[0])
        mine = state()
        call(k["SwapPane"], 0, s=3)
        check("SwapPane: the other pane's state (/, empty, banks 3-4)", state(), ("/", 0, 3))
        call(k["SwapPane"], 0, s=3)
        check("SwapPane again: this pane's back", state(), mine)
        check("its entries unchanged", order()[:3], ["..", "Adir", "Mdir"])
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
