# Conformance cases for the disk driver (src/drivers/reudrv.s) and the
# device routines: GEOS 2.0 reads its boot disk through the 1541 turbo,
# GeoUltra the same disk image from the REU (tools/harness/harness.py,
# prepare_disks).

BUF = 0x4000
BUF2 = 0x4100
RES = 0x4380
TAB = 0x4400                    # GetNxtDirEntry log: X, r5L, r5H, Y per call
COUNT = 0x43F0


def blk(t, s, buf=BUF):
    return {"r1L": t, "r1H": s, "r4": buf}


def read(name, t, s, extra=()):
    return dict(name=name, routine="GetBlock", r=blk(t, s), mem={BUF: [0xEE] * 256},
                compare=["X", "r1", "r4", "mem:$4000-$40FF"] + list(extra))


# After Get1stDirEntry: 40 calls of GetNxtDirEntry, results logged at TAB
NEXT_LOOP = [0xA2, 0x00,                                  # ldx #0
             0x8E, COUNT & 0xFF, COUNT >> 8,              # loop: stx COUNT
             0x20, 0x33, 0x90,                            # jsr GetNxtDirEntry
             0x8A,                                        # txa
             0xAE, COUNT & 0xFF, COUNT >> 8,              # ldx COUNT
             0x9D, 0x00, 0x44,                            # sta TAB,x
             0xA5, 0x0C, 0x9D, 0x40, 0x44,                # r5L -> TAB+$40,x
             0xA5, 0x0D, 0x9D, 0x80, 0x44,                # r5H -> TAB+$80,x
             0x98, 0x9D, 0xC0, 0x44,                      # Y -> TAB+$C0,x
             0xE8, 0xE0, 40,                              # inx; cpx #40
             0xD0, 0x100 - 32]                            # bne loop

# InitForIO, then $01, $D015, $D01A to RES, DoneWithIO, $01 to RES+3
IO_AFTER = [0xA5, 0x01, 0x8D, RES & 0xFF, RES >> 8,
            0xAD, 0x15, 0xD0, 0x8D, (RES + 1) & 0xFF, RES >> 8,
            0xAD, 0x1A, 0xD0, 0x8D, (RES + 2) & 0xFF, RES >> 8,
            0x20, 0x5F, 0xC2,
            0xA5, 0x01, 0x8D, (RES + 3) & 0xFF, RES >> 8]

CASES = [
    read("GetBlock 18/0 (directory header)", 18, 0),
    read("GetBlock 1/0", 1, 0),
    read("GetBlock 17/20 (end of zone 1)", 17, 20),
    read("GetBlock 24/18", 24, 18),
    read("GetBlock 35/16 (last block)", 35, 16),
    read("GetBlock track 0", 0, 0, ["mem:$4000-$4001"]),
    read("GetBlock track 36", 36, 0),
    # GEOS 2.0 then copies the drive's stale buffer; GeoUltra leaves it alone
    dict(name="GetBlock sector 21 on track 1", routine="GetBlock", r=blk(1, 21),
         compare=["X", "r1", "r4"]),
    dict(name="ReadBlock 18/1", routine="ReadBlock", r=blk(18, 1), mem={BUF: [0] * 256},
         pre=["EnterTurbo", "InitForIO"], after=[0x20, 0x5F, 0xC2],
         compare=["X", "mem:$4000-$40FF"]),
    dict(name="ReadBuff 18/1", routine="ReadBuff", r={"r1L": 18, "r1H": 1},
         compare=["X", "r4", "mem:$8000-$80FF"]),
    dict(name="ReadLink 18/2", routine="ReadLink", r=blk(18, 2), mem={BUF: [0] * 256},
         pre=["EnterTurbo", "InitForIO"], after=[0x20, 0x5F, 0xC2],
         compare=["X", "mem:$4000-$4001"]),
    dict(name="PutBlock and GetBlock back", writes=True, routine="PutBlock", r=blk(35, 15),
         mem={BUF: [(i * 7 + 3) & 0xFF for i in range(256)], BUF2: [0] * 256},
         after=[0x8E, RES & 0xFF, RES >> 8,                       # stx RES
                0xA9, BUF2 & 0xFF, 0x85, 0x0A, 0xA9, BUF2 >> 8, 0x85, 0x0B,
                0x20, 0xE4, 0xC1],                                # GetBlock to BUF2
         compare=["X", "mem:$4380-$4380", "mem:$4100-$41FF", "r1"]),
    dict(name="GetDirHead", routine="GetDirHead", mem={0x8200: [0] * 256},
         compare=["X", "r4", "mem:$8200-$82FF"]),
    dict(name="OpenDisk", routine="OpenDisk", mem={0x841E: [0] * 18, 0x848B: [0x55]},
         compare=["X", "r5", "mem:$841E-$842F", "mem:$848B-$848B", "mem:$8200-$82FF"]),
    dict(name="ChkDkGEOS on the GEOS disk", routine="ChkDkGEOS", pre=["GetDirHead"],
         r={"r5": 0x8200}, compare=["A", "mem:$848B-$848B"]),
    dict(name="ChkDkGEOS on a plain header", routine="ChkDkGEOS", r={"r5": BUF},
         mem={BUF: [0] * 173 + [ord(c) for c in "GEOS formax"] + [0] * 72},
         compare=["A", "mem:$848B-$848B"]),
    dict(name="CalcBlksFree", routine="CalcBlksFree", pre=["GetDirHead"],
         r={"r5": 0x8200}, compare=["r3", "r4", "r5"]),
    dict(name="Get1stDirEntry", routine="Get1stDirEntry",
         compare=["X", "r1", "r5", "mem:$8000-$80FF"]),
    dict(name="GetNxtDirEntry to the end and the border", routine="Get1stDirEntry",
         after=NEXT_LOOP, mem={TAB: [0] * 256}, compare=["mem:$4400-$44FF", "mem:$8000-$80FF"]),
    dict(name="GetBorder", routine="GetBorder", compare=["X", "Y", "r1", "r5"]),
    dict(name="InitForIO and DoneWithIO", routine="InitForIO", after=IO_AFTER,
         compare=["mem:$4380-$4383", "io:$D015-$D015", "io:$D01A-$D01A"]),
    dict(name="SetDevice printer", routine="SetDevice", a=4,
         compare=["X", "mem:$8489-$8489", "mem:$BA-$BA"]),
    # curType differs by design: GeoUltra's drives are RAM drives ($80 | type)
    dict(name="SetDevice 8", routine="SetDevice", a=8,
         compare=["X", "mem:$8489-$8489", "mem:$BA-$BA"]),
    dict(name="GetPtrCurDkNm", routine="GetPtrCurDkNm", x=0x06, compare=["r2"]),
]

# BAM and allocation (after GetDirHead; the BAM changes stay in curDirHead)
HEAD = "mem:$8200-$82FF"


def bam(name, routine, r, compare, **kw):
    return dict(name=name, routine=routine, pre=["GetDirHead"], r=r, compare=compare, **kw)


CASES += [
    dict(name="interleave", routine="SetDevice", a=8, compare=["mem:$848C-$848C"]),
    bam("FindBAMBit used block", "FindBAMBit", {"r6L": 18, "r6H": 0}, ["A", "X", "r7H", "r8H"]),
    bam("FindBAMBit free block", "FindBAMBit", {"r6L": 34, "r6H": 9}, ["A", "X", "r7H", "r8H"]),
    bam("AllocateBlock free", "AllocateBlock", {"r6L": 34, "r6H": 9}, ["X", "r6", HEAD]),
    bam("AllocateBlock used", "AllocateBlock", {"r6L": 18, "r6H": 0}, ["X", "r6", HEAD]),
    bam("FreeBlock used", "FreeBlock", {"r6L": 18, "r6H": 1}, ["X", "r6", HEAD]),
    bam("FreeBlock free", "FreeBlock", {"r6L": 34, "r6H": 9}, ["X", "r6", HEAD]),
    bam("SetNextFree from 1/0", "SetNextFree", {"r3L": 1, "r3H": 0}, ["X", "r3", HEAD]),
    bam("SetNextFree from 18/1", "SetNextFree", {"r3L": 18, "r3H": 1}, ["X", "r3", HEAD]),
    bam("SetNextFree from 17/20", "SetNextFree", {"r3L": 17, "r3H": 20}, ["X", "r3", HEAD]),
    bam("SetNextFree from 28/12", "SetNextFree", {"r3L": 28, "r3H": 12}, ["X", "r3", HEAD]),
    bam("BlkAlloc 3000 bytes", "BlkAlloc", {"r2": 3000, "r6": BUF},
        ["X", "r2", "r3", HEAD, "mem:$4000-$403F"], mem={BUF: [0xEE] * 64}),
    bam("BlkAlloc 2540 bytes (whole blocks)", "BlkAlloc", {"r2": 2540, "r6": BUF},
        ["X", "r2", "r3", HEAD, "mem:$4000-$403F"], mem={BUF: [0xEE] * 64}),
    bam("NxtBlkAlloc from 20/3", "NxtBlkAlloc", {"r2": 1000, "r3L": 20, "r3H": 3, "r6": BUF},
        ["X", "r2", "r3", HEAD, "mem:$4000-$403F"], mem={BUF: [0xEE] * 64}),
    bam("BlkAlloc more than the disk", "BlkAlloc", {"r2": 0x7F00, "r6": BUF},
        ["X", HEAD]),
    # These write to the disk (writes=True: run last, each on a fresh disk)
    dict(name="GetFreeDirBlk adds a block", writes=True, routine="GetFreeDirBlk", pre=["GetDirHead"],
         r={"r10L": 4}, compare=["X", "Y", "r1", "r10L", "mem:$8000-$80FF", HEAD]),
    dict(name="SetGEOSDisk", writes=True, routine="SetGEOSDisk",
         compare=["X", "r1", "mem:$8000-$80FF", HEAD]),
]
