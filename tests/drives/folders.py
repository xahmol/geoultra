#!/usr/bin/env python3
"""Folders on a native (DNP) drive on GeoUltra in VICE (src/kernal/folders.s).

Drive B is a copy of GEOS_NATIVE_DISK (default the user's own
ramapps.DNP in GEOS_DEV, only read). Through the extension jump
table (guExtTable): MakeDir, SetCurDir (the folder's name becomes the
disk name, root files are not seen), SaveFile and ReadFile inside it,
DirUp (the file is not seen at the root), a folder without a name in
its header (as DirMaster makes them) named after its entry, RemoveDir refused while the
folder holds a file, DeleteFile, RemoveDir, and the free count back where
it started. Usage: tests/drives/folders.py
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
SOURCE = localcfg.disk("GEOS_NATIVE_DISK", "ramapps.DNP")
TEST_DISK = os.path.join(ROOT, "build", "harness", "folders-test.dnp")
os.environ["GEOS_APPS_DISK"] = TEST_DISK
import apprun  # noqa: E402
import harness  # noqa: E402
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402

PORT = 6524
NAME, FOLDER, HDR, DATA, BACK, RES = 0x4F00, 0x4F40, 0x4000, 0x4400, 0x5000, 0x02F0
GET_CUR_DIR, SET_CUR_DIR, DIR_UP, DIR_ROOT, MAKE_DIR, REMOVE_DIR = range(6)


def label(name):
    for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
        if line.strip().endswith("." + name):
            return int(line.split()[1], 16)
    raise SystemExit("no label " + name)


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
    os.makedirs(os.path.dirname(TEST_DISK), exist_ok=True)
    shutil.copyfile(SOURCE, TEST_DISK)
    import geosdisk                             # a folder as DirMaster makes
    d = geosdisk.Disk(TEST_DISK)                # it: no name in its header
    d.mkdir("DM folder")
    hdr, _ = d.folder("DM folder")
    h = d.get(hdr)
    h[4:20] = b"\xa0" * 16
    d.put(hdr, h)
    d.save()
    apprun.APPS_DISK = TEST_DISK
    apprun.REU_IMAGE = apprun.REU_IMAGE.replace("reu-apps", "reu-folders")
    apprun.reu_image()
    ext = label("ExtTable")
    cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
           "-binarymonitoraddress", "127.0.0.1:%d" % PORT,
           "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
           "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "+reuimagerw"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    v = Vice(port=PORT)
    t = harness.jumptab()

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

    def free():
        run(ldw(0x8200, 0x0C) + jsr("CalcBlksFree"))
        z = v.mem_get(0x0A, 0x0B)
        return z[0] | z[1] << 8

    def find(name):                             # X of FindFile, entry type
        v.mem_set(NAME, name.encode() + b"\0")
        r = run(ldw(NAME, 0x0E) + jsr("FindFile") + stx(0))
        return r[0], v.mem_get(0x8400, 0x8400)[0]

    ok = True

    def check(title, good, detail=""):
        nonlocal ok
        ok = ok and good
        print("%s %s%s" % ("pass" if good else "FAIL", title, (": " + detail) if detail else ""))

    try:
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        before = free()
        v.mem_set(FOLDER, b"GU folder\0")
        r = run(ldw(FOLDER, 0x02) + xcall(MAKE_DIR) + stx(0))
        made = free()
        x, kind = find("GU folder")
        check("MakeDir", r[0] == 0 and x == 0 and kind == 0x86 and before - made == 2,
              "X=$%02X, entry X=$%02X type $%02X, %d blocks" % (r[0], x, kind, before - made))
        r = run(ldw(FOLDER, 0x02) + xcall(SET_CUR_DIR) + stx(0) + xcall(GET_CUR_DIR) + stx(1)
                + [0xA5, 0x04, 0x8D, (RES + 2) & 0xFF, RES >> 8, 0xA5, 0x05, 0x8D, (RES + 3) & 0xFF,
                   RES >> 8])
        name = v.mem_get(0x8290, 0x829F).split(b"\xA0")[0]
        x, _ = find("GEOWRITE")
        check("SetCurDir", r[0] == 0 and r[1] == 0 and (r[2], r[3]) != (1, 1)
              and name == b"GU folder" and x == 5,
              "X=$%02X, folder %d/%d, disk name %r, a root file: FindFile X=$%02X"
              % (r[0], r[2], r[3], name, x))
        data = bytes((i * 7 + 3) & 0xFF for i in range(1000))
        v.mem_set(NAME, b"In the folder\0")
        v.mem_set(HDR, bytes(header(1000)))
        v.mem_set(DATA, data)
        v.mem_set(BACK, b"\xEE" * 1100)
        r = run(ldw(HDR, 0x14) + [0xA9, 0, 0x85, 0x16] + jsr("SaveFile") + stx(0)
                + ldw(NAME, 0x0E) + jsr("FindFile") + stx(1)
                + [0xAD, 0x01, 0x84, 0x85, 0x04, 0xAD, 0x02, 0x84, 0x85, 0x05]
                + ldw(BACK, 0x10) + ldw(0x1000, 0x06) + jsr("ReadFile") + stx(2), wait=5)
        back = v.mem_get(BACK, BACK + 999)
        check("SaveFile and ReadFile in the folder", list(r[:3]) == [0, 0, 0] and back == data,
              "X=$%02X/$%02X/$%02X, data %s" % (r[0], r[1], r[2],
                                                "same" if back == data else "DIFFERENT"))
        v.mem_set(FOLDER + 16, b"DM folder\0")    # (DirMaster's: header unnamed)
        v.mem_set(0x8430, b"\xEE" * 16)
        r = run(xcall(DIR_UP) + stx(0) + ldw(FOLDER + 16, 0x02) + xcall(SET_CUR_DIR) + stx(1)
                + jsr("OpenDisk") + stx(2) + xcall(DIR_UP) + stx(3))
        name = v.mem_get(0x8430, 0x843F).split(b"\xA0")[0]
        check("a folder without a name in its header: its entry's name", list(r[:4]) == [0] * 4
              and name == b"DM folder", "X=$%02X/$%02X/$%02X/$%02X, disk name %r"
              % (r[0], r[1], r[2], r[3], name))
        r = run(ldw(FOLDER, 0x02) + xcall(SET_CUR_DIR) + stx(0))
        r = run(xcall(DIR_UP) + stx(0))
        x1, _ = find("In the folder")
        x2, _ = find("GEOWRITE")
        check("DirUp", r[0] == 0 and x1 == 5 and x2 == 0,
              "X=$%02X, the folder's file at the root: X=$%02X, a root file: X=$%02X" % (r[0], x1, x2))
        r = run(ldw(FOLDER, 0x02) + xcall(REMOVE_DIR) + stx(0))
        check("RemoveDir refuses a folder with a file", r[0] == 0x41, "X=$%02X" % r[0])
        v.mem_set(NAME, b"In the folder\0")
        r = run(ldw(FOLDER, 0x02) + xcall(SET_CUR_DIR) + stx(0) + ldw(NAME, 0x02)
                + jsr("DeleteFile") + stx(1) + xcall(DIR_UP) + stx(2) + ldw(FOLDER, 0x02)
                + xcall(REMOVE_DIR) + stx(3), wait=5)
        after = free()
        x, _ = find("GU folder")
        check("DeleteFile, RemoveDir", list(r[:4]) == [0, 0, 0, 0] and x == 5 and after == before,
              "X=$%02X/$%02X/$%02X/$%02X, the folder: X=$%02X, free %d -> %d"
              % (r[0], r[1], r[2], r[3], x, before, after))
    finally:
        v.quit()
        proc.kill()
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
