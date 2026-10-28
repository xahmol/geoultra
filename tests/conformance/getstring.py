# Conformance cases for GetString, the text prompt and DBGETSTRING
# (tools/harness/harness.py). Keys are delivered through keyVector at the
# top of MainLoop ({"key": code}).

BUF = 0x4000
DONE_AT = 0x4200
DLG_AT = 0x4300
RESULT = 0x4380
SCREENS = ["fore", "back"]
CR, BACKSPACE, KEY_DELETE, KEY_F1 = 13, 8, 29, 1

# keyVector routine after RETURN: X (the length) to RESULT, count calls
DONE = [0x8E, RESULT & 0xFF, RESULT >> 8, 0xEE, (RESULT + 1) & 0xFF, (RESULT + 1) >> 8, 0x60]
AFTER = SCREENS + ["mem:$4000-$400F", "mem:$4380-$4381", "mem:$84A3-$84A4",
                   "mem:$84AB-$84AC"]


def keys(text):
    return [dict(key=c if isinstance(c, int) else ord(c)) for c in text]


def gs(name, default, typed, maxlen=10, compare=AFTER, **kw):
    buf = [ord(c) for c in default] + [0] * (16 - len(default))
    mem = {BUF: buf, DONE_AT: DONE, RESULT: [0xEE, 0]}
    return dict(name=name, routine="GetString", pre=["UseSystemFont"], mem=mem,
                poke={0x84A3: [DONE_AT & 0xFF, DONE_AT >> 8]},
                r={"r0": BUF, "r1L": 0, "r2L": maxlen, "r11": 40, "r1H": 50},
                events=[dict(x=200, y=150)] + keys(typed), compare=compare,
                fillfore=0x00, fillback=0x00, **kw)


CASES = [
    gs("GetString shows the default text", "abc", [], compare=SCREENS + ["mem:$4000-$400F"]),
    gs("GetString typing and RETURN", "ab", "cD1" + "\r"),
    gs("GetString backspace", "", ["x", "y", BACKSPACE, "z", CR]),
    gs("GetString DEL at the start does nothing", "", [KEY_DELETE, "q", CR]),
    gs("GetString buffer full", "a", "wxyz" + "\r", maxlen=3),
    gs("GetString ignores control keys", "", [KEY_F1, "k", CR]),
    gs("GetString ignores shortcuts", "", [0xE1, "m", CR]),
    gs("GetString prompt sprite", "ab", [],
       compare=["mem:$8A40-$8A7F", "io:$D002-$D003", "io:$D017-$D017", "io:$D028-$D028"]),
    gs("GetString prompt after typing", "", "Wide",
       compare=["io:$D002-$D003", "io:$D010-$D010", "mem:$84BE-$84C0"]),
]

# DBGETSTRING in a dialog: r5 holds the buffer pointer
DLG = [0x80 | 1, 13, 16, 30, 0x0C, 8, 1, 1, 72, 0]       # DBGETSTRING x 16 y 30 r5 max 8, OK
CASES += [
    dict(name="DBGETSTRING, RETURN ends the dialog", routine="DoDlgBox",
         mem={DLG_AT: DLG, BUF: [0] * 16, RESULT: [0xEE, 0]}, r={"r0": DLG_AT, "r5": BUF},
         after=[0xA5, 0x02, 0x8D, RESULT & 0xFF, RESULT >> 8], noreturn=True,
         events=[dict(x=200, y=150)] + keys("hi") + [dict(key=CR)],
         compare=["fore", "mem:$4000-$400F", "mem:$4380-$4380"],
         fillfore=0x00, fillback=0x24),
]
