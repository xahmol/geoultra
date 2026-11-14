#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: two panes, the inactive pane's selection
hidden (the user, 2026-11-13; list.s IsSelected with panes.s paneDim):
kept, and shown again when the pane is active. The left pane (drive B)
drawn inactive with nothing selected is the reference; then everything
in it selected (C=A) and the right pane made active (C=SPACE): the left
pane's bitmap is the reference again and its selection still there;
active again, it shows the selection. Screens:
build/harness/gush/desktop-d20*.png.
Usage: tests/desktop/d20.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

C_SPACE, C_A = 0x80 | 0x20, 0x80 | ord("a")
SIZES = {"a": 1, "bb": 5, "ccc": 3}                 # blocks (254 bytes each)


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
    g = Gush("desktop-d20", 6720, files)
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
        call(k["TwoPanes"], 0, s=8)
        settle(3)

        def left():
            """The left pane's list rows in the bitmap (cards 0-18, rows 6-21)."""
            out = b""
            for r in range(6, 22):
                a = 0xA000 + r * 320
                out += bytes(v.mem_get(a, a + 19 * 8 - 1))
            return out

        def selected():
            return any(bytes(v.mem_get(k["sel"], k["sel"] + 7)))

        g.keys([C_SPACE], settle=1)                       # right pane active
        settle(4)
        ref = left()
        g.png("desktop-d20-ref")
        g.keys([C_SPACE], settle=1)                       # left again
        settle(4)
        g.keys([C_A], settle=1)                           # everything selected
        settle(3)
        on = left()
        g.png("desktop-d20-selected")
        check("the active left pane shows its selection", (on != ref, selected()), (True, True))
        g.keys([C_SPACE], settle=1)                       # right pane active
        settle(4)
        g.png("desktop-d20-hidden")
        check("inactive: drawn as with nothing selected", left() == ref, True)
        g.keys([C_SPACE], settle=1)                       # left again
        settle(4)
        check("active again: its selection kept and shown", (selected(), left() == on), (True, True))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
