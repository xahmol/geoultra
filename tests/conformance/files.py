# Conformance cases for the file reading routines (src/kernal/files.s) on
# the oracle disk (GEOS 2.0's boot disk; GeoUltra mounts the same image).

NAME = 0x4F00                   # file name buffer
BUF = 0x4000
RES = 0x4E80


def name(text):
    return {NAME: [ord(c) for c in text] + [0]}


def find(title, text):
    return dict(name=title, routine="FindFile", r={"r6": NAME}, mem=name(text),
                compare=["X", "r1", "r5", "mem:$8400-$841D", "mem:$8000-$80FF"])


# After FindFile: GetFHdrInfo on dirEntryBuf
HDR_AFTER = [0xA9, 0x00, 0x85, 0x14, 0xA9, 0x84, 0x85, 0x15,      # r9 = dirEntryBuf
             0x20, 0x29, 0xC2]                                    # GetFHdrInfo

# ReadByte to the end of the chain, bytes to BUF on; X, end pointer to RES
READ_BYTES = [0xE0, 0x00, 0xD0, 0x10, 0xA0, 0x00, 0x91, 0x70, 0xE6, 0x70, 0xD0, 0x02,
              0xE6, 0x71, 0x20, 0xB6, 0xC2, 0xB8, 0x50, 0xEC,
              0x8E, RES & 0xFF, RES >> 8,
              0xA5, 0x70, 0x8D, (RES + 1) & 0xFF, RES >> 8,
              0xA5, 0x71, 0x8D, (RES + 2) & 0xFF, RES >> 8]


def read(title, t, s, size, end):
    return dict(name=title, routine="ReadFile", r={"r1L": t, "r1H": s, "r7": BUF, "r2": size},
                mem={BUF: [0xEE] * (end - BUF + 1), 0x8300: [0] * 64},
                compare=["X", "r7", "r2", "mem:$4000-$%04X" % end, "mem:$8300-$833F"])


CASES = [
    find("FindFile DESK TOP", "DESK TOP"),
    find("FindFile alarm clock (second block)", "alarm clock"),
    find("FindFile CONVERT (last entry)", "CONVERT"),
    dict(name="FindFile not found", routine="FindFile", r={"r6": NAME}, mem=name("NOPE"),
         compare=["X"]),
    dict(name="FindFile prefix is not a match", routine="FindFile", r={"r6": NAME},
         mem=name("DESK"), compare=["X"]),
    dict(name="GetFHdrInfo", routine="FindFile", r={"r6": NAME}, mem=name("preference mgr"),
         after=HDR_AFTER,
         compare=["X", "r1", "r7", "mem:$8100-$81FF", "mem:$8300-$8301"]),
    read("ReadFile alarm clock", 3, 3, 0x1F00, 0x4BFF),
    read("ReadFile GEOS (one block)", 16, 7, 0x1000, 0x41FF),
    dict(name="ReadFile buffer overflow", routine="ReadFile",
         r={"r1L": 3, "r1H": 3, "r7": BUF, "r2": 1000}, mem={BUF: [0xEE] * 0x400},
         compare=["X", "r1", "r7", "r2", "mem:$4000-$43FF", "mem:$8000-$80FF"]),
    dict(name="ReadByte to the end", routine="ReadByte",
         r={"r1L": 3, "r1H": 3, "r4": 0x4D00, "r5": 0}, poke={0x70: [0x00, 0x40]},
         mem={BUF: [0xEE] * 0xC00},
         after=READ_BYTES, compare=["mem:$4000-$4BFF", "mem:$4E80-$4E82"]),
    dict(name="FollowChain", routine="FollowChain", r={"r1L": 1, "r1H": 17, "r3": BUF},
         mem={BUF: [0xEE] * 64}, compare=["X", "r3", "mem:$4000-$403F"]),
    dict(name="FindFTypes printer drivers", routine="FindFTypes",
         r={"r6": BUF, "r7L": 9, "r7H": 10, "r10": 0}, mem={BUF: [0xEE] * 0xB0},
         compare=["X", "r7H", "mem:$4000-$40AF"]),
    # the names differ on purpose: through the jump table drive E's desk
    # accessory (GU Folder) comes first and keeps a place in a full list
    # (the user, 2026-11-13; sysdrive.s AppFTypes, rootmerge.s EFirst)
    dict(name="FindFTypes desk accessories, at most 2", routine="FindFTypes",
         r={"r6": BUF, "r7L": 5, "r7H": 2, "r10": 0}, mem={BUF: [0xEE] * 0x40},
         compare=["X", "r7H"]),
    dict(name="FindFTypes input drivers V1.1", routine="FindFTypes",
         r={"r6": BUF, "r7L": 10, "r7H": 5, "r10": NAME},
         mem={BUF: [0xEE] * 0x60, **name("Input Drvr  V1.1")},
         compare=["X", "r7H", "mem:$4000-$405F"]),
    dict(name="FindFTypes no match", routine="FindFTypes",
         r={"r6": BUF, "r7L": 10, "r7H": 5, "r10": NAME},
         mem={BUF: [0xEE] * 0x60, **name("Zzz")}, compare=["X", "r7H", "mem:$4000-$405F"]),
    # fonts and desk accessories pass GeoUltra's root folder and drive E
    # merges (rootmerge.s, sysdrive.s); a wrong carry once made a 1541
    # drive count as a folder and the search recursed without end. The
    # names and the count differ on purpose since 2026-11-16: drive E
    # holds GeoUltra's own fonts, which the jump table's FindFTypes adds
    # (docs/design/DESIGN.md "Fonts"; tests/fonts/fontlist.py checks them)
    dict(name="FindFTypes fonts, none on the disk", routine="FindFTypes",
         r={"r6": BUF, "r7L": 8, "r7H": 5, "r10": 0},
         mem={BUF: [0xEE] * 0x60}, compare=["X"]),
    dict(name="FindFTypes fonts by permanent name, none", routine="FindFTypes",
         r={"r6": BUF, "r7L": 8, "r7H": 5, "r10": NAME},
         mem={BUF: [0xEE] * 0x60, **name("Zzz")}, compare=["X", "r7H", "mem:$4000-$405F"]),
]
