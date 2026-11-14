#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: icon colours by type (S4.6; the user,
2026-11-14; iconview.s Tint): in the icon view of /b, the first entry
"..": its icon's colour cells in the folders' ink (cIconT, the theme's
icons-folders=) on the desk's paper; icons-bytype=off in the theme
(tByType) or iconcolours=off in SETTINGS.INI (deskPrefs PREF_PLAIN):
the desk's own colours.
Usage: tests/desktop/d22.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

VIEW_ICONS = 1
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
    g = Gush("desktop-d22", 6723, files)
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
        ORANGE = 8
        v.mem_set(k["cIconT"] + 4, bytes([ORANGE]))         # folders and drives

        def cell():
            """The first cell's icon: its colour cells (3 x 3)."""
            top = byte("gridTop") // 8
            card = byte("gridCard") + 1
            out = set()
            for r in range(top, top + 3):
                a = 0x8C00 + r * 40 + card
                out |= set(v.mem_get(a, a + 2))
            return out

        call(k["View"], VIEW_ICONS, s=8)
        paper = byte("cDesk") & 0x0F
        check("\"..\" (a folder): orange on the desk's paper", cell(), {ORANGE << 4 | paper})
        g.png("desktop-d22")
        v.mem_set(k["tByType"], b"\x01")
        call(k["View"], VIEW_ICONS, s=8)
        check("icons-bytype=off: the desk's colours", cell(), {byte("cDesk")})
        v.mem_set(k["tByType"], b"\x00")
        v.mem_set(k["deskPrefs"], bytes([byte("deskPrefs") | 0x08]))
        call(k["View"], VIEW_ICONS, s=8)
        check("iconcolours=off (SETTINGS.INI): the desk's colours", cell(), {byte("cDesk")})
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
