# Conformance cases for dialog boxes (tools/harness/harness.py).
#
# DoDlgBox only returns when the dialog ends, so the cases run as event
# cases with "noreturn"; after the call r0L (the result) is stored at
# RESULT. Screens are comparable because the harness gives GEOS 2.0
# GeoUltra's system font and system icons.

DLG_AT = 0x4000
TEXT_AT = 0x4100
ROUTINE_AT = 0x4200
RESULT = 0x4380
SCREENS = ["fore", "back"]
OK, CANCEL, YES, NO, OPEN, DISK = 1, 2, 3, 4, 5, 6
DBTXTSTR, DBVARSTR, DBSYSOPV, DBOPVEC, DBUSRICON, DB_USR_ROUT = 11, 12, 14, 17, 18, 19
DEF_DB_POS, SET_DB_POS = 0x80, 0x00
DBI_X_0, DBI_X_1, DBI_X_2 = 1, 9, 17
DBI_Y_0, DBI_Y_1, DBI_Y_2 = 8, 40, 72
TXT_LN_X, TXT_LN_1_Y, TXT_LN_2_Y = 16, 16, 32

STORE_R0L = [0xA5, 0x02, 0x8D, RESULT & 0xFF, RESULT >> 8]       # lda r0L; sta RESULT


def text(s):
    """Null-terminated string; s is a str or a list of str and codes."""
    out = []
    for part in ([s] if isinstance(s, str) else s):
        out += [ord(c) for c in part] if isinstance(part, str) else [part]
    return out + [0]


TEXTS = {TEXT_AT: text("Delete this file?"), TEXT_AT + 0x20: text(["It cannot be ", 24, "undone", 27, "."]),
         TEXT_AT + 0x40: text("Variable text")}
T1, T2, T3 = TEXT_AT, TEXT_AT + 0x20, TEXT_AT + 0x40

# A user routine that ends the dialog with 9: sysDBData = 9; jmp RstrFrmDialogue
END9 = [0xA9, 0x09, 0x8D, 0x1D, 0x85, 0x4C, 0xBF, 0xC2]
# A routine that counts calls at RESULT+1 (for DBOPVEC and DB_USR_ROUT)
COUNT = [0xEE, (RESULT + 1) & 0xFF, (RESULT + 1) >> 8, 0x60]
USRICON_PIC = [32, 0xFF]                          # 2 cards x 16 lines, solid
USRICON = [ROUTINE_AT + 0x40 & 0xFF, ROUTINE_AT + 0x40 >> 8, 0, 0, 2, 16,
           ROUTINE_AT & 0xFF, ROUTINE_AT >> 8]

AFTER = SCREENS + ["mem:$4380-$4381", "mem:$0030-$0030"]
FILL = dict(fillfore=0x00, fillback=0x24)


def dlg(name, table, events, extra=None, r=None, compare=AFTER):
    mem = {DLG_AT: table, RESULT: [0xEE, 0], 0x30: [0x80], **TEXTS}   # mouseOn before
    mem.update(extra or {})
    return dict(name=name, routine="DoDlgBox", mem=mem, r=dict({"r0": DLG_AT}, **(r or {})),
                after=STORE_R0L, noreturn=True, events=events, compare=compare, **FILL)


def click(x, y):
    return [dict(x=x, y=y, button="press"), dict(x=x, y=y, button="release")]


STD = [DEF_DB_POS | 1, DBTXTSTR, TXT_LN_X, TXT_LN_1_Y, T1 & 0xFF, T1 >> 8,
       DBTXTSTR, TXT_LN_X, TXT_LN_2_Y, T2 & 0xFF, T2 >> 8,
       OK, DBI_X_0, DBI_Y_2, CANCEL, DBI_X_2, DBI_Y_2, 0]
CUSTOM = [SET_DB_POS | 1, 40, 120, 40, 0, 0x10, 0x01,             # 40-120 x 40-272
          DBTXTSTR, 12, 20, T1 & 0xFF, T1 >> 8,
          YES, 2, 50, NO, 20, 50, 0]
# OK at DBI_X_0 = card 9 (x 72-119), DBI_Y_2 = line 104; CANCEL card 25.
OK_XY, CANCEL_XY = (90, 110), (220, 110)

CASES = [
    dlg("dialog drawn (default position)", STD, [dict(x=160, y=180)]),
    dlg("OK ends with 1", STD, click(*OK_XY)),
    dlg("CANCEL ends with 2", STD, click(*CANCEL_XY)),
    dlg("custom position, NO ends with 4", CUSTOM, click(220, 98)),
    dlg("custom position, YES ends with 3", CUSTOM, click(80, 98)),
    dlg("press outside the icons does nothing", STD, click(160, 180)),
    dlg("DBVARSTR from r5", [DEF_DB_POS | 0, DBVARSTR, TXT_LN_X, TXT_LN_1_Y, 0x0C,
                              OK, DBI_X_1, DBI_Y_1, 0], click(160, 80), r={"r5": T3}),
    dlg("DBSYSOPV ends with 14", [DEF_DB_POS | 1, DBSYSOPV, OK, DBI_X_0, DBI_Y_2, 0],
        click(160, 180)),
    dlg("DBOPVEC routine on other presses", [DEF_DB_POS | 1, DBOPVEC,
                                              (ROUTINE_AT + 0x20) & 0xFF, (ROUTINE_AT + 0x20) >> 8,
                                              OK, DBI_X_0, DBI_Y_2, 0],
        click(160, 180) + click(*OK_XY), extra={ROUTINE_AT + 0x20: COUNT}),
    dlg("DBUSRICON routine ends with 9", [DEF_DB_POS | 1, DBUSRICON, 12, 30,
                                           (ROUTINE_AT + 0x60) & 0xFF, (ROUTINE_AT + 0x60) >> 8,
                                           OK, DBI_X_0, DBI_Y_2, 0],
        click(18 * 8 + 4, 32 + 30 + 4),
        extra={ROUTINE_AT: END9, ROUTINE_AT + 0x40: USRICON_PIC, ROUTINE_AT + 0x60: USRICON}),
    dlg("DB_USR_ROUT runs", [DEF_DB_POS | 1, DB_USR_ROUT, (ROUTINE_AT + 0x20) & 0xFF,
                             (ROUTINE_AT + 0x20) >> 8, OK, DBI_X_0, DBI_Y_2, 0],
        click(*OK_XY), extra={ROUTINE_AT + 0x20: COUNT}),
    dlg("state restored after the dialog", STD, click(*OK_XY),
        extra={0x84A3: [0x33, 0x44], 0x84AB: [0x55, 0x66], 0x84B3: [7],
               0x2E: [0x40], 0x35: [5, 0, 0x2C, 0x01]},
        compare=AFTER + ["mem:$84A3-$84A4", "mem:$84AB-$84AC", "mem:$84B3-$84B3", "mem:$002E-$002E",
                         "mem:$0033-$0038"]),
]

GSTR = [1, 80, 0, 50, 7, 0xF0, 0, 100, 1, 72, 0, 58, 3, 0xE8, 0, 92, 0]   # frame, solid box
CASES += [
    dlg("DBGRPHSTR draws", [DEF_DB_POS | 1, 15, (ROUTINE_AT + 0x80) & 0xFF,
                            (ROUTINE_AT + 0x80) >> 8, OK, DBI_X_0, DBI_Y_2, 0],
        [dict(x=160, y=180)], extra={ROUTINE_AT + 0x80: GSTR}),
]

# DBGETFILES on the oracle disk: the box at (4, 4) of the default dialog
# (64..255 x 32..127), OPEN to the right of it. At most three files of a
# type there, so no arrows (GEOS 2.0's arrow picture is Berkeley's).
DBGETFILES = 16
NAMEBUF = 0x4500                # not $4F00: the harness's clean-up code
FILES_DLG = [DEF_DB_POS | 1, DBGETFILES, 4, 4, OPEN, DBI_X_2, 16, 0]
FILES_AFTER = ["fore", "mem:$4500-$4510", "mem:$4380-$4380"]
# GeoUltra's drive letters in the box's bottom strip (module 87,
# drvlist.s: x 3-54, y 74-84 in the 124 x 88 box at 68, 36), not GEOS
# 2.0's: left out of the screens' comparison
LETTERS = (68 + 3, 36 + 74, 68 + 3 + 3 * 13 + 10, 36 + 74 + 10)


def files(name, ftype, events, buf="", cls=None, compare=FILES_AFTER):
    extra = {NAMEBUF: text(buf) + [0] * (16 - len(buf))}
    r = {"r5": NAMEBUF, "r7L": ftype, "r10": 0}
    if cls:
        extra[TEXT_AT + 0x60] = text(cls)
        r["r10"] = TEXT_AT + 0x60
    c = dlg(name, FILES_DLG, events, extra=extra, r=r, compare=compare)
    c["mask"] = [LETTERS]
    return c


IDLE = [dict(x=300, y=190)]
CASES += [
    files("DBGETFILES lists the printer drivers", 9, IDLE),
    files("DBGETFILES selects with a click, then OPEN", 9,
          click(100, 57) + click(210, 55)),
    files("DBGETFILES starts at the name in the buffer", 9, IDLE, buf="ASCII Only"),
    files("DBGETFILES filters by permanent name", 10, IDLE, cls="Input Drvr  V1.1"),
    # (TEMPORARY: none on either disk. FONT was used until 2026-11-16:
    # GeoUltra's fonts on drive E are listed after a drive's own on purpose)
    files("DBGETFILES with no files of the type", 13, IDLE),
]
