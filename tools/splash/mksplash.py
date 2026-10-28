#!/usr/bin/env python3
"""Draw the GeoUltra boot splash (320 x 200 hires, C64).

Usage: mksplash.py BITMAP.bin COLORS.bin PREVIEW.png [STATUS]
       mksplash.py --boot BITMAP.bin COLORS.bin MESSAGES.bin MESSAGES.inc

--boot also writes the status line strips for the boot ROM (layout A):
for every message in MESSAGES, the bitmap of the status line cells
(2 rows of STATUS_CELLS cells, row by row), and MESSAGES.inc with their
position and numbers for src/boot/boot.s.

GeoUltra's own pixel art, after the user's design sketch (2026-10-28):
the "U" with a dithered shadow and a desktop window with pointer, a row
of folder, floppy and printer icons, "GeoUltra" in rounded bold letters,
the tagline, the version line and a status line. Colours: the desktop's
dark grey on light grey, with subtle accents per 8x8 cell (blue U,
pointer and title bar; coloured icons; red status line for errors).
Accents use the colours of the idreamtin8bits (idi8b) logo; the logo
itself (tools/splash/idi8b-logo.png, the user's own) sits at half size in
a black band at the bottom, each letter in its own cells and colour.

Outputs: the bitmap in C64 hires layout (8000 bytes, card by card), the
colour matrix (1000 bytes, high nibble = pixel colour, low nibble =
background) and a PNG preview in the C64 palette.
"""
import importlib.util
import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
W, H = 320, 200

# C64 colours
BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = range(8)
ORANGE, BROWN, LRED, DGREY, GREY, LGREEN, LBLUE, LGREY = range(8, 16)
PALETTE = [
    (0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x81, 0x33, 0x38), (0x75, 0xCE, 0xC8),
    (0x8E, 0x3C, 0x97), (0x56, 0xAC, 0x4D), (0x2E, 0x2C, 0x9B), (0xED, 0xF1, 0x71),
    (0x8E, 0x50, 0x29), (0x55, 0x38, 0x00), (0xC4, 0x6C, 0x71), (0x4A, 0x4A, 0x4A),
    (0x7B, 0x7B, 0x7B), (0xA9, 0xFF, 0x9F), (0x70, 0x6D, 0xEB), (0xB2, 0xB2, 0xB2),
]
BACKGROUND = LGREY
INK = DGREY
LAYOUT = os.environ.get("SPLASH_LAYOUT", "A")   # bottom: A logo left, B right, C centred

pix = [[0] * W for _ in range(H)]
ink = [[INK] * 40 for _ in range(25)]          # pixel colour per 8x8 cell
paper = [[BACKGROUND] * 40 for _ in range(25)]  # background colour per cell


def put(x, y, v=1):
    if 0 <= x < W and 0 <= y < H:
        pix[y][x] = v


def rect(x, y, w, h, v=1):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            put(xx, yy, v)


def frame(x, y, w, h):
    rect(x, y, w, 1)
    rect(x, y + h - 1, w, 1)
    rect(x, y, 1, h)
    rect(x + w - 1, y, 1, h)


def art(x, y, rows, scale=1):
    """Draw pixel art rows ('#' = set, '.' = clear, ' ' = leave)."""
    for r, line in enumerate(rows):
        for c, ch in enumerate(line):
            if ch in "#.":
                rect(x + c * scale, y + r * scale, scale, scale, 1 if ch == "#" else 0)


def colour(cx, cy, cw, ch, col, bg=None):
    for yy in range(cy, cy + ch):
        for xx in range(cx, cx + cw):
            ink[yy][xx] = col
            if bg is not None:
                paper[yy][xx] = bg


# --- The "U" with its dithered shadow (cells 11-17, rows 1-7) -----------

def u_shape(x, y, w=44, h=56, stem=14):
    """Set of pixels of a rounded U."""
    pts = set()
    for yy in range(h):
        for xx in range(w):
            inner_l, inner_r = stem, w - stem
            bottom = h - 14                       # start of the round bottom
            if yy < bottom:
                inside = xx < stem or xx >= w - stem
            else:
                # outer and inner ellipse for the round bottom
                cx, cy = (w - 1) / 2, bottom
                ox, oy = w / 2, h - bottom
                ix, iy = (w - 2 * stem) / 2, max(h - bottom - stem, 1)
                outer = ((xx - cx) / ox) ** 2 + ((yy - cy) / oy) ** 2 <= 1
                inner = ((xx - cx) / ix) ** 2 + ((yy - cy) / iy) ** 2 <= 1 \
                    if inner_l < xx < inner_r else False
                inside = outer and not inner
            if inside:
                pts.add((x + xx, y + yy))
    return pts


U_X, U_Y = 96, 8
solid = u_shape(U_X, U_Y)
shadow = u_shape(U_X - 6, U_Y + 4)
for (x, y) in shadow:
    if (x, y) not in solid and (x + y) % 2 == 0:
        put(x, y)
for (x, y) in solid:
    put(x, y)
# a one-pixel light rim keeps the shadow apart from the letter
for (x, y) in solid:
    for dx, dy in ((-1, 0), (0, 1), (-1, 1)):
        if (x + dx, y + dy) not in solid and (x + dx, y + dy) in shadow:
            put(x + dx, y + dy, 0)
colour(11, 1, 7, 8, LBLUE)

# --- Desktop window with scroll bar and pointer (cells 19-25) -----------

WX, WY, WW, WH = 152, 8, 64, 60                # cells 19-26, rows 1-8
frame(WX, WY, WW, WH)
rect(WX + 1, WY + 1, WW - 2, 6)                 # title bar
for xx in range(WX + 3, WX + WW - 3, 2):        # title bar lines (light)
    put(xx, WY + 3, 0)
rect(WX, WY + 7, WW, 1)
SB = WX + WW - 9                                # scroll bar
rect(SB, WY + 7, 1, WH - 7)
art(SB + 2, WY + 10, ["...#...", "..###..", ".#####."])
rect(SB + 4, WY + 15, 1, WH - 26)
rect(SB + 2, WY + 22, 5, 12)
art(SB + 2, WY + WH - 7, [".#####.", "..###..", "...#..."])
colour(19, 1, 8, 1, PURPLE)                     # title bar row

POINTER = [
    "##..........",
    "#.#.........",
    "#..#........",
    "#...#.......",
    "#....#......",
    "#.....#.....",
    "#......#....",
    "#.......#...",
    "#........#..",
    "#.....#####.",
    "#..#..#.....",
    "#.#.#..#....",
    "##..#..#....",
    "#....#..#...",
    ".....#..#...",
    "......##....",
]
art(168, 24, POINTER, scale=2)                  # inside the window's interior
colour(21, 3, 3, 4, PURPLE)                     # pointer cells (no frame in them)

# --- Icons: folder, floppy, printer (cells 13-26, rows 9-11) ------------

FOLDER = [
    "..####..........",
    ".######.........",
    "################",
    "##..............",
    "##.#############",
    "##.#############",
    "###############.",
    "###############.",
    "##############..",
    "##############..",
    "#############...",
    "#############...",
]
FLOPPY = [
    "##############..",
    "##..######..###.",
    "##..######..####",
    "##..######..####",
    "##..........####",
    "################",
    "################",
    "###..........###",
    "###.########.###",
    "###..........###",
    "###.########.###",
    "################",
]
PRINTER = [
    "....########....",
    "....#......#....",
    "....#.####.#....",
    "..############..",
    ".##############.",
    "#############.##",
    "################",
    "################",
    "####........####",
    "....#......#....",
    "....#.####.#....",
    "....########....",
]
ICON_Y = 80                                     # rows 10-12
art(96, ICON_Y, FOLDER, scale=2)
art(144, ICON_Y, FLOPPY, scale=2)
art(192, ICON_Y, PRINTER, scale=2)
colour(12, 10, 4, 3, LRED)
colour(18, 10, 4, 3, LBLUE)
colour(24, 10, 4, 3, PURPLE)

# --- "GeoUltra" in rounded bold letters, 2x2 pixels ---------------------

LETTERS = {
    "G": ["..#####..", ".#######.", "##.....##", "##.......", "##.......", "##..#####",
          "##..#####", "##.....##", "##.....##", "##.....##", ".#######.", "..#####.."],
    "e": ["", "", "", "", "..####..", ".######.", "##....##", "########", "########",
          "##......", ".#######", "..######"],
    "o": ["", "", "", "", "..####..", ".######.", "##....##", "##....##", "##....##",
          "##....##", ".######.", "..####.."],
    "U": ["##.....##"] * 9 + ["##.....##", ".#######.", "..#####.."],
    "l": ["##"] * 11 + [".##"],
    "t": ["", ".##...", ".##...", ".##...", "######", "######", ".##...", ".##...",
          ".##...", ".##...", ".##.##", "..###."],
    "r": ["", "", "", "", "##.###.", "#######", "###..##", "##.....", "##.....",
          "##.....", "##.....", "##....."],
    "a": ["", "", "", "", "..#####.", ".######.", ".....##.", ".######.", "#######.",
          "##...##.", "########", ".####.##"],
}
WORD = "GeoUltra"
widths = [max(len(r) for r in LETTERS[c]) for c in WORD]
total = sum(widths) * 2 + 4 * (len(WORD) - 1)
x = (W - total) // 2
for c, w in zip(WORD, widths):
    art(x, 116 if LAYOUT in "AB" else 108, LETTERS[c], scale=2)
    x += w * 2 + 4

# --- Small text in GeoUltra's own system font ---------------------------


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


font = load(os.path.join(ROOT, "tools", "fonts", "system9.py"), "system9")


def text_width(s):
    return sum(font.WIDTHS[ord(c) - 32] for c in s)


def text(s, x, baseline, bold=False):
    top = baseline - font.BASELINE
    for c in s:
        w = font.WIDTHS[ord(c) - 32]
        for row, line in font.GLYPHS[c].items():
            for col, ch in enumerate(line):
                if ch == "#":
                    put(x + 1 + col, top + row)
                    if bold:
                        put(x + 2 + col, top + row)
        x += w + (1 if bold else 0)


def centred(s, baseline, bold=False):
    width = text_width(s) + (len(s) if bold else 0)
    text(s, (W - width) // 2, baseline, bold)


centred("Graphical desktop for the Ultimate", 158 if LAYOUT in "AB" else 146, bold=True)

# --- idi8b logo, version and status line --------------------------------

LOGO_COLOURS = {(178, 236, 145): LGREEN, (132, 197, 204): CYAN, (134, 122, 222): LBLUE,
                (192, 129, 120): LRED, (147, 81, 182): PURPLE}


def logo():
    """The idi8b logo redrawn compactly: every bar of the original becomes
    a 1-pixel bar with a 1-pixel gap, every 4-pixel row of it one pixel
    (the original's proportions). Returns [(colour, width, {(x, y)})] per
    letter, x relative to the letter."""
    from PIL import Image
    im = Image.open(os.path.join(ROOT, "tools", "splash", "idi8b-logo.png")).convert("RGBA")
    px = im.load()

    def col(x, y):
        r, g, b, a = px[x, y]
        return LOGO_COLOURS.get((r, g, b)) if a > 100 else None
    w, h = im.size
    runs = []                                   # bars: [x0, x1, colour]
    for x in range(w):
        c = next((col(x, y) for y in range(h) if col(x, y) is not None), None)
        if c is None:
            continue
        if runs and runs[-1][1] == x - 1 and runs[-1][2] == c:
            runs[-1][1] = x
        else:
            runs.append([x, x, c])
    bars = []                                   # a double-width run is two bars
    for x0, x1, c in runs:
        if x1 - x0 + 1 >= 12:
            mid = (x0 + x1) // 2
            bars += [[x0, mid, c], [mid + 1, x1, c]]
        else:
            bars.append([x0, x1, c])
    ys = [y for y in range(h) if any(col(x, y) is not None for x in range(w))]
    top, units = min(ys), (max(ys) - min(ys) + 1) // 4
    letters = []
    for x0, x1, c in bars:
        if not letters or letters[-1][0] != c:
            letters.append([c, 0, set()])
        letter = letters[-1]
        for u in range(units):
            y = top + u * 4 + 2
            if any(col(x, y) is not None for x in range(x0, x1 + 1)):
                letter[2].add((letter[1], u))
        letter[1] += 2
    return [(c, wd - 1, pts) for c, wd, pts in letters], units


def draw_logo(cell_x, y):
    """Logo from cell column cell_x, top line y; each letter in its own
    cells (colour per cell). Returns the first cell column after it."""
    letters, units = logo()
    row0, rows = y // 8, (y + units - 1) // 8 - y // 8 + 1
    for c, width, pts in letters:
        cells = (width + 7) // 8
        x = cell_x * 8 + (cells * 8 - width) // 2
        for px_, py in pts:
            put(x + px_, y + py)
        colour(cell_x, row0, cells, rows, c, BLACK)
        cell_x += cells
    return cell_x


VERSION = "v0.1   (C) 2026 Xander Mol"
# Boot status messages: (symbol, text), strip number = index; the boot
# ROM colours error messages light red.
MESSAGES = [
    ("MSG_COPYING", "Copying the system to the REU ..."),
    ("MSG_STARTING", "Starting GeoUltra ..."),
    ("MSG_NO_REU", "No REU found: enable the REU (16 MB)"),
]
STATUS = sys.argv[4] if len(sys.argv) > 4 and not sys.argv[1].startswith("--") \
    else MESSAGES[0][1]
BAND_ROW = 22                                   # cell rows 22-24
if LAYOUT in "AB":
    colour(0, BAND_ROW, 40, 3, LGREY, BLACK)
    if LAYOUT == "A":                           # logo left, text right
        end = draw_logo(1, BAND_ROW * 8 + 2)
        tx = (end + 1) * 8
    else:                                       # text left, logo right
        draw_logo(31, BAND_ROW * 8 + 2)
        tx = 8
    text(VERSION, tx, BAND_ROW * 8 + 7)          # in cell row 22 only
    text(STATUS, tx, BAND_ROW * 8 + 20)         # in cell rows 23-24 only
    STATUS_CELLS = (tx // 8, 24)
else:                                           # C: small logo above centred lines
    draw_logo(16, 19 * 8 + 2)
    centred(VERSION, 186)
    centred(STATUS, 197)
    STATUS_CELLS = (0, 24)
if "--error" in sys.argv:
    cx, cy = STATUS_CELLS
    for xx in range(cx, 40):
        ink[cy][xx] = LRED

# --- Output ------------------------------------------------------------


def c64_bitmap():
    out = bytearray()
    for cy in range(25):
        for cx in range(40):
            for line in range(8):
                byte = 0
                for bit in range(8):
                    byte = byte << 1 | pix[cy * 8 + line][cx * 8 + bit]
                out.append(byte)
    return bytes(out)


def c64_colours():
    return bytes((ink[cy][cx] << 4) | paper[cy][cx] for cy in range(25) for cx in range(40))


def png(path, scale=3):
    rows = []
    for y in range(H):
        line = bytearray([0])
        for x in range(W):
            col = PALETTE[ink[y // 8][x // 8] if pix[y][x] else paper[y // 8][x // 8]]
            line += bytes(col) * scale
        rows += [bytes(line)] * scale

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W * scale, H * scale, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(b"".join(rows), 9)))
        f.write(chunk(b"IEND", b""))


def status_strips():
    """Bitmap bytes of the status line cells for every message."""
    col0, rows = STATUS_CELLS[0], (BAND_ROW + 1, BAND_ROW + 2)
    out = bytearray()
    for _, msg in MESSAGES:
        for y in range(rows[0] * 8, (rows[1] + 1) * 8):
            for x in range(col0 * 8, W):
                pix[y][x] = 0
        text(msg, col0 * 8, BAND_ROW * 8 + 20)
        for cy in rows:
            for cx in range(col0, 40):
                for line in range(8):
                    byte = 0
                    for bit in range(8):
                        byte = byte << 1 | pix[cy * 8 + line][cx * 8 + bit]
                    out.append(byte)
    return bytes(out)


def main(argv):
    if argv[1:2] == ["--boot"]:
        if LAYOUT != "A":
            sys.exit("--boot needs layout A")
        open(argv[2], "wb").write(c64_bitmap())
        open(argv[3], "wb").write(c64_colours())
        open(argv[4], "wb").write(status_strips())
        col0 = STATUS_CELLS[0]
        inc = ["; Generated by tools/splash/mksplash.py --boot",
               "STATUS_COL   = %d" % col0,
               "STATUS_ROW   = %d" % (BAND_ROW + 1),
               "STATUS_CELLS = %d" % (40 - col0),
               "STATUS_SIZE  = %d" % ((40 - col0) * 16),
               "STATUS_ERROR_COLOURS = $%02X" % (LRED << 4 | BLACK),
               "BORDER_COLOUR = %d" % BACKGROUND,
               "MSG_COUNT    = %d" % len(MESSAGES)]
        for i, (name, msg) in enumerate(MESSAGES):
            inc.append("%-12s = %d    ; %s" % (name, i, msg))
        open(argv[5], "w").write("\n".join(inc) + "\n")
        return
    if len(argv) < 4:
        sys.exit(__doc__)
    open(argv[1], "wb").write(c64_bitmap())
    open(argv[2], "wb").write(c64_colours())
    png(argv[3])


if __name__ == "__main__":
    main(sys.argv)
