"""cbmarc.py - Commodore archive and container formats for geosdisk.py
(docs/manuals/TOOLS_MANUAL.md; the user's request of 2026-11-18, after geoBEAP's
list of formats): Lynx (read and write), G64 (GCR) images, and .gz / .zip
around anything. Each reader gives bytes (a disk image) or a list of
files (name, CBM type letter, data).

- Lynx (Will Corley's LYNX; LYNX XV, as geoBEAP writes it): a BASIC
  stub, then the directory as PETSCII text after the stub's end: the
  number of directory blocks, the signature, the number of files, and per
  file its name, its blocks, its type (P, S, U, R; R: a record length
  follows) and the bytes in its last block + 1, each ended by CR. The
  data starts at directory blocks * 254; each file takes its blocks * 254
  bytes, the last one only what it holds. GEOS files are inside as CVTs.
  Format: observed in LYNX XV archives (zimmers.net GEOS archive) and as
  geoBEAP II reads it (Bo Zimmerman, Apache 2.0, S_8gbLNX).
- G64: "GCR-1541", the half-track offset table, each track's GCR bytes;
  sectors found by their header ($08) and data ($07) blocks after a sync,
  5 GCR bits to 4 data bits (the 1541's code).
Own code (GeoUltra, 2026).
"""
import gzip
import io
import os
import zipfile

BLOCK = 254


def petscii_name(raw):
    """A file name from PETSCII as text (letters swapped as the C64 shows
    them in lower case mode: unshifted A-Z are lower case)."""
    out = []
    for b in raw:
        if 0x41 <= b <= 0x5A:
            out.append(chr(b + 0x20))
        elif 0xC1 <= b <= 0xDA:
            out.append(chr(b - 0x80))
        elif 0x20 <= b < 0x7F:
            out.append(chr(b))
        else:
            out.append("?")
    return "".join(out)


# --- containers ------------------------------------------------------------

def read_path(spec):
    """The bytes of a file, through .gz and .zip: "x.d64.gz", "x.zip:inner"
    (an inner name is matched without case); a .zip with one member needs
    no inner name."""
    inner = None
    if not os.path.exists(spec) and ":" in spec:
        spec, inner = spec.split(":", 1)
        if os.path.exists(inner) or not os.path.exists(spec):
            spec, inner = spec + ":" + inner, None
    data = open(spec, "rb").read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if data[:4] == b"PK\x03\x04":
        z = zipfile.ZipFile(io.BytesIO(data))
        names = [n for n in z.namelist() if not n.endswith("/")]
        if inner is None:
            if len(names) != 1:
                raise ValueError("%s holds %d files: name one, %s:NAME (%s)"
                                 % (spec, len(names), spec, ", ".join(names[:12])))
            inner = names[0]
        hit = [n for n in names if n.lower() == inner.lower() or n.lower().endswith("/" + inner.lower())]
        if not hit:
            raise ValueError("%s: no %s in it" % (spec, inner))
        data = z.read(hit[0])
        if data[:2] == b"\x1f\x8b":
            data = gzip.decompress(data)
    return data


def zip_members(spec):
    data = open(spec, "rb").read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    if data[:4] != b"PK\x03\x04":
        return None
    return [n for n in zipfile.ZipFile(io.BytesIO(data)).namelist() if not n.endswith("/")]


# --- Lynx -------------------------------------------------------------------

def is_lynx(data):
    return b"LYNX" in data[:BLOCK * 4].upper()


def lynx_read(data):
    """[(name, type letter, data)] of a Lynx archive."""
    stub_end = data.find(b"\x00\x00\x00", 2)
    if stub_end < 0:
        raise ValueError("not a Lynx archive: no end of its BASIC stub")
    p = stub_end + 3
    fields = []
    field = bytearray()
    while p < len(data) and len(fields) < 4 + 5 * 300:
        b = data[p]
        p += 1
        if b == 0x0D:
            fields.append(bytes(field))
            field = bytearray()
        elif b == 0:
            break
        else:
            field.append(b)
    fields = [f for f in fields]
    while fields and not fields[0].strip():
        fields.pop(0)
    head = fields[0].split()
    dirblocks = int(head[0])
    count = int(fields[1].strip())
    i = 2
    files = []
    for _ in range(count):
        name = fields[i].rstrip(b"\xa0 ")
        blocks = int(fields[i + 1].strip())
        kind = fields[i + 2].strip()[:1].decode("latin1").upper() or "P"
        i += 3
        if kind == "R":
            i += 1                                      # (the record length)
        last = int(fields[i].strip())
        i += 1
        files.append((name, kind, blocks, last))
    out = []
    pos = dirblocks * BLOCK
    for n, (name, kind, blocks, last) in enumerate(files):
        size = (blocks - 1) * BLOCK + last - 1 if blocks else 0
        if n == len(files) - 1:
            size = min(size, len(data) - pos)
        out.append((name, kind, data[pos:pos + size]))
        pos += blocks * BLOCK
    return out


STUB = (b"\x01\x08\x1e\x08\x0a\x00\x99\x22\x55\x53\x45\x20\x4c\x59\x4e\x58\x20\x54\x4f\x20"
        b"\x55\x4e\x50\x41\x43\x4b\x22\x00\x00\x00")   # 10 PRINT"USE LYNX TO UNPACK"


def lynx_write(files):
    """A LYNX XV compatible archive of [(name bytes, type letter, data)]."""
    def entries(dirblocks):
        t = b"\r %d  *LYNX XV  GEOSDISK\r %d \r" % (dirblocks, len(files))
        for name, kind, data in files:
            blocks = max(1, (len(data) + BLOCK - 1) // BLOCK)
            last = len(data) - (blocks - 1) * BLOCK + 1
            t += name[:16] + b"\r %d \r%s \r %d \r" % (blocks, kind.encode(), last)
        return t
    dirblocks = 1
    while len(STUB) + len(entries(dirblocks)) > dirblocks * BLOCK:
        dirblocks += 1
    head = (STUB + entries(dirblocks)).ljust(dirblocks * BLOCK, b"\0")
    body = bytearray()
    for k, (name, kind, data) in enumerate(files):
        blocks = max(1, (len(data) + BLOCK - 1) // BLOCK)
        body += data if k == len(files) - 1 else data.ljust(blocks * BLOCK, b"\0")
    return bytes(head + body)


# --- G64 ------------------------------------------------------------------------

GCR = {0x0A: 0, 0x0B: 1, 0x12: 2, 0x13: 3, 0x0E: 4, 0x0F: 5, 0x16: 6, 0x17: 7,
       0x09: 8, 0x19: 9, 0x1A: 10, 0x1B: 11, 0x0D: 12, 0x1D: 13, 0x1E: 14, 0x15: 15}


def is_g64(data):
    return data[:8] == b"GCR-1541"


def g64_to_d64(data):
    """A D64 (35 tracks) from a G64; sectors not found stay zero (the
    count of those is returned as well)."""
    tracks = data[9]
    spt = lambda t: 21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17
    d64 = bytearray(683 * 256)
    missing = 0
    for t in range(1, 36):
        ht = (t - 1) * 2
        if ht >= tracks:
            missing += spt(t)
            continue
        off = int.from_bytes(data[12 + 4 * ht:16 + 4 * ht], "little")
        if not off:
            missing += spt(t)
            continue
        n = data[off] | data[off + 1] << 8
        raw = data[off + 2:off + 2 + n]
        bits = "".join("{:08b}".format(b) for b in raw + raw[:40])   # (wraps round)
        found = {}
        i = 0
        while True:
            i = bits.find("1111111111", i)
            if i < 0:
                break
            while i < len(bits) and bits[i] == "1":
                i += 1
            dec = decode(bits, i, 8)
            if dec and dec[0] == 0x08:              # a header: sector, track
                s, tt = dec[2], dec[3]
                j = bits.find("1111111111", i + 80)
                if j < 0 or j > i + 80 + 400:
                    continue
                while j < len(bits) and bits[j] == "1":
                    j += 1
                blk = decode(bits, j, 260)
                if blk and blk[0] == 0x07 and tt == t and s < spt(t) and s not in found:
                    found[s] = bytes(blk[1:257])
                i = j
        start = sum(spt(x) for x in range(1, t))
        for s in range(spt(t)):
            if s in found:
                d64[(start + s) * 256:(start + s + 1) * 256] = found[s]
            else:
                missing += 1
    return bytes(d64), missing


def decode(bits, i, nbytes):
    out = []
    for k in range(nbytes * 2):
        q = bits[i + 5 * k:i + 5 * k + 5]
        if len(q) < 5 or int(q, 2) not in GCR:
            return None
        out.append(GCR[int(q, 2)])
    return [out[2 * k] << 4 | out[2 * k + 1] for k in range(nbytes)]
