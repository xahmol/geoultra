#!/usr/bin/env python3
"""Pack 8 KB ROM banks into a Megabyter (CRT type 86) cartridge image.

Usage: mkcrt.py OUT.crt NAME BANK0.bin [FILE.bin ...]
       mkcrt.py OUT.crt NAME BANK0.bin --pattern N

Files larger than 8 KB fill several consecutive banks.

--pattern N appends banks 1..N filled with the smoke test pattern
(byte 0 = bank number, then (i ^ (i >> 8) ^ bank * 37) & 0xFF).

CRT layout from the VICE manual (crt format) and the Ultimate firmware's
c64_crt.cc: 64-byte header, then one CHIP packet per bank.
"""
import struct
import sys

BANK_SIZE = 0x2000
CRT_TYPE_MEGABYTER = 86


def header(name):
    # EXROM line 0 (active), GAME line 1 (inactive): 8K mode at start-up
    return (b"C64 CARTRIDGE   "
            + struct.pack(">IHHBBB", 0x40, 0x0100, CRT_TYPE_MEGABYTER, 0, 1, 0)
            + bytes(5)
            + name.encode("ascii")[:32].ljust(32, b"\0"))


def chip(bank, data):
    data = data.ljust(BANK_SIZE, b"\xff")
    if len(data) != BANK_SIZE:
        sys.exit("bank %d larger than 8 KB" % bank)
    return b"CHIP" + struct.pack(">IHHHH", 0x10 + BANK_SIZE, 0, bank, 0x8000,
                                 BANK_SIZE) + data


def pattern(bank):
    data = bytearray((i ^ (i >> 8) ^ bank * 37) & 0xFF for i in range(BANK_SIZE))
    data[0] = bank
    return bytes(data)


def read_banks(files):
    banks = []
    for f in files:
        data = open(f, "rb").read()
        banks += [data[i:i + BANK_SIZE] for i in range(0, max(len(data), 1), BANK_SIZE)]
    return banks


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    out, name, files = argv[1], argv[2], argv[3:]
    banks = []
    if "--pattern" in files:
        i = files.index("--pattern")
        count = int(files[i + 1])
        files = files[:i] + files[i + 2:]
        banks = read_banks(files)
        banks += [pattern(b) for b in range(len(banks), len(banks) + count)]
    else:
        banks = read_banks(files)
    with open(out, "wb") as f:
        f.write(header(name))
        for n, data in enumerate(banks):
            f.write(chip(n, data))


if __name__ == "__main__":
    main(sys.argv)
