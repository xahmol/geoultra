# Conformance cases for text output (tools/dev/harness/harness.py).
#
# Metrics are compared with each system's own system font (same metrics
# by design). Drawing is compared with one shared test font: GeoUltra's
# system font, placed at FONT_AT on both systems, with the font variables
# pointing to it, so the screens must match pixel for pixel.

import importlib.util
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_mkfont = _load(os.path.join(ROOT, "tools", "mkfont.py"), "mkfont")
_font = _mkfont.build(_load(os.path.join(ROOT, "tools", "fonts", "system9.py"), "system9"))

FONT_AT = 0x4000
STRING_AT = 0x4800
SCREENS = ["fore", "back"]
TEXT_STATE = "mem:$0026-$002E"          # font variables and currentMode


def font_vars(mode=0):
    """Memory writes that select the shared test font and text defaults."""
    idx, data = FONT_AT + 8, FONT_AT + 8 + 194
    return {
        FONT_AT: list(_font),
        0x26: [_font[0], _font[1], _font[2], _font[3],
               idx & 0xFF, idx >> 8, data & 0xFF, data >> 8, mode],
        0x33: [0, 199, 0, 0, 0x3F, 0x01],     # windowTop/Bottom, margins 0-319
        0x84AB: [0, 0],                      # StringFaultVec
    }


def text(s, **kw):
    """Font defaults plus a string at STRING_AT."""
    mem = font_vars(kw.pop("mode", 0))
    data = []
    for c in s:
        data.append(c if isinstance(c, int) else ord(c))
    mem[STRING_AT] = data + [0]
    mem.update(kw.pop("mem", {}))
    return mem


def with_mem(base, extra):
    base = dict(base)
    base.update(extra)
    return base


CASES = []

# Metrics with each system's own font
for ch in " !AiMW~0":
    CASES.append(dict(name="GetCharWidth %r" % ch, routine="GetCharWidth",
                      pre=["UseSystemFont"], a=ord(ch), compare=["A"]))
CASES.append(dict(name="GetCharWidth below 32", routine="GetCharWidth",
                  pre=["UseSystemFont"], a=13, compare=["A"]))
for mode, label in ((0x00, "plain"), (0x40, "bold"), (0x08, "outline"), (0xA0, "underline reverse")):
    CASES.append(dict(name="GetRealSize 'A' %s" % label, routine="GetRealSize",
                      pre=["UseSystemFont"], a=ord("A"), x=mode, compare=["A", "X", "Y"]))
CASES.append(dict(name="UseSystemFont font variables", routine="UseSystemFont",
                  compare=["mem:$0026-$0026", "mem:$0027-$0029"]))

# Drawing with the shared test font
CASES += [
    dict(name="PutChar 'A' plain", routine="PutChar", a=ord("A"), mem=font_vars(),
         r={"r11": 10, "r1H": 20}, compare=SCREENS + ["r11", "r1H"]),
    dict(name="PutChar on a filled screen", routine="PutChar", a=ord("g"), fill=0xFF,
         mem=font_vars(), r={"r11": 13, "r1H": 40}, compare=SCREENS + ["r11"]),
    dict(name="PutChar on a pattern", routine="PutChar", a=ord("W"), fill=0x55,
         mem=font_vars(), r={"r11": 101, "r1H": 60}, compare=SCREENS + ["r11"]),
    dict(name="PutChar bold", routine="PutChar", a=ord("M"), mem=font_vars(0x40),
         r={"r11": 30, "r1H": 30}, compare=SCREENS + ["r11"]),
    dict(name="PutChar underline", routine="PutChar", a=ord("y"), mem=font_vars(0x80),
         r={"r11": 30, "r1H": 30}, compare=SCREENS + ["r11"]),
    dict(name="PutChar reverse", routine="PutChar", a=ord("e"), mem=font_vars(0x20),
         fill=0xAA, r={"r11": 30, "r1H": 30}, compare=SCREENS + ["r11"]),
    dict(name="PutChar x above 255", routine="PutChar", a=ord("Q"), mem=font_vars(),
         r={"r11": 300, "r1H": 100}, compare=SCREENS + ["r11"]),
    dict(name="PutChar left of leftMargin", routine="PutChar", a=ord("A"),
         mem=with_mem(font_vars(), {0x35: [50, 0]}), r={"r11": 40, "r1H": 50},
         compare=SCREENS + ["r11"]),
    dict(name="PutChar past rightMargin", routine="PutChar", a=ord("A"),
         mem=with_mem(font_vars(), {0x37: [50, 0]}), r={"r11": 48, "r1H": 50},
         compare=SCREENS + ["r11"]),
    dict(name="PutChar clipped by windowTop", routine="PutChar", a=ord("H"),
         mem=with_mem(font_vars(), {0x33: [18, 199]}), r={"r11": 20, "r1H": 22},
         compare=SCREENS),
    dict(name="PutChar clipped by windowBottom", routine="PutChar", a=ord("p"),
         mem=with_mem(font_vars(), {0x33: [0, 21]}), r={"r11": 20, "r1H": 20},
         compare=SCREENS),
    dict(name="SmallPutChar 'k'", routine="SmallPutChar", a=ord("k"), mem=font_vars(),
         r={"r11": 70, "r1H": 70}, compare=SCREENS + ["r11"]),
    dict(name="PutString plain", routine="PutString",
         mem=text("Hello, GEOS!"), r={"r0": STRING_AT, "r11": 8, "r1H": 12},
         compare=SCREENS + ["r0", "r11", "r1H"]),
    dict(name="PutString style codes", routine="PutString",
         mem=text(["a", 24, "b", 14, "c", 18, "d", 19, 15, "e", 27, "f"]),
         r={"r0": STRING_AT, "r11": 8, "r1H": 40},
         compare=SCREENS + ["r0", "r11", TEXT_STATE]),
    dict(name="PutString CR and LF", routine="PutString",
         mem=with_mem(text(["a", 13, "b", 10, "c"]), {0x35: [6, 0]}),
         r={"r0": STRING_AT, "r11": 30, "r1H": 60},
         compare=SCREENS + ["r0", "r11", "r1H"]),
    dict(name="PutString GOTOX GOTOY GOTOXY", routine="PutString",
         mem=text(["a", 20, 0x2C, 0x01, "b", 21, 90, "c", 22, 7, 0, 150, "d"]),
         r={"r0": STRING_AT, "r11": 5, "r1H": 20},
         compare=SCREENS + ["r0", "r11", "r1H"]),
    dict(name="PutString UPLINE and HOME", routine="PutString",
         mem=text(["a", 12, "b", 11, "c"]), r={"r0": STRING_AT, "r11": 100, "r1H": 100},
         compare=SCREENS + ["r0", "r11", "r1H"]),
    dict(name="PutDecimal right justified", routine="PutDecimal", a=0x28,
         mem=font_vars(), r={"r0": 1234, "r11": 40, "r1H": 80}, compare=SCREENS + ["r11"]),
    dict(name="PutDecimal right, zeros", routine="PutDecimal", a=0x28,
         mem=font_vars(), r={"r0": 7, "r11": 40, "r1H": 80}, compare=SCREENS + ["r11"]),
    dict(name="PutDecimal left, suppressed", routine="PutDecimal", a=0xC0,
         mem=font_vars(), r={"r0": 65535, "r11": 40, "r1H": 80}, compare=SCREENS + ["r11"]),
    dict(name="PutDecimal left, suppressed zero", routine="PutDecimal", a=0xC0,
         mem=font_vars(), r={"r0": 0, "r11": 40, "r1H": 80}, compare=SCREENS + ["r11"]),
    dict(name="PutDecimal right, suppressed", routine="PutDecimal", a=0x5A,
         mem=font_vars(), r={"r0": 305, "r11": 40, "r1H": 80}, compare=SCREENS + ["r11"]),
]
