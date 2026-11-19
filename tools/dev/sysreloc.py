#!/usr/bin/env python3
"""sysreloc.py - relocate the system drive image to tracks above OFFSET.

    sysreloc.py IN.dnp OUT.dnp OFFSET [TRACKS]
    sysreloc.py IN.d64 OUT.d64 [OFFSET]

Drive E (docs/reference/ARCHITECTURE.md "System drive") is an image whose blocks
the disk driver shows as tracks OFFSET+1 and up (src/inc/sysdrive.inc)
of every drive. Every track/sector reference in the image is moved up by
OFFSET; block positions, the BAM (read by position) and the data stay as
they are.

DNP (CMD native, since 2026-11-06; the layout tools/mkappsdnp.py
writes): the root header 1/1 (its directory, its own block at $20, the
parent fields $22 and $24, the border block at $AB), each folder's
header the same way (reached through its directory entry, type $86),
every directory chain, and per file its data or VLIR index and record
chains and its GEOS header. TRACKS, when given, must be the image's
(src/inc/sysdrive.inc SYSDRV_TRACKS). OUT ends after the last track
holding any of the image's blocks (the cartridge stores no empty
tracks; nothing reads E's free blocks). D64 (35 tracks, the format until then): the
directory header's link and border block, the directory chain, each
entry's data and header block, the file's block links, a VLIR file's
index block and record chains.

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


class Dnp:
    """A DNP image's references moved up by `shift`."""

    def __init__(self, image, shift):
        self.image, self.shift = image, shift
        self.tracks = len(image) // 65536
        self.done = set()
        self.files = 0

    def at(self, track, sector):
        if not 1 <= track <= self.tracks:
            sys.exit("sysreloc.py: bad block %d/%d" % (track, sector))
        return ((track - 1) * 256 + sector) * 256

    def move(self, at):
        if self.image[at]:
            self.image[at] += self.shift

    def claim(self, ts):
        if ts in self.done:
            sys.exit("sysreloc.py: block %d/%d reached twice" % ts)
        self.done.add(ts)

    def chain(self, track, sector):
        """A chain's links moved (each read before it changes)."""
        while track:
            self.claim((track, sector))
            at = self.at(track, sector)
            track, sector = self.image[at], self.image[at + 1]
            self.move(at)

    def folder(self, header, root):
        """A folder: its header's fields, its directory, its entries."""
        self.claim(header)
        h = self.at(*header)
        img = self.image
        first = (img[h], img[h + 1])
        border = (img[h + 0xAB], img[h + 0xAC]) if root else (0, 0)
        for field in (0, 0x20, 0x22, 0x24):
            self.move(h + field)
        if border[0]:
            self.move(h + 0xAB)
        blocks = []
        track, sector = first
        while track:
            if (track, sector) in blocks:
                sys.exit("sysreloc.py: a directory chain loops at %d/%d" % (track, sector))
            blocks.append((track, sector))
            at = self.at(track, sector)
            track, sector = img[at], img[at + 1]
        self.chain(*first)
        if border[0]:
            blocks.append(border)
            self.claim(border)
        for block in blocks:
            base = self.at(*block)
            for e in range(8):
                self.entry(base + 2 + 32 * e)

    def entry(self, entry):
        img = self.image
        kind = img[entry] & 0x07
        if not kind:
            return
        data = (img[entry + 1], img[entry + 2])
        if kind == 6:                               # a folder ($86)
            self.move(entry + 1)
            self.folder(data, False)
            return
        self.files += 1
        header = (img[entry + 0x13], img[entry + 0x14])
        geos = img[entry + 0x16] != 0
        vlir = geos and img[entry + 0x15] == 1
        self.move(entry + 1)
        if geos and header[0]:
            self.move(entry + 0x13)
            self.claim(header)                      # header block: link 0/$FF
        if vlir:
            self.claim(data)
            at = self.at(*data)
            records = []
            for r in range(2, 256, 2):
                if img[at + r]:
                    records.append((img[at + r], img[at + r + 1]))
                    self.move(at + r)
            for record in records:
                self.chain(*record)
        else:
            self.chain(*data)


def dnp(argv):
    image = bytearray(open(argv[1], "rb").read())
    if len(image) % 65536 or not image:
        sys.exit("sysreloc.py: %s is not a DNP image" % argv[1])
    shift = int(argv[3])
    d = Dnp(image, shift)
    if shift + d.tracks > 255:
        sys.exit("sysreloc.py: offset %d too large for %d tracks" % (shift, d.tracks))
    if len(argv) > 4 and int(argv[4]) != d.tracks:
        sys.exit("sysreloc.py: %d tracks, SYSDRV_TRACKS says %s" % (d.tracks, argv[4]))
    d.folder((1, 1), True)
    last = max(t for t, _ in d.done | {(1, 0)})
    open(argv[2], "wb").write(image[:last * 65536])
    print("%s: %d files, %d blocks relocated to tracks %d-%d, %d track(s) stored"
          % (argv[2], d.files, len(d.done), shift + 1, shift + d.tracks, last))


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    if argv[1].lower().endswith(".dnp"):
        if len(argv) < 4:
            sys.exit(__doc__)
        return dnp(argv)
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
