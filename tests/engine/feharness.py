"""Calling the file engine on GeoUltra in VICE, for tests/engine/*.py.

Drive A is the GEOS 2.0 disk (GEOS_ORACLE, only read), drive B a D81 made
by the real 1581 DOS (tests/drives/part81.py: SUB1 with HELLO and the
nested SUB2 with DEEP, RAW, ROOTFILE). Each call runs with the caller on
drive B in SUB1; afterwards the caller's drive, folder and directory
header must be as before (Engine.fe checks it after every call).
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
PATH, PATH2, FOLDER, INFO, NAMEBUF, PWDBUF, RES = 0x4F00, 0x4F80, 0x4E00, 0x5000, 0x5020, 0x5100, 0x02F0
SET_CUR_DIR, DIR_ROOT, FILE_ENGINE = 1, 3, 6
D81_BANK, D81_SIZE = 40, 819200             # drive B in the REU (apprun)

(FE_VERSION, FE_STAT, FE_OPENDIR, FE_READDIR, FE_CLOSE, FE_COPY, FE_MOVE, FE_DELETE,
 FE_MKDIR, FE_RMDIR, FE_RENAME, FE_CD, FE_PWD, FE_OPEN, FE_READ, FE_WRITE, FE_DF) = range(17)
K_ROOT, K_DRIVE, K_FOLDER, K_GEOS, K_CBM = range(5)
CANCELLED = 0x47
END_OF_DIR, BAD_PATH, NOT_FOLDER, IS_FOLDER, BAD_HANDLE, NO_HANDLE, NOT_SUPPORTED = range(0x48, 0x4F)
INSUFF_SPACE, FILE_NOT_FOUND, STRUCT_MISMAT, DEV_NOT_FOUND, FILE_EXISTS = 3, 5, 10, 13, 0x40
FC_OVERWRITE = 1
FO_READ, FO_WRITE, FO_APPEND = 0, 1, 2


class Engine:
    """VICE with GeoUltra, drive B a fresh copy of the reference D81."""

    def __init__(self, name, port):
        os.makedirs(OUT, exist_ok=True)
        self.name = name
        self.ok = True
        self.ref = os.path.join(OUT, name + ".d81")
        if os.path.exists(self.ref):
            os.remove(self.ref)
        subprocess.run([os.path.join(part81.VICEBIN, "c1541"), "-format", "blank,bl", "d81", self.ref],
                       capture_output=True, check=True)
        part81.basic_on(self.ref, part81.MAKE, "make")
        apprun.APPS_DISK = self.ref
        apprun.REU_IMAGE = os.path.join(OUT, "reu-%s.bin" % name)
        if os.path.exists(apprun.REU_IMAGE):
            os.remove(apprun.REU_IMAGE)
        apprun.reu_image()
        labels = {}
        for line in open(os.path.join(ROOT, "build", "kernal64.lbl")):
            parts = line.split()
            labels[parts[2].lstrip(".")] = int(parts[1], 16)
        self.ext, self.folder_t, self.folder_s = labels["ExtTable"], labels["folderT"], labels["folderS"]
        cmd = [harness.VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
               "-binarymonitoraddress", "127.0.0.1:%d" % port,
               "-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
               "-reu", "-reusize", "16384", "-reuimage", apprun.REU_IMAGE, "-reuimagerw"]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.v = Vice(port=port)
        self.t = harness.jumptab()
        self.caller = None

    def start(self):
        """Up to the deskTop's start; the caller's folder SUB1."""
        v = self.v
        v.resume()
        time.sleep(5)
        v.ping()
        jt = v.mem_get(0xC1C3, 0xC1C5)          # wait for the deskTop's start
        cid = v.checkpoint(jt[1] | jt[2] << 8, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        v.delete_checkpoint(cid)
        self.text(FOLDER, "SUB1")
        self.caller = (9, 10, 0, b"INNER ONE")

    def stop(self):
        """VICE ends (the REU image written); drive B's image after the run."""
        try:
            self.v.quit()
        finally:
            self.proc.wait(timeout=30)
        after = os.path.join(OUT, self.name + "-after.d81")
        reu = open(apprun.REU_IMAGE, "rb").read()
        open(after, "wb").write(reu[D81_BANK << 16:(D81_BANK << 16) + D81_SIZE])
        return after

    @staticmethod
    def jsr(addr):
        return [0x20, addr & 0xFF, addr >> 8]

    def xcall(self, n):
        return self.jsr(self.ext + 5 * n)

    @staticmethod
    def ldw(value, zp):
        return [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]

    def run(self, code):
        """The caller: drive B in SUB1; then code; results in RES."""
        v, t = self.v, self.t
        start = harness.TRAMPOLINE
        prog = ([0x78, 0xA9, 0x30, 0x85, 0x01, 0xA9, 0x09] + self.jsr(t["SetDevice"]) + self.jsr(t["OpenDisk"])
                + self.xcall(DIR_ROOT) + self.ldw(FOLDER, 0x02) + self.xcall(SET_CUR_DIR) + code)
        end = start + len(prog)
        prog += [0x4C, end & 0xFF, end >> 8]
        v.mem_set(start, bytes(prog))
        v.regs_set({"PC": start})
        v.checkpoint(end)
        v.resume()
        v.wait_event(RESP_CHECKPOINT, timeout=120)
        return v.mem_get(RES, RES + 14)

    def text(self, addr, s):
        self.v.mem_set(addr, s.encode("latin1") + b"\0")

    def fe(self, func, r0=None, r1=None, r2=None, r3=None, y=0, s0=None, s1=None):
        """One engine call (strings s0, s1 to PATH, PATH2 as r0, r1);
        returns X, A, r0-r4 as words, and checks the caller's state."""
        code = []
        if func in (FE_COPY, FE_MOVE):          # flags and progress: 0 unless given
            r2 = 0 if r2 is None else r2
            r3 = 0 if r3 is None else r3
        if s0 is not None:
            self.text(PATH, s0)
            r0 = PATH
        if s1 is not None:
            self.text(PATH2, s1)
            r1 = PATH2
        for value, zp in ((r0, 0x02), (r1, 0x04), (r2, 0x06), (r3, 0x08)):
            if value is not None:
                code += self.ldw(value, zp)
        code += [0xA9, func, 0xA0, y] + self.xcall(FILE_ENGINE)
        code += [0x8E, RES & 0xFF, RES >> 8, 0x8D, (RES + 1) & 0xFF, RES >> 8]
        for i in range(10):
            code += [0xA5, 0x02 + i, 0x8D, (RES + 2 + i) & 0xFF, RES >> 8]
        code += [0xAD, 0x89, 0x84, 0x8D, (RES + 12) & 0xFF, RES >> 8]
        for i, a in enumerate((self.folder_t + 1, self.folder_s + 1)):
            code += [0xAD, a & 0xFF, a >> 8, 0x8D, (RES + 13 + i) & 0xFF, RES >> 8]
        r = self.run(code)
        state = (r[12], r[13], r[14], self.v.mem_get(0x8290, 0x829F).split(b"\xA0")[0])
        if state != self.caller:
            self.ok = False
            print("FAIL the caller's state after function %d: %s, expected %s" % (func, state, self.caller))
        return r[0], r[1], [r[2 + 2 * i] | r[3 + 2 * i] << 8 for i in range(5)]

    def info(self, path):
        """FE_STAT: X and the info block (bytes), or X alone."""
        x, _, _ = self.fe(FE_STAT, s0=path, r1=INFO)
        return (x, self.v.mem_get(INFO, INFO + 15)) if x == 0 else (x, None)

    def stat(self, path):
        x, info = self.info(path)
        return (x, info[0], info[4] | info[5] << 8) if x == 0 else (x,)

    def listing(self, path, infos=False):
        """FE_OPENDIR/READDIR/CLOSE: the names (with infos: (name, info))."""
        x, h, _ = self.fe(FE_OPENDIR, s0=path)
        if x:
            return x
        names = []
        while True:
            x, _, _ = self.fe(FE_READDIR, y=h, r1=INFO, r2=NAMEBUF)
            if x:
                break
            name = self.v.mem_get(NAMEBUF, NAMEBUF + 16).split(b"\0")[0].decode("latin1")
            names.append((name, self.v.mem_get(INFO, INFO + 15)) if infos else name)
        self.fe(FE_CLOSE, y=h)
        return names if x == END_OF_DIR else ("error %02x" % x, names)

    def pwd(self):
        self.fe(FE_PWD, r0=PWDBUF)
        return self.v.mem_get(PWDBUF, PWDBUF + 127).split(b"\0")[0].decode("latin1")

    def check(self, title, got, want):
        good = got == want
        self.ok = self.ok and good
        print("%s %s: %s" % ("pass" if good else "FAIL", title, got if good else "%s, expected %s" % (got, want)))
