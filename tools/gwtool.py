#!/usr/bin/env python3
"""gwtool.py - geoWrite documents on a PC: list, convert to 2.x, merge.

    gwtool.py list IMAGE
    gwtool.py convert IMAGE OUT [NAME ...] [--fonts]
    gwtool.py merge IMAGE OUT NEWNAME NAME [NAME ...] [--fonts] [--start=N]

IMAGE is a D64, D71, D81 or DNP (a name may carry a DNP folder,
"Writing/Letter"). OUT is a folder (CVT files written there) or a new
.d64 / .d81 image (made with VICE's c1541, which must be on the PATH or
in ~/.local/opt/vice-3.10/bin). `convert` turns geoWrite 1.x documents
(all of them without NAMEs) into geoWrite 2.x documents and copies 2.x
ones as they are; `merge` joins the documents NAME... in that order into
one 2.x document NEWNAME: their pages one after another (each starts on
a new page), their pictures renumbered. --fonts adds the font files the
documents use (by font ID) from IMAGE; --start=N sets the merged
document's first page number (geoWrite's header, 1 by default).

What a conversion does (geoWrite 1.x "Write Image V1.x" to 2.x, as
geoWrite 2.1 itself converts a document when it opens one; observed by
comparing a document before and after geoWrite 2.1 converted it, in
VICE, 2026-11-18):
- each page record starts with a ruler of 20 bytes without an escape
  code (left margin, right margin, 8 tab stops); 2.x pages start with a
  27-byte ruler escape ($11, those 20 bytes, the paragraph margin = the
  left margin, $10 for spacing and alignment as geoWrite 2.1 writes it,
  3 reserved zeros); the rest of the page is kept byte for byte;
- the header's class becomes "Write Image V2.0" and its geoWrite 2.x
  fields ($89-$91, 0 in 1.x) are set: first page 1, no title page, no
  header or footer, page height 752 dots (the default without a
  printer: geoWrite repaginates for the printer it prints with).
The 2.x format is Michael Steil's description ("Inside geoWrite - 7:
File Format and Pagination", pagetable.com): records 0-60 pages, 61
header, 62 footer, 64-126 pictures (graphics escape $10, its record in
byte 4); ruler escape $11 (27 bytes), NewCardSet $17 (4 bytes). Rulers
inside the text and pictures of 1.x documents: assumed to be laid out
as their 2.x counterparts without the 7 added ruler bytes (none in the
documents this was made with; reported when met).

Restrictions: geoWrite repaginates on opening when the page height
differs; each merged document starts a new page; 61 pages and 63
pictures at most. Own code (GeoUltra, 2026), the image reading from
tools/mkappsdnp.py.
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkappsdnp import Image, GeoFile, read_cvt   # noqa: E402

BLOCK = 254
ESC_GRAPHICS, ESC_RULER, ESC_NEWCARDSET = 0x10, 0x11, 0x17
V1_RULER, V2_RULER = 20, 27
PAGES, HEADER_REC, FOOTER_REC, PIC_FIRST, PIC_LAST = 61, 61, 62, 64, 126
PAGE_HEIGHT = 752
CLASS_AT, VERSION_AT = 0x4D, 0x4D + 12         # "Write Image " and "V1.0"
FONT = 8                                        # GEOS file type
C1541 = shutil.which("c1541") or os.path.expanduser("~/.local/opt/vice-3.10/bin/c1541")


def die(msg):
    sys.exit("gwtool.py: " + msg)


def version(gf):
    """'1.0', '2.1' ... for a geoWrite document, else None."""
    if not gf.header or gf.records is None:
        return None
    cls = gf.header[CLASS_AT:CLASS_AT + 16].decode("latin1", "replace")
    if not cls.startswith("Write Image V"):
        return None
    return cls[13:16]


def documents(img):
    """(name, GeoFile) of every geoWrite document, folders included."""
    out = []

    def walk(start, prefix):
        for en in img.entries(start):
            name = en[3:19].split(b"\xa0")[0].decode("latin1")
            if en[0] & 0x07 == 6 and img.kind == "dnp":
                walk(tuple(img.block(en[1], en[2])[0:2]), prefix + name + "/")
                continue
            if en[0x15] == 1 and en[0x16]:
                gf = img.gfile(en)
                if version(gf):
                    out.append((prefix + name, gf))
    walk(None, "")
    return out


def pages(gf):
    return [r for r in gf.records[:PAGES] if r not in (None, "end")]


def ruler_v2(r20):
    """A 1.x page's 20-byte ruler as a 2.x ruler escape."""
    return bytes([ESC_RULER]) + r20 + r20[0:2] + bytes([0x10, 0, 0, 0])


def scan(text, v1, warn, where):
    """Rulers in the text of a 1.x page widened; graphics escapes' records
    listed. Returns (new text, [offsets of graphics record bytes])."""
    out = bytearray()
    pics = []
    i = 0
    while i < len(text):
        b = text[i]
        if b == ESC_NEWCARDSET:
            out += text[i:i + 4]
            i += 4
        elif b == ESC_RULER:
            if v1:
                warn("%s: a ruler inside a 1.x page (widened as at a page's start)" % where)
                out += ruler_v2(text[i + 1:i + 1 + V1_RULER])
                i += 1 + V1_RULER
            else:
                out += text[i:i + V2_RULER]
                i += V2_RULER
        elif b == ESC_GRAPHICS:
            if v1:
                warn("%s: a picture in a 1.x page (its escape taken as 2.x's)" % where)
            pics.append(len(out) + 4)
            out += text[i:i + 5]
            i += 5
        else:
            out.append(b)
            i += 1
    return bytes(out), pics


def to_v2(name, gf, warn):
    """A GeoFile of the document as geoWrite 2.x: [page texts], header and
    footer records, {old picture record: data}, its header block."""
    v1 = version(gf).startswith("1")
    recs = gf.records
    pg, pic_refs = [], []
    for k, rec in enumerate(pages(gf)):
        if v1:
            head = ruler_v2(rec[:V1_RULER])
            body = rec[V1_RULER:]
        else:
            head, body = rec[:V2_RULER], rec[V2_RULER:]
        body, pics = scan(body, v1, warn, "%s page %d" % (name, k + 1))
        page = head + body
        pg.append(page)
        pic_refs.append([p + len(head) for p in pics])
    hf = [recs[r] if r < len(recs) and recs[r] not in (None, "end") else None
          for r in (HEADER_REC, FOOTER_REC)]
    pics = {r: recs[r] for r in range(PIC_FIRST, min(len(recs), PIC_LAST + 1))
            if recs[r] not in (None, "end")}
    header = bytearray(gf.header)
    if v1:
        header[VERSION_AT:VERSION_AT + 4] = b"V2.0"
        header[0x89:0x92] = bytes([1, 0, 0, 0, 0, 0, 0]) + PAGE_HEIGHT.to_bytes(2, "little")
    return pg, pic_refs, hf, pics, bytes(header)


def build(name, parts, warn):
    """One 2.x document from parts (to_v2 results, in order): its GeoFile."""
    records = [None] * (PIC_LAST + 1)
    page_no, pic_no = 0, PIC_FIRST
    for pg, refs, hf, pics, _ in parts:
        renum = {}
        for old in sorted(pics):
            if pic_no > PIC_LAST:
                die("more than %d pictures" % (PIC_LAST - PIC_FIRST + 1))
            renum[old] = pic_no
            records[pic_no] = pics[old]
            pic_no += 1
        for page, offs in zip(pg, refs):
            if page_no >= PAGES:
                die("more than %d pages" % PAGES)
            page = bytearray(page)
            for o in offs:
                if page[o] in renum:
                    page[o] = renum[page[o]]
                else:
                    warn("%s: a picture record %d not in the document" % (name, page[o]))
            records[page_no] = bytes(page)
            page_no += 1
    first = parts[0]
    for r, data in zip((HEADER_REC, FOOTER_REC), first[2]):
        records[r] = data
    while records and records[-1] is None:
        records.pop()
    header = bytearray(first[4])
    entry = bytearray(30)
    entry[0] = 0x83                                     # USR, closed
    entry[3:19] = name.encode("latin1")[:16].ljust(16, b"\xa0")
    entry[0x15] = 1                                     # VLIR
    entry[0x16] = header[0x45] if len(header) > 0x45 else 7
    return GeoFile(bytes(entry), bytes(header), None, records)


def write_cvt(gf, path):
    """A CVT (the layout c1541 -geoswrite reads, as tools/vlircvt.py)."""
    sig = bytearray(gf.entry[:30]) + b"PRG formatted GEOS file V1.0"
    sig += bytes(BLOCK - len(sig))
    header = gf.header[2:2 + BLOCK].ljust(BLOCK, b"\0")
    out = bytearray(sig) + header
    if gf.records is None:
        out += gf.data
    else:
        table = bytearray()
        body = bytearray()
        for rec in gf.records:
            if rec is None or rec == "end":
                table += b"\x00\xff"
                continue
            n = max(1, (len(rec) + BLOCK - 1) // BLOCK)
            last = len(rec) - (n - 1) * BLOCK + 1
            table += bytes([n, last])
            body += rec + bytes(n * BLOCK - len(rec))
        out += table.ljust(BLOCK, b"\0") + body
    blocks = (len(out) - BLOCK) // BLOCK
    out[0x1C:0x1E] = blocks.to_bytes(2, "little")
    open(path, "wb").write(out)


def fonts_of(parts):
    ids = set()
    for pg, *_ in parts:
        for page in pg:
            i = 0
            while i < len(page):
                if page[i] == ESC_NEWCARDSET and i + 3 < len(page):
                    ids.add((page[i + 1] | page[i + 2] << 8) >> 6)
                    i += 4
                elif page[i] == ESC_RULER:
                    i += V2_RULER
                elif page[i] == ESC_GRAPHICS:
                    i += 5
                else:
                    i += 1
    return ids - {0}


def font_files(img, ids):
    """The font files (GEOS type FONT) whose ID is in ids."""
    out = []
    for en in img.entries():
        if en[0x16] != FONT or not en[0x13]:
            continue
        gf = img.gfile(en)
        fid = gf.header[0x80] | gf.header[0x81] << 8     # (the header's font ID)
        if fid in ids:
            out.append(gf)
    return out


def output(files, out):
    """files (GeoFiles) to a folder of CVTs, or into a new D64/D81."""
    ext = os.path.splitext(out)[1].lower()
    if ext in (".d64", ".d81"):
        tmp = tempfile.mkdtemp()
        cmd = [C1541, "-format", "converted,gw", ext[1:], out]
        for gf in files:
            p = os.path.join(tmp, gf.name.replace("/", "_") + ".cvt")
            write_cvt(gf, p)
            cmd += ["-geoswrite", p]
        r = subprocess.run(cmd, capture_output=True, text=True)
        shutil.rmtree(tmp)
        if r.returncode or not os.path.exists(out):
            die("c1541: %s" % (r.stderr or r.stdout).strip()[-300:])
        print("%s: %d files" % (out, len(files)))
    else:
        os.makedirs(out, exist_ok=True)
        for gf in files:
            p = os.path.join(out, gf.name.replace("/", "_") + ".cvt")
            write_cvt(gf, p)
            print(p)


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    with_fonts = "--fonts" in argv
    start = next((int(a[8:]) for a in argv if a.startswith("--start=")), None)
    if not args:
        sys.exit(__doc__.strip().split("\n\n")[1])
    warnings = []
    warn = warnings.append
    cmd = args[0]
    if cmd == "list" and len(args) == 2:
        for name, gf in documents(Image(args[1])):
            pics = sum(1 for r in gf.records[PIC_FIRST:] if r not in (None, "end"))
            print("%-24s V%s  %2d page(s)%s" % (name, version(gf), len(pages(gf)),
                  ", %d picture(s)" % pics if pics else ""))
        return
    if cmd not in ("convert", "merge") or len(args) < 3 + (cmd == "merge") * 2:
        sys.exit(__doc__.strip().split("\n\n")[1])
    img = Image(args[1])
    docs = dict(documents(img))
    names = args[3:] if cmd == "convert" else args[4:]
    if cmd == "convert" and not names:
        names = list(docs)
    for n in names:
        if n not in docs:
            die("%s: no geoWrite document of that name in %s" % (n, args[1]))
    parts = [to_v2(n, docs[n], warn) for n in names]
    if cmd == "convert":
        files = [build(n.split("/")[-1], [p], warn) for n, p in zip(names, parts)]
    else:
        files = [build(args[3], parts, warn)]
        if start is not None:
            h = bytearray(files[0].header)
            h[0x89:0x8B] = start.to_bytes(2, "little")
            files[0].header = bytes(h)
        print("%s: %d pages from %d documents" % (args[3], sum(len(p[0]) for p in parts), len(parts)))
    if with_fonts:
        files += font_files(img, fonts_of(parts))
    output(files, args[2])
    for w in warnings:
        print("warning: " + w)


if __name__ == "__main__":
    main(sys.argv)
