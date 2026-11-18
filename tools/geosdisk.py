#!/usr/bin/env python3
"""geosdisk.py - GEOS disk images on a PC: make, list, add, extract.

    geosdisk.py new IMAGE [--name=NAME] [--id=XY]
    geosdisk.py list IMAGE
    geosdisk.py add IMAGE SOURCE [SOURCE ...] [--replace] [--seq]
    geosdisk.py extract IMAGE [NAME ...] [--out=DIR]
    geosdisk.py delete IMAGE NAME [NAME ...]
    geosdisk.py rename IMAGE OLD NEW

IMAGE: a .d64, .d71 or .d81 (all commands), a .dnp (list and extract;
GeoUltra's own DNPs are made with tools/mkappsdnp.py). `new` makes an
empty GEOS disk: BAM, directory, a border block (the off-page directory)
and the "GEOS format V1.0" signature, so GEOS and GeoUltra take it as a
GEOS disk without converting it first (VICE's c1541 formats plain CBM
disks). `list` shows every file with its GEOS type, structure, class,
date and size, the border block's files too. `add` takes a CVT file
(GEOS Convert's format), a file from another image ("other.d81:Name",
"apps.dnp:Writing/geoWrite"), or a plain file (a PRG; --seq: a SEQ),
named after the file; --replace replaces a file of the same name.
`extract` writes GEOS files as CVT files and plain ones as .prg/.seq
(all files when no NAME is given) into DIR (the current one by default).

Formats (CBM DOS, as documented for the 1541/1571/1581; GEOS: HG2G):
D64 35 tracks, BAM 18/0, directory from 18/1; D71 70 tracks, side 2's
free counts at 18/0 $DD and its bitmaps in 53/0; D81 80 tracks of 40
sectors, header 40/0, BAM 40/1 and 40/2, directory from 40/3. The GEOS
signature at header offset $AD, the border block's address at $AB.
Own code (GeoUltra, 2026); image reading from tools/mkappsdnp.py, the
CVT writer from tools/gwtool.py.
"""
import datetime
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkappsdnp import Image, GeoFile, read_cvt   # noqa: E402
from gwtool import write_cvt                      # noqa: E402

GEOS_SIG = b"GEOS format V1.0"
TYPES = {0: "DEL", 1: "SEQ", 2: "PRG", 3: "USR", 4: "REL", 6: "DIR"}
GEOS_TYPES = {0: "", 1: "BASIC", 2: "assembly", 3: "data", 4: "system", 5: "desk acc.",
              6: "application", 7: "appl. data", 8: "font", 9: "printer", 10: "input",
              11: "disk driver", 12: "boot", 13: "temporary", 14: "auto-exec", 15: "input 128"}


def die(msg):
    sys.exit("geosdisk.py: " + msg)


def pad(name, n=16):
    return name.encode("latin1")[:n].ljust(n, b"\xa0")


class Disk:
    """A D64, D71 or D81 image held in memory, with its free block map."""

    SIZES = {"d64": 174848, "d71": 349696, "d81": 819200}

    def __init__(self, path, kind=None, data=None):
        self.path = path
        if data is None:
            data = open(path, "rb").read()
            kind = {174848: "d64", 175531: "d64", 349696: "d71", 351062: "d71",
                    819200: "d81", 822400: "d81"}.get(len(data))
            if kind is None:
                die("%s: not a D64, D71 or D81" % path)
            data = data[:self.SIZES[kind]]
        self.kind = kind
        self.data = bytearray(data)
        if kind == "d81":
            self.tracks, self.dirt, self.dir0 = 80, 40, (40, 3)
        else:
            self.tracks, self.dirt, self.dir0 = (35 if kind == "d64" else 70), 18, (18, 1)
        self.free = {}
        if any(self.data):
            self.read_bam()

    # --- geometry -------------------------------------------------------
    def spt(self, t):
        if self.kind == "d81":
            return 40
        if t > 35:
            t -= 35
        return 21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17

    def off(self, t, s):
        if self.kind == "d81":
            return ((t - 1) * 40 + s) * 256
        side = 0
        if t > 35:
            side, t = 683, t - 35
        return (side + sum(self.spt(x) for x in range(1, t)) + s) * 256

    def get(self, ts):
        o = self.off(*ts)
        return bytearray(self.data[o:o + 256])

    def put(self, ts, block):
        o = self.off(*ts)
        self.data[o:o + 256] = bytes(block).ljust(256, b"\0")

    def header_ts(self):
        return (40, 0) if self.kind == "d81" else (18, 0)

    # --- the BAM --------------------------------------------------------
    def read_bam(self):
        for t in range(1, self.tracks + 1):
            for s in range(self.spt(t)):
                self.free[(t, s)] = self.bam_bit(t, s)

    def bam_bit(self, t, s):
        if self.kind == "d81":
            blk = self.get((40, 1 if t <= 40 else 2))
            e = 0x10 + 6 * ((t - 1) % 40)
            return bool(blk[e + 1 + s // 8] & (1 << (s % 8)))
        if t <= 35:
            blk = self.get((18, 0))
            return bool(blk[4 * t + 1 + s // 8] & (1 << (s % 8)))
        blk = self.get((53, 0))
        return bool(blk[3 * (t - 36) + s // 8] & (1 << (s % 8)))

    def write_bam(self):
        if self.kind == "d81":
            for half in (1, 2):
                blk = self.get((40, half))
                for t in range(1 + 40 * (half - 1), 41 + 40 * (half - 1)):
                    e = 0x10 + 6 * ((t - 1) % 40)
                    bits = sum(1 << s for s in range(40) if self.free[(t, s)])
                    blk[e] = bin(bits).count("1")
                    blk[e + 1:e + 6] = bits.to_bytes(5, "little")
                self.put((40, half), blk)
            return
        h = self.get((18, 0))
        for t in range(1, 36):
            bits = sum(1 << s for s in range(self.spt(t)) if self.free[(t, s)])
            h[4 * t] = bin(bits).count("1")
            h[4 * t + 1:4 * t + 4] = bits.to_bytes(3, "little")
        if self.kind == "d71":
            b2 = self.get((53, 0))
            for t in range(36, 71):
                bits = sum(1 << s for s in range(self.spt(t)) if self.free[(t, s)])
                h[0xDD + t - 36] = bin(bits).count("1")
                b2[3 * (t - 36):3 * (t - 36) + 3] = bits.to_bytes(3, "little")
            self.put((53, 0), b2)
        self.put((18, 0), h)

    def blocks_free(self):
        return sum(1 for (t, s), f in self.free.items() if f and t != self.dirt
                   and not (self.kind == "d71" and t == 53))

    def alloc(self, near=None):
        """A free block, the tracks nearest the directory track first
        (data never on the directory track: that is the directory's)."""
        order = sorted((t for t in range(1, self.tracks + 1)
                        if t != self.dirt and not (self.kind == "d71" and t == 53)),
                       key=lambda t: (abs(t - self.dirt), t))
        for t in order:
            for s in range(self.spt(t)):
                if self.free[(t, s)]:
                    self.free[(t, s)] = False
                    return (t, s)
        die("%s: disk full" % self.path)

    def release(self, ts):
        if ts in self.free:
            self.free[ts] = True

    # --- making a disk --------------------------------------------------
    @classmethod
    def new(cls, path, name, disk_id):
        kind = os.path.splitext(path)[1].lower()[1:]
        if kind not in cls.SIZES:
            die("%s: give the image a .d64, .d71 or .d81 name" % path)
        d = cls(path, kind, bytes(cls.SIZES[kind]))
        for t in range(1, d.tracks + 1):
            for s in range(d.spt(t)):
                d.free[(t, s)] = True
        ident = disk_id.encode("latin1")[:2].ljust(2, b" ")
        if kind == "d81":
            for s in range(4):
                d.free[(40, s)] = False
            h = bytearray(256)
            h[0:4] = bytes([40, 3, ord("D"), 0])
            h[4:20] = pad(name)
            h[0x14:0x16] = b"\xa0\xa0"
            h[0x16:0x18] = ident
            h[0x18] = 0xA0
            h[0x19:0x1B] = b"3D"
            h[0x1B:0x1D] = b"\xa0\xa0"
            d.put((40, 0), h)
            for half in (1, 2):
                b = bytearray(256)
                b[0:2] = bytes([40, 2]) if half == 1 else b"\x00\xff"
                b[2:8] = bytes([ord("D"), ord("D") ^ 0xFF]) + ident + bytes([0xC0, 0])
                d.put((40, half), b)
            d.put((40, 3), b"\x00\xff")
        else:
            d.free[(18, 0)] = d.free[(18, 1)] = False
            if kind == "d71":
                for s in range(d.spt(53)):
                    d.free[(53, s)] = False
            h = bytearray(256)
            h[0:4] = bytes([18, 1, ord("A"), 0x80 if kind == "d71" else 0])
            h[0x90:0xA0] = pad(name)
            h[0xA0:0xA2] = b"\xa0\xa0"
            h[0xA2:0xA4] = ident
            h[0xA4] = 0xA0
            h[0xA5:0xA7] = b"2A"
            h[0xA7:0xAB] = b"\xa0" * 4
            d.put((18, 0), h)
            d.put((18, 1), b"\x00\xff")
        border = d.alloc()
        d.put(border, b"\x00\xff")
        h = d.get(d.header_ts())
        h[0xAB:0xAD] = bytes(border)
        h[0xAD:0xAD + 16] = GEOS_SIG
        d.put(d.header_ts(), h)
        d.write_bam()
        return d

    def save(self):
        self.write_bam()
        open(self.path, "wb").write(self.data)

    # --- the directory --------------------------------------------------
    def border(self):
        h = self.get(self.header_ts())
        if h[0xAD:0xAD + 16] == GEOS_SIG and h[0xAB]:
            return (h[0xAB], h[0xAC])
        return None

    def slots(self):
        """(block, offset, entry) of every directory entry, used or not,
        the border block's last."""
        out = []
        ts, seen = self.dir0, set()
        while ts[0] and ts not in seen:
            seen.add(ts)
            b = self.get(ts)
            for e in range(8):
                out.append((ts, 32 * e + 2, bytes(b[32 * e + 2:32 * e + 32])))
            ts = (b[0], b[1])
        bd = self.border()
        if bd:
            b = self.get(bd)
            for e in range(8):
                out.append((bd, 32 * e + 2, bytes(b[32 * e + 2:32 * e + 32])))
        return out

    def files(self):
        return [(ts, o, e) for ts, o, e in self.slots() if e[0] & 0x07]

    def find(self, name):
        for ts, o, e in self.files():
            if e[3:19].split(b"\xa0")[0].decode("latin1") == name:
                return ts, o, e
        return None

    def free_slot(self):
        bd = self.border()
        for ts, o, e in self.slots():
            if e[0] == 0 and ts != bd:
                return ts, o
        ts = self.dir0                  # a new directory block on its track
        while True:
            b = self.get(ts)
            if b[0] == 0:
                break
            ts = (b[0], b[1])
        for s in range(self.spt(self.dirt)):
            if self.free[(self.dirt, s)]:
                self.free[(self.dirt, s)] = False
                b[0:2] = bytes([self.dirt, s])
                self.put(ts, b)
                self.put((self.dirt, s), b"\x00\xff")
                return (self.dirt, s), 2
        die("%s: directory full" % self.path)

    # --- files ----------------------------------------------------------
    def chain(self, data):
        pieces = [data[i:i + 254] for i in range(0, len(data), 254)] or [b""]
        where = [self.alloc() for _ in pieces]
        for i, p in enumerate(pieces):
            link = bytes(where[i + 1]) if i + 1 < len(pieces) else bytes([0, len(p) + 1])
            self.put(where[i], link + p)
        return where[0], len(pieces)

    def free_chain(self, ts):
        seen = set()
        while ts[0] and ts not in seen and ts in self.free:
            seen.add(ts)
            b = self.get(ts)
            self.release(ts)
            ts = (b[0], b[1])

    def add(self, gf):
        e = bytearray(gf.entry)
        blocks = 0
        if gf.header is not None and e[0x16]:
            ht = self.alloc()
            self.put(ht, b"\x00\xff" + bytes(gf.header[2:256]))
            e[0x13:0x15] = bytes(ht)
            blocks += 1
        else:
            e[0x13:0x15] = b"\0\0"
        if gf.records is not None:
            index = bytearray(256)
            index[1] = 0xFF
            for r, rec in enumerate(gf.records[:127]):
                if rec is None or rec == "end":
                    index[2 + 2 * r:4 + 2 * r] = b"\x00\xff"
                else:
                    first, n = self.chain(rec)
                    index[2 + 2 * r:4 + 2 * r] = bytes(first)
                    blocks += n
            it = self.alloc()
            self.put(it, index)
            e[1:3] = bytes(it)
            e[0x15] = 1
            blocks += 1
        else:
            first, n = self.chain(gf.data or b"")
            e[1:3] = bytes(first)
            blocks += n
        e[0] |= 0x80                    # closed
        e[0x1C:0x1E] = blocks.to_bytes(2, "little")
        ts, o = self.free_slot()
        b = self.get(ts)
        b[o:o + 30] = e
        self.put(ts, b)

    def delete(self, name):
        hit = self.find(name)
        if not hit:
            die("%s: no file %r" % (self.path, name))
        ts, o, e = hit
        if e[0x15] == 1 and e[0x16]:                    # VLIR: each record
            index = self.get((e[1], e[2]))
            for r in range(127):
                t, s = index[2 + 2 * r], index[3 + 2 * r]
                if t:
                    self.free_chain((t, s))
            self.release((e[1], e[2]))
        else:
            self.free_chain((e[1], e[2]))
        if e[0x16] and e[0x13]:
            self.release((e[0x13], e[0x14]))
        b = self.get(ts)
        b[o] = 0
        self.put(ts, b)


def source(spec, seq):
    """A GeoFile from a CVT, "image:name", or a plain file."""
    if ":" in spec and not os.path.exists(spec):
        img, name = spec.split(":", 1)
        src = Image(img)
        en = src.find(name)
        if en is None:
            die("%s: no file %r" % (img, name))
        return src.gfile(en)
    data = open(spec, "rb").read()
    if data[30:60].find(b"formatted GEOS file") >= 0:
        return read_cvt(spec)
    e = bytearray(30)
    e[0] = 0x81 if seq else 0x82
    base = os.path.splitext(os.path.basename(spec))[0]
    e[3:19] = pad(base)
    now = datetime.datetime.now()
    e[0x17:0x1C] = bytes([now.year % 100, now.month, now.day, now.hour, now.minute])
    return GeoFile(bytes(e), None, data, None)


def describe(e):
    name = e[3:19].split(b"\xa0")[0].decode("latin1")
    kind = TYPES.get(e[0] & 7, "?")
    blocks = e[0x1C] | e[0x1D] << 8
    if e[0x16] or e[0x13]:
        geos = "%-12s %s" % (GEOS_TYPES.get(e[0x16], str(e[0x16])), "VLIR" if e[0x15] == 1 else "seq.")
        date = "%02d-%02d-%02d %02d:%02d" % (e[0x19], e[0x18], e[0x17], e[0x1A], e[0x1B])
    else:
        geos, date = "", ""
    return name, kind, blocks, geos, date


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], True) for a in argv[1:] if a.startswith("--"))
    if len(args) < 2:
        sys.exit(__doc__.strip().split("\n\n")[1])
    cmd, path = args[0], args[1]
    if cmd == "new":
        if os.path.exists(path) and "replace" not in opts:
            die("%s exists (--replace to overwrite)" % path)
        d = Disk.new(path, opts.get("name", "GEOS disk"), opts.get("id", "GU"))
        d.save()
        print("%s: empty GEOS disk, %d blocks free" % (path, d.blocks_free()))
        return
    if cmd in ("list", "extract") and os.path.splitext(path)[1].lower() == ".dnp":
        img = Image(path)
        entries = []

        def walk(start, prefix):
            for en in img.entries(start):
                nm = en[3:19].split(b"\xa0")[0].decode("latin1")
                entries.append((prefix + nm, en))
                if en[0] & 7 == 6:
                    walk(tuple(img.block(en[1], en[2])[0:2]), prefix + nm + "/")
        walk(None, "")
    else:
        d = Disk(path)
        img = Image(path)
        entries = [(e[3:19].split(b"\xa0")[0].decode("latin1"), e) for _, _, e in d.files()]
    if cmd == "list":
        for name, e in entries:
            nm, kind, blocks, geos, date = describe(e)
            gf = img.gfile(e) if (e[0x16] and e[0x13] and e[0] & 7 != 6) else None
            cls = gf.header[0x4D:0x61].split(b"\0")[0].decode("latin1", "replace") if gf and gf.header else ""
            print("%5d  %-24s %-3s  %-17s %-20s %s" % (blocks, name, kind, geos, cls, date))
        if cmd == "list" and os.path.splitext(path)[1].lower() != ".dnp":
            print("%d blocks free%s" % (d.blocks_free(), ", GEOS disk" if d.border() else ", not a GEOS disk"))
        return
    if cmd == "extract":
        out = opts.get("out", ".")
        os.makedirs(out, exist_ok=True)
        want = set(args[2:])
        for name, e in entries:
            if (want and name not in want) or e[0] & 7 == 6:
                continue
            gf = img.gfile(e)
            safe = name.replace("/", "_")
            if e[0x16] or e[0x13]:
                p = os.path.join(out, safe + ".cvt")
                write_cvt(gf, p)
            else:
                p = os.path.join(out, safe + "." + TYPES.get(e[0] & 7, "bin").lower())
                open(p, "wb").write(gf.data or b"")
            print(p)
            want.discard(name)
        if want:
            die("not found: %s" % ", ".join(sorted(want)))
        return
    if cmd == "add":
        for spec in args[2:]:
            gf = source(spec, "seq" in opts)
            if d.find(gf.name):
                if "replace" not in opts:
                    die("%s: %r is there already (--replace)" % (path, gf.name))
                d.delete(gf.name)
            d.add(gf)
            print("%s: %s added" % (path, gf.name))
        d.save()
        print("%d blocks free" % d.blocks_free())
        return
    if cmd == "delete":
        for name in args[2:]:
            d.delete(name)
        d.save()
        print("%d blocks free" % d.blocks_free())
        return
    if cmd == "rename" and len(args) == 4:
        hit = d.find(args[2])
        if not hit:
            die("%s: no file %r" % (path, args[2]))
        if d.find(args[3]):
            die("%s: %r is there already" % (path, args[3]))
        ts, o, e = hit
        b = d.get(ts)
        b[o + 3:o + 19] = pad(args[3])
        d.put(ts, b)
        d.save()
        return
    sys.exit(__doc__.strip().split("\n\n")[1])


if __name__ == "__main__":
    main(sys.argv)
