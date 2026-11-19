#!/usr/bin/env python3
"""GU Commodore MPS (src/printer/mps.s) in VICE, as tests/print/ep1.py
(its runner: the bytes caught at the ROM's serial routines, read back by
cbmstream.py): a page of ten bands of pseudo-random dots (some cards
blank: runs; every other band blank from a card on: shorter lines)
printed directly, every dot of the first 60 cards where docs/design/DESIGN.md
"Printing" puts it (column X at 4X/240", row R at 3R/216": 7 rows a pass,
the rows left over carried to the next call and printed by StopPrint),
and no other; the same bytes through the spooler; an ASCII page as
PETSCII on channel 7 with NLQ. The driver is written onto a copy of an
applications disk (GEOS_APPS_DISK, the user's own).
Usage: tests/print/mp1.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cbmstream                                 # noqa: E402
import ep1                                       # noqa: E402

NAME = b"GU Commodore MPS"
CARDS = 60


def expected(data):
    want = set()
    for band in range(ep1.BANDS):
        for c in range(CARDS):
            for r in range(8):
                byte = data[band * 640 + c * 8 + r]
                for k in range(8):
                    if byte & (0x80 >> k):
                        want.add(((c * 8 + k) * 4, (band * 8 + r) * 3))
    return want


def petscii(text):
    out = bytearray()
    for ch in text:
        if 0x61 <= ch <= 0x7A:
            out.append(ch - 0x20)
        elif 0x41 <= ch <= 0x5A:
            out.append(ch + 0x80)
        else:
            out.append(ch)
    return bytes(out)


def main():
    ep1.disk_with("mps")
    rnd = random.Random(60)
    data = bytearray(rnd.getrandbits(8) for _ in range(ep1.BANDS * 640))
    for band in range(ep1.BANDS):               # blank cards: runs, a short line
        for i in range(20 * 8, 30 * 8):
            data[band * 640 + i] = 0
        for i in range(band * 4 * 8 + 300, 640):
            data[band * 640 + i] = 0 if band % 2 else data[band * 640 + i]
    data = bytes(data)
    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, "" if good else ": " + detail))

    res, direct = ep1.run("black", False, 0, data, bytes(800), name=NAME)
    check("driver loaded, StartPrint and StopPrint X = 0", res == "00aa0000", res)
    got = cbmstream.parse(direct)
    check("one page, ended by FF, nothing unexpected",
          len(got["pages"]) == 1 and direct.endswith(b"\x0c") and not got["unknown"],
          "%d pages, %d bytes, unknown %s" % (len(got["pages"]), len(direct), got["unknown"][:5]))
    want, have = expected(data), (got["pages"] or [set()])[0]
    check("every dot in place, 7 rows a pass, the last 3 by StopPrint (%d dots)" % len(want),
          want == have, "%d missing (e.g. %s), %d extra (e.g. %s)" % (
              len(want - have), sorted(want - have)[:3], len(have - want), sorted(have - want)[:3]))
    check("runs (blank cards) sent as CHR$(26) n b, lines cut after the last dot (%d bytes)"
          % len(direct), b"\x1a" in direct and len(direct) < 12 * 481 - 400, "")
    res, stream = ep1.run("spooled", False, 0, data, bytes(800), spooled=True, name=NAME)
    check("spooled (played from MainLoop): the same bytes", stream == direct and res == "00aa0000",
          "%s, %d bytes" % (res, len(stream)))
    res, stream = ep1.run("absent", False, 0, data, bytes(800), name=NAME, absent=True)
    check("no printer: StartPrint and StopPrint X = DEV_NOT_FOUND, the program goes on",
          res == "00aa0d0d" and stream == b"", "%s, %d bytes" % (res, len(stream)))
    res, stream = ep1.run("ascii", False, 1, data, bytes(800), name=NAME)
    got = cbmstream.parse(stream)
    check("ascii: StartASCII and StopPrint X = 0", res == "00aa0000", res)
    want = petscii(ep1.TEXT) + b"\f"
    check("ascii: the text as PETSCII (lower case set), CR, FF", got["text"] == want,
          "%r, expected %r" % (got["text"], want))
    check("ascii: SetNLQ as NLQ (CHR$(31)), channel 7", got["nlq"] and not got["unknown"],
          str(got["unknown"]))
    print("mp1: %s" % ("all passed" if ok else "FAILED"))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
