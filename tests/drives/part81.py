#!/usr/bin/env python3
"""1581 partitions as folders on GeoUltra, checked against the real 1581 DOS.

1. A reference D81 made by the real 1581 DOS (VICE's true 1581 emulation,
   a BASIC program on a blank image): partition SUB1 (tracks 10-19) with
   the file HELLO, SUB2 nested in it (tracks 12-14) with DEEP, ROOTFILE and
   RAW (a partition that is no sub-directory: 30/5, 50 blocks) at the root. No private files are used.
2. GeoUltra in VICE with that image as drive B: GetCurDir, SetCurDir into
   SUB1 and SUB2, DirUp twice, DirRoot (folder, the partition's header
   name, free blocks, which files are visible), SetCurDir on a file
   refused, then SaveFile and ReadFile of a GEOS file in SUB2.
3. The image as GeoUltra left it back to the real 1581 DOS, which selects
   SUB1 and SUB2, reads that file and DEEP, and writes what it read to a
   RESULT file at the root, checked here.
Usage: tests/drives/part81.py
"""
import os
import shutil
import subprocess
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "dev", "harness"))
OUT = os.path.join(ROOT, "build", "harness", "part81")
os.makedirs(OUT, exist_ok=True)
VICEBIN = (localcfg.VICE_BIN or "")
X64HL = localcfg.X64SC_HEADLESS
REF = os.path.join(OUT, "ref.d81")
os.environ["GEOS_APPS_DISK"] = REF
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6546
NAME, FOLDER, HDR, DATA, BACK, RES = 0x4F00, 0x4F40, 0x4000, 0x4400, 0x5000, 0x02F0
GET_CUR_DIR, SET_CUR_DIR, DIR_UP, DIR_ROOT, MAKE_DIR, REMOVE_DIR = 0, 1, 2, 3, 4, 5

MAKE = """10 open15,8,15
20 print#15,"n0:reference,rf"
30 print#15,"/0:sub1,"+chr$(10)+chr$(0)+chr$(144)+chr$(1)+",c"
40 print#15,"/0:sub1"
50 print#15,"n0:inner one,s1"
60 open2,8,2,"hello,s,w":print#2,"in sub1":close2
70 print#15,"/0:sub2,"+chr$(12)+chr$(0)+chr$(120)+chr$(0)+",c"
80 print#15,"/0:sub2"
90 print#15,"n0:inner two,s2"
100 open2,8,2,"deep,s,w":print#2,"in sub2":close2
110 print#15,"/"
115 print#15,"/0:raw,"+chr$(30)+chr$(5)+chr$(50)+chr$(0)+",c"
120 open2,8,2,"rootfile,s,w":print#2,"at root":close2
130 close15
"""
CHECK = """10 open15,8,15:r$=""
20 print#15,"/0:sub1":input#15,a:r$=r$+str$(a)
30 print#15,"/0:sub2":input#15,a:r$=r$+str$(a)
40 open2,8,2,"geo in sub2,u,r":input#15,a:r$=r$+str$(a)
50 for i=1 to 4:get#2,a$:r$=r$+str$(asc(a$+chr$(0))):next:close2
60 open2,8,2,"deep,s,r":input#15,a:r$=r$+str$(a):close2
70 print#15,"/":input#15,a:r$=r$+str$(a)
72 print#15,"/0:new":input#15,a,b$,c,d:r$=r$+str$(a)+str$(c)+str$(d)
74 open2,8,2,"dosfile,s,w":print#2,"x":close2:input#15,a:r$=r$+str$(a)
76 open2,8,2,"dosfile,s,r":input#15,a:r$=r$+str$(a):close2
78 print#15,"/":input#15,a:r$=r$+str$(a)
80 open2,8,2,"@0:result,s,w":print#2,r$:close2:close15
"""


def basic_on(image, program, name):
    """Run a BASIC program with the real 1581 DOS on image (in place)."""
    bas = os.path.join(OUT, name + ".bas")
    prg = os.path.join(OUT, name + ".prg")
    open(bas, "w").write(program)
    subprocess.run([os.path.join(VICEBIN, "petcat"), "-w2", "-o", prg, "--", bas], check=True)
    subprocess.run([X64HL, "-default", "+sound", "-sounddev", "dummy", "-warp",
                    "-drive8type", "1581", "-drive8truedrive", "-8", image,
                    "-autostartprgmode", "1", "-autostart", prg, "-limitcycles", "400000000"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)


def block(image, t, s):
    d = open(image, "rb").read()
    o = ((t - 1) * 40 + s) * 256
    return d[o:o + 256]


def result_text(image):
    """The RESULT file's text from the root directory."""
    t, s = 40, 3
    while t:
        b = block(image, t, s)
        for e in range(8):
            en = b[32 * e + 2:32 * e + 32]
            if en[0] and en[3:9] == b"RESULT":
                out, (ft, fs) = b"", (en[1], en[2])
                while ft:
                    fb = block(image, ft, fs)
                    out += fb[2:256] if fb[0] else fb[2:fb[1] + 1]
                    ft, fs = fb[0], fb[1]
                return out.decode("latin1").strip()
        t, s = b[0], b[1]
    return None


def header(length):
    h = [0] * 256
    h[0], h[1] = NAME & 0xFF, NAME >> 8
    h[2], h[3], h[4] = 3, 21, 0xBF
    h[0x44], h[0x45], h[0x46] = 0x83, 7, 0
    end = DATA + length
    h[0x47], h[0x48], h[0x49], h[0x4A] = DATA & 0xFF, DATA >> 8, end & 0xFF, end >> 8
    h[0x4D:0x4D + 12] = [ord(c) for c in "GeoUltraTest"]
    return h


def main():
    if os.path.exists(REF):
        os.remove(REF)
    subprocess.run([os.path.join(VICEBIN, "c1541"), "-format", "blank,bl", "d81", REF],
                   capture_output=True, check=True)
    basic_on(REF, MAKE, "make")
    apprun.APPS_DISK = REF
    apprun.REU_IMAGE = apprun.REU_IMAGE.replace("reu-apps", "reu-part81")
    apprun.reu_image()
    ext = None
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        if line.strip().endswith(".ExtTable"):
            ext = int(line.split()[1], 16)
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "-reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    t = harness.jumptab()
    ok = True

    def jsr(name):
        a = t[name]
        return [0x20, a & 0xFF, a >> 8]

    def xcall(n):
        a = ext + 5 * n
        return [0x20, a & 0xFF, a >> 8]

    def ldw(value, zp):
        return [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]

    def stx(i):
        return [0x8E, (RES + i) & 0xFF, RES >> 8]

    def run(code, wait=3):
        start = harness.TRAMPOLINE
        prog = [0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + jsr("SetDevice") + jsr("OpenDisk") + code
        end = start + len(prog)
        prog += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(RES, b"\xEE" * 8)
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        v.resume()
        time.sleep(wait)
        v.ping()
        return v.mem_get(RES, RES + 7)

    def find(name):
        v.mem_set(NAME, name.encode() + b"\0")
        return run(ldw(NAME, 0x0E) + jsr("FindFile") + stx(0))[0]

    def state():
        r = run(xcall(GET_CUR_DIR) + stx(0) + [0xA5, 0x04, 0x8D, (RES + 1) & 0xFF, RES >> 8,
                                              0xA5, 0x05, 0x8D, (RES + 2) & 0xFF, RES >> 8])
        name = v.mem_get(0x8290, 0x829F).split(b"\xA0")[0].decode("latin1")
        z = run(ldw(0x8200, 0x0C) + jsr("CalcBlksFree"))
        z = v.mem_get(0x0A, 0x0B)
        seen = " ".join(n for n in ("ROOTFILE", "HELLO", "DEEP") if find(n) == 0)
        return (r[1], r[2]), name, z[0] | z[1] << 8, seen

    def setdir(name):
        v.mem_set(FOLDER, name.encode() + b"\0")
        return run(ldw(FOLDER, 0x02) + xcall(SET_CUR_DIR) + stx(0))[0]

    def check(title, got, want):
        nonlocal ok
        good = got == want
        ok = ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))

    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        check("the root", state(), ((40, 0), "REFERENCE", 2709, "ROOTFILE"))
        x = setdir("SUB1")
        check("SetCurDir SUB1", (x,) + state(), (0, (10, 0), "INNER ONE", 275, "HELLO"))
        x = setdir("SUB2")
        check("SetCurDir SUB2 (nested)", (x,) + state(), (0, (12, 0), "INNER TWO", 115, "DEEP"))
        x = run(xcall(DIR_UP) + stx(0))[0]
        check("DirUp", (x,) + state(), (0, (10, 0), "INNER ONE", 275, "HELLO"))
        x = run(xcall(DIR_UP) + stx(0))[0]
        check("DirUp to the root", (x,) + state(), (0, (40, 0), "REFERENCE", 2709, "ROOTFILE"))
        check("SetCurDir on a file refused", setdir("ROOTFILE"), 0x0A)
        setdir("SUB1")
        setdir("SUB2")
        x = run(xcall(DIR_ROOT) + stx(0))[0]
        check("DirRoot", (x,) + state(), (0, (40, 0), "REFERENCE", 2709, "ROOTFILE"))
        setdir("SUB1")
        setdir("SUB2")
        data = bytes((i * 7 + 3) & 0xFF for i in range(1000))
        v.mem_set(NAME, b"GEO IN SUB2\0")
        v.mem_set(HDR, bytes(header(1000)))
        v.mem_set(DATA, data)
        v.mem_set(BACK, b"\xEE" * 1100)
        r = run(ldw(HDR, 0x14) + [0xA9, 0, 0x85, 0x16] + jsr("SaveFile") + stx(0)
                + ldw(NAME, 0x0E) + jsr("FindFile") + stx(1)
                + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05]
                + ldw(BACK, 0x10) + ldw(0x1000, 0x06) + jsr("ReadFile") + stx(2), wait=5)
        back = v.mem_get(BACK, BACK + 999)
        check("SaveFile, ReadFile in SUB2", (list(r[:3]), back == data, state()[2]), ([0, 0, 0], True, 110))
        run(xcall(DIR_ROOT) + stx(0))

        def make(name, tracks):
            v.mem_set(FOLDER, name.encode() + b"\0")
            return run(ldw(FOLDER, 0x02) + [0xA9, tracks, 0x85, 0x06] + xcall(MAKE_DIR) + stx(0), wait=5)[0]

        def remove(name):
            v.mem_set(FOLDER, name.encode() + b"\0")
            return run(ldw(FOLDER, 0x02) + xcall(REMOVE_DIR) + stx(0), wait=5)[0]

        x = make("NEW", 3)
        check("MakeDir NEW (3 tracks) at the root", (x,) + state(), (0, (40, 0), "REFERENCE", 2589, "ROOTFILE"))
        x = setdir("NEW")
        check("SetCurDir NEW", (x,) + state(), (0, (1, 0), "NEW", 116, ""))
        run(xcall(DIR_UP) + stx(0))
        x1 = make("TMP", 4)
        x2 = remove("TMP")
        check("MakeDir TMP, RemoveDir TMP", (x1, x2) + state(), (0, 0, (40, 0), "REFERENCE", 2589, "ROOTFILE"))
        check("RemoveDir SUB1 (not empty) refused", remove("SUB1"), 0x41)
        check("RemoveDir RAW (a partition, no sub-directory) refused", remove("RAW"), 0x0A)
        check("MakeDir NEW again refused", make("NEW", 3), 0x40)
        v.mem_set(0x0340, bytes([0x60]))
    finally:
        v.quit()
        proc.wait(timeout=30)
    after = os.path.join(OUT, "after.d81")
    reu = open(apprun.REU_IMAGE, "rb").read()
    open(after, "wb").write(reu[40 << 16:(40 << 16) + 819200])
    basic_on(after, CHECK, "check")
    # its status after each step (02 selected, 00 ok) and the first four
    # bytes of the GEOS file (i * 7 + 3)
    check("the real 1581 DOS reads it, and uses GeoUltra's partition",
          (result_text(after) or "").split(),
          ["2", "2", "0", "3", "10", "17", "24", "0", "2", "2", "1", "3", "0", "0", "2"])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
