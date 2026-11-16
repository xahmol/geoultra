"""epsonstream.py - read an Epson FX-80/JX-80 byte stream as GeoUltra's
printer tests need it (tests/print/ep1.py): the dots it prints, per ink,
at (column in 1/240", row in 1/216"), and the commands seen. Only the
commands GU Epson FX-80 sends (src/drivers/epson.s): ESC @, ESC E,
ESC F, ESC J n, ESC r n, ESC * m nL nH data, CR, LF, FF, and text.
Anything else is reported, so a stray byte shows. Own code, 2026-11-16.
"""

STEP = {0: 4, 1: 2, 2: 2, 3: 1, 4: 3, 6: 3}     # ESC * m: 1/240" per column
PIN = 3                                         # the pins 1/72" = 3/216" apart


def parse(data):
    """The stream DATA (bytes) as a dict: dots {ink: set((x, y))} per page
    (a list of pages), text (the printed characters), unknown (bytes or
    commands not expected), emphasised (ESC E seen)."""
    pages, dots, text, unknown = [], {}, [], []
    x = y = 0
    ink = 0
    emph = False
    i = 0
    while i < len(data):
        b = data[i]
        if b == 0x1B and i + 1 < len(data):
            c = data[i + 1]
            if c == ord("@"):
                x = 0
                ink = 0
                emph = False
                i += 2
            elif c == ord("E"):
                emph = True
                i += 2
            elif c == ord("F"):
                emph = False
                i += 2
            elif c == ord("J"):
                y += data[i + 2]
                i += 3
            elif c == ord("r"):
                ink = data[i + 2]
                i += 3
            elif c == ord("*"):
                m, n = data[i + 2], data[i + 3] | data[i + 4] << 8
                cols = data[i + 5:i + 5 + n]
                for col in cols:
                    for pin in range(8):
                        if col & (0x80 >> pin):
                            dots.setdefault(ink, set()).add((x, y + pin * PIN))
                    x += STEP.get(m, 0)
                if m not in STEP:
                    unknown.append("ESC * %d" % m)
                i += 5 + n
            else:
                unknown.append("ESC %r" % chr(c))
                i += 2
        elif b == 0x0D:
            x = 0
            text.append("\r")
            i += 1
        elif b == 0x0A:
            y += 36
            x = 0
            text.append("\n")
            i += 1
        elif b == 0x0C:
            pages.append(dots)
            dots = {}
            x = y = 0
            text.append("\f")
            i += 1
        elif 0x20 <= b < 0x7F:
            text.append(chr(b))
            x += 24
            i += 1
        else:
            unknown.append("$%02X" % b)
            i += 1
    if dots:
        pages.append(dots)
    return {"pages": pages, "text": "".join(text), "unknown": unknown, "emphasised": emph}
