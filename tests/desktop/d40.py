#!/usr/bin/env python3
"""GeoUltra's desktop in VICE: a PRG file opened runs in BASIC (the user's
decision 2026-11-26; open.s, desktop.s Ov_RunPrg, src/inc/prgrun.inc,
the kernal's ToBASIC loading it from the drive). Drive B with BP, a
BASIC program (10 PRINT "PRG OK") written by c1541 as a PRG. Opened:
the question; No: the desktop stays; opened again, Yes: BASIC starts,
loads BP from drive B, RUN typed, "PRG OK" on the screen. Screens:
build/harness/gush/desktop-d40*.png.
Usage: tests/desktop/d40.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402


def program():
    line = bytes([0x99]) + b' "PRG OK"' + b"\0"
    nxt = 0x0801 + 4 + len(line)
    return b"\x01\x08" + bytes([nxt & 0xFF, nxt >> 8, 10, 0]) + line + b"\0\0"


def screen_has(v, text):
    codes = bytes((c - 0x40) if 0x41 <= c <= 0x5A else c for c in text.encode())
    return codes in bytes(v.mem_get(0x0400, 0x07E7))


def main():
    os.makedirs(OUT, exist_ok=True)
    k, kern = {}, {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    path = os.path.join(OUT, "bp")
    open(path, "wb").write(program())
    g = Gush("desktop-d40", 6666, [path])
    check = g.check
    v = g.v

    def word(name):
        return int.from_bytes(bytes(v.mem_get(k[name], k[name] + 1)), "little")

    def settle(s=3):                                # (VICE kept running while
        v.resume()                                  # waiting)
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
        time.sleep(0.5)
        v.ping()
        v.mem_set(0x8505, b"\x80")
        v.resume()
        settle(s)

    def names():
        out = []
        for i in range(word("count")):
            call(k["Fetch"], i, s=0.7)
            out.append(bytes(v.mem_get(k["entryName"], k["entryName"] + 16)).split(b"\0")[0].decode("latin1"))
        return out

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
        YES, NO = (64 + 8 + 20, 32 + 72 + 8), (64 + 17 * 8 + 20, 32 + 72 + 8)
        call(k["Drive"], ord("b"))
        settle(5)
        lst = names()
        check("drive B: BP", "BP" in lst, True)
        v.mem_set(k["cur"], bytes([lst.index("BP"), 0]))
        call(k["Open"], 0, s=5)
        g.png("desktop-d40-ask")
        press(*NO, s=5)
        check("BP opened, No: the desktop stays", (screen_has(v, "PRG OK"),
              v.mem_get(0xC006, 0xC00E) == b"GEOS BOOT"), (False, True))
        v.mem_set(k["cur"], bytes([lst.index("BP"), 0]))
        call(k["Open"], 0, s=5)
        press(*YES, s=15)
        check("BP opened, Yes: BASIC loads it from drive B and runs it", screen_has(v, "PRG OK"), True)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
