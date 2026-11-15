#!/usr/bin/env python3
"""The print spooler's banks in VICE (docs/DESIGN.md "Print spooler";
src/kernal/spool.s): SpoolInit as module 92 calls it with
spool='s first and fourth characters: none (128 KB: banks 27-28 only),
"1024" (16 banks: 14 more, banks 174-187; FE_MOUNT's limit below them),
"2048" with a drive on bank 180 (only the banks above it: 181-187),
"5000" (not a size: as none). Reads spoolExtra, spoolBase, driveLimit.
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

        check("none: banks 27-28 only", init(0, 0), (0, 188, 189))
        check("1024 KB: 14 more, 174-187", init(ord("1"), ord("0")), (14, 174, 175))
        types = bytes(v.mem_get(DRIVE_TYPE, DRIVE_TYPE + 3))
        bases = bytes(v.mem_get(RAM_BASE, RAM_BASE + 3))
        v.mem_set(DRIVE_TYPE + 3, bytes([0x82]))            # drive D: an REU 1571
        v.mem_set(RAM_BASE + 3, bytes([175]))               # on banks 175-180
        check("2048 KB, a drive on 175-180: only 181-187", init(ord("2"), ord("4")), (7, 181, 182))
        v.mem_set(DRIVE_TYPE, types)
        v.mem_set(RAM_BASE, bases)
        check("5000: not a size, as none", init(ord("5"), ord("0")), (0, 188, 189))
    finally:
        g.stop()
    sys.exit(0 if g.ok else 1)


if __name__ == "__main__":
    main()
