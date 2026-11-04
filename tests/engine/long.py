#!/usr/bin/env python3
"""File engine step L: long names on GEOS drives, in VICE (docs/
FILE_ENGINE.md, "Long names").

On the drives of feharness.py (B: the reference D81 of the real 1581
DOS): files and a folder (a 1581 partition) with long names, their short
names (13 characters and ~n), reading by either name, FE_STAT and
FE_GETLONG, listings (long names, short ones in r3, patterns on long
names, GU.LONGNAMES hidden), rename (long to long, long to short),
FE_SETLONG, copy and move carrying the long name, delete dropping the
record, a stale record after an application's RenameFile, a path of more
than 127 bytes. Then the image in Python: GU.LONGNAMES's records and the
root BAM; the real 1581 DOS reads the image.
Usage: tests/engine/long.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feharness import *  # noqa: E402,F401,F403  (Engine, constants, part81)
from e2 import Image  # noqa: E402

FE_GETLONG, FE_SETLONG = 19, 20
WBUF, RBUF, LONGBUF, SHORTBUF = 0x5200, 0x5600, 0x5180, 0x51C0
LONG1 = "A very long file name number one"
LONG2 = "A very long file name number two"
LONG3 = "Renamed to yet another long name"
FOLDER = "My folder with a rather long name"
DATA = bytes((i * 5 + 1) & 0xFF for i in range(300))

CHECK = """10 open15,8,15:r$=""
20 open2,8,2,"gu.longnames,u,r":input#15,a:r$=r$+str$(a):close2
30 open2,8,2,"@0:result,s,w":print#2,r$:close2:close15
"""


def main():
    e = Engine("long", 6549)
    v, fe, stat, check = e.v, e.fe, e.stat, e.check

    def text(addr):
        return v.mem_get(addr, addr + 63).split(b"\0")[0].decode("latin1")

    def write(path, data):
        x, h, _ = fe(FE_OPEN, s0=path, r2=FO_WRITE)
        if x:
            return x
        v.mem_set(WBUF, data)
        x = fe(FE_WRITE, y=h, r1=WBUF, r2=len(data))[0]
        fe(FE_CLOSE, y=h)
        return x

    def read(path):
        x, h, _ = fe(FE_OPEN, s0=path, r2=FO_READ)
        if x:
            return x
        x, _, r = fe(FE_READ, y=h, r1=RBUF, r2=1000)
        fe(FE_CLOSE, y=h)
        return v.mem_get(RBUF, RBUF + r[2] - 1) if not x and r[2] else x

    def names(path):
        """FE_READDIR: (long or short name, short name) pairs."""
        x, h, _ = fe(FE_OPENDIR, s0=path)
        if x:
            return x
        out = []
        while True:
            x, _, _ = fe(FE_READDIR, y=h, r1=INFO, r2=LONGBUF, r3=SHORTBUF)
            if x:
                break
            out.append((text(LONGBUF), text(SHORTBUF)))
        fe(FE_CLOSE, y=h)
        return out

    def long_of(path):
        x = fe(FE_GETLONG, s0=path, r1=LONGBUF)[0]
        return text(LONGBUF) if x == 0 else x

    def stat_long(path):
        x = fe(FE_STAT, s0=path, r1=INFO, r2=LONGBUF)[0]
        return text(LONGBUF) if x == 0 else x

    try:
        e.start()
        check("FE_VERSION", fe(FE_VERSION)[2][0], 3)
        check("a file with a long name", (write("/b/" + LONG1, DATA), stat("/b/" + LONG1)), (0, (0, K_CBM, 2)))
        check("a second one", write("/b/" + LONG2, DATA[:10]), 0)
        root = names("/b")
        check("listed by long name, short names ~1 and ~2",
              [p for p in root if p[0].startswith("A very")],
              [(LONG1, "A very long f~1"), (LONG2, "A very long f~2")])
        check("GU.LONGNAMES not listed", [p for p in root if p[1] == "GU.LONGNAMES"], [])
        check("read by long name", read("/b/" + LONG1) == DATA, True)
        check("read by short name", read("/b/A very long f~2") == DATA[:10], True)
        check("FE_STAT's long name", stat_long("/b/A very long f~1"), LONG1)
        check("FE_GETLONG", (long_of("/b/A very long f~2"), long_of("/b/ROOTFILE")), (LONG2, "ROOTFILE"))
        check("a pattern on long names", [p[0] for p in names("/b/*number t*")], [LONG2])
        check("one file by its long name", names("/b/" + LONG2), [(LONG2, "A very long f~2")])
        check("FE_RENAME long to long",
              (fe(FE_RENAME, s0="/b/" + LONG1, s1=LONG3)[0], stat("/b/" + LONG1), long_of("/b/" + LONG3)),
              (0, (FILE_NOT_FOUND,), LONG3))
        check("FE_RENAME onto another file's long name", fe(FE_RENAME, s0="/b/" + LONG3, s1=LONG2)[0],
              FILE_EXISTS)
        check("FE_SETLONG long to short",
              (fe(FE_SETLONG, s0="/b/" + LONG3, s1="SHORTER")[0], long_of("/b/SHORTER"), read("/b/SHORTER") == DATA),
              (0, "SHORTER", True))
        check("FE_SETLONG short to long",
              (fe(FE_SETLONG, s0="/b/SHORTER", s1=LONG1)[0], long_of("/b/" + LONG1)), (0, LONG1))
        check("FE_MKDIR with a long name (a partition)",
              (fe(FE_MKDIR, s0="/b/" + FOLDER, r2=3)[0], stat("/b/" + FOLDER)[:2]), (0, (0, K_FOLDER)))
        check("FE_CD into it by its long name", (fe(FE_CD, s0="/b/" + FOLDER)[0], e.pwd()), (0, "/b/" + FOLDER))
        check("a long name inside it", (write(LONG2 + " inside", b"in"), read(LONG2 + " inside")), (0, b"in"))
        check("FE_COPY into a folder keeps the long name",
              (fe(FE_COPY, s0="/b/" + LONG1, s1=".")[0], read(LONG1) == DATA), (0, True))
        deep = "/b/" + FOLDER + "/" + "x" * 60
        far = deep + "/../" + LONG1
        check("a path of %d bytes" % len(far),
              (fe(FE_COPY, s0=LONG1, s1="x" * 60)[0], stat(deep)[:2], stat(far), fe(FE_DELETE, s0=deep)[0]),
              (0, (0, K_CBM), (0, K_CBM, 2), 0))
        check("FE_COPY to a new long name", (fe(FE_COPY, s0="/b/" + LONG2, s1="/b/" + FOLDER + "/copy with a long name too")[0],
                                             read("/b/" + FOLDER + "/copy with a long name too")), (0, DATA[:10]))
        check("FE_MOVE in one folder: a rename", (fe(FE_MOVE, s0="copy with a long name too", s1="moved, long name kept")[0],
                                                 stat("copy with a long name too"), read("moved, long name kept")),
              (0, (FILE_NOT_FOUND,), DATA[:10]))
        check("FE_CD /", fe(FE_CD, s0="/")[0], 0)
        check("FE_DELETE drops the record", (fe(FE_DELETE, s0="/b/" + LONG2)[0], stat("/b/" + LONG2),
                                             long_of("/b/A very long f~2")), (0, (FILE_NOT_FOUND,), FILE_NOT_FOUND))
        # An application renames LONG1's short name through the kernal: the
        # record goes stale and is ignored.
        e.text(PATH, "A very long f~1")
        e.text(PATH2, "PLAIN")
        e.run(e.xcall(DIR_ROOT) + e.ldw(PATH, 0x0E) + e.ldw(PATH2, 0x02) + e.jsr(e.t["RenameFile"]))
        check("after an application's RenameFile", (stat("/b/" + LONG1), long_of("/b/PLAIN")),
              ((FILE_NOT_FOUND,), "PLAIN"))
        check("a new file takes the name again", (write("/b/" + LONG1, b"new"), read("/b/" + LONG1)), (0, b"new"))
    finally:
        after = e.stop()
    img = Image(after)
    gu = img.entry("GU.LONGNAMES")
    recs = []
    if gu:
        data = img.chain(gu[1], gu[2])
        for i in range(0, len(data) - 126, 127):
            r = data[i:i + 127]
            if r[0]:
                recs.append((r[3:19].split(b"\xA0")[0].decode("latin1"), r[19:80].split(b"\0")[0].decode("latin1")))
    check("GU.LONGNAMES in the root: the records", sorted(recs),
          [("A very long f~1", LONG1), ("A very long f~1", LONG1), ("My folder wit~1", FOLDER)])
    # (the stale record and the new file's; the folder's)
    check("drive B's root BAM: exactly the blocks in use", img.root_bam_check(), ([], []))
    part81.basic_on(after, CHECK, "long-check")
    check("the real 1581 DOS reads GU.LONGNAMES", (part81.result_text(after) or "").split(), ["0"])
    sys.exit(0 if e.ok else 1)


if __name__ == "__main__":
    main()
