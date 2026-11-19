#!/usr/bin/env python3
"""File engine on GeoUltra in VICE (docs/design/FILE_ENGINE.md).

The reference D81 of tests/drives/part81.py (made by the real 1581 DOS:
SUB1 with HELLO and the nested SUB2 with DEEP, RAW, ROOTFILE) is drive B;
drive A is the GEOS 2.0 disk (GEOS_ORACLE, only read). Each call runs with
the caller on drive B in SUB1; afterwards the caller's drive, folder and
directory header must be as before. Checked: FE_VERSION, FE_PWD, FE_CD,
FE_STAT, FE_OPENDIR/READDIR/CLOSE (patterns, "/", handles running out),
FE_DF, FE_MKDIR/RMDIR, FE_RENAME, FE_DELETE, the errors; then the real 1581
DOS reads the image back. No private files are written.
Usage: tests/engine/e1.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from feharness import *  # noqa: E402,F401,F403  (Engine, constants, part81)

CHECK = """10 open15,8,15:r$=""
20 print#15,"/0:sub1":input#15,a:r$=r$+str$(a)
30 open2,8,2,"hello,s,r":input#15,a:r$=r$+str$(a):close2
50 print#15,"/":input#15,a:r$=r$+str$(a)
60 open2,8,2,"rootfile,s,r":input#15,a:r$=r$+str$(a):close2
70 open2,8,2,"@0:result,s,w":print#2,r$:close2:close15
"""


def main():
    e = Engine("e1", 6547)
    v, fe, stat, listing, pwd, check = e.v, e.fe, e.stat, e.listing, e.pwd, e.check
    try:
        e.start()
        x, _, r = fe(FE_VERSION)
        check("FE_VERSION", (x, r[0]), (0, 3))
        check("FE_PWD at the start", pwd(), "/")
        check("FE_STAT /", stat("/"), (0, K_ROOT, 0))
        check("FE_STAT /b", stat("/b"), (0, K_DRIVE, 0))
        check("FE_STAT /b/ROOTFILE", stat("/b/ROOTFILE"), (0, K_CBM, 1))
        check("FE_STAT /b/SUB1", stat("/b/SUB1"), (0, K_FOLDER, 400))
        check("FE_STAT /b/SUB1/SUB2/DEEP", stat("/b/SUB1/SUB2/DEEP"), (0, K_CBM, 1))
        check("FE_STAT with . and ..", stat("/b/./SUB1/SUB2/../../ROOTFILE"), (0, K_CBM, 1))
        check("FE_STAT .. above the top", stat("/../../b/ROOTFILE"), (0, K_CBM, 1))
        check("FE_STAT a missing file", stat("/b/NOPE"), (FILE_NOT_FOUND,))
        check("FE_STAT through a file", stat("/b/ROOTFILE/X"), (NOT_FOLDER,))
        check("FE_STAT through RAW (no sub-directory)", stat("/b/RAW/X"), (NOT_FOLDER,))
        check("FE_STAT an unknown top", stat("/z"), (FILE_NOT_FOUND,))
        check("FE_STAT /usb0 without an Ultimate", stat("/usb0/x"), (DEV_NOT_FOUND,))
        check("FE_STAT a 17-character name (a long one, not there)", stat("/b/ABCDEFGHIJKLMNOPQ"), (FILE_NOT_FOUND,))
        check("FE_STAT a long path", stat("/b/" + "./" * 55 + "ROOTFILE"), (0, K_CBM, 1))
        check("FE_STAT a path of 200 bytes", stat("/b/" + "./" * 95 + "ROOTFILE"), (0, K_CBM, 1))
        check("FE_STAT a path too long", stat("/b/" + "./" * 130 + "ROOTFILE"), (BAD_PATH,))
        check("FE_CD /b/SUB1", fe(FE_CD, s0="/b/SUB1")[0], 0)
        check("FE_PWD", pwd(), "/b/SUB1")
        check("FE_STAT relative", stat("HELLO"), (0, K_CBM, 1))
        check("FE_CD relative", (fe(FE_CD, s0="SUB2")[0], pwd()), (0, "/b/SUB1/SUB2"))
        check("FE_CD ..", (fe(FE_CD, s0="..")[0], pwd()), (0, "/b/SUB1"))
        check("FE_CD to a file refused", (fe(FE_CD, s0="/b/ROOTFILE")[0], pwd()), (NOT_FOLDER, "/b/SUB1"))
        check("FE_CD /", (fe(FE_CD, s0="/")[0], pwd()), (0, "/"))
        check("FE_OPENDIR / (and e, the system drive)", listing("/"), ["a", "b", "e"])
        check("FE_OPENDIR /b", listing("/b"), ["SUB1", "RAW", "ROOTFILE"])
        check("FE_OPENDIR /b/SUB1 (a folder)", listing("/b/SUB1"), ["HELLO", "SUB2"])
        check("FE_OPENDIR /b/R*", listing("/b/R*"), ["RAW", "ROOTFILE"])
        check("FE_OPENDIR /b/*1", listing("/b/*1"), ["SUB1"])
        check("FE_OPENDIR /b/R??", listing("/b/R??"), ["RAW"])
        check("FE_OPENDIR /b/*O*E", listing("/b/*O*E"), ["ROOTFILE"])
        check("FE_OPENDIR /b/ROOTFILE (one file)", listing("/b/ROOTFILE"), ["ROOTFILE"])
        check("FE_OPENDIR a missing name", listing("/b/NOPE"), FILE_NOT_FOUND)
        a_names = listing("/a")
        check("FE_OPENDIR /a (the GEOS disk) lists files", isinstance(a_names, list) and len(a_names) > 3, True)
        geos = [n for n in a_names[:8] if stat("/a/" + n)[1:2] == (K_GEOS,)] if isinstance(a_names, list) else []
        check("FE_STAT finds GEOS files on /a", len(geos) > 0, True)
        hs = [fe(FE_OPENDIR, s0="/b") for _ in range(5)]
        check("handles: four, then none", [(h[0], h[1]) for h in hs[:4]] + [hs[4][0]],
              [(0, 0), (0, 1), (0, 2), (0, 3), NO_HANDLE])
        check("FE_READDIR on a closed handle", (fe(FE_CLOSE, y=2)[0], fe(FE_READDIR, y=2, r1=INFO, r2=NAMEBUF)[0]),
              (0, BAD_HANDLE))
        check("FE_CLOSE all", (fe(FE_CLOSE, y=0xFF)[0], fe(FE_OPENDIR, s0="/b")[:2]), (0, (0, 0)))
        fe(FE_CLOSE, y=0xFF)
        x, _, r = fe(FE_DF, s0="/b")
        check("FE_DF /b", (x, r[1], r[2]), (0, 2709, 3160))
        x, _, r = fe(FE_DF, s0="/b/SUB1")
        check("FE_DF /b/SUB1 (its partition)", (x, r[1]), (0, 275))
        check("FE_MKDIR /b/NEWDIR", (fe(FE_MKDIR, s0="/b/NEWDIR", r2=3)[0], stat("/b/NEWDIR")[:2]),
              (0, (0, K_FOLDER)))
        check("FE_MKDIR again refused", fe(FE_MKDIR, s0="/b/NEWDIR", r2=3)[0], FILE_EXISTS)
        check("FE_RMDIR /b/NEWDIR", (fe(FE_RMDIR, s0="/b/NEWDIR")[0], stat("/b/NEWDIR")), (0, (FILE_NOT_FOUND,)))
        check("FE_RMDIR on a file refused", fe(FE_RMDIR, s0="/b/ROOTFILE")[0], NOT_FOLDER)
        check("FE_RENAME", (fe(FE_RENAME, s0="/b/ROOTFILE", s1="TOPFILE")[0], stat("/b/TOPFILE")[:2]),
              (0, (0, K_CBM)))
        check("FE_RENAME onto an existing name refused", fe(FE_RENAME, s0="/b/TOPFILE", s1="SUB1")[0], FILE_EXISTS)
        check("FE_RENAME with a / refused", fe(FE_RENAME, s0="/b/TOPFILE", s1="A/B")[0], BAD_PATH)
        fe(FE_RENAME, s0="/b/TOPFILE", s1="ROOTFILE")
        check("FE_RENAME in a partition", fe(FE_RENAME, s0="/b/SUB1/SUB2/DEEP", s1="NEWER")[0], 0)
        fe(FE_RENAME, s0="/b/SUB1/SUB2/NEWER", s1="DEEP")
        check("FE_DELETE a folder refused", fe(FE_DELETE, s0="/b/SUB1")[0], IS_FOLDER)
        check("FE_DELETE /b/SUB1/HELLO", (fe(FE_DELETE, s0="/b/SUB1/HELLO")[0], stat("/b/SUB1/HELLO"),
                                          fe(FE_DF, s0="/b/SUB1")[2][1]), (0, (FILE_NOT_FOUND,), 276))
        check("FE_DELETE / refused", fe(FE_DELETE, s0="/")[0], BAD_PATH)
        check("FE_MOUNT without a UCI (VICE): no device", fe(17, s0="/c", s1="/usb0/x.d64")[0], 13)
        check("a function number past the end", fe(40)[0], NOT_SUPPORTED)
        v.mem_set(0x0340, bytes([0x60]))
    finally:
        after = e.stop()
    part81.basic_on(after, CHECK, "e1-check")
    # SUB1 selected (2), HELLO gone (62), the root (2), ROOTFILE renamed
    # back (0)
    check("the real 1581 DOS reads it back", (part81.result_text(after) or "").split(),
          ["2", "62", "2", "0"])
    sys.exit(0 if e.ok else 1)


if __name__ == "__main__":
    main()
