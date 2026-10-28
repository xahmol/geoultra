# Conformance cases for VLIR files (src/kernal/vlir.s) on the oracle
# disk's VLIR files (DESK TOP, CONFIGURE). Cases that change records
# close the file, open it again and compare the index (fileHeader), the
# BAM, usedRecords, curRecord, fileSize and the data read back.
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
_names = [l.split("#")[0].split("=")[0].strip()
          for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
_names = [n for n in _names if n]


def jsr(name):
    a = 0xC100 + 3 * _names.index(name)
    return [0x20, a & 0xFF, a >> 8]


def ld(zp, value):                                  # 16-bit lda/sta to zp
    return [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]


def keep(slot):                                     # A, X, Y to RES + 3 * slot
    a = RES + 3 * slot
    return [0x8D, a & 0xFF, a >> 8, 0x8E, (a + 1) & 0xFF, a >> 8, 0x8C, (a + 2) & 0xFF, a >> 8]


NAME = 0x4F00
DATA = 0x4400
BACK = 0x5000
RES = 0x4E80
CODE = 0x4D00
R0, R2, R7 = 0x02, 0x06, 0x10
STATE = ["mem:$8496-$849A", "mem:$8100-$81FF"]       # curRecord .. fileSize, index
BAM = "mem:$8200-$82FF"


def text(s):
    return [ord(c) for c in s] + [0]


def vlir(title, steps, compare, name="DESK TOP", writes=False, extra_mem=None):
    """Open NAME, run steps (code), store results; the code runs from CODE."""
    code = ld(R0, NAME) + jsr("OpenRecordFile") + keep(0) + steps + [0x60]
    mem = {NAME: text(name), CODE: code, RES: [0xEE] * 48, BACK: [0xEE] * 0x800,
           DATA: [(i * 11 + 1) & 0xFF for i in range(0x400)]}
    mem.update(extra_mem or {})
    return dict(name=title, routine="CallRoutine", a=CODE & 0xFF, x=CODE >> 8, mem=mem,
                writes=writes, compare=["mem:$4E80-$4EAF"] + compare)


def read_record(n):                                 # ReadRecord n into BACK
    return ([0xA9, n] + jsr("PointRecord") + ld(R7, BACK) + ld(R2, 0x800)
            + jsr("ReadRecord"))


def keepx(slot):                                    # X only (A, Y undefined)
    a = RES + 3 * slot + 1
    return [0x8E, a & 0xFF, a >> 8]


REOPEN = jsr("CloseRecordFile") + keepx(5) + ld(R0, NAME) + jsr("OpenRecordFile") + keep(6)

CASES = [
    vlir("OpenRecordFile DESK TOP", [], STATE),
    vlir("OpenRecordFile CONFIGURE", [], STATE, name="CONFIGURE"),
    vlir("OpenRecordFile on a sequential file", [], [], name="alarm clock"),
    vlir("OpenRecordFile not found", [], [], name="NOPE"),
    vlir("NextRecord, PreviousRecord, PointRecord",
         jsr("NextRecord") + keep(1) + jsr("NextRecord") + keep(2) + jsr("PreviousRecord")
         + keep(3) + [0xA9, 5] + jsr("PointRecord") + keep(4) + [0xA9, 200]
         + jsr("PointRecord") + keep(5) + [0xA9, 0xFF] + jsr("PointRecord") + keep(6),
         STATE + ["r1"]),
    vlir("ReadRecord 1", read_record(1) + keep(1), ["r7", "r2", "mem:$5000-$57FF"]),
    vlir("ReadRecord on CONFIGURE, records 0 and 1", read_record(0) + keep(1)
         + read_record(1) + keep(2), ["r7", "mem:$5000-$57FF"], name="CONFIGURE"),
    vlir("CloseRecordFile without changes", jsr("CloseRecordFile") + keep(1)
         + jsr("CloseRecordFile") + keep(2) + jsr("UpdateRecordFile") + keep(3), []),
    # changes
    vlir("WriteRecord replaces record 2", [0xA9, 2] + jsr("PointRecord") + ld(R7, DATA)
         + ld(R2, 600) + jsr("WriteRecord") + keep(1) + REOPEN + read_record(2) + keep(7),
         STATE + [BAM, "mem:$5000-$57FF"], writes=True),
    vlir("WriteRecord empties record 1", [0xA9, 1] + jsr("PointRecord") + ld(R2, 0)
         + jsr("WriteRecord") + keep(1) + REOPEN, STATE + [BAM], writes=True),
    vlir("DeleteRecord 0", [0xA9, 0] + jsr("PointRecord") + jsr("DeleteRecord") + keep(1)
         + REOPEN, STATE + [BAM], writes=True),
    vlir("DeleteRecord the last record", [0xA9, 0] + jsr("PointRecord")
         + [0xAD, 0x97, 0x84, 0x38, 0xE9, 0x01] + jsr("PointRecord") + jsr("DeleteRecord")
         + keep(1) + REOPEN, STATE + [BAM], writes=True),
    vlir("InsertRecord at 1, then write it", [0xA9, 1] + jsr("PointRecord")
         + jsr("InsertRecord") + keep(1) + ld(R7, DATA) + ld(R2, 300) + jsr("WriteRecord")
         + keep(2) + REOPEN + read_record(1) + keep(7), STATE + [BAM, "mem:$5000-$57FF"],
         writes=True),
    vlir("AppendRecord after the last", [0xA9, 0] + jsr("PointRecord")
         + [0xAD, 0x97, 0x84, 0x38, 0xE9, 0x01] + jsr("PointRecord") + jsr("AppendRecord")
         + keep(1) + ld(R7, DATA) + ld(R2, 1000) + jsr("WriteRecord") + keep(2) + REOPEN,
         STATE + [BAM], writes=True),
]
