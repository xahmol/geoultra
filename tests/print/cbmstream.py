"""cbmstream.py - read a Commodore MPS-801/803 byte stream as GeoUltra's
printer tests need it (tests/print/mp1.py): the bit image dots it prints
at (column in 1/240", row in 1/216"), and the text. Only the codes GU
Commodore MPS sends (src/printer/mps.s): CHR$(8) bit image, CHR$(26) n b
(b n times, 0 = 256), CR (with LF: 7/72" in bit image, else 1/6"),
CHR$(15) bit image off, CHR$(31)/CHR$(159) NLQ on/off, FF, and text.
Anything else is reported. Own code, 2026-11-16.
"""

COL = 4                                         # 60 dpi: 4/240" a column
PIN = 3                                         # 1/72" = 3/216"


def parse(data):
    """The stream DATA (bytes) as a dict: pages (a list of sets of
    (x, y) dots), text (bytes printed as characters, CR as "\\r", FF as
    "\\f"), unknown, nlq (on at the end)."""
    pages, dots, text, unknown = [], set(), bytearray(), []
    mark = 0                            # text since the last page

    x = y = 0
    bim = nlq = False

    def column(b):
        nonlocal x
        for pin in range(7):
            if b & (1 << pin):
                dots.add((x, y + pin * PIN))
        x += COL
    i = 0
    while i < len(data):
        b = data[i]
        if bim and b & 0x80:                    # (as the firmware: a column,
            column(b)                           # whatever else the byte is)
        elif b == 0x08:
            bim = True
        elif b == 0x0F:
            bim = False
        elif b == 0x1F:
            nlq = True
        elif b == 0x9F:
            nlq = False
        elif b == 0x1A and bim:
            n = data[i + 1] or 256
            for _ in range(n):
                column(data[i + 2])
            i += 2
        elif b == 0x0D:
            y += 21 if bim else 36
            x = 0
            text += b"\r"
        elif b == 0x0C:                 # (an empty page: nothing, as the
            if dots or any(c not in b"\r\f" for c in text[mark:]):   # firmware)
                pages.append(dots)
                text += b"\f"
            mark = len(text)
            dots = set()
            x = y = 0
        elif b >= 0x20:
            bim = False
            text.append(b)
        else:
            unknown.append("$%02X" % b)
        i += 1
    if dots:
        pages.append(dots)
    return {"pages": pages, "text": bytes(text), "unknown": unknown, "nlq": nlq}
