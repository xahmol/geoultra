#!/usr/bin/env python3
"""geosup.py - does GEOS (GeoUltra) run on the Ultimate? For make deploy,
which must not replace disk images a running session has mounted (the
samples D81, 2026-11-25: its old copy's changed blocks were written into
the new file).

    tools/dev/geosup.py IP

Exit 0 when GEOS runs: "GEOS BOOT" at $C006 and the VIC in bitmap mode
($D011 bit 5). After a reset into BASIC the RAM still holds the bytes,
but the screen is text again. Exit 1 when it does not (or the Ultimate
does not answer: then nothing is mounted anywhere that could be hurt
by the copy either way the user decides).
"""
import sys
import urllib.request


def read(ip, addr, n):
    url = "http://%s/v1/machine:readmem?address=%04X&length=%d" % (ip, addr, n)
    with urllib.request.urlopen(url, timeout=10) as r:
        return r.read()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.strip().split("\n\n")[1].strip())
    try:
        geos = read(sys.argv[1], 0xC006, 9) == b"GEOS BOOT"
        bitmap = read(sys.argv[1], 0xD011, 1)[0] & 0x20 != 0
    except OSError:
        sys.exit(1)
    sys.exit(0 if geos and bitmap else 1)


if __name__ == "__main__":
    main()
