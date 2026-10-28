# Conformance cases for the graphics primitives (tools/harness/harness.py).

CHECKER = [0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55]
STRIPES = [0xFF, 0x00, 0x81, 0x42, 0x24, 0x18, 0x00, 0xF0]
SCREENS = ["fore", "back"]

CASES = [
    dict(name="GetScanLine y=0", routine="GetScanLine", x=0, compare=["r5", "r6", "X"]),
    dict(name="GetScanLine y=77", routine="GetScanLine", x=77, compare=["r5", "r6", "X"]),
    dict(name="GetScanLine y=199 fore only", routine="GetScanLine", x=199, disp=0x80,
         compare=["r5", "r6"]),
    dict(name="GetScanLine y=100 back only", routine="GetScanLine", x=100, disp=0x40,
         compare=["r5", "r6"]),
    dict(name="HorizontalLine in one card", routine="HorizontalLine", a=0xFF,
         r={"r3": 9, "r4": 14, "r11L": 20}, compare=SCREENS + ["r11L"]),
    dict(name="HorizontalLine across cards", routine="HorizontalLine", a=0xA5,
         r={"r3": 3, "r4": 300, "r11L": 101}, compare=SCREENS + ["r11L"]),
    dict(name="HorizontalLine full width", routine="HorizontalLine", a=0xFF,
         r={"r3": 0, "r4": 319, "r11L": 199}, compare=SCREENS),
    dict(name="HorizontalLine x above 255", routine="HorizontalLine", a=0x0F,
         r={"r3": 250, "r4": 270, "r11L": 7}, compare=SCREENS),
    dict(name="VerticalLine solid", routine="VerticalLine", a=0xFF,
         r={"r3L": 10, "r3H": 60, "r4": 33}, compare=SCREENS),
    dict(name="VerticalLine pattern", routine="VerticalLine", a=0xA6,
         r={"r3L": 3, "r3H": 40, "r4": 290}, compare=SCREENS),
    dict(name="Rectangle checker", routine="Rectangle", pattern=CHECKER,
         r={"r2L": 5, "r2H": 50, "r3": 7, "r4": 140}, compare=SCREENS),
    dict(name="Rectangle stripes odd edges", routine="Rectangle", pattern=STRIPES,
         r={"r2L": 61, "r2H": 133, "r3": 77, "r4": 263}, compare=SCREENS),
    dict(name="Rectangle fore only", routine="Rectangle", pattern=CHECKER, disp=0x80,
         r={"r2L": 0, "r2H": 10, "r3": 0, "r4": 319}, compare=SCREENS),
    dict(name="FrameRectangle", routine="FrameRectangle", a=0xFF,
         r={"r2L": 20, "r2H": 90, "r3": 13, "r4": 222}, compare=SCREENS),
    dict(name="FrameRectangle pattern", routine="FrameRectangle", a=0xCC,
         r={"r2L": 100, "r2H": 180, "r3": 160, "r4": 311}, compare=SCREENS),
]

RECT = {"r2L": 13, "r2H": 70, "r3": 21, "r4": 290}
CASES += [
    dict(name="InvertLine both buffers", routine="InvertLine", fillfore=0x0F, fillback=0x33,
         r={"r3": 5, "r4": 170, "r11L": 33}, compare=SCREENS),
    dict(name="InvertLine foreground only", routine="InvertLine", disp=0x80, fillfore=0x0F,
         fillback=0x33, r={"r3": 5, "r4": 170, "r11L": 33}, compare=SCREENS),
    dict(name="InvertLine background only", routine="InvertLine", disp=0x40, fillfore=0x0F,
         fillback=0x33, r={"r3": 5, "r4": 170, "r11L": 33}, compare=SCREENS),
    dict(name="RecoverLine", routine="RecoverLine", disp=0x00, fillfore=0x0F, fillback=0x33,
         r={"r3": 9, "r4": 300, "r11L": 120}, compare=SCREENS),
    dict(name="InvertRectangle", routine="InvertRectangle", fillfore=0x5A, fillback=0x81,
         r=RECT, compare=SCREENS),
    dict(name="InvertRectangle foreground only", routine="InvertRectangle", disp=0x80,
         fillfore=0x5A, fillback=0x81, r=RECT, compare=SCREENS),
    dict(name="RecoverRectangle", routine="RecoverRectangle", disp=0x00, fillfore=0x5A,
         fillback=0x81, r=RECT, compare=SCREENS + ["r2", "r3", "r4"]),
    dict(name="ImprintRectangle", routine="ImprintRectangle", fillfore=0x5A, fillback=0x81,
         r=RECT, compare=SCREENS),
    dict(name="i_Rectangle", routine="i_Rectangle", pattern=STRIPES,
         inline=[40, 90, 17, 0, 0x2C, 0x01], compare=SCREENS + ["r2", "r3", "r4"]),
    dict(name="i_FrameRectangle", routine="i_FrameRectangle",
         inline=[40, 90, 17, 0, 0x2C, 0x01, 0xF0], compare=SCREENS),
    dict(name="i_RecoverRectangle", routine="i_RecoverRectangle", disp=0x00, fillfore=0x5A,
         fillback=0x81, inline=[3, 9, 250, 0, 0x08, 0x01], compare=SCREENS),
    dict(name="i_ImprintRectangle", routine="i_ImprintRectangle", fillfore=0x5A,
         fillback=0x81, inline=[3, 9, 250, 0, 0x08, 0x01], compare=SCREENS),
]

# With different foreground and background contents (GEOS 2.0 takes the
# background as the source and writes both).
CASES += [
    dict(name="HorizontalLine, different buffers", routine="HorizontalLine", a=0x3C,
         fillfore=0x0F, fillback=0xA5, r={"r3": 13, "r4": 190, "r11L": 40}, compare=SCREENS),
    dict(name="Rectangle, different buffers", routine="Rectangle", pattern=STRIPES,
         fillfore=0x0F, fillback=0xA5, r={"r2L": 3, "r2H": 20, "r3": 5, "r4": 60},
         compare=SCREENS),
    dict(name="VerticalLine, different buffers", routine="VerticalLine", a=0xA6,
         fillfore=0x0F, fillback=0xA5, r={"r3L": 3, "r3H": 40, "r4": 21}, compare=SCREENS),
    dict(name="FrameRectangle, different buffers", routine="FrameRectangle", a=0xFF,
         fillfore=0x0F, fillback=0xA5, r={"r2L": 20, "r2H": 90, "r3": 13, "r4": 222},
         compare=SCREENS),
]

# BitmapClip / BitOtherClip: a 6 x 10 card bitmap, a 3 x 6 window with
# 1 card left, 2 right and 2 lines above it.
CLIP_DATA = 0x4000
CLIP_BUF = 0x4D00
CLIP_IN = 0x4C00
CLIP_SYNC = 0x4C20


def clip_stream(big):
    """Packets for 60 bytes: unique, repeat and (optionally) bigcount."""
    out, n, k = [], 0, 0
    while n < 60:
        k += 1
        left = 60 - n
        if big and k == 3 and left >= 8:            # a 3-byte packet x 4
            out += [220 + 3, 4, 0x82, 0x18, 0x7E]
            n += 8
        elif k % 2:
            c = min(5, left)
            out += [128 + c] + [(n + i) * 37 & 0xFF for i in range(c)]
            n += c
        else:
            c = min(7, left)
            out += [c, (k * 53) & 0xFF]
            n += c
    return out


CLIP_R = {"r1L": 5, "r1H": 40, "r2L": 3, "r2H": 6, "r11L": 1, "r11H": 2, "r12": 2}
# APPINPUT: next byte from ($70) to (r0); SYNC: r0 = the buffer
CLIP_IN_CODE = [0xA0, 0x00, 0xB1, 0x70, 0x91, 0x02, 0xE6, 0x70, 0xD0, 0x02, 0xE6, 0x71, 0x60]
CLIP_SYNC_CODE = [0xA9, CLIP_BUF & 0xFF, 0x85, 0x02, 0xA9, CLIP_BUF >> 8, 0x85, 0x03, 0x60]

CASES += [
    dict(name="BitmapClip window with bigcount", routine="BitmapClip",
         r=dict(CLIP_R, r0=CLIP_DATA), mem={CLIP_DATA: clip_stream(True)},
         compare=["fore", "back"]),
    dict(name="BitmapClip without clipping", routine="BitmapClip",
         r=dict(CLIP_R, r0=CLIP_DATA, r2L=6, r2H=10, r11L=0, r11H=0, r12=0),
         mem={CLIP_DATA: clip_stream(False)}, compare=["fore", "back"]),
    dict(name="BitOtherClip from an input routine", routine="BitOtherClip",
         r=dict(CLIP_R, r0=CLIP_BUF, r13=CLIP_IN, r14=CLIP_SYNC),
         poke={0x70: [CLIP_DATA & 0xFF, CLIP_DATA >> 8]},
         mem={CLIP_DATA: clip_stream(False), CLIP_IN: CLIP_IN_CODE, CLIP_SYNC: CLIP_SYNC_CODE},
         compare=["fore", "back"]),
]
