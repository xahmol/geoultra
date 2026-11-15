# Conformance cases for loading and starting (src/kernal/load.s): CRC,
# GetFile / LdFile / LdApplic with an own load address, StartAppl's warm
# state, a desk accessory round trip (LdDeskAcc, RstrAppl) and Sleep.
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
_names = [l.split("#")[0].split("=")[0].strip()
          for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
_names = [n for n in _names if n]


def jsr(name):
    a = 0xC100 + 3 * _names.index(name)
    return [0x20, a & 0xFF, a >> 8]


def ld(zp, value):
    return [0xA9, value & 0xFF, 0x85, zp, 0xA9, value >> 8, 0x85, zp + 1]


def text(s):
    return [ord(c) for c in s] + [0]


NAME = 0x4F00
RES = 0x4E80
CODE = 0x4D00
R0, R2, R3, R6, R7, R9, R10 = 0x02, 0x06, 0x08, 0x0E, 0x10, 0x14, 0x16


def get(title, name, opt, addr, compare, mem=None):
    m = {NAME: text(name), 0x4000: [0xEE] * 0x900, 0x8300: [0] * 64}
    m.update(mem or {})
    return dict(name=title, routine="GetFile", r={"r6": NAME, "r0L": opt, "r7": addr},
                mem=m, compare=["X"] + compare)


# StartAppl: the "application" stores the warm-start state and returns to
# MainLoop: zero page $22-$38, globals $849B-$84C0, r0L, r2, r3, r10L, the
# stack pointer, VIC $D011-$D01F (from I/O).
APP = 0x4C00
APP_CODE = ([0xA5, 0x02, 0x8D, 0x80, 0x4E, 0xA5, 0x06, 0x8D, 0x81, 0x4E, 0xA5, 0x07, 0x8D,
             0x82, 0x4E, 0xA5, 0x08, 0x8D, 0x83, 0x4E, 0xA5, 0x09, 0x8D, 0x84, 0x4E, 0xA5,
             0x16, 0x8D, 0x85, 0x4E, 0xBA, 0x8E, 0x86, 0x4E,                 # tsx; stx
             0xA2, 0x16, 0xB5, 0x22, 0x9D, 0x90, 0x4E, 0xCA, 0x10, 0xF8,     # zp $22-$38
             0xA2, 0x25, 0xBD, 0x9B, 0x84, 0x9D, 0xB0, 0x4E, 0xCA, 0x10, 0xF7,  # globals
             0xA9, 0x35, 0x85, 0x01, 0xA2, 0x0E, 0xBD, 0x11, 0xD0, 0x9D, 0xE0, 0x4E,
             0xCA, 0x10, 0xF7, 0xA9, 0x30, 0x85, 0x01, 0x60])

# A desk accessory that marks RES+$10 and returns at once
DA_START = 0x5000
DA_CODE = [0xA9, 0x77, 0x8D, 0x90, 0x4E] + jsr("RstrAppl")
DA_HDR = 0x4000


def da_header():
    h = [0] * 256
    h[0], h[1] = (NAME & 0xFF), NAME >> 8
    h[2], h[3], h[4] = 3, 21, 0xBF
    h[0x44], h[0x45], h[0x46] = 0x83, 5, 0
    end = DA_START + len(DA_CODE)
    h[0x47], h[0x48], h[0x49], h[0x4A] = DA_START & 0xFF, DA_START >> 8, end & 0xFF, end >> 8
    h[0x4B], h[0x4C] = DA_START & 0xFF, DA_START >> 8
    return h


DA_TEST = (ld(R9, DA_HDR) + [0xA9, 0, 0x85, R10] + jsr("SaveFile")
           + [0x8E, RES & 0xFF, RES >> 8]
           + [0xA2, len(DA_CODE) - 1, 0xA9, 0xAA, 0x9D, 0x00, 0x50, 0xCA, 0x10, 0xFA]  # app data
           + ld(R6, NAME) + [0xA9, 0, 0x85, R0, 0x85, R10] + jsr("GetFile")
           + [0x8E, (RES + 1) & 0xFF, RES >> 8, 0xBA, 0x8E, (RES + 2) & 0xFF, RES >> 8, 0x60])

SLEEPER = 0x4D80
SLEEP_CODE = ld(R0, 10) + jsr("Sleep") + [0xEE, 0x91, 0x4E, 0x60]   # after: inc RES+$11

CASES = [
    dict(name="CRC of 300 bytes", routine="CRC", r={"r0": 0x4000, "r1": 300},
         mem={0x4000: [(i * 31 + 7) & 0xFF for i in range(300)]}, compare=["r2"]),
    dict(name="CRC of one byte", routine="CRC", r={"r0": 0x4000, "r1": 1},
         mem={0x4000: [0x41]}, compare=["r2"]),
    get("GetFile printer driver (at its own address)", "MPS-803", 0, 0,
        ["r7", "mem:$7918-$7DFF", "mem:$8100-$81FF", "mem:$8300-$831F"],
        mem={0x7900: [0xEE] * 0x500}),  # ($7900-$7917: its entries, caught by
                                         # GeoUltra's print spooler, src/kernal/
                                         # spool.s: `jsr SpoolEnt`, by design)
    get("GetFile input driver at r7", "JOYSTICK", 1, 0x4000, ["r7", "mem:$4000-$45FF"]),
    get("GetFile application at r7 (not started)", "CONVERT", 1, 0x4000,
        ["r7", "mem:$4000-$48FF", "mem:$8100-$81FF"]),
    get("GetFile VLIR auto-exec at r7 (record 0)", "CONFIGURE", 1, 0x4000,
        ["r7", "mem:$4000-$48FF"]),
    get("GetFile not found", "NOPE", 0, 0, []),
    dict(name="StartAppl warm state", routine="StartAppl", noreturn=True,
         r={"r7": APP, "r0L": 0x80, "r2": NAME, "r3": NAME + 0x20, "r10L": 0x5A},
         mem={APP: APP_CODE, NAME: text("DataDisk") + [0] * 23, NAME + 0x20: text("DataFile")
              + [0] * 23, RES: [0xEE] * 0x80},
         # not compared: addresses inside each kernal (curPattern, font
         # pointers, intTopVector, BRKVector, RecoverVector), the unused
         # string pointer, VIC values read while running (raster, IRQ
         # flags, collisions)
         compare=["mem:$4E80-$4E86", "mem:$4E9C-$4EA6", "mem:$4EB0-$4EB1",
                  "mem:$4EB4-$4EC3", "mem:$4EC8-$4ED5", "mem:$4EE4-$4EE7",
                  "mem:$4EE9-$4EED", "mem:$8442-$8463"]),
    dict(name="Desk accessory round trip", routine="CallRoutine", writes=True,
         a=CODE & 0xFF, x=CODE >> 8,
         mem={CODE: DA_TEST, DA_HDR: da_header(), NAME: text("GeoUltra DA"),
              DA_START: DA_CODE, RES: [0xEE] * 0x20},
         compare=["mem:$4E80-$4E81", "mem:$4E90-$4E90", "mem:$5000-$5007"]),
    dict(name="Sleep continues from MainLoop", routine="CallRoutine",
         a=SLEEPER & 0xFF, x=SLEEPER >> 8, mem={SLEEPER: SLEEP_CODE, RES + 0x11: [0]},
         after=[0xAD, 0x91, 0x4E, 0x8D, 0x92, 0x4E],          # before waking: RES+$12
         events=[dict(x=200, y=150, wait=1.0)], compare=["mem:$4E91-$4E92"]),
]

# BRK goes through BRKVector with X intact and the BRK address + 2 on the
# stack; the handler records both and returns to the trampoline.
BRK_CODE = [0xA2, 0x5A, 0x00, 0xEA]                          # ldx #$5A; brk; nop
BRK_HANDLER = [0x68, 0x8D, 0xA0, 0x4E, 0x68, 0x8D, 0xA1, 0x4E,  # pla/sta x2
               0x8E, 0xA2, 0x4E, 0x60]                         # stx; rts
CASES += [
    dict(name="BRK through BRKVector", routine="CallRoutine", a=0x00, x=0x4D,
         poke={0x84AF: [0x80, 0x4D]}, mem={0x4D00: BRK_CODE, 0x4D80: BRK_HANDLER,
                                           0x4EA0: [0xEE] * 3},
         compare=["mem:$4EA0-$4EA2"]),
]

# Clock: the TOD set to 11:59:59.8 PM, the date to 28 February; after
# MainLoop has run past midnight the date is the next day.
TOD_SET = [0xA9, 0x35, 0x85, 0x01, 0xA9, 0x00, 0x8D, 0x0F, 0xDC,      # $01 = $35; CRB
           0xA9, 0x91, 0x8D, 0x0B, 0xDC, 0xA9, 0x59, 0x8D, 0x0A, 0xDC,  # 11 PM, 59
           0xA9, 0x59, 0x8D, 0x09, 0xDC, 0xA9, 0x08, 0x8D, 0x08, 0xDC,  # 59, .8 (runs)
           0xA9, 0x30, 0x85, 0x01, 0x60]


def midnight(title, year):
    return dict(name=title, routine="CallRoutine", a=0x00, x=0x4D,
                mem={0x4D00: TOD_SET}, poke={0x8516: [year, 2, 28, 23, 59, 59]},
                events=[dict(x=200, y=150, wait=1.0)],
                compare=["mem:$8516-$8519"])


CASES += [
    midnight("Clock passes midnight on 28 February 2026", 26),
    midnight("Clock passes midnight on 28 February 2024", 24),
]

# ToBASIC: BASIC starts and runs the command; the first nine text lines
# (banner, READY., the command, its output, READY.) compared, the cursor
# line after them not (it blinks).
CASES += [
    dict(name="ToBASIC runs PRINT 7*6", routine="ToBASIC", noreturn=3,
         r={"r0": NAME, "r5": 0, "r7": 0x0803}, mem={NAME: text("PRINT 7*6"), 0x0800: [0, 0, 0]},
         compare=["mem:$0400-$0567"]),
]
