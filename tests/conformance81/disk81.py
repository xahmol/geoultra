# Conformance cases for 1581 images (harness --set d81: GEOS 2.0 boots
# GEOS64.D81 on a 1581 in VICE, GeoUltra mounts the same image as REU
# drive A, type 1581).

BUF = 0x4000
NAME = 0x4500
RES = 0x4380
TAB = 0x4400
COUNT = 0x43F0


def blk(t, s, buf=BUF):
    return {"r1L": t, "r1H": s, "r4": buf}


def read(name, t, s):
    return dict(name=name, routine="GetBlock", r=blk(t, s), mem={BUF: [0xEE] * 256},
                compare=["X", "r1", "r4", "mem:$4000-$40FF"])


def text(s):
    return [ord(c) for c in s] + [0]


# After Get1stDirEntry: 60 calls of GetNxtDirEntry, logged at TAB
NEXT_LOOP = [0xA2, 0x00, 0x8E, COUNT & 0xFF, COUNT >> 8, 0x20, 0x33, 0x90, 0x8A,
             0xAE, COUNT & 0xFF, COUNT >> 8, 0x9D, 0x00, 0x44, 0xA5, 0x0C, 0x9D, 0x40, 0x44,
             0xA5, 0x0D, 0x9D, 0x80, 0x44, 0x98, 0x9D, 0xC0, 0x44, 0xE8, 0xE0, 60,
             0xD0, 0x100 - 32]

CASES = [
    read("1581 GetBlock 40/0 (header)", 40, 0),
    read("1581 GetBlock 40/1 (BAM 1)", 40, 1),
    read("1581 GetBlock 1/0", 1, 0),
    read("1581 GetBlock 80/39 (last block)", 80, 39),
    read("1581 GetBlock track 81", 81, 0),
    dict(name="1581 GetDirHead", routine="GetDirHead",
         compare=["X", "r4", "mem:$8200-$82FF", "mem:$8900-$89FF", "mem:$9C80-$9D7F"]),
    dict(name="1581 OpenDisk", routine="OpenDisk", mem={0x841E: [0] * 18},
         compare=["X", "r5", "mem:$841E-$842F", "mem:$848B-$848B"]),
    dict(name="1581 CalcBlksFree", routine="CalcBlksFree", pre=["GetDirHead"],
         r={"r5": 0x8200}, compare=["r3", "r4"]),
    dict(name="1581 Get1stDirEntry", routine="Get1stDirEntry",
         compare=["X", "r1", "r5", "mem:$8000-$80FF"]),
    dict(name="1581 GetNxtDirEntry to the end", routine="Get1stDirEntry",
         after=NEXT_LOOP, mem={TAB: [0] * 256}, compare=["mem:$4400-$44FF"]),
    dict(name="1581 FindFile GEOWRITE", routine="FindFile", r={"r6": NAME},
         mem={NAME: text("GEOWRITE")}, compare=["X", "r1", "r5", "mem:$8400-$841D"]),
    dict(name="1581 ReadFile alarm clock", routine="FindFile", r={"r6": NAME},
         mem={NAME: text("alarm clock"), 0x5000: [0xEE] * 0x1000},
         after=[0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05,
                0xA9, 0x00, 0x85, 0x10, 0xA9, 0x50, 0x85, 0x11,
                0xA9, 0x00, 0x85, 0x06, 0xA9, 0x10, 0x85, 0x07,
                0x20, 0xFF, 0xC1, 0x8E, RES & 0xFF, RES >> 8],
         compare=["mem:$4380-$4380", "mem:$5000-$5FFF", "r7", "r2"]),
]
