# Conformance cases for DrawPoint, TestPoint, DrawLine and GraphicsString
# (tools/harness/harness.py). The mode of DrawPoint and DrawLine is in the
# N and carry flags ("flags": "C" set, "" clear, "N" recover).

STR_AT = 0x4000
SCREENS = ["fore", "back"]
FILL = dict(fillfore=0x0F, fillback=0xA5)

MOVEPENTO, LINETO, RECTANGLETO, NEWPATTERN = 1, 2, 3, 5
ESC_PUTSTRING, FRAME_RECTO, PEN_X_DELTA, PEN_Y_DELTA, PEN_XY_DELTA = 6, 7, 8, 9, 10


def w(v):
    return [v & 0xFF, (v >> 8) & 0xFF]


def line(name, x1, y1, x2, y2, flags="C", **kw):
    return dict(name=name, routine="DrawLine", flags=flags,
                r={"r3": x1, "r11L": y1, "r4": x2, "r11H": y2}, compare=SCREENS, **kw)


CASES = [
    dict(name="DrawPoint set", routine="DrawPoint", flags="C", r={"r3": 17, "r11L": 33},
         compare=SCREENS, **FILL),
    dict(name="DrawPoint clear", routine="DrawPoint", flags="", r={"r3": 300, "r11L": 33},
         compare=SCREENS, **FILL),
    dict(name="DrawPoint recover", routine="DrawPoint", flags="N", r={"r3": 9, "r11L": 101},
         compare=SCREENS, **FILL),
    dict(name="DrawPoint set foreground only", routine="DrawPoint", flags="C", disp=0x80,
         r={"r3": 270, "r11L": 199}, compare=SCREENS, **FILL),
    dict(name="TestPoint set pixel", routine="TestPoint", fillfore=0xFF, fillback=0x00,
         disp=0x80, r={"r3": 100, "r11L": 50}, after=[0x08, 0x68, 0x29, 0x01, 0x85, 0x20],
         compare=["r15L", "r3", "r11L"]),
    dict(name="TestPoint background when both", routine="TestPoint", fillfore=0xFF,
         fillback=0x00, r={"r3": 100, "r11L": 50},
         after=[0x08, 0x68, 0x29, 0x01, 0x85, 0x20], compare=["r15L"]),
    line("DrawLine shallow right down", 10, 20, 200, 60),
    line("DrawLine shallow left up", 250, 150, 30, 120),
    line("DrawLine steep", 100, 10, 130, 190),
    line("DrawLine steep reversed", 140, 180, 90, 5),
    line("DrawLine 45 degrees", 0, 0, 199, 199),
    line("DrawLine x above 255", 240, 10, 319, 70),
    line("DrawLine clear", 10, 20, 200, 60, flags="", **FILL),
    line("DrawLine recover", 10, 20, 200, 60, flags="N", **FILL),
    line("DrawLine horizontal", 10, 77, 300, 77),
    line("DrawLine horizontal clear", 10, 77, 300, 77, flags="", **FILL),
    line("DrawLine vertical", 160, 10, 160, 150),
    line("DrawLine single point", 55, 55, 55, 55),
]

GS = ([MOVEPENTO] + w(20) + [30] + [LINETO] + w(120) + [60] + [LINETO] + w(40) + [150] +
      [NEWPATTERN, 1, RECTANGLETO] + w(200) + [100] + [FRAME_RECTO] + w(150) + [20] +
      [PEN_X_DELTA] + w(-30) + [PEN_Y_DELTA] + w(25) + [LINETO] + w(300) + [190] +
      [PEN_XY_DELTA] + w(-100) + w(-20) + [FRAME_RECTO] + w(260) + [140] + [0])
GSTEXT = ([MOVEPENTO] + w(10) + [10] + [FRAME_RECTO] + w(120) + [40] +
          [ESC_PUTSTRING] + w(20) + [28] + [ord(c) for c in "Graphics"] + [0])
CASES += [
    dict(name="GraphicsString lines, rectangles, deltas", routine="GraphicsString",
         mem={STR_AT: GS}, r={"r0": STR_AT}, compare=SCREENS),
    dict(name="GraphicsString ESC_PUTSTRING ends it", routine="GraphicsString",
         pre=["UseSystemFont"], mem={STR_AT: GSTEXT}, r={"r0": STR_AT}, compare=SCREENS + ["r0"]),
    dict(name="i_GraphicsString", routine="i_GraphicsString",
         inline=GS, after=[0xA9, 0x77, 0x85, 0x20], compare=SCREENS + ["r15L"]),
]
