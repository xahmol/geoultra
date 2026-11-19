#!/usr/bin/env python3
"""Choosing the printer in GeoUltra's desktop (docs/design/DESIGN.md "Printing",
the user's decisions of 2026-11-16; src/desktop/inifile.s UsePrinter,
open.s, ctxmenu.s) in VICE: at the desktop's start, with no printer
chosen, PrntFilename is GU Epson FX-80 (drive E); in /b (the test disk,
GeoUltra's two printer drivers on it) the right button over GU
Commodore MPS shows "use as printer" for the menu's first item; opening
the driver (a double click's Open) makes it the printer and says so (its
name, "is the printer now."). Port 1 as VICE's joyport I/O simulation
(the 1351's right button, as d12). Screens:
build/harness/gush/desktop-d27*.png.
Usage: tests/desktop/d27.py
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, OUT, harness, KEY_STUB  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

JOY_IDLE, JOY_UP = 0xFF, 0xFE
OK_XY = (220, 112)              # the dialog's OK (DBI_X_2, DBI_Y_2)
PRNT = 0x8465                   # PrntFilename


def main():
    os.makedirs(OUT, exist_ok=True)
    subprocess.run(["make", "-s", "build/printer/epson.cvt", "build/printer/mps.cvt"], cwd=ROOT,
                   check=True, capture_output=True)
    drivers = [os.path.join(ROOT, "build", "printer", n + ".cvt") for n in ("epson", "mps")]
    k = {}
    for line in open(os.path.join(ROOT, "build", "desktop", "desktop.lbl")):
        p = line.split()
        k.setdefault(p[2].lstrip("."), int(p[1], 16))
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("desktop-d27", 6741, drivers, extra=["-controlport1device", "37"])
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

    def stub(code, s=4):
        """CODE run once from MainLoop (appMain), appMain then ClockTick."""
        tick = k["ClockTick"]
        v.mem_set(KEY_STUB, bytes([0xA9, tick & 0xFF, 0x8D, 0x9B, 0x84, 0xA9, tick >> 8, 0x8D, 0x9C,
                                   0x84] + code))
        v.mem_set(0x849B, bytes([KEY_STUB & 0xFF, KEY_STUB >> 8]))
        v.resume()
        settle(s)

    def left(x, y, s=3):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.mem_set(0x8505, b"\x00")
        pf = v.mem_get(0x39, 0x39)[0]
        v.mem_set(0x39, bytes([pf | 0x20]))
        v.resume()
        settle(s)

    def right(x, y, s=3):
        v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
        v.joyport_set(0, JOY_UP)
        v.resume()
        settle(0.5)
        v.joyport_set(0, JOY_IDLE)
        v.resume()
        settle(s)

    def in_menu(want=True, tries=15):
        for _ in range(tries):
            if (0x5000 <= v.regs_get()["PC"] < 0x6000) == want:
                return True
            v.resume()
            settle(1)
        return False

    def name_at(addr, n=17):
        return bytes(v.mem_get(addr, addr + n - 1)).split(b"\0")[0].decode("latin1")

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
        v.mem_set(PRNT, bytes(17))                          # no printer chosen yet
        v.mem_set(start, bytes(code))
        v.mem_set(nm, b"/b\0")
        v.mem_set(desk, b"GeoUltra Desktop\0")
        v.regs_set({"PC": start})
        v.resume()
        settle(8)
        check("at the start, none chosen: GU Epson FX-80", name_at(PRNT), "GU Epson FX-80")
        index = None                                        # GU Commodore MPS in /b
        for i in range(word("count")):
            stub([0xA9, i, 0xA2, 0x00, 0x4C, k["Fetch"] & 0xFF, k["Fetch"] >> 8], s=1)
            if name_at(k["entryName"]) == "GU Commodore MPS":
                index = i
                break
        check("GU Commodore MPS listed in /b", index is not None, True)
        row = byte("listTop") + (index or 0) * byte("rowH") + 3
        right(150, row)
        check("the right button over it: the menu", in_menu(), True)
        check("its first item reads \"use as printer\"", byte("isPrn"), 0x80)
        g.png("desktop-d27-menu")
        right(150, row)
        in_menu(False)
        v.mem_set(k["cur"], bytes([index or 0, 0]))
        stub([0x4C, k["Open"] & 0xFF, k["Open"] >> 8], s=5)  # a double click's Open
        g.png("desktop-d27-chosen")
        check("opened: GU Commodore MPS is the printer", name_at(PRNT), "GU Commodore MPS")
        check("and the note says so", (name_at(k["entryName"]), word("errLine") == k["EPrinter"]),
              ("GU Commodore MPS", True))
        left(*OK_XY, s=3)
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
