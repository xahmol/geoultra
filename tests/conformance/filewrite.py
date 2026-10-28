# Conformance cases for the file writing routines (src/kernal/filewrite.s).
# All write to the disk (writes=True: run last, each on a fresh copy of the
# oracle disk). Results are read back through the kernal: the directory
# entry (FindFile), the data (ReadFile), the BAM (GetDirHead). File dates
# come from each system's clock and are not compared.

NAME = 0x4F00
NAME2 = 0x4F20
HDR = 0x4000                    # file header for SaveFile
DATA = 0x4400
BACK = 0x5000                   # read back here
CHECK = 0x4E00                  # read-back routine
RES = 0x4E80

ENTRY = ["mem:$8400-$8416", "mem:$841C-$841D"]          # without the date
BAM = "mem:$8200-$82FF"


def text(s):
    return [ord(c) for c in s] + [0]


def lda_sta(value, zp):
    return [0xA9, value, 0x85, zp]


# RES = X of the call; FindFile NAME (RES+1); ReadFile of its data to BACK
# (RES+2); GetDirHead.
READ_BACK = ([0x8E, RES & 0xFF, RES >> 8]
             + lda_sta(NAME & 0xFF, 0x0E) + lda_sta(NAME >> 8, 0x0F)
             + [0x20, 0x0B, 0xC2, 0x8E, (RES + 1) & 0xFF, RES >> 8]
             + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05]
             + lda_sta(BACK & 0xFF, 0x10) + lda_sta(BACK >> 8, 0x11)
             + lda_sta(0x00, 0x06) + lda_sta(0x10, 0x07)
             + [0x20, 0xFF, 0xC1, 0x8E, (RES + 2) & 0xFF, RES >> 8]
             + [0x20, 0x47, 0xC2, 0x60])
AFTER = [0x20, CHECK & 0xFF, CHECK >> 8]


def header(name_ptr, cbm, gtype, struct, start, end):
    h = [0] * 256
    h[0], h[1] = name_ptr & 0xFF, name_ptr >> 8
    h[2], h[3], h[4] = 3, 21, 0xBF                      # icon: 3 x 21, bitmap
    h[0x44], h[0x45], h[0x46] = cbm, gtype, struct
    h[0x47], h[0x48], h[0x49], h[0x4A] = start & 0xFF, start >> 8, end & 0xFF, end >> 8
    h[0x4D:0x4D + 12] = [ord(c) for c in "GeoUltraTest"]
    h[0xA0:0xA0 + 5] = [ord(c) for c in "info!"]
    return h


def save(title, struct, length, compare_back):
    return dict(name=title, routine="SaveFile", writes=True,
                r={"r9": HDR, "r10L": 0},
                mem={HDR: header(NAME, 0x83, 7, struct, DATA, DATA + length),
                     NAME: text("GeoUltra test"), DATA: [(i * 13 + 5) & 0xFF for i in range(0x600)],
                     CHECK: READ_BACK, BACK: [0xEE] * 0x700, RES: [0xEE] * 3},
                after=AFTER,
                compare=["mem:$4E80-$4E82", BAM] + ENTRY + compare_back)


CASES = [
    save("SaveFile sequential", 0, 1000,
         ["mem:$5000-$56FF", "mem:$8100-$81FF"]),
    save("SaveFile exactly two blocks", 0, 508, ["mem:$5000-$52FF"]),
    save("SaveFile VLIR (empty index)", 1, 0, ["mem:$5000-$50FF", "mem:$8100-$81FF"]),
    dict(name="DeleteFile alarm clock", routine="DeleteFile", writes=True,
         r={"r0": NAME}, mem={NAME: text("alarm clock"), CHECK: READ_BACK, RES: [0xEE] * 3},
         after=AFTER, compare=["mem:$4E80-$4E81", BAM]),
    dict(name="DeleteFile DESK TOP (VLIR)", routine="DeleteFile", writes=True,
         r={"r0": NAME}, mem={NAME: text("DESK TOP"), CHECK: READ_BACK, RES: [0xEE] * 3},
         after=AFTER, compare=["mem:$4E80-$4E81", BAM]),
    # FollowChain builds the table (header block first), then FastDelFile
    dict(name="FastDelFile pad color mgr", routine="FollowChain", writes=True,
         r={"r1L": 2, "r1H": 2, "r3": 0x4002},
         mem={0x4000: [2, 15], NAME: text("pad color mgr"), CHECK: READ_BACK,
              RES: [0xEE] * 3},
         after=(lda_sta(NAME & 0xFF, 0x02) + lda_sta(NAME >> 8, 0x03)
                + lda_sta(0x00, 0x08) + lda_sta(0x40, 0x09)
                + [0x20, 0x44, 0xC2] + AFTER),
         compare=["mem:$4E80-$4E81", BAM]),
    dict(name="RenameFile CONVERT", routine="RenameFile", writes=True,
         r={"r6": NAME2, "r0": NAME},
         mem={NAME2: text("CONVERT"), NAME: text("Converted file"), CHECK: READ_BACK,
              RES: [0xEE] * 3},
         after=AFTER, compare=["mem:$4E80-$4E81"] + ENTRY),
    dict(name="RenameFile not found", routine="RenameFile", writes=True,
         r={"r6": NAME2, "r0": NAME}, mem={NAME2: text("NOPE"), NAME: text("x")},
         compare=["X"]),
    dict(name="WriteFile two blocks", routine="WriteFile", writes=True,
         r={"r6": 0x4000, "r7": DATA},
         mem={0x4000: [35, 0, 35, 1, 0, 0x80], DATA: [(i * 7) & 0xFF for i in range(0x300)],
              BACK: [0] * 0x200},
         after=([0x8E, RES & 0xFF, RES >> 8]
                + lda_sta(35, 0x04) + lda_sta(0, 0x05) + lda_sta(0x00, 0x0A) + lda_sta(0x50, 0x0B)
                + [0x20, 0xE4, 0xC1]
                + lda_sta(1, 0x05) + lda_sta(0x51, 0x0B) + [0x20, 0xE4, 0xC1]),
         compare=["mem:$4E80-$4E80", "r6", "r7", "mem:$5000-$51FF"]),
]
