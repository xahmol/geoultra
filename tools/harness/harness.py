#!/usr/bin/env python3
"""Conformance harness: run kernal routines on GEOS 2.0 and on GeoUltra in
VICE and compare the results (docs/ARCHITECTURE.md, DESIGN.md).

Usage: harness.py [--rebuild] [--keep] CASEFILE.py [CASEFILE.py ...]

For each system the harness boots VICE once, stops at the top of
MainLoop and saves a snapshot (build/harness/<system>.vsf, reused unless
--rebuild). Every test case then restores the snapshot, clears both
screen buffers, writes its inputs, calls the routine through a
trampoline in the cassette buffer and reads the results. A case passes
when every item in its `compare` list is equal on both systems.

Case files define CASES, a list of dicts:
  name     text
  routine  jump table name (src/kernal/jumptab.txt) or disk driver entry
           (DRIVER_ENTRIES, e.g. Get1stDirEntry)
  a, x, y  register values (optional)
  r        {"r3": 10, "r11L": 50, ...} pseudo-register inputs
  pattern  8 bytes for curPattern (optional; curPattern points to them)
  disp     dispBufferOn (default $C0: foreground and background)
  fill     byte both screen buffers are filled with first (default 0);
           fillfore / fillback set them separately
  inline   bytes placed right after the jsr to the routine (i_ routines)
  after    code placed after the call (e.g. store r0L), run when it returns
  flags    processor flags set just before the call: "C" carry set, "N" N
           set (A is then overwritten), e.g. "C", "NC", "" (both clear)
  noreturn the routine does not return before the events (DoDlgBox): the
           events start after a short wait instead of at its return
           (True: 0.5 s; a number: that many seconds)
  poke     {address: bytes} written by the trampoline after the clean-up
           of event cases (e.g. keyVector, which the clean-up clears)
  mem      {address: bytes} extra memory writes
  pre      routines called (in order) before the r-register inputs are set
           and the routine runs, e.g. ["UseSystemFont"]
  events   after the routine returns, let MainLoop run and inject mouse
           events, in order: {"x": .., "y": .., "button": "press" |
           "release" | None, "wait": seconds (default 0.4)}; a press or
           release sets mouseData and MOUSE_BIT, a move sets INPUT_BIT
  writes   True when the case writes to the disk: such cases run after
           all others, and each on a fresh copy of the oracle disk (GEOS
           2.0's disk keeps the changes; GeoUltra's REU is restored)
  mask     optional: pixel rectangles (x0, y0, x1, y1) left out of "fore"
           (GeoUltra's deliberate additions, e.g. the file box's letters)
  compare  list of: "fore", "back" (screen buffers), "A", "X", "Y",
           r-register names (r0..r15, r0L..r15H), "mem:$ADDR-$ADDR",
           "io:$ADDR-$ADDR" (I/O, e.g. VIC-II registers)

The trampoline at $0340 is generated per case: sei, jsr to each `pre`
routine, lda/sta of the r-register inputs, lda/ldx/ldy, jsr routine.
"""
import argparse
import importlib.util
import os
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vicemon import Vice, RESP_CHECKPOINT  # noqa: E402
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "tools"))
import localcfg  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "harness")
# Headless VICE 3.10 (no window, no sound) when built, else the GTK one.
VICE = os.environ.get("VICE_HARNESS") or next(
    (p for p in (localcfg.X64SC_HEADLESS,
                 localcfg.X64SC)
     if os.path.exists(p)))
# Disk sets (--set): the GEOS 2.0 oracle boot disk (the user's own, never
# committed), its GeoUltra drive type, its size and VICE's drive 8 type.
DISK_SETS = {
    "d64": dict(oracle=localcfg.disk("GEOS_ORACLE", "GEOS64-v2.0-unkeyed.d64"),
                type=1, size=683 * 256, drive=[], suffix=""),
    "d81": dict(oracle=localcfg.disk("GEOS_ORACLE81", "GEOS64.D81"),
                type=3, size=3200 * 256, drive=["-drive8type", "1581"], suffix="-d81"),
}
DRIVE_BANK = 31


def use_disk_set(name):
    """GEOS 2.0 runs from a copy of the oracle disk (tests write to it);
    GeoUltra gets the same disk as drive A through an REU image with a
    mount table (src/drivers/reudrv.s): REU bank 1 holds the table, the
    image starts at DRIVE_BANK. VICE does not write the REU image back."""
    global DISK_SET, ORACLE_DISK, ORACLE_COPY, REU_IMAGE, SYSTEMS
    DISK_SET = DISK_SETS[name]
    ORACLE_DISK = DISK_SET["oracle"]
    ORACLE_COPY = os.path.join(OUT, "oracle." + name)
    REU_IMAGE = os.path.join(OUT, "reu%s.bin" % DISK_SET["suffix"])
    SYSTEMS = {
        "geos": ["-drive8truedrive"] + DISK_SET["drive"]
                + ["+autostart-delay-random", "-autostart-delay", "3",
                   "-reu", "-reusize", "512", "-autostart", ORACLE_COPY],
        "geoultra": ["-cartcrt", os.path.join(ROOT, "build", "geoultra64.crt"),
                     "-reu", "-reusize", "16384", "-reuimage", REU_IMAGE, "+reuimagerw"],
    }


use_disk_set("d64")
PORTS = {"geos": 6502, "geoultra": 6503}

TRAMPOLINE = 0x0340
# Event tests let MainLoop run; this routine first stops the application
# that was running (GEOS 2.0: the deskTop): appMain, intBotVector, key,
# input, other-press, string-fault and alarm vectors cleared, RecoverVector
# back to the kernal's RecoverRectangle, its processes replaced by one
# frozen dummy.
CLEAN_AT = 0x4F00
KEY_STUB = 0x4FA0
CLEAN_CODE = [0xA9, 0x00]                                    # lda #0
for a in (0x849B, 0x849C, 0x849F, 0x84A0, 0x84A3, 0x84A4, 0x84A5, 0x84A6,
          0x84A9, 0x84AA, 0x84AB, 0x84AC, 0x84AD, 0x84AE):
    CLEAN_CODE += [0x8D, a & 0xFF, a >> 8]                   # sta vector
CLEAN_CODE += [0xA9, 0x2D, 0x8D, 0xB1, 0x84,                 # RecoverVector =
               0xA9, 0xC1, 0x8D, 0xB2, 0x84]                 # RecoverRectangle
CLEAN_CODE += [0xA9, 0x80, 0x85, 0x02, 0xA9, 0x4F, 0x85, 0x03,  # r0 = $4F80
               0xA9, 0x01, 0x20, 0x03, 0xC1, 0x60]           # InitProcesses(1); rts
CLEAN_TABLE = [0x7F, 0x4F, 0xE8, 0x03]                       # .word $4F7F (rts), 1000
assert len(CLEAN_CODE) < 0x7F
# GEOS 2.0's BSW 9 (header at $D210, measured): same widths, set width and
# height as GeoUltra's system font, so writing our bitstream over its
# bitstream makes GEOS 2.0 draw system-font text with our glyphs and
# screens with text become comparable.
BSW_HEADER = 0xD210
BSW_DATA = 0xD2DC
# GEOS 2.0's dialog system icons are Berkeley's pictures; the harness puts
# GeoUltra's (tools/mkicons.py) at ICONS_AT and points GEOS 2.0's table
# of the six system icons (found by its layout) at them.
ICONS_AT = 0x5C00
PATTERN_BUF = 0x0380
FORE = (0xA000, 0xBF3F)
BACK = (0x6000, 0x7F3F)
CUR_PATTERN = 0x22
DISP_BUFFER_ON = 0x2F


def our_bitstream():
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import importlib.util as iu
    spec = iu.spec_from_file_location("system9", os.path.join(ROOT, "tools", "fonts", "system9.py"))
    font = iu.module_from_spec(spec)
    spec.loader.exec_module(font)
    import mkfont
    blob = mkfont.build(font)
    return blob[8 + 194:]


def our_sysicons():
    import importlib.util as iu
    spec = iu.spec_from_file_location("mkicons", os.path.join(ROOT, "tools", "mkicons.py"))
    mod = iu.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return [mod.compact(mod.icon(label)) for _, label in mod.LABELS]


def find_sysicon_table(v):
    """Address of GEOS 2.0's six system icon entries (.word picture,
    .word 0, .byte 6, 16, .word routine)."""
    ram = v.mem_get(0xC000, 0xFFFF)
    for i in range(len(ram) - 48):
        if all(ram[i + 8 * k + 2:i + 8 * k + 6] == bytes([0, 0, 6, 16]) for k in range(6)):
            return 0xC000 + i
    raise SystemExit("geos: system icon table not found")


# Disk driver entries applications call directly
DRIVER_ENTRIES = {"Get1stDirEntry": 0x9030, "GetNxtDirEntry": 0x9033, "GetBorder": 0x9036,
                  "AddDirBlock": 0x9039, "ReadBuff": 0x903C, "WriteBuff": 0x903F,
                  "AllocateBlock": 0x9048, "ReadLink": 0x904B}


def jumptab():
    names = [l.split("#")[0].split("=")[0].strip()
             for l in open(os.path.join(ROOT, "src", "kernal", "jumptab.txt"))]
    names = [n for n in names if n]
    table = dict((n, 0xC100 + 3 * i) for i, n in enumerate(names))
    table.update(DRIVER_ENTRIES)
    return table


def prepare_disks():
    """The oracle disk copy (fresh each run) and GeoUltra's REU image."""
    shutil.copyfile(ORACLE_DISK, ORACLE_COPY)
    if (os.path.exists(REU_IMAGE) and os.path.getmtime(REU_IMAGE) > os.path.getmtime(ORACLE_DISK)
            and os.path.getmtime(REU_IMAGE) > os.path.getmtime(__file__)):
        return
    image = open(ORACLE_DISK, "rb").read()[:DISK_SET["size"]]
    reu = bytearray(16 << 20)
    table = 0x010100
    reu[table:table + 5] = b"GUMT\x01"
    reu[table + 0x20:table + 0x24] = bytes([DISK_SET["type"], DRIVE_BANK, 0, 0])   # drive A
    reu[DRIVE_BANK << 16:(DRIVE_BANK << 16) + len(image)] = image
    open(REU_IMAGE, "wb").write(reu)


def rreg(name):
    """Address and size of r0..r15, r0L..r15H."""
    base = name.rstrip("LH")
    addr = 2 + 2 * int(base[1:])
    if name.endswith("H"):
        return addr + 1, 1
    if name.endswith("L"):
        return addr, 1
    return addr, 2


class CaseHang(Exception):
    pass


class System:
    def __init__(self, name, rebuild):
        self.name = name
        self.snapshot = os.path.join(OUT, name + DISK_SET["suffix"] + ".vsf")
        self.log = open(os.path.join(OUT, name + DISK_SET["suffix"] + ".log"), "w")
        self.disk_written = False
        crt = os.path.join(ROOT, "build", "geoultra64.crt")
        stale = (name == "geoultra" and os.path.exists(self.snapshot)
                 and max(os.path.getmtime(crt), os.path.getmtime(REU_IMAGE))
                 > os.path.getmtime(self.snapshot))
        # GEOS 2.0's emulated 1581 only works reliably in the VICE that
        # booted it: with the d81 set it always boots afresh.
        self.boot_always = name == "geos" and DISK_SET["drive"] != []
        try:
            if rebuild or stale or self.boot_always or not os.path.exists(self.snapshot):
                self.launch(boot=True)
                self.make_snapshot()
            else:
                self.launch()
        except BaseException:
            if hasattr(self, "proc"):           # no VICE left behind on the port
                self.proc.kill()
            raise

    def make_snapshot(self):
        """Let the system boot, then stop at the top of its MainLoop."""
        v = self.vice
        for _ in range(60):
            v.resume()
            time.sleep(2)
            v.ping()                        # stops the emulation
            jt = v.mem_get(0xC1C3, 0xC1C5)
            if jt[0] == 0x4C and v.mem_get(0xA000, 0xA000)[0] != 0:
                break
        else:
            raise SystemExit("%s: no GEOS kernal after boot" % self.name)
        time.sleep(0)
        main = jt[1] | jt[2] << 8
        # A temporary checkpoint lets VICE 3.10 run on after the hit (the
        # snapshot then lands anywhere); a permanent one stays stopped.
        cid = v.checkpoint(main, temporary=False)
        v.resume()
        v.wait_event(RESP_CHECKPOINT)
        pc = v.regs_get()["PC"]
        if pc != main:
            raise SystemExit("%s: stopped at $%04X, not MainLoop $%04X" % (self.name, pc, main))
        v.dump(self.snapshot)
        v.delete_checkpoint(cid)
        print("%s: snapshot at MainLoop $%04X" % (self.name, main))

    def run(self, case, table):
        """One case; GEOS 2.0's emulated 1581 turbo sometimes waits forever
        right after a snapshot is restored: such a case runs once more in a
        newly started VICE."""
        try:
            self.key_lost = False
            out = self.run_once(case, table)
            if self.key_lost and self.name == "geos":
                # GEOS 2.0 now and then has no keyVector when the first key
                # arrives (its text input already gone): once more.
                self.key_lost = False
                out = self.run_once(case, table)
            return out
        except CaseHang as hang:
            if self.name != "geos":
                raise SystemExit(str(hang))
            print("%s, retried in a new VICE" % hang, flush=True)
            self.close()
            if case.get("writes"):              # the hung attempt may have
                shutil.copyfile(ORACLE_DISK, ORACLE_COPY)  # written half
            self.launch()
            if self.boot_always:
                self.make_snapshot()
            try:
                return self.run_once(case, table)
            except CaseHang as again:
                raise SystemExit(str(again))

    def run_once(self, case, table):
        if os.environ.get("HARNESS_TRACE"):
            print("%s: %s" % (self.name, case["name"]), flush=True)
        if case.get("writes"):
            self.fresh_disk()
        v = self.vice
        v.undump(self.snapshot)
        v.events.clear()                        # no stale events of a previous case
        if self.name == "geos":
            head = v.mem_get(BSW_HEADER, BSW_HEADER + 3)
            if list(head) != [6, 60, 0, 9]:
                raise SystemExit("geos: BSW 9 not at $%04X" % BSW_HEADER)
            v.mem_set(BSW_DATA, our_bitstream())
            if not hasattr(self, "icon_table"):
                self.icon_table = find_sysicon_table(v)
                self.icon_data = our_sysicons()
            at = ICONS_AT
            for k, data in enumerate(self.icon_data):
                v.mem_set(at, bytes(data))
                v.mem_set(self.icon_table + 8 * k, bytes([at & 0xFF, at >> 8]))
                at += len(data)
        fill = case.get("fill", 0)
        v.mem_set(FORE[0], bytes([case.get("fillfore", fill)]) * (FORE[1] - FORE[0] + 1))
        v.mem_set(BACK[0], bytes([case.get("fillback", fill)]) * (BACK[1] - BACK[0] + 1))
        # sei; I/O on: read the TOD tenths (unlatches the clock if the
        # snapshot caught a time read halfway); $01 = $30, the normal GEOS
        # state (the snapshot may hold another one)
        # clv: V as the snapshots left it differs between systems (cases
        # that compare P after the call saw it)
        code = [0xB8, 0x78, 0xA9, 0x35, 0x85, 0x01, 0xAD, 0x08, 0xDC, 0xA9, 0x30, 0x85, 0x01]
        if "events" in case:
            v.mem_set(CLEAN_AT, bytes(CLEAN_CODE))
            v.mem_set(0x4F7F, bytes([0x60]))
            v.mem_set(0x4F80, bytes(CLEAN_TABLE))
            code += [0x20, CLEAN_AT & 0xFF, CLEAN_AT >> 8]
        for a, data in case.get("poke", {}).items():
            for i, byte in enumerate(data):
                code += [0xA9, byte, 0x8D, (a + i) & 0xFF, (a + i) >> 8]
        for pre in case.get("pre", []):
            a = table[pre]
            code += [0x20, a & 0xFF, a >> 8]
        for name, value in case.get("r", {}).items():
            a, size = rreg(name)
            for i in range(size):
                code += [0xA9, value >> (8 * i) & 0xFF, 0x85, a + i]
        for reg, op in (("a", 0xA9), ("x", 0xA2), ("y", 0xA0)):
            if reg in case:
                code += [op, case[reg]]
        if "flags" in case:
            code += [0xA9, 0xFF if "N" in case["flags"] else 0x00]   # lda: N flag
            code += [0x38 if "C" in case["flags"] else 0x18]          # sec / clc
        a = table[case["routine"]]
        code += [0x20, a & 0xFF, a >> 8] + list(case.get("inline", []))
        code += list(case.get("after", []))
        end = TRAMPOLINE + len(code)
        if "events" in case:
            jt = v.mem_get(0xC1C3, 0xC1C5)      # cli; jmp MainLoop
            code += [0x58, 0x4C, jt[1], jt[2]]
        else:
            code += [0xEA, 0x4C, end & 0xFF, end >> 8]
        v.mem_set(TRAMPOLINE, bytes(code))
        v.mem_set(DISP_BUFFER_ON, bytes([case.get("disp", 0xC0)]))
        if "pattern" in case:
            v.mem_set(PATTERN_BUF, bytes(case["pattern"]))
            v.mem_set(CUR_PATTERN, bytes([PATTERN_BUF & 0xFF, PATTERN_BUF >> 8]))
        for a, data in case.get("mem", {}).items():
            v.mem_set(a, bytes(data))
        v.regs_set({"PC": TRAMPOLINE})
        cid = v.checkpoint(end)
        v.resume()
        if case.get("noreturn"):
            wait = case["noreturn"]
            time.sleep(0.5 if wait is True else wait)
            v.ping()
        else:
            try:
                v.wait_event(RESP_CHECKPOINT, timeout=30)
            except (TimeoutError, OSError):
                v.ping()
                r = v.regs_get()
                raise CaseHang("%s: case %r did not return (PC $%04X, SP $%02X)" % (
                    self.name, case["name"], r["PC"], r["SP"]))
        for ev in case.get("events", []):
            if "key" in ev:
                self.key_event(ev)
                continue
            v.resume()
            time.sleep(0.1)
            v.ping()                            # stop
            x, y = ev["x"], ev["y"]
            v.mem_set(0x3A, bytes([x & 0xFF, x >> 8, y]))
            flag = v.mem_get(0x39, 0x39)[0] | 0x40
            if ev.get("button"):
                v.mem_set(0x8505, bytes([0x00 if ev["button"] == "press" else 0x80]))
                flag |= 0x20
            v.mem_set(0x39, bytes([flag]))
            for a, data in ev.get("mem", {}).items():
                v.mem_set(a, bytes(data))
            v.resume()
            time.sleep(ev.get("wait", 0.4))
            v.ping()
        v.delete_checkpoint(cid)                # not hit when it never returned
        out = {}
        cpu = v.regs_get()
        for item in case["compare"]:
            if item == "fore":
                out[item] = v.mem_get(*FORE)
            elif item == "back":
                out[item] = v.mem_get(*BACK)
            elif item in ("A", "X", "Y"):
                out[item] = cpu[item]
            elif item.startswith(("mem:", "io:")):
                bank, rng = item.split(":")
                lo, hi = rng.replace("$", "").split("-")
                out[item] = v.mem_get(int(lo, 16), int(hi, 16),
                                      bank="io" if bank == "io" else "ram")
            else:
                a, size = rreg(item)
                out[item] = v.mem_get(a, a + size - 1)
        return out

    def key_event(self, ev):
        """Deliver one key through keyVector from MainLoop: appMain is set
        to a one-shot routine that clears appMain, sets keyData and calls
        keyVector (both systems call appMain on every pass)."""
        v = self.vice
        v.ping()                                    # stopped
        stub = KEY_STUB
        code = [0xA9, 0x00, 0x8D, 0x9B, 0x84, 0x8D, 0x9C, 0x84,   # appMain = 0
                0xAD, 0xA3, 0x84, 0x0D, 0xA4, 0x84, 0xF0, 0x08,   # keyVector set?
                0xA9, ev["key"], 0x8D, 0x04, 0x85,               # keyData = key
                0x6C, 0xA3, 0x84,                                # jmp (keyVector)
                0x60]                                            # rts
        v.mem_set(stub, bytes(code))
        v.mem_set(0x849B, bytes([stub & 0xFF, stub >> 8]))
        kv = v.mem_get(0x84A3, 0x84A4)
        for _ in range(20):                         # until the stub has run
            v.resume()                              # (it clears appMain)
            time.sleep(ev.get("wait", 0.2))
            v.ping()
            if v.mem_get(0x849B, 0x849C) != bytes([stub & 0xFF, stub >> 8]):
                break
        else:
            print("%s: key $%02X not delivered (appMain never called, PC $%04X)"
                  % (self.name, ev["key"], v.regs_get()["PC"]), flush=True)
        if kv == b"\0\0":
            self.key_lost = True

    def launch(self, boot=False):
        """Start VICE (GEOS 2.0 autostarts its disk; restoring the snapshot
        over a VICE that only attached the disk made the emulated 1581 hang
        on its first access)."""
        probe = socket.socket()
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)   # (TIME_WAIT is fine)
        try:                                    # a VICE left running from an
            probe.bind(("127.0.0.1", PORTS[self.name]))   # earlier run would
        except OSError:                         # answer in place of the new one
            raise SystemExit("%s: port %d in use (an old VICE still running?)"
                             % (self.name, PORTS[self.name]))
        finally:
            probe.close()
        args = [VICE, "-default", "+sound", "-sounddev", "dummy", "-warp", "-binarymonitor",
                "-binarymonitoraddress", "127.0.0.1:%d" % PORTS[self.name]] + SYSTEMS[self.name]
        self.proc = subprocess.Popen(args, stdout=self.log, stderr=subprocess.STDOUT)
        self.vice = Vice(port=PORTS[self.name])

    def fresh_disk(self):
        """GEOS 2.0 keeps disk writes: a write case after another one gets
        a new VICE with a new copy of the oracle disk (the snapshot then
        restores the booted system)."""
        if self.name == "geos" and self.disk_written:
            self.close()
            shutil.copyfile(ORACLE_DISK, ORACLE_COPY)
            self.launch()
            if self.boot_always:
                self.make_snapshot()
        self.disk_written = True

    def close(self):
        self.vice.quit()
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def describe(item, ours, ref):
    if isinstance(ref, bytes) and len(ref) > 2:
        diffs = [i for i in range(len(ref)) if ref[i] != ours[i]]
        base = FORE[0] if item == "fore" else BACK[0]
        shown = ", ".join("$%04X geos %02X ours %02X" % (base + i, ref[i], ours[i])
                          for i in diffs[:4])
        return "%s: %d bytes differ (%s)" % (item, len(diffs), shown)
    return "%s: geos %s ours %s" % (item, ref.hex() if isinstance(ref, bytes) else ref,
                                     ours.hex() if isinstance(ours, bytes) else ours)


def masked(fore, rects):
    """The foreground screen with the pixels in rects (x0, y0, x1, y1,
    inclusive) cleared: GeoUltra's deliberate additions left out of the
    comparison (a case's "mask", e.g. the file box's drive letters)."""
    b = bytearray(fore)
    for x0, y0, x1, y1 in rects:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                b[(y >> 3) * 320 + (y & 7) + (x & 0x1F8)] &= ~(0x80 >> (x & 7)) & 0xFF
    return bytes(b)


def pixels(fore, x0, y0, x1, y1):
    """ASCII rows of the foreground screen area (inclusive)."""
    out = []
    for y in range(y0, y1 + 1):
        line = ""
        for x in range(x0, x1 + 1):
            byte = fore[(y >> 3) * 320 + (y & 7) + (x & 0x1F8)]
            line += "#" if byte & (0x80 >> (x & 7)) else "."
        out.append(line)
    return out


def load_cases(paths):
    cases = []
    for p in paths:
        spec = importlib.util.spec_from_file_location(os.path.basename(p)[:-3], p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        cases += mod.CASES
    # Cases that write to the disk run last: GEOS 2.0's disk copy keeps
    # their changes for the rest of the run (GeoUltra's REU is restored).
    return sorted(cases, key=lambda c: bool(c.get("writes")))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--rebuild", action="store_true", help="make new snapshots")
    ap.add_argument("--show", metavar="NAME",
                    help="run only the cases whose name contains NAME and print "
                         "the --area of both foreground screens")
    ap.add_argument("--area", default="0,0,63,15", help="x0,y0,x1,y1 for --show")
    ap.add_argument("--systems", default="geos,geoultra",
                    help="systems to run (--show only), e.g. geos")
    ap.add_argument("--set", default="d64", choices=sorted(DISK_SETS),
                    help="disk set: d64 (1541) or d81 (1581, tests/conformance81)")
    ap.add_argument("casefiles", nargs="+")
    args = ap.parse_args()
    use_disk_set(args.set)
    os.makedirs(OUT, exist_ok=True)
    prepare_disks()
    cases = load_cases(args.casefiles)
    if args.show:
        cases = [c for c in cases if args.show in c["name"]]
        for c in cases:
            if "fore" not in c["compare"]:
                c["compare"] = c["compare"] + ["fore"]
    table = jumptab()
    results = {}
    for name in (args.systems.split(",") if args.show else ("geos", "geoultra")):
        system = System(name, args.rebuild)
        try:
            results[name] = [system.run(c, table) for c in cases]
        finally:
            system.close()
    if args.show:
        area = [int(n) for n in args.area.split(",")]
        for i, case in enumerate(cases):
            print("%s   (x %d-%d, y %d-%d)" % (case["name"], area[0], area[2], area[1], area[3]))
            g = pixels(results["geos"][i]["fore"], *area) if "geos" in results else None
            o = pixels(results["geoultra"][i]["fore"], *area) if "geoultra" in results else None
            if g and o:
                print("%-*s   %s" % (len(g[0]), "GEOS 2.0", "GeoUltra"))
                for a, b in zip(g, o):
                    print("%s   %s%s" % (a, b, "   <" if a != b else ""))
            else:
                print("\n".join(g or o))
        return
    failed = 0
    for i, case in enumerate(cases):
        ref, ours = results["geos"][i], results["geoultra"][i]
        if case.get("mask") and "fore" in ref:
            ref["fore"] = masked(ref["fore"], case["mask"])
            ours["fore"] = masked(ours["fore"], case["mask"])
        bad = [k for k in case["compare"] if ref[k] != ours[k]]
        if bad:
            failed += 1
            print("FAIL %-40s %s" % (case["name"], "; ".join(
                describe(k, ours[k], ref[k]) for k in bad)))
        else:
            print("pass %s" % case["name"])
    print("%d of %d cases pass" % (len(cases) - failed, len(cases)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
