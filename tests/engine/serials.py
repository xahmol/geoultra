#!/usr/bin/env python3
"""[serials] in VICE (src/kernal/serials.s; docs/design/DESIGN.md "Serial
number", step S1): FE_SERIALS with an INI text in memory, then
GetSerialNumber with taskName set (as the kernal sets it when an
application starts): a listed class gives its serial (any case, the
class only), another the system's own, a class longer than 12
characters is left out, an empty [serials] clears the table. The
refusal note (step S5): a dialog box whose DBVARSTR text is geoWrite
2.1's "Please reboot your system..." (BOLDON first, as geoWrite shows
it) with taskName "geoWrite" noted, FE_SERIALS with r1 = 0 gives the
class once, then nothing; an ordinary box (DBTXTSTR) notes nothing.
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

    def box(item, text):
        """A dialog box with one text item (DBTXTSTR or DBVARSTR, r5),
        opened and left: the CPU stopped while it waits for a click."""
        import time
        v.mem_set(0x4F00, text + b"\0")
        if item == 12:
            desc = [0x81, 12, 16, 16, 0x0C, 1, 17, 72, 0]
        else:
            desc = [0x81, 11, 16, 16, 0x00, 0x4F, 1, 17, 72, 0]
        v.mem_set(0x4E80, bytes(desc))
        dlg = jt["DoDlgBox"]
        code = [0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x00, 0x85, 0x0C, 0xA9, 0x4F, 0x85, 0x0D,
                0xA9, 0x80, 0x85, 0x02, 0xA9, 0x4E, 0x85, 0x03, 0x20, dlg & 0xFF, dlg >> 8]
        v.mem_set(harness.TRAMPOLINE, bytes(code + [0x4C, 0, 0]))
        v.regs_set({"PC": harness.TRAMPOLINE})
        v.resume()
        time.sleep(3)
        v.ping()

    def refused():
        """FE_SERIALS with r1 = 0: (X, the class noted or None)."""
        fe = k["ExtTable"] + 30
        v.mem_set(0x4D00, b"\xEE" * 13)
        run([0xA9, 0x00, 0x85, 0x02, 0xA9, 0x4D, 0x85, 0x03, 0xA9, 0, 0x85, 0x04, 0x85, 0x05,
             0xA9, 36, 0x20, fe & 0xFF, fe >> 8, 0x8E, 0xF0, 0x02])
        x = v.mem_get(0x02F0, 0x02F0)[0]
        return x, (bytes(v.mem_get(0x4D00, 0x4D0C)).split(b"\0")[0] if x == 0 else None)

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
        v.mem_set(0x04, bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]))   # r1-r3
        serial_for("geoWrite")
        check("GetSerialNumber keeps r1-r3 (HG2G: destroys A only)",
              bytes(v.mem_get(0x04, 0x09)), bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]))
        check("not listed: the system's own", serial_for("geoPaint"), own)
        check("a class longer than 12 characters: left out", serial_for("A Very Long "), own)
        check("[desktop]'s line is no serial", serial_for("geoCalc"), own)
        serials(b"[serials]\r\n")
        check("an empty [serials]: the table cleared", serial_for("geoWrite"), own)
        check("no refusal noted at first", refused()[0] != 0, True)
        v.mem_set(k["taskName"], b"geoWrite".ljust(12, b"\0") + b"\0")
        box(11, b"\x18Not a refusal")
        check("an ordinary box: nothing noted", refused()[0] != 0, True)
        box(12, b"\x18Please reboot your system\x16\x50\x00\x40using the same GEOS disk")
        check("geoWrite's refusal (DBVARSTR): its class noted", refused(), (0, b"geoWrite"))
        check("the note read once: then nothing", refused()[0] != 0, True)
        box(11, b"\x18Please reboot your system")
        check("the same text with DBTXTSTR: noted too", refused(), (0, b"geoWrite"))
    finally:
        g.stop()
    print("serials: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
