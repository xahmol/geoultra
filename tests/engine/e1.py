#!/usr/bin/env python3
"""File engine step E1 on GeoUltra in VICE (docs/FILE_ENGINE.md).

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
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "drives"))
import part81  # noqa: E402  (the reference D81, the real 1581 DOS)
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

OUT = os.path.join(ROOT, "build", "harness", "engine")
os.makedirs(OUT, exist_ok=True)
REF = os.path.join(OUT, "e1.d81")
PORT = 6547
PATH, PATH2, FOLDER, INFO, NAMEBUF, PWDBUF, RES = 0x4F00, 0x4F80, 0x4E00, 0x5000, 0x5020, 0x5100, 0x02F0
SET_CUR_DIR, DIR_ROOT, FILE_ENGINE = 1, 3, 6

(FE_VERSION, FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE, FE_COPY, FE_MOVE, FE_DELETE,
 FE_MKDIR, FE_RMDIR, FE_RENAME, FE_CD, FE_PWD, FE_OPEN, FE_READ, FE_WRITE, FE_DF) = range(17)
K_ROOT, K_DRIVE, K_FOLDER, K_GEOS, K_CBM = range(5)
END_OF_DIR, BAD_PATH, NOT_FOLDER, IS_FOLDER, BAD_HANDLE, NO_HANDLE, NOT_SUPPORTED = range(0x48, 0x4F)
FILE_NOT_FOUND, FILE_EXISTS = 5, 0x40

CHECK = """10 open15,8,15:r$=""
20 print#15,"/0:sub1":input#15,a:r$=r$+str$(a)
30 open2,8,2,"hello,s,r":input#15,a:r$=r$+str$(a):close2
50 print#15,"/":input#15,a:r$=r$+str$(a)
60 open2,8,2,"rootfile,s,r":input#15,a:r$=r$+str$(a):close2
70 open2,8,2,"@0:result,s,w":print#2,r$:close2:close15
"""


def main():
    if os.path.exists(REF):
        os.remove(REF)
    subprocess.run([os.path.join(part81.VICEBIN, "c1541"), "-format", "blank,bl", "d81", REF],
                   capture_output=True, check=True)
    part81.basic_on(REF, part81.MAKE, "make")
    apprun.APPS_DISK = REF
    apprun.REU_IMAGE = os.path.join(OUT, "reu-e1.bin")
    if os.path.exists(apprun.REU_IMAGE):
        os.remove(apprun.REU_IMAGE)
    apprun.reu_image()
    labels = {}
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        parts = line.split()
        labels[parts[2].lstrip(".")] = int(parts[1], 16)
    ext, folder_t, folder_s = labels["ExtTable"], labels["folderT"], labels["folderS"]
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "-reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    t = harness.jumptab()
    ok = True
    caller = None

    def jsr(addr):
        return [0x20, addr & 0xFF, addr >> 8]

    def xcall(n):
        return jsr(ext + 5 * n)

    def ldw(value, zp):
        return [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]

    def run(code):
        """The caller: drive B in SUB1; then code; results in RES."""
        start = harness.TRAMPOLINE
        prog = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + jsr(t["SetDevice"]) + jsr(t["OpenDisk"])
                + xcall(DIR_ROOT) + ldw(FOLDER, 0x02) + xcall(SET_CUR_DIR) + code)
        end = start + len(prog)
        prog += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        v.checkpoint(end)
        v.resume()
        v.wait_event(RESP_CHECKPOINT, timeout=120)
        return v.mem_get(RES, RES + 14)

    def text(addr, s):
        v.mem_set(addr, s.encode("latin1") + b"\0")

    def fe(func, r0=None, r1=None, r2=None, y=0, s0=None, s1=None):
        """One engine call (strings s0, s1 to PATH, PATH2 as r0, r1);
        returns X, A, r0-r4 as words, and checks the caller's state."""
        nonlocal ok
        code = []
        if s0 is not None:
            text(PATH, s0)
            r0 = PATH
        if s1 is not None:
            text(PATH2, s1)
            r1 = PATH2
        for value, zp in ((r0, 0x02), (r1, 0x04), (r2, 0x06)):
            if value is not None:
                code += ldw(value, zp)
        code += [0xA9, func, 0xA0, y] + xcall(FILE_ENGINE)
        code += [0x8E, RES & 0xFF, RES >> 8, 0x8D, (RES + 1) & 0xFF, RES >> 8]
        for i in range(10):
            code += [0xA5, 0x02 + i, 0x8D, (RES + 2 + i) & 0xFF, RES >> 8]
        code += [0xAD, 0x89, 0x84, 0x8D, (RES + 12) & 0xFF, RES >> 8]
        for i, a in enumerate((folder_t + 1, folder_s + 1)):
            code += [0xAD, a & 0xFF, a >> 8, 0x8D, (RES + 13 + i) & 0xFF, RES >> 8]
        r = run(code)
        state = (r[12], r[13], r[14], v.mem_get(0x8290, 0x829F).split(b"\xA0")[0])
        if state != caller:
            ok = False
            print("FAIL the caller's state after function %d: %s, expected %s" % (func, state, caller))
        return r[0], r[1], [r[2 + 2 * i] | r[3 + 2 * i] << 8 for i in range(5)]

    def stat(path):
        x, _, _ = fe(FE_STAT, s0=path, r1=INFO)
        info = v.mem_get(INFO, INFO + 15)
        return (x, info[0], info[4] | info[5] << 8) if x == 0 else (x,)

    def listing(path):
        x, h, _ = fe(FE_OPENDIR, s0=path)
        if x:
            return x
        names = []
        while True:
            x, _, _ = fe(FE_READDIR, y=h, r1=INFO, r2=NAMEBUF)
            if x:
                break
            names.append(v.mem_get(NAMEBUF, NAMEBUF + 16).split(b"\0")[0].decode("latin1"))
        fe(FE_CLOSE, y=h)
        return names if x == END_OF_DIR else ("error %02x" % x, names)

    def pwd():
        fe(FE_PWD, r0=PWDBUF)
        return v.mem_get(PWDBUF, PWDBUF + 127).split(b"\0")[0].decode("latin1")

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)          # wait for the deskTop's start
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        text(FOLDER, "SUB1")
        caller = (9, 10, 0, b"INNER ONE")
        x, _, r = fe(FE_VERSION)
        check("FE_VERSION", (x, r[0]), (0, 1))
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
        check("FE_STAT /usb0 (step E3)", stat("/usb0/x"), (NOT_SUPPORTED,))
        check("FE_STAT a name too long", stat("/b/ABCDEFGHIJKLMNOPQ"), (BAD_PATH,))
        check("FE_STAT a long path", stat("/b/" + "./" * 55 + "ROOTFILE"), (0, K_CBM, 1))
        check("FE_STAT a path too long", stat("/b/" + "./" * 70 + "ROOTFILE"), (BAD_PATH,))
        check("FE_CD /b/SUB1", fe(FE_CD, s0="/b/SUB1")[0], 0)
        check("FE_PWD", pwd(), "/b/SUB1")
        check("FE_STAT relative", stat("HELLO"), (0, K_CBM, 1))
        check("FE_CD relative", (fe(FE_CD, s0="SUB2")[0], pwd()), (0, "/b/SUB1/SUB2"))
        check("FE_CD ..", (fe(FE_CD, s0="..")[0], pwd()), (0, "/b/SUB1"))
        check("FE_CD to a file refused", (fe(FE_CD, s0="/b/ROOTFILE")[0], pwd()), (NOT_FOLDER, "/b/SUB1"))
        check("FE_CD /", (fe(FE_CD, s0="/")[0], pwd()), (0, "/"))
        check("FE_OPENDIR /", listing("/"), ["a", "b"])
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
        check("FE_COPY: a later step", fe(FE_COPY, s0="/b/ROOTFILE", s1="/b/X")[0], NOT_SUPPORTED)
        check("a function number past the end", fe(40)[0], NOT_SUPPORTED)
        v.mem_set(0x0340, bytes([0x60]))
    finally:
        v.quit()
        proc.wait(timeout=30)
    after = os.path.join(OUT, "e1-after.d81")
    reu = open(apprun.REU_IMAGE, "rb").read()
    open(after, "wb").write(reu[40 << 16:(40 << 16) + 819200])
    part81.basic_on(after, CHECK, "e1-check")
    # SUB1 selected (2), HELLO gone (62), the root (2), ROOTFILE renamed
    # back (0)
    check("the real 1581 DOS reads it back", (part81.result_text(after) or "").split(),
          ["2", "62", "2", "0"])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
