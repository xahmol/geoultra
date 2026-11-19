#!/usr/bin/env python3
"""mkappsdnp.py - build a GEOS applications DNP with folders from a manifest.

    mkappsdnp.py MANIFEST.toml

Builds a CMD native (DNP) image in GEOS format with CMD native folders and
fills it with GEOS files copied block by block from D64, D81 and DNP images
(also from folders inside DNPs) and from CVT files (sequential and VLIR,
the Convert 2.5 / c1541 format). Meant for a private test, screenshot and
video set of the user's own applications: the manifest and the image stay
outside the repository (private/, gitignored); this tool holds no
third-party content.

Manifest (TOML):

    [dnp]
    out = "geoultra-apps.dnp"     # relative to the manifest
    name = "GeoUltra Apps"         # disk name, max 16 characters
    id = "GU"
    tracks = 48                    # 64 KB each; 0: as small as fits (+25%)
    strict = false                 # true: a missing file stops the build

    [sources]                      # name = image or folder of CVTs
    gdos = "private/ramapps.DNP"
    geoutools = "../GeoUTools/build"

    [[folder]]
    path = ""                      # "" is the root; "A/B" nested
    files = ["gdos:GEOWRITE", "gdos:Sub/Name", "geoutools:geoumount.cvt"]
    all = ["src2"]                 # optional: every file of these sources

A file is "source:name": the name as in the directory (GEOS names are
ASCII, case matters), with "Folder/Name" for a folder inside a DNP source;
for a folder source, the CVT file name. A name may appear in several
folders. Files that are not found are reported, the build goes on.

DNP layout (CMD native, as GeoUltra's driver and DirMaster read it; checked
against DirMaster's own DNP, docs/design/DESIGN.md "DirMaster and native
folders"): 256 sectors per track; header 1/1 (directory at 1/34, "H",
name, ID, "1H", own block at $20); BAM blocks 1/2-1/33 (1/2: "H", ID,
the last track at $08; from offset $20 32 bytes per track, bit 7 first,
set = free); folders as directory entries of type $86 whose first block
is the folder header (as the root header, plus the parent header at $22,
the parent entry's block at $24 and its offset at $26). GEOS format: the
signature "GEOS format V1.0" at $AD of the header and an empty border
block at $AB.

Written 2026 by Xander Mol for GeoUltra (own code).
"""
import os
import sys
import tomllib

GEOS_SIG = b"GEOS format V1.0"
TYPE_DIR = 0x86


def die(msg):
    sys.exit("mkappsdnp.py: " + msg)


def pad(name, length=16):
    data = name.encode("latin1")[:length]
    return data + b"\xa0" * (length - len(data))


class Image:
    """A source disk image (D64, D71, D81, DNP): blocks and directories."""

    def __init__(self, path):
        self.path = path
        self.data = open(path, "rb").read()
        n = len(self.data)
        if n in (174848, 175531):
            self.kind, self.root = "d64", (18, 1)
        elif n in (349696, 351062):
            self.kind, self.root = "d71", (18, 1)
        elif n in (819200, 822400):
            self.kind, self.root = "d81", (40, 3)
        elif n % 65536 == 0:
            self.kind = "dnp"
            self.root = tuple(self.block(1, 1)[0:2])
        else:
            die("%s: unknown image size %d" % (path, n))

    def offset(self, t, s):
        if self.kind == "dnp":
            return ((t - 1) * 256 + s) * 256
        if self.kind == "d81":
            return ((t - 1) * 40 + s) * 256
        side = 0
        if t > 35:
            side, t = 683, t - 35
        o = sum(21 if x <= 17 else 19 if x <= 24 else 18 if x <= 30 else 17
                for x in range(1, t))
        return (side + o + s) * 256

    def block(self, t, s):
        o = self.offset(t, s)
        return self.data[o:o + 256]

    def entries(self, start=None):
        t, s = start or self.root
        seen = set()
        while t and (t, s) not in seen:
            seen.add((t, s))
            b = self.block(t, s)
            for e in range(8):
                en = b[32 * e + 2:32 * e + 32]
                if en[0] & 0x07:
                    yield en
            t, s = b[0], b[1]

    def find(self, name):
        """The entry for "Name" or "Folder/Name" (DNP folders)."""
        parts = name.split("/")
        start = None
        for i, part in enumerate(parts):
            for en in self.entries(start):
                if en[3:19].split(b"\xa0")[0].decode("latin1") == part:
                    break
            else:
                return None
            if i < len(parts) - 1:
                if en[0] & 0x07 != 6:
                    return None
                start = tuple(self.block(en[1], en[2])[0:2])
        return en

    def chain(self, t, s):
        blocks = []
        seen = set()
        while t and (t, s) not in seen:
            seen.add((t, s))
            b = self.block(t, s)
            blocks.append(b)
            t, s = b[0], b[1]
        return blocks

    def gfile(self, en):
        """GeoFile from a directory entry: header block, data or records."""
        header = self.block(en[0x13], en[0x14]) if en[0x16] else None
        if en[0x15] == 1:                               # VLIR
            index = self.block(en[1], en[2])
            records = []
            for r in range(2, 256, 2):
                t, s = index[r], index[r + 1]
                if t == 0:
                    records.append(None if s == 0xFF else "end")
                    if s != 0xFF:
                        break
                    continue
                records.append(chain_data(self.chain(t, s)))
            while records and records[-1] == "end":
                records.pop()
            return GeoFile(bytes(en), header, None, records)
        return GeoFile(bytes(en), header, chain_data(self.chain(en[1], en[2])), None)


def chain_data(blocks):
    out = b""
    for b in blocks:
        out += b[2:256] if b[0] else b[2:b[1] + 1]
    return out


class GeoFile:
    """A file to write: its 30-byte entry, header block, data or records."""

    def __init__(self, entry, header, data, records):
        self.entry, self.header, self.data, self.records = entry, header, data, records

    @property
    def name(self):
        return self.entry[3:19].split(b"\xa0")[0].decode("latin1")


def read_cvt(path, d=None):
    """A GeoFile from a CVT file (or its bytes, d; path then names it)."""
    if d is None:
        d = open(path, "rb").read()
    entry = d[0:30]
    if not (d[30:58].endswith(b"formatted GEOS file V1.0") or b"formatted GEOS file" in d[30:60]):
        die("%s: not a CVT file" % path)
    header = b"\x00\xff" + d[254:508]
    if entry[0x15] != 1:
        return GeoFile(entry, header, d[508:], None)
    table = d[508:762]
    pos = 762
    records = []
    pairs = []
    for i in range(0, 254, 2):                  # (an empty record: 00 FF from
        pairs.append((table[i], table[i + 1]))  # GEOS Convert, 00 00 from others
    while pairs and pairs[-1] == (0, 0):        # in the middle: read all 127;
        pairs.pop()                             # only 00 00 at the end dropped,
                                                # trailing 00 FF kept: a geoWrite
                                                # document needs them, gwtool.py
                                                # EMPTY)
    for k, (n, last) in enumerate(pairs):
        if n == 0:
            records.append(None)
            continue
        size = (n - 1) * 254 + last - 1
        records.append(d[pos:pos + size])
        pos += n * 254
    return GeoFile(entry, header, None, records)


class DNP:
    """The image being built."""

    def __init__(self, tracks, name, disk_id):
        if not 2 <= tracks <= 255:
            die("tracks must be 2-255")
        self.tracks = tracks
        self.data = bytearray(tracks * 65536)
        self.id = disk_id.encode("latin1")[:2].ljust(2, b" ")
        self.free = [True] * (tracks * 256)
        for s in range(35):                     # boot, header, BAM, root dir
            self.use(1, s)
        self.root = (1, 1)
        h = bytearray(256)
        h[0:2] = b"\x01\x22"
        h[2] = ord("H")
        h[4:20] = pad(name)
        h[0x14:0x16] = b"\xa0\xa0"
        h[0x16:0x18] = self.id
        h[0x18] = 0xA0
        h[0x19:0x1B] = b"1H"
        h[0x1B:0x1D] = b"\xa0\xa0"
        h[0x20:0x22] = b"\x01\x01"
        border = self.alloc()
        self.put(border, b"\x00\xff" + bytes(254))
        h[0xAB:0xAD] = bytes(border)
        h[0xAD:0xAD + 16] = GEOS_SIG
        self.put((1, 1), h)
        self.put((1, 34), b"\x00\xff" + bytes(254))
        self.dirs = {"": ((1, 1), (1, 34))}     # path -> (header, first dir block)

    def off(self, ts):
        t, s = ts
        return ((t - 1) * 256 + s) * 256

    def put(self, ts, block):
        o = self.off(ts)
        self.data[o:o + 256] = bytes(block).ljust(256, b"\x00")

    def get(self, ts):
        o = self.off(ts)
        return bytearray(self.data[o:o + 256])

    def use(self, t, s):
        self.free[(t - 1) * 256 + s] = False

    def alloc(self):
        try:
            i = self.free.index(True, 35)
        except ValueError:
            die("image full: raise [dnp] tracks")
        self.free[i] = False
        return (i // 256 + 1, i % 256)

    def write_chain(self, data):
        """data in a new chain; (first block, block count)."""
        if not data:
            data = b""
        pieces = [data[i:i + 254] for i in range(0, len(data), 254)] or [b""]
        where = [self.alloc() for _ in pieces]
        for i, piece in enumerate(pieces):
            if i + 1 < len(pieces):
                link = bytes(where[i + 1])
            else:
                link = bytes([0, len(piece) + 1])
            self.put(where[i], link + piece)
        return where[0], len(pieces)

    def new_entry(self, folder):
        """A free directory slot in folder: (block, offset of the type byte)."""
        header, first = self.dirs[folder]
        ts = first
        while True:
            b = self.get(ts)
            for e in range(8):
                if b[32 * e + 2] == 0:
                    return ts, 32 * e + 2
            if b[0] == 0:
                nxt = self.alloc()
                b[0:2] = bytes(nxt)
                self.put(ts, b)
                self.put(nxt, b"\x00\xff" + bytes(254))
                return nxt, 2
            ts = (b[0], b[1])

    def mkdir(self, path):
        if path in self.dirs:
            return
        parent, _, name = path.rpartition("/")
        self.mkdir(parent)
        at, off = self.new_entry(parent)
        header = self.alloc()
        first = self.alloc()
        h = bytearray(256)
        h[0:2] = bytes(first)
        h[2] = ord("H")
        h[4:20] = pad(name)
        h[0x14:0x16] = b"\xa0\xa0"
        h[0x16:0x18] = self.id
        h[0x18] = 0xA0
        h[0x19:0x1B] = b"1H"
        h[0x1B:0x1D] = b"\xa0\xa0"
        h[0x20:0x22] = bytes(header)
        h[0x22:0x24] = bytes(self.dirs[parent][0])
        h[0x24:0x26] = bytes(at)
        h[0x26] = off
        self.put(header, h)
        self.put(first, b"\x00\xff" + bytes(254))
        e = bytearray(30)
        e[0] = TYPE_DIR
        e[1:3] = bytes(header)
        e[3:19] = pad(name)
        e[0x1C:0x1E] = (2).to_bytes(2, "little")
        b = self.get(at)
        b[off:off + 30] = e
        self.put(at, b)
        self.dirs[path] = (header, first)

    def add(self, folder, gf):
        e = bytearray(gf.entry)
        blocks = 0
        if gf.header is not None and e[0x16]:
            ht = self.alloc()
            self.put(ht, b"\x00\xff" + bytes(gf.header[2:256]))
            e[0x13:0x15] = bytes(ht)
            blocks += 1
        else:
            e[0x13:0x15] = b"\x00\x00"
        if gf.records is not None:
            index = bytearray(256)
            index[0:2] = b"\x00\xff"
            for r, rec in enumerate(gf.records[:127]):
                if rec is None:
                    index[2 + 2 * r:4 + 2 * r] = b"\x00\xff"
                else:
                    first, n = self.write_chain(rec)
                    index[2 + 2 * r:4 + 2 * r] = bytes(first)
                    blocks += n
            it = self.alloc()
            self.put(it, index)
            e[1:3] = bytes(it)
            blocks += 1
            e[0x15] = 1
        else:
            first, n = self.write_chain(gf.data)
            e[1:3] = bytes(first)
            blocks += n
        e[0x1C:0x1E] = blocks.to_bytes(2, "little")
        at, off = self.new_entry(folder)
        b = self.get(at)
        b[off:off + 30] = e
        self.put(at, b)

    def finish(self):
        """The BAM blocks 1/2-1/33."""
        bam = bytearray(32 * 256)
        bam[2] = ord("H")
        bam[3] = ord("H") ^ 0xFF
        bam[4:6] = self.id
        bam[6] = 0xC0
        bam[8] = self.tracks
        for t in range(1, self.tracks + 1):
            for s in range(256):
                if self.free[(t - 1) * 256 + s]:
                    bam[t * 32 + s // 8] |= 0x80 >> (s % 8)
        for i in range(32):                     # (no block links: 1/2 starts
            self.put((1, 2 + i), bam[i * 256:(i + 1) * 256])  # with 0 0)

    def blocks_used(self):
        return self.free.count(False)


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    mpath = argv[1]
    base = os.path.dirname(os.path.abspath(mpath))
    m = tomllib.load(open(mpath, "rb"))
    srcs = {}
    for key, path in m.get("sources", {}).items():
        p = os.path.expanduser(path)
        if not os.path.isabs(p):
            p = os.path.join(base, p)
        srcs[key] = p if os.path.isdir(p) else Image(p)
    plan = []
    missing = []
    for f in m.get("folder", []):
        folder = f.get("path", "")
        names = list(f.get("files", []))
        for key in f.get("all", []):
            src = srcs[key]
            if isinstance(src, str):
                names += ["%s:%s" % (key, n) for n in sorted(os.listdir(src))
                          if n.lower().endswith(".cvt")]
            else:
                names += ["%s:%s" % (key, en[3:19].split(b"\xa0")[0].decode("latin1"))
                          for en in src.entries() if en[0] & 0x07 != 6]
        for spec in names:
            key, _, name = spec.partition(":")
            src = srcs.get(key)
            if src is None:
                die("unknown source %r in %r" % (key, spec))
            if isinstance(src, str):
                p = os.path.join(src, name)
                gf = read_cvt(p) if os.path.exists(p) else None
            else:
                en = src.find(name)
                gf = src.gfile(en) if en is not None else None
            if gf is None:
                missing.append(spec)
                continue
            plan.append((folder, gf))
    dnp_cfg = m["dnp"]
    tracks = dnp_cfg.get("tracks", 0)
    if not tracks:
        need = 40
        for _, gf in plan:
            if gf.records is not None:
                need += 3 + sum(len(r) // 254 + 1 for r in gf.records if r)
            else:
                need += 2 + len(gf.data or b"") // 254
        tracks = min(255, max(2, (need * 5 // 4) // 256 + 1))
    dnp = DNP(tracks, dnp_cfg.get("name", "GeoUltra Apps"), dnp_cfg.get("id", "GU"))
    for folder, gf in plan:
        if folder:
            dnp.mkdir(folder)
        dnp.add(folder, gf)
    dnp.finish()
    out = os.path.join(base, dnp_cfg.get("out", "apps.dnp"))
    open(out, "wb").write(dnp.data)
    print("%s: %d files in %d folders, %d tracks, %d of %d blocks used"
          % (out, len(plan), len(dnp.dirs) - 1, tracks, dnp.blocks_used(), tracks * 256))
    for spec in missing:
        print("  not found: %s" % spec)
    if missing and dnp_cfg.get("strict"):
        die("files missing (strict: the system drive's build)")


if __name__ == "__main__":
    main(sys.argv)
