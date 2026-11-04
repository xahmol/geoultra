#!/usr/bin/env python3
"""sysreloc.py - relocate the system drive image to tracks 221-255.

    sysreloc.py IN.d64 OUT.d64 [OFFSET]

Drive E (docs/ARCHITECTURE.md "System drive") is a 1541 image whose
blocks the disk driver shows as tracks OFFSET+1 .. OFFSET+35 (default
220, src/inc/sysdrive.inc) of every drive. Every track/sector reference
in the image is moved up by OFFSET: the directory header's link and
border block, the directory chain, each entry's data and header block,
the block links of every file, and a VLIR file's index block and record
chains. Block positions, the BAM and the data stay as they are.

Written 2026 by Xander Mol for GeoUltra (own code).
"""
import sys

TRACKS = 35


def sectors(track):
    return 21 if track <= 17 else 19 if track <= 24 else 18 if track <= 30 else 17


def offset(track, sector):
    if not 1 <= track <= TRACKS or sector >= sectors(track):
        sys.exit("sysreloc.py: bad block %d/%d" % (track, sector))
    return (sum(sectors(t) for t in range(1, track)) + sector) * 256


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    image = bytearray(open(argv[1], "rb").read())
    if len(image) != 174848:
        sys.exit("sysreloc.py: %s is not a 35-track D64 without error bytes" % argv[1])
    shift = int(argv[3]) if len(argv) > 3 else 220
    if shift + TRACKS > 255:
        sys.exit("sysreloc.py: offset %d too large" % shift)
    done = set()

    def move(at):
        """The track/sector pair at image offset `at`, if it is one."""
        if image[at]:
            image[at] += shift

    def chain(track, sector):
        """Relocate the links of a block chain (read before changing)."""
        while track:
            if (track, sector) in done:
                sys.exit("sysreloc.py: block %d/%d in two chains" % (track, sector))
            done.add((track, sector))
            at = offset(track, sector)
            track, sector = image[at], image[at + 1]
            move(at)

    head = offset(18, 0)
    border = (image[head + 0xAB], image[head + 0xAC])
    first = (image[head], image[head + 1])
    move(head)
    if border[0]:
        move(head + 0xAB)
    blocks = []
    track, sector = first
    while track:
        if (track, sector) in blocks:
            sys.exit("sysreloc.py: the directory chain loops at %d/%d" % (track, sector))
        blocks.append((track, sector))
        at = offset(track, sector)
        track, sector = image[at], image[at + 1]
    chain(*first)
    if border[0]:
        blocks.append(border)
        done.add(border)
    files = 0
    for track, sector in blocks:
        base = offset(track, sector)
        for e in range(8):
            entry = base + 2 + 32 * e
            if not image[entry] & 0x07:
                continue
            files += 1
            data = (image[entry + 1], image[entry + 2])
            header = (image[entry + 0x13], image[entry + 0x14])
            geos = image[entry + 0x16] != 0
            vlir = geos and image[entry + 0x15] == 1
            move(entry + 1)
            if geos and header[0]:
                move(entry + 0x13)
                done.add(header)           # header block: link 0/$FF
            if vlir:
                at = offset(*data)
                done.add(data)
                records = []
                for r in range(2, 256, 2):
                    if image[at + r]:
                        records.append((image[at + r], image[at + r + 1]))
                        move(at + r)
                for record in records:
                    chain(*record)
            else:
                chain(*data)
    open(argv[2], "wb").write(image)
    print("%s: %d files, %d blocks relocated to tracks %d-%d"
          % (argv[2], files, len(done), shift + 1, shift + TRACKS))


if __name__ == "__main__":
    main(sys.argv)
