# Conformance cases for BitmapUp, the sprite routines and icons
# (tools/harness/harness.py).

DATA_AT = 0x4000
TABLE_AT = 0x4200
ROUTINE_AT = 0x4300
RESULT = 0x4380
SCREENS = ["fore", "back"]

# Compacted bitmaps (HG2G2022 format): repeat (1-127, byte), unique
# (129-219, bytes), bigcount (221-255, count, packets).
REPEATS = [24, 0xAA, 24, 0x55]                                  # 3 cards x 16 lines
UNIQUE_SPAN = [128 + 10] + list(range(1, 11)) + [6, 0xFF]       # 4 x 4: packet spans lines
BIG = [220 + 4, 6, 2, 0x81, 129, 0x3C, 5, 0x0F, 3, 0xF0]        # bigcount, then repeat
MIXED = [2, 0x11, 131, 0xA1, 0xB2, 0xC3, 3, 0x7E, 220 + 4, 3, 129, 0x01, 2, 0x99, 8, 0x42]

CASES = [
    dict(name="BitmapUp repeats", routine="BitmapUp", mem={DATA_AT: REPEATS},
         r={"r0": DATA_AT, "r1L": 3, "r1H": 21, "r2L": 3, "r2H": 16}, compare=SCREENS),
    dict(name="BitmapUp unique over line ends", routine="BitmapUp", mem={DATA_AT: UNIQUE_SPAN},
         r={"r0": DATA_AT, "r1L": 10, "r1H": 7, "r2L": 4, "r2H": 4}, compare=SCREENS),
    dict(name="BitmapUp bigcount", routine="BitmapUp", mem={DATA_AT: BIG},
         r={"r0": DATA_AT, "r1L": 0, "r1H": 99, "r2L": 5, "r2H": 4}, compare=SCREENS + ["r0"]),
    dict(name="BitmapUp mixed packets", routine="BitmapUp", mem={DATA_AT: MIXED},
         r={"r0": DATA_AT, "r1L": 20, "r1H": 150, "r2L": 3, "r2H": 4}, compare=SCREENS),
    dict(name="BitmapUp at card 35", routine="BitmapUp", mem={DATA_AT: REPEATS},
         r={"r0": DATA_AT, "r1L": 35, "r1H": 180, "r2L": 3, "r2H": 16}, compare=SCREENS),
    dict(name="BitmapUp foreground only", routine="BitmapUp", disp=0x80, mem={DATA_AT: REPEATS},
         r={"r0": DATA_AT, "r1L": 3, "r1H": 21, "r2L": 3, "r2H": 16}, compare=SCREENS),
    dict(name="i_BitmapUp", routine="i_BitmapUp", mem={DATA_AT: REPEATS},
         inline=[DATA_AT & 0xFF, DATA_AT >> 8, 12, 60, 3, 16], compare=SCREENS),
    dict(name="DrawSprite 3", routine="DrawSprite", mem={DATA_AT: list(range(64))},
         r={"r3L": 3, "r4": DATA_AT}, compare=["mem:$8AC0-$8AFF"]),
    dict(name="PosSprite 2 at x 300", routine="PosSprite", r={"r3L": 2, "r4": 300, "r5L": 77},
         compare=["io:$D004-$D005", "io:$D010-$D010"]),
    dict(name="PosSprite 5 at x 10", routine="PosSprite", r={"r3L": 5, "r4": 10, "r5L": 190},
         compare=["io:$D00A-$D00B", "io:$D010-$D010"]),
    dict(name="EnablSprite 6", routine="EnablSprite", r={"r3L": 6}, compare=["io:$D015-$D015"]),
    dict(name="DisablSprite 0", routine="DisablSprite", r={"r3L": 0}, compare=["io:$D015-$D015"]),
]

# --- Icons ----------------------------------------------------------------

ICON = [32, 0xFF, 64, 0x81, 32, 0xFF]                  # 2 cards x 64 bytes: frame-ish
HANDLER = [0xA5, 0x02, 0x8D, RESULT & 0xFF, RESULT >> 8,          # lda r0L; sta RESULT
           0xA5, 0x03, 0x8D, (RESULT + 1) & 0xFF, (RESULT + 1) >> 8,  # lda r0H; sta RESULT+1
           0xEE, (RESULT + 2) & 0xFF, (RESULT + 2) >> 8, 0x60]    # inc RESULT+2; rts
OTHER = [0xEE, (RESULT + 3) & 0xFF, (RESULT + 3) >> 8, 0x60]      # count other presses


def table(mouse=(0, 0), icons=((DATA_AT, 4, 40, 2, 32), (DATA_AT, 10, 40, 2, 32),
                              (0, 16, 40, 2, 32))):
    t = [len(icons), mouse[0] & 0xFF, mouse[0] >> 8, mouse[1]]
    for pic, x, y, w, h in icons:
        t += [pic & 0xFF, pic >> 8, x, y, w, h, ROUTINE_AT & 0xFF, ROUTINE_AT >> 8]
    return t


def icons(mouse_on=0x80, flag=0x80, mouse=(0, 0)):
    return {DATA_AT: ICON * 1, TABLE_AT: table(mouse), ROUTINE_AT: HANDLER,
            ROUTINE_AT + 0x40: OTHER, RESULT: [0xEE, 0xEE, 0, 0],
            0x30: [mouse_on], 0x84B5: [flag], 0x3A: [100, 0, 100]}


STATE = ["mem:$003A-$003C", "mem:$0030-$0030", "mem:$003F-$0040", "mem:$84B8-$84BD"]
AFTER = SCREENS + ["mem:$4380-$4383", "mem:$0030-$0030"]
FILL = dict(fillfore=0x00, fillback=0x24)


def ev(name, events, **kw):
    mem = icons(**kw)
    mem[0x84A9] = [(ROUTINE_AT + 0x40) & 0xFF, (ROUTINE_AT + 0x40) >> 8]   # otherPressVec
    return dict(name=name, routine="DoIcons", mem=mem, r={"r0": TABLE_AT}, events=events,
                compare=AFTER, **FILL)


def click(x, y, mem=None):
    press = dict(x=x, y=y, button="press")
    if mem:
        press["mem"] = mem
    return [press, dict(x=x, y=y, button="release")]


CASES += [
    dict(name="DoIcons draws, mouse on", routine="DoIcons", mem=icons(mouse=(48, 56)),
         r={"r0": TABLE_AT}, compare=SCREENS + STATE),
    dict(name="DoIcons, mouse off", routine="DoIcons", mem=icons(mouse_on=0x40),
         r={"r0": TABLE_AT}, compare=SCREENS + STATE),
    dict(name="DoIcons, foreground only", routine="DoIcons", disp=0x80, mem=icons(),
         r={"r0": TABLE_AT}, compare=SCREENS),
    ev("click icon 1, flash", click(90, 60)),
    ev("click icon 0, invert", click(40, 45), flag=0x40),
    ev("click icon 0, nothing", click(40, 45), flag=0x00),
    ev("double click icon 1", click(90, 60) + click(90, 60, mem={0x8515: [20]})),
    ev("click outside the icons", click(200, 150)),
    ev("click the disabled icon", click(130, 60)),
    ev("click below an icon", click(40, 72)),
]
