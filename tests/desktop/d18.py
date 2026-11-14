#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: the sort order from the path line (the
user's decisions 2026-11-13 and 2026-11-14; list.s Header, SortArrow;
listin.s SortUnder, SortCol, SortFlip). One list, the detailed view of
drive B with three files of different sizes: a click on the Size
heading sorts by size (largest first), a second click reverses it, a
third goes back to names; the arrow at the path line's right end turns
the order round. Folders and ".." stay first throughout. Two panes:
the arrow is the first of the letters and turns the order round too.
The order is read back with the desktop's own Fetch. Screens:
build/harness/gush/desktop-d18*.png.
Usage: tests/desktop/d18.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

VIEW_DETAILED = 2
COL_SIZE, COL_DATE, ARROW_ROOM, LET_PITCH, PANE_W = 246, 254, 10, 9, 160
SORT_REV = 0x80
SIZES = {"a": 1, "bb": 5, "ccc": 3}                 # blocks (254 bytes each)
ORDER_NAME, ORDER_SIZE = ["A", "BB", "CCC"], ["BB", "CCC", "A"]   # (c1541 writes capitals)


def main():
    os.makedirs(OUT, exist_ok=True)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    files = []
    for name, blocks in SIZES.items():
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"x" * (254 * blocks - 10))
        files.append(path)
    g = Gush("desktop-d18", 6718, files)
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

    def press(x, y, s=5):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(s)

    def names():
        """The list's names in order, through the desktop's Fetch (A/X =
        the entry), called from appMain as ClockTick's stand-in."""
        out = []
        tick, fetch = k["ClockTick"], k["Fetch"]
        for i in range(word("count")):
            v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                       0x84, 0xA9, i & 0xFF, 0xA2, i >> 8, 0x4C, fetch & 0xFF, fetch >> 8]))
            v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
            v.resume()
            settle(0.6)
            out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0].decode("latin1"))
        return out

    def mine():
        return [n for n in names() if n.lower() in SIZES]
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
        call(k["View"], VIEW_DETAILED)
        y = byte("pathY") - 3
        check("by name at the start (no SETTINGS.INI)", (byte("sortMode"), mine()), (0, ORDER_NAME))
        g.png("desktop-d18")
        press(COL_SIZE - 10, y)
        g.png("desktop-d18-size")
        check("Size heading: by size, largest first", (byte("sortMode"), mine()), (2, ORDER_SIZE))
        press(COL_SIZE - 10, y)
        check("Size again: reversed", (byte("sortMode"), mine()), (2 | SORT_REV, ORDER_SIZE[::-1]))
        g.png("desktop-d18-reversed")
        press(COL_SIZE - 10, y)
        check("a third time: by name again", (byte("sortMode"), mine()), (0, ORDER_NAME))
        right = word("listR")
        press(right - ARROW_ROOM + 4, y)
        g.png("desktop-d18-arrow")
        all_names = names()
        check("the arrow: names reversed", (byte("sortMode"), mine()), (SORT_REV, ORDER_NAME[::-1]))
        check("\"..\" still first", all_names[:1], [".."])
        press(COL_DATE + 6, y)
        check("Date heading: by date (no dates here: the files keep a stable order)",
              (byte("sortMode"), sorted(mine())), (1, ORDER_NAME))
        call(k["TwoPanes"], 0, s=8)
        settle(3)
        n = 0
        while byte("lettersDue") and n < 10:
            settle(1)
            n += 1
        g.png("desktop-d18-panes")
        before = byte("sortMode")
        y = byte("pathY") - 3                            # (two panes: no title bars)
        letters = 4                                      # arrow, A, B, E (VICE: drives A and B)
        press(PANE_W - 2 - letters * LET_PITCH + 3, y, s=10)
        check("two panes: the arrow (first of the letters) turns the order round",
              byte("sortMode"), before ^ SORT_REV)
        g.png("desktop-d18-panes-arrow")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
