#!/usr/bin/env python3
"""The print spooler's banks in VICE (docs/design/DESIGN.md "Print spooler";
src/kernal/spool.s): SpoolInit as module 92 calls it with
spool='s first and fourth characters (since 0.9.1 the extra banks come
from bank 255 down, in the legacy area the task slots leave; the drives
keep 31-179): none (1 MB, the default: 242-255), "128" (banks 27-28
only), "1024", "2048" with a drive on banks 167-172 (all 30, 226-255),
8 task slots (the legacy area full: 27-28 only), "5000" (as none). Reads spoolExtra, spoolBase, driveLimit.
Usage: tests/spool/sp1.py
"""
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

DRIVE_TYPE, RAM_BASE = 0x848E, 0x88C7


def main():
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    g = Gush("spool-sp1", 6727, [])
    v = g.v
    check = g.check
    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        start = harness.TRAMPOLINE
        si = kern["SpoolInit"]

        def init(a, x):
            code = [0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, a, 0xA2, x, 0x20, si & 0xFF, si >> 8]
            end = start + len(code)
            code += [0x4C, end & 0xFF, end >> 8]
            v.mem_set(start, bytes(code))
            v.regs_set({"PC": start})
            v.resume()
            time.sleep(1)
            v.ping()
            return tuple(v.mem_get(kern[n], kern[n])[0] for n in ("spoolExtra", "spoolBase", "driveLimit"))

        check("none: 1 MB, the default (14 more from bank 255 down: 242-255; the drives to 179)",
              init(0, 0), (14, 242, 181))
        check("128 KB: banks 27-28 only", init(ord("1"), 0), (0, 0, 181))
        check("1024 KB: 14 more, 242-255", init(ord("1"), ord("0")), (14, 242, 181))
        types = bytes(v.mem_get(DRIVE_TYPE, DRIVE_TYPE + 3))
        bases = bytes(v.mem_get(RAM_BASE, RAM_BASE + 3))
        v.mem_set(DRIVE_TYPE + 3, bytes([0x82]))            # drive D: an REU 1571
        v.mem_set(RAM_BASE + 3, bytes([167]))               # on banks 167-172
        check("2048 KB with a drive on 167-172: all 30 (226-255), the drives' area not touched",
              init(ord("2"), ord("4")), (30, 226, 181))
        v.mem_set(DRIVE_TYPE, types)
        v.mem_set(RAM_BASE, bases)
        slots = kern["taskSlots"]
        keep = v.mem_get(slots, slots)[0]
        v.mem_set(slots, b"\x08")                         # 8 slots of 512 KB: full
        check("8 task slots fill the legacy area: banks 27-28 only", init(ord("1"), ord("0")), (0, 0, 181))
        v.mem_set(slots, bytes([keep]))
        check("5000: not a size, as none (1 MB)", init(ord("5"), ord("0")), (14, 242, 181))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
