#!/usr/bin/env python3
"""The GEOS 2.0 deskTop on GeoUltra in VICE with a 1581 as drive A (the
user's GEOS64.D81, GEOS_ORACLE81; never committed), as on the U64.

The deskTop calls the disk driver between InitForIO and DoneWithIO, with
the KERNAL ROM over $E000; the driver's routines and variables there
(Dir81, folderT ...) then read ROM bytes: the deskTop ran the ROM's
"BYTES FREE" text and its stack overflowed (found 2026-11-06, broken
since the code sweep of 2026-11-04 shifted Dir81). The driver now keeps
the CPU port at RAM_IO around them (reudrv.s, HeaderSwap and DirHead).
Checked: the CPU never below $0400 after the start, and drive A's disk
name in the deskTop's notepad header (curDirHead). Screen in
build/harness/gush/desktop81.png.
Usage: tests/drives/desktop81.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

ENTER_DESKTOP = 0xC22C


def main():
    harness.use_disk_set("d81")
    g = Gush("desktop81", 6619)
    try:
        v = g.v
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)                      # up to MainLoop
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        v.regs_set({"PC": ENTER_DESKTOP})
        v.resume()
        time.sleep(25)
        low = 0
        for _ in range(6):
            v.ping()
            if v.regs_get()["PC"] < 0x0400:
                low += 1
            v.resume()
            time.sleep(0.3)
        v.ping()
        g.check("the deskTop runs (the CPU never below $0400)", low, 0)
        name = bytes(v.mem_get(0x8290, 0x829F)).split(b"\xA0")[0].decode("latin1")
        g.check("drive A open: its disk name", name, "GEOS 64")
        g.png("desktop81")
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
