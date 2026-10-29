# Conformance cases for 1581 allocation (harness --set d81). The oracle
# D81 is full on tracks 1-37 and 39, has 15 free blocks on track 38 and
# 30 on the directory track 40; tracks above 40 are mostly free.

BUF = 0x4000
NAME = 0x4500
HDR = 0x4600
DATA = 0x4800
BACK = 0x5000
CHECK = 0x4D00
RES = 0x4E80
BAMS = ["mem:$8200-$82FF", "mem:$8900-$89FF", "mem:$9C80-$9D7F"]


def bam(name, routine, r, compare, **kw):
    return dict(name=name, routine=routine, pre=["GetDirHead"], r=r, compare=compare, **kw)


def text(s):
    return [ord(c) for c in s] + [0]


def lda_sta(value, zp):
    return [0xA9, value, 0x85, zp]


READ_BACK = ([0x8E, RES & 0xFF, RES >> 8]
             + lda_sta(NAME & 0xFF, 0x0E) + lda_sta(NAME >> 8, 0x0F)
             + [0x20, 0x0B, 0xC2, 0x8E, (RES + 1) & 0xFF, RES >> 8]
             + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05]
             + lda_sta(BACK & 0xFF, 0x10) + lda_sta(BACK >> 8, 0x11)
             + lda_sta(0x00, 0x06) + lda_sta(0x10, 0x07)
             + [0x20, 0xFF, 0xC1, 0x8E, (RES + 2) & 0xFF, RES >> 8]
             + [0x20, 0x47, 0xC2, 0x60])
AFTER = [0x20, CHECK & 0xFF, CHECK >> 8]


def header(struct, start, end):
    h = [0] * 256
    h[0], h[1] = NAME & 0xFF, NAME >> 8
    h[2], h[3], h[4] = 3, 21, 0xBF
    h[0x44], h[0x45], h[0x46] = 0x83, 7, struct
    h[0x47], h[0x48], h[0x49], h[0x4A] = start & 0xFF, start >> 8, end & 0xFF, end >> 8
    return h


CASES = [
    bam("1581 FindBAMBit used (40/0)", "FindBAMBit", {"r6L": 40, "r6H": 0},
        ["A", "X", "r7H", "r8H"]),
    bam("1581 FindBAMBit free (70/13)", "FindBAMBit", {"r6L": 70, "r6H": 13},
        ["A", "X", "r7H", "r8H"]),
    bam("1581 AllocateBlock free", "AllocateBlock", {"r6L": 70, "r6H": 13}, ["X"] + BAMS),
    bam("1581 AllocateBlock used", "AllocateBlock", {"r6L": 1, "r6H": 0}, ["X"] + BAMS),
    bam("1581 FreeBlock used", "FreeBlock", {"r6L": 20, "r6H": 7}, ["X"] + BAMS),
    bam("1581 FreeBlock free", "FreeBlock", {"r6L": 80, "r6H": 39}, ["X"] + BAMS),
    bam("1581 SetNextFree from 1/0", "SetNextFree", {"r3L": 1, "r3H": 0}, ["X", "r3"] + BAMS),
    bam("1581 SetNextFree from 39/5", "SetNextFree", {"r3L": 39, "r3H": 5},
        ["X", "r3"] + BAMS),
    bam("1581 SetNextFree from 40/3 (directory)", "SetNextFree", {"r3L": 40, "r3H": 3},
        ["X", "r3"] + BAMS),
    bam("1581 SetNextFree from 60/38", "SetNextFree", {"r3L": 60, "r3H": 38},
        ["X", "r3"] + BAMS),
    bam("1581 BlkAlloc 8000 bytes", "BlkAlloc", {"r2": 8000, "r6": BUF},
        ["X", "r2", "r3", "mem:$4000-$407F"] + BAMS, mem={BUF: [0xEE] * 128}),
    bam("1581 NxtBlkAlloc from 50/10", "NxtBlkAlloc",
        {"r2": 3000, "r3L": 50, "r3H": 10, "r6": BUF},
        ["X", "r2", "r3", "mem:$4000-$403F"] + BAMS, mem={BUF: [0xEE] * 64}),
    dict(name="1581 GetFreeDirBlk page 1", routine="GetFreeDirBlk", r={"r10L": 1},
         compare=["X", "Y", "r1", "r10L", "mem:$8000-$80FF"]),
    # writes (each on a fresh disk)
    dict(name="1581 SaveFile (from SaveFile: track 39 first)", routine="SaveFile",
         writes=True, r={"r9": HDR, "r10L": 0},
         mem={HDR: header(0, DATA, DATA + 2000), NAME: text("GU 1581 test"),
              DATA: [(i * 13 + 5) & 0xFF for i in range(0x800)], CHECK: READ_BACK,
              BACK: [0xEE] * 0x800, RES: [0xEE] * 3},
         after=AFTER, compare=["mem:$4E80-$4E82", "mem:$5000-$57FF", "mem:$8400-$8416"] + BAMS),
    dict(name="1581 SaveFile VLIR", routine="SaveFile", writes=True,
         r={"r9": HDR, "r10L": 0},
         mem={HDR: header(1, DATA, DATA), NAME: text("GU 1581 vlir"), CHECK: READ_BACK,
              RES: [0xEE] * 3},
         after=AFTER, compare=["mem:$4E80-$4E81", "mem:$8400-$8416"] + BAMS),
    dict(name="1581 DeleteFile GEOWRITE", routine="DeleteFile", writes=True,
         r={"r0": NAME}, mem={NAME: text("GEOWRITE"), CHECK: READ_BACK, RES: [0xEE] * 3},
         after=AFTER, compare=["mem:$4E80-$4E81"] + BAMS),
    # SetGEOSDisk is not here: GEOS 2.0's 1581 turbo in VICE 3.10 hangs in
    # it almost every time (several writes to track 40 in a row). In the
    # one complete run (2026-10-29) it gave GeoUltra's result exactly:
    # X = 0, r1 = 40/2, border block 40/20, the signature in the header.
]
