#!/usr/bin/env python3
"""The desktop's clipboard menu in VICE (docs/design/DESIGN.md "Clipboard";
src/desktop/clip.s; the user's decisions of 2026-11-15): a text scrap put
into the store (SaveFile through the jump table, src/kernal/scrap.s);
and a small photo scrap; clipboard > show: the text's size and first
characters, the picture's size, the picture drawn;
save as file: the name proposed ("Text  Scrap 1") taken, the file in /b;
clear: asked, then the store empty (FindFile: not found). Screens:
build/harness/gush/desktop-d25*.png.
Usage: tests/desktop/d25.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

KEY_UP, KEY_DOWN, CR, KEY_STOP = 16, 17, 13, 22
P_COUNT, P_ITEMS = 0x9FF0, 0x9FF5
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
    files = [os.path.join(ROOT, "build", "settings", "settings.cvt")]   # a VLIR file
    for name, blocks in SIZES.items():
        path = os.path.join(OUT, name)
        open(path, "wb").write(b"x" * (254 * blocks - 10))
        files.append(path)
    g = Gush("desktop-d25", 6726, files)
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

        def press(x, y, s=4):
            v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
            v.mem_set(0x8505, b"\x00")
            pf = v.mem_get(0x39, 0x39)[0]
            v.mem_set(0x39, bytes([pf | 0x20]))
            v.resume()
            time.sleep(0.5)
            v.ping()
            v.mem_set(0x8505, b"\x80")
            v.resume()
            settle(s)

        def text(at, n=40):
            return bytes(v.mem_get(at, at + n)).split(b"\0")[0]

        # a text scrap into the store: SaveFile (the jump table) of a header
        hdr, name, data, run = 0x7E00, 0x7F00, 0x7F10, 0x5F80
        scrap = b"Hello clipboard"
        payload = bytes([len(scrap) + 4, 0, 0x17, 0, 0, 0]) + scrap
        h = bytearray(256)
        h[0:2] = bytes([name & 0xFF, name >> 8])
        h[2:5] = bytes([3, 21, 0xBF])
        h[0x44], h[0x45], h[0x46] = 0x83, 7, 0
        h[0x47:0x49] = bytes([data & 0xFF, data >> 8])
        end = data + len(payload)
        h[0x49:0x4B] = bytes([end & 0xFF, end >> 8])
        h[0x4D:0x4D + 16] = b"Text  Scrap V2.0"
        v.mem_set(hdr, bytes(h))
        v.mem_set(name, b"Text  Scrap\0")
        v.mem_set(data, payload)
        v.mem_set(run, bytes([0xA9, hdr & 0xFF, 0x85, 0x14, 0xA9, hdr >> 8, 0x85, 0x15,
                              0xA9, 0x00, 0x85, 0x16, 0x20, 0xED, 0xC1, 0x8E, 0xF0, 0x02, 0x60]))
        v.mem_set(0x2F0, b"\xEE")
        call(run, 0, s=4)
        check("a text scrap saved into the store", v.mem_get(0x2F0, 0x2F0)[0], 0)
        pic = bytes([2, 8, 0, 16, 0xAA])                    # a photo scrap: 2 cards
        h[0:2] = bytes([name & 0xFF, name >> 8])            # x 8 lines, $AA
        end = data + len(pic)
        h[0x49:0x4B] = bytes([end & 0xFF, end >> 8])
        h[0x4D:0x4D + 16] = b"Photo Scrap V1.1"
        v.mem_set(hdr, bytes(h))
        v.mem_set(name, b"Photo Scrap\0")
        v.mem_set(data, pic)
        v.mem_set(run, bytes([0xA9, hdr & 0xFF, 0x85, 0x14, 0xA9, hdr >> 8, 0x85, 0x15,
                              0xA9, 0x00, 0x85, 0x16, 0x20, 0xED, 0xC1, 0x8E, 0xF0, 0x02, 0x60]))
        v.mem_set(0x2F0, b"\xEE")
        call(run, 0, s=4)
        check("a photo scrap too", v.mem_get(0x2F0, 0x2F0)[0], 0)
        call(k["MClipShow"], 0, s=4)
        g.png("desktop-d25-show")
        check("show: its size", text(k["Line2"]), b"Text: %d bytes" % (len(scrap) + 4))
        check("show: its first characters", text(k["Line3"]), b'"' + scrap + b'"')
        check("show: the picture's size", text(k["Line4"]), b"Picture: 16 x 8")
        shown = v.mem_get(0xA000 + 10 * 320 + 22 * 8, 0xA000 + 10 * 320 + 22 * 8)[0]
        check("show: the picture drawn (card 22, row 10)", shown, 0xAA)
        press(90, 110, s=6)                                 # OK
        call(k["MClipSave"], 0, s=4)
        g.png("desktop-d25-save")
        press(90, 110, s=8)                                 # OK: "Text  Scrap 1"
        press(90, 110, s=8)                                 # OK: "Photo Scrap 1"
        v.mem_set(0x4E00, b"Text  Scrap 1\0")
        find = [0xA9, 0x00, 0x85, 0x0E, 0xA9, 0x4E, 0x85, 0x0F, 0x20, 0x0B, 0xC2, 0x8E, 0xF0, 0x02, 0x60]
        v.mem_set(run, bytes(find))
        v.mem_set(0x2F0, b"\xEE")
        call(run, 0, s=3)
        check("save as file: \"Text  Scrap 1\" in /b", v.mem_get(0x2F0, 0x2F0)[0], 0)
        call(k["MClipClear"], 0, s=4)
        g.png("desktop-d25-clear")
        press(90, 110, s=6)                                 # YES
        g.png("desktop-d25-cleared")
        v.mem_set(0x4E00, b"Text  Scrap\0")
        v.mem_set(run, bytes(find))                         # (overlays load 4 KB:
        v.mem_set(0x2F0, b"\xEE")                           # the code again)
        call(run, 0, s=3)
        check("clear: the store empty (FindFile: not found)", v.mem_get(0x2F0, 0x2F0)[0], 5)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
