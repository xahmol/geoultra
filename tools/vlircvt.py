#!/usr/bin/env python3
"""vlircvt.py - make a VLIR CVT from a sequential one and record files.

    vlircvt.py IN.cvt OUT.cvt RECORD1 [RECORD2 ...]

IN.cvt is a sequential CVT (geos-oscar64's geosapp.py): its data becomes
record 0, each RECORD file the next record. The file becomes VLIR in its
directory entry and header, the signature "PRG formatted", and a record
table block (a block count and the last block's bytes + 1 per record)
comes before the records, each padded to whole 254-byte blocks: the CVT
layout c1541 -geoswrite and the GEOS converters read. gush's overlays
(docs/GUSH.md, "Memory").

Written 2026 by Xander Mol for GeoUltra (own code).
"""
import sys

BLOCK = 254


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__.strip().split("\n")[2].strip())
    cvt = open(argv[1], "rb").read()
    records = [cvt[2 * BLOCK:]] + [open(p, "rb").read() for p in argv[3:]]
    entry = bytearray(cvt[0:30])
    sig = bytearray(cvt[0:BLOCK])
    header = bytearray(cvt[BLOCK:2 * BLOCK])
    if not sig[30:58] == b"SEQ formatted GEOS file V1.0":
        sys.exit("vlircvt.py: %s is no sequential CVT" % argv[1])
    entry[21] = 1                                   # VLIR
    header[0x46 - 2] = 1                            # (the CVT keeps bytes 2-255)
    table = bytearray(BLOCK)
    data = b""
    blocks = 1                                      # the header block
    for i, r in enumerate(records):
        if not r:
            table[2 * i:2 * i + 2] = b"\x00\xff"    # an empty record
            continue
        n = (len(r) + BLOCK - 1) // BLOCK
        table[2 * i] = n
        table[2 * i + 1] = len(r) - (n - 1) * BLOCK + 1
        data += r + bytes(n * BLOCK - len(r))
        blocks += n
    blocks += 1                                     # the index block
    entry[28:30] = blocks.to_bytes(2, "little")
    sig[0:30] = entry
    sig[30:58] = b"PRG formatted GEOS file V1.0"
    with open(argv[2], "wb") as f:
        f.write(sig + header + table + data)
    print("%s: VLIR, %d records (%s bytes), %d blocks" % (argv[2], len(records),
          ", ".join(str(len(r)) for r in records), blocks))


if __name__ == "__main__":
    main(sys.argv)
