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
