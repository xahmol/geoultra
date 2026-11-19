#!/usr/bin/env python3
"""The clock from NTP seconds in VICE (src/kernal/enginentp.s, module 78,
and module 79's summer-time rule; docs/design/SETTINGS.md, the Time page): the
module called directly with an NTP time, [time] offset= and summer=
set in its variables (VICE has no network for FE_NTP itself), GEOS's
clock read afterwards. The EU rule around both switches of 2026 (the
last Sundays, 29 March and 25 October, at 01:00 UTC), a summer and a
winter day, the rule off, a negative offset, and 29 February 2028 (the
month loop's leap-year February, fixed 2026-11-12).
Usage: tests/engine/dst.py
"""
import calendar
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feharness import *  # noqa: E402,F401,F403  (Engine)
from vicemon import RESP_CHECKPOINT  # noqa: E402

NTP_FROM_UNIX = 2208988800
FE_WORK = 0x9F70
FE_INFO = FE_WORK + 62
N_TIME, N_OFF, N_DST = FE_INFO, FE_INFO + 4, FE_WORK + 105
CLOCK = 0x8516                                  # year, month, day, hour, minutes, seconds
SET_TIME = 0x9D80 + 3                           # module 78's SetTime (after its entry jmp)


def main():
    e = Engine("dst", 6595)
    v, check = e.v, e.check
    kern = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        p = line.split()
        kern.setdefault(p[2].lstrip("."), int(p[1], 16))
    ovl = kern["OvlCall"]

    def clock(utc, offset, dst):
        ntp = calendar.timegm(utc) + NTP_FROM_UNIX
        v.mem_set(N_TIME, ntp.to_bytes(4, "little"))
        v.mem_set(N_OFF, (offset & 0xFFFFFF).to_bytes(3, "little"))
        v.mem_set(N_DST, bytes([dst]))
        start = 0x0800                                  # (no file engine call:
        prog = [0x78, 0xA9, 0x30, 0x85, 0x01,           # stopped at module 78's
                0x20, ovl & 0xFF, ovl >> 8, 78, 0]      # SetTime, the clock set)
        prog += [0x4C, (start + len(prog)) & 0xFF, (start + len(prog)) >> 8]
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        cid = v.checkpoint(SET_TIME, temporary=False)
        while True:
            v.resume()
            v.wait_event(RESP_CHECKPOINT, timeout=30)
            if bytes(v.mem_get(SET_TIME, SET_TIME + 4)) == bytes([0x20, ovl & 0xFF, ovl >> 8, 75, 6]):
                break                                   # (module 78's, not 79's)
        v.delete_checkpoint(cid)
        c = v.mem_get(CLOCK, CLOCK + 5)
        return "%02d-%02d-%02d %02d:%02d:%02d" % tuple(c)

    try:
        e.start()
        cases = [
            ("EU: 29 March 2026 00:59:59 UTC, still winter", (2026, 3, 29, 0, 59, 59), 3600, 1,
             "26-03-29 01:59:59"),
            ("EU: 29 March 2026 01:00 UTC, summer", (2026, 3, 29, 1, 0, 0), 3600, 1, "26-03-29 03:00:00"),
            ("EU: 28 March 2026 23:00 UTC (the day before)", (2026, 3, 28, 23, 0, 0), 3600, 1,
             "26-03-29 00:00:00"),
            ("EU: 25 October 2026 00:59:59 UTC, still summer", (2026, 10, 25, 0, 59, 59), 3600, 1,
             "26-10-25 02:59:59"),
            ("EU: 25 October 2026 01:00 UTC, winter", (2026, 10, 25, 1, 0, 0), 3600, 1,
             "26-10-25 02:00:00"),
            ("EU: 1 July 2026 12:00 UTC", (2026, 7, 1, 12, 0, 0), 3600, 1, "26-07-01 14:00:00"),
            ("EU: 1 December 2026 12:00 UTC", (2026, 12, 1, 12, 0, 0), 3600, 1, "26-12-01 13:00:00"),
            ("summer time off: 1 July 2026 12:00 UTC", (2026, 7, 1, 12, 0, 0), 3600, 0,
             "26-07-01 13:00:00"),
            ("a negative offset with the EU rule (-1 h)", (2026, 7, 1, 12, 0, 0), -3600, 1,
             "26-07-01 12:00:00"),
            ("29 February 2028 (a leap year's February)", (2028, 2, 29, 12, 0, 0), 0, 0,
             "28-02-29 12:00:00"),
            ("1 March 2028", (2028, 3, 1, 0, 0, 1), 0, 0, "28-03-01 00:00:01"),
            ("EU 2028: 26 March 01:00 UTC (its last Sunday)", (2028, 3, 26, 1, 0, 0), 3600, 1,
             "28-03-26 03:00:00"),
        ]
        for title, utc, offset, dst, want in cases:
            check(title, clock(utc + (0, 0, 0), offset, dst), want)
    finally:
        e.stop()
    sys.exit(0 if e.ok else 1)


if __name__ == "__main__":
    main()
