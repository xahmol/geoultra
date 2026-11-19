#!/usr/bin/env python3
"""[serials] in VICE (src/kernal/serials.s; docs/DESIGN.md "Serial
number", step S1): FE_SERIALS with an INI text in memory, then
GetSerialNumber with taskName set (as the kernal sets it when an
application starts): a listed class gives its serial (any case, the
class only), another the system's own, a class longer than 12
characters is left out, an empty [serials] clears the table.
Usage: tests/engine/serials.py
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "gush"))
from gushvice import Gush, harness  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

TEXT = 0x4E00
INI = (b"[system]\r\nserial=1234\r\n[serials]\r\ngeoWrite=4321\r\nTest App=1a2B\r\n"
       b"A Very Long Class=0101\r\n\r\n[desktop]\r\ngeoCalc=7777\r\n")


def labels():
    out = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        out.setdefault(p[2].lstrip("."), int(p[1], 16))
    return out


def main():
    k = labels()
    jt = harness.jumptab()
    g = Gush("serials", 6791, [])
    v = g.v
    ok = True

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, hex(got) if isinstance(got, int) and good
                             else "%s, expected %s" % (got, want)))

    def run(code):
        start = harness.TRAMPOLINE
        code = [0x78, 0xA9, 0x30, 0x85, 0x01] + code
        end = start + len(code)
        v.mem_set(start, bytes(code + [0x4C, end & 0xFF, end >> 8]))
        cp = v.checkpoint(end, temporary=False)
        v.regs_set({"PC": start})
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cp)

    def serials(text):
        v.mem_set(TEXT, text)
        fe = k["ExtTable"] + 30
        n = len(text)
        run([0xA9, TEXT & 0xFF, 0x85, 0x02, 0xA9, TEXT >> 8, 0x85, 0x03,
             0xA9, n & 0xFF, 0x85, 0x04, 0xA9, n >> 8, 0x85, 0x05,
             0xA9, 36, 0x20, fe & 0xFF, fe >> 8])

    def serial_for(cls):
        v.mem_set(k["taskName"], cls.encode().ljust(12, b"\0")[:12] + b"\0")
        gsn = jt["GetSerialNumber"]
        run([0x20, gsn & 0xFF, gsn >> 8])
        r = v.mem_get(0x02, 0x03)
        return r[0] | r[1] << 8

    try:
        v.resume()
        import time
        time.sleep(6)
        v.ping()
        jtc = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jtc[1] | jtc[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        own = serial_for("Nothing")
        check("the system's own differs from the test's values", own not in (0x4321, 0x1A2B), True)
        serials(INI)
        check("geoWrite: its listed serial", serial_for("geoWrite"), 0x4321)
        check("any case: GEOWRITE too", serial_for("GEOWRITE"), 0x4321)
        check("Test App (hex in any case)", serial_for("Test App"), 0x1A2B)
        check("not listed: the system's own", serial_for("geoPaint"), own)
        check("a class longer than 12 characters: left out", serial_for("A Very Long "), own)
        check("[desktop]'s line is no serial", serial_for("geoCalc"), own)
        serials(b"[serials]\r\n")
        check("an empty [serials]: the table cleared", serial_for("geoWrite"), own)
    finally:
        g.stop()
    print("serials: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
