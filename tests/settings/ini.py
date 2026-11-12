#!/usr/bin/env python3
"""src/inc/ini.inc in VICE (docs/SETTINGS.md, "Structure"): IniFind,
IniSet and IniDel on texts in a buffer, checked byte for byte. GeoUltra
boots as in the engine tests (tests/engine/feharness.py) and stops
before the desktop loads; the test program (tests/settings/initest.s)
then sits at $2000 with its buffer at $3000 and each routine is called
from a few bytes of code. No files are read or written.
Usage: tests/settings/ini.py
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tests", "engine"))
from feharness import Engine, OUT  # noqa: E402
from vicemon import RESP_CHECKPOINT  # noqa: E402

BASE, BUF, INI_MAX = 0x2000, 0x3000, 1023
SECT, KEY, VAL, CODE, RES = 0x3800, 0x3840, 0x3880, 0x3980, 0x3A00
FIND, SET, DEL = BASE, BASE + 3, BASE + 6


def build():
    obj = os.path.join(OUT, "initest.o")
    binary = os.path.join(OUT, "initest.bin")
    os.makedirs(OUT, exist_ok=True)
    subprocess.run(["ca65", "-I", os.path.join(ROOT, "src", "inc"), "-o", obj,
                    os.path.join(ROOT, "tests", "settings", "initest.s")], check=True)
    subprocess.run(["ld65", "-C", os.path.join(ROOT, "tests", "settings", "initest.cfg"), "-o", binary, obj],
                   check=True)
    return open(binary, "rb").read()


def main():
    blob = build()
    e = Engine("ini", 6581)
    v, check = e.v, e.check
    try:
        e.start()
        v.mem_set(BASE, blob)
        len_at = blob[9] | blob[10] << 8

        def text(t):
            v.mem_set(BUF, t + b"\0")
            v.mem_set(len_at, bytes([len(t) & 0xFF, len(t) >> 8]))

        def get():
            n = v.mem_get(len_at, len_at + 1)
            n = n[0] | n[1] << 8
            t = bytes(v.mem_get(BUF, BUF + n))                    # (with the zero)
            if t[-1] != 0:
                return "no zero after the text"
            return t[:-1]

        def call(entry, sect, key, val=None):
            v.mem_set(SECT, sect.encode() + b"\0")
            v.mem_set(KEY, key.encode() + b"\0")
            if val is not None:
                v.mem_set(VAL, val.encode() + b"\0")
            code = [0x78, 0xA9, 0x30, 0x85, 0x01,                     # sei; RAM
                    0xA9, SECT & 0xFF, 0x85, 0x02, 0xA9, SECT >> 8, 0x85, 0x03,
                    0xA9, KEY & 0xFF, 0x85, 0x04, 0xA9, KEY >> 8, 0x85, 0x05,
                    0xA9, VAL & 0xFF, 0x85, 0x06, 0xA9, VAL >> 8, 0x85, 0x07,
                    0x20, entry & 0xFF, entry >> 8,
                    0x08, 0x8D, (RES + 1) & 0xFF, RES >> 8,           # php; sta A
                    0x68, 0x8D, RES & 0xFF, RES >> 8,                 # pla; sta P
                    0xA5, 0x06, 0x8D, (RES + 2) & 0xFF, RES >> 8,     # r2
                    0xA5, 0x07, 0x8D, (RES + 3) & 0xFF, RES >> 8]
            end = CODE + len(code)
            code += [0x4C, end & 0xFF, end >> 8]
            v.mem_set(CODE, bytes(code))
            v.regs_set({"PC": CODE})
            v.checkpoint(end)
            v.resume()
            v.wait_event(RESP_CHECKPOINT, timeout=30)
            r = v.mem_get(RES, RES + 3)
            return r[0] & 1, r[1], r[2] | r[3] << 8              # C, A, r2

        def find(t, sect, key):
            text(t)
            c, a, r2 = call(FIND, sect, key)
            if c:
                return None
            return bytes(v.mem_get(r2, r2 + a - 1)) if a else b""

        def iset(t, sect, key, val):
            text(t)
            c, _, _ = call(SET, sect, key, val)
            return c, get()

        def idel(t, sect, key):
            text(t)
            c, _, _ = call(DEL, sect, key)
            return c, get()

        T = b"; GeoUltra\r\n[desktop]\r\nview=icons\r\nclock=24\r\n\r\n[system]\r\nturbo=8\r\nview=no\r\n"
        check("IniFind: a key's value", find(T, "desktop", "view"), b"icons")
        check("IniFind: names in any case", find(T.replace(b"[desktop]", b"[Desktop]"), "desktop", "VIEW"),
              b"icons")
        check("IniFind: the same key in another section", find(T, "system", "view"), b"no")
        check("IniFind: a key not there", find(T, "desktop", "turbo"), None)
        check("IniFind: a section not there", find(T, "time", "ntp"), None)
        check("IniFind: a key that only starts the same", find(T, "desktop", "vie"), None)
        check("IniFind: LF line ends", find(T.replace(b"\r\n", b"\n"), "system", "turbo"), b"8")
        check("IniFind: the last line without its end", find(b"[a]\r\nk=v", "a", "k"), b"v")
        check("IniFind: an empty value", find(b"[a]\r\nk=\r\n", "a", "k"), b"")

        check("IniSet: a value replaced by a shorter one", iset(T, "desktop", "view", "list"),
              (0, T.replace(b"view=icons", b"view=list")))
        check("IniSet: by a longer one", iset(T, "system", "turbo", "15"),
              (0, T.replace(b"turbo=8", b"turbo=15")))
        check("IniSet: a new key at its section's end (before the blank line)",
              iset(T, "desktop", "panes", "2"),
              (0, T.replace(b"clock=24\r\n", b"clock=24\r\npanes=2\r\n")))
        check("IniSet: a new key in the last section", iset(T, "system", "slow", "geoWrite"),
              (0, T + b"slow=geoWrite\r\n"))
        check("IniSet: a new section at the end", iset(T, "time", "ntp", "pool.ntp.org"),
              (0, T + b"[time]\r\nntp=pool.ntp.org\r\n"))
        check("IniSet: a line end added after a last line without one",
              iset(b"[a]\r\nk=v", "a", "x", "1"), (0, b"[a]\r\nk=v\r\nx=1\r\n"))
        check("IniSet: into an empty text", iset(b"", "desktop", "view", "list"),
              (0, b"[desktop]\r\nview=list\r\n"))
        check("IniSet: an empty section header only", iset(b"[a]\r\n", "a", "k", "v"),
              (0, b"[a]\r\nk=v\r\n"))
        big = b"[a]\r\nk=v\r\n" + b"x" * (INI_MAX - 10 - 4) + b"\r\n"
        check("IniSet: too long for the buffer: refused, unchanged", iset(big, "a", "new", "value"), (1, big))

        check("IniDel: a line taken out", idel(T, "desktop", "clock"),
              (0, T.replace(b"clock=24\r\n", b"")))
        check("IniDel: the other section's key stays", idel(T, "system", "view"),
              (0, T.replace(b"view=no\r\n", b"")))
        check("IniDel: a key not there", idel(T, "desktop", "nope"), (1, T))
    finally:
        e.stop()
    sys.exit(0 if e.ok else 1)


if __name__ == "__main__":
    main()
