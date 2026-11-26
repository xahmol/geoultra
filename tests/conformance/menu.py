# Conformance cases for menus (tools/dev/harness/harness.py).
#
# Menu structures and item texts are placed at MENU_AT; screens are
# comparable because the harness gives GEOS 2.0 GeoUltra's system font.

MENU_AT = 0x4000
TEXT_AT = 0x4100
ROUTINE_AT = 0x4200


def menu(top, bottom, left, right, attr, items, at=MENU_AT, text_at=TEXT_AT):
    """Menu structure at `at`, item texts from `text_at`.
    items: list of (text, type, pointer). Returns {address: bytes}."""
    data = [top, bottom, left & 0xFF, left >> 8, right & 0xFF, right >> 8, attr]
    texts = []
    addr = text_at
    for text, typ, ptr in items:
        data += [addr & 0xFF, addr >> 8, typ, ptr & 0xFF, ptr >> 8]
        b = [ord(c) for c in text] + [0]
        texts += b
        addr += len(b)
    return {at: data, text_at: texts}


RTS = {ROUTINE_AT: [0x60], 0x30: [0x80]}       # rts; mouseOn = MOUSEON_BIT
MAIN = menu(0, 14, 0, 140, 0x03,
            [("geos", 0x00, ROUTINE_AT), ("file", 0x00, ROUTINE_AT), ("options", 0x00, ROUTINE_AT)])
SCREENS = ["fore", "back"]
STATE = ["mem:$003A-$003C",             # mouseXPos, mouseYPos
         "mem:$0030-$0030",             # mouseOn
         "mem:$84B6-$84B7",             # faultData, menuNumber
         "mem:$84B8-$84BD"]             # mouse limits

CASES = [
    dict(name="DoMenu horizontal main menu", routine="DoMenu", a=0,
         mem={**MAIN, **RTS}, r={"r0": MENU_AT}, compare=SCREENS + STATE),
]

VERT = menu(17, 60, 30, 101, 0x80 | 0x03,
            [("open", 0x00, ROUTINE_AT), ("close all", 0x00, ROUTINE_AT), ("quit", 0x00, ROUTINE_AT)])
CASES += [
    dict(name="DoMenu vertical, odd top", routine="DoMenu", a=1,
         mem={**VERT, **RTS}, r={"r0": MENU_AT}, compare=SCREENS + STATE),
]

for i in range(3):
    CASES.append(dict(name="DoMenu pointer on horizontal item %d" % i, routine="DoMenu", a=i,
                      mem={**MAIN, **RTS}, r={"r0": MENU_AT}, compare=["mem:$003A-$003C"]))
    CASES.append(dict(name="DoMenu pointer on vertical item %d" % i, routine="DoMenu", a=i,
                      mem={**VERT, **RTS}, r={"r0": MENU_AT}, compare=["mem:$003A-$003C"]))
CASES.append(dict(name="DoMenu with the mouse off", routine="DoMenu", a=0,
                  mem={**MAIN, ROUTINE_AT: [0x60], 0x30: [0x00]}, r={"r0": MENU_AT},
                  compare=STATE))

# --- Interaction: MainLoop runs, mouse events are injected -------------

RESULT = 0x4300
OTHER = 0x4302
SUB_AT = 0x4400
SUBTEXT_AT = 0x4480
DYN_AT = 0x4220
OTHER_AT = 0x4240


def action(goto):
    """Item routine: store A at RESULT, count at RESULT+1, then call goto
    (GotoFirstMenu $C1BD, DoPreviousMenu $C190, ReDoMenu $C193) with
    interrupts off.

    A click on the sub-menu's third item ("quit") is not among the cases:
    in this set-up GEOS 2.0 does not call it at y 44-46 and from y 48 on
    calls a fourth item that does not exist (the bytes after the
    structure: "System error"). Looked into on 2026-11-26: a test
    artefact, not a GEOS 2.0 bug. GEOS 2.0 lays out the items 14 dots
    apart as the sub-menu's top and bottom expect, and in a vertical
    menu of its own it calls the third item wherever it is clicked (the
    "vertical menu, third item" cases below, which GeoUltra passes); only
    the injected press in an open constrained sub-menu misses, as GEOS
    2.0's own input driver keeps moving the pointer between the
    harness's events."""
    return [0x8D, RESULT & 0xFF, RESULT >> 8, 0xEE, (RESULT + 1) & 0xFF, (RESULT + 1) >> 8,
            0x78, 0x20, goto & 0xFF, goto >> 8, 0x58, 0x60]


def sub(attr):
    return menu(15, 15 + 3 * 14, 20, 100, attr,
                [("about", 0x00, ROUTINE_AT), ("print", 0x00, ROUTINE_AT), ("quit", 0x00, ROUTINE_AT)],
                at=SUB_AT, text_at=SUBTEXT_AT)


TREE = menu(0, 14, 0, 140, 0x03,
            [("geos", 0x80, SUB_AT), ("file", 0x00, ROUTINE_AT), ("view", 0x40, DYN_AT)])
DYN = [0xA9, SUB_AT & 0xFF, 0x85, 0x02, 0xA9, SUB_AT >> 8, 0x85, 0x03, 0x60]   # r0 = SUB
DYN_NONE = [0xA9, 0x00, 0x85, 0x02, 0x85, 0x03, 0x60]                          # r0 = 0
OTHER_ROUTINE = [0xEE, OTHER & 0xFF, OTHER >> 8, 0x60]                          # count presses


def tree(goto=0xC1BD, dyn=DYN, subattr=0xC3):
    return {**TREE, **sub(subattr), ROUTINE_AT: action(goto), DYN_AT: dyn,
            OTHER_AT: OTHER_ROUTINE, RESULT: [0xEE, 0, 0], 0x30: [0x80]}


def click(x, y):
    return [dict(x=x, y=y, button="press"), dict(x=x, y=y, button="release")]


# faultData ($84B6) is not compared: the interrupt level sets it every
# frame while the pointer is off the menu and MainLoop clears it, so its
# value depends on the moment of sampling.
AFTER = SCREENS + ["mem:$4300-$4302", "mem:$0030-$0030", "mem:$84B7-$84B7",
                   "mem:$003A-$003C", "mem:$84B8-$84BD"]
FILL = dict(fillfore=0x00, fillback=0x24)
OPEN = click(10, 7)          # "geos": opens the sub-menu, pointer to its item 0


def ev(name, events, **kw):
    mem = tree(**kw)
    mem[0x84A9] = [OTHER_AT & 0xFF, OTHER_AT >> 8]       # otherPressVec, set after clean-up
    return dict(name=name, routine="DoMenu", a=0, mem=mem, r={"r0": MENU_AT},
                events=events, compare=AFTER, **FILL)


CASES += [
    ev("click main action item", click(36, 7)),
    ev("click main sub-menu item", OPEN),
    ev("sub-menu action, GotoFirstMenu", OPEN + click(40, 35)),
    ev("sub-menu action, DoPreviousMenu", OPEN + click(40, 35), goto=0xC190),
    ev("sub-menu action, ReDoMenu", OPEN + click(40, 22), goto=0xC193),
    ev("leave constrained sub-menu at the top", OPEN + [dict(x=40, y=10)]),
    ev("constrained sub-menu: off the right side", OPEN + [dict(x=200, y=30)]),
    ev("unconstrained sub-menu closes at once", OPEN, subattr=0x83),
    ev("unconstrained sub-menu: move into it", [dict(x=10, y=7, button="press"),
                                                dict(x=40, y=30), dict(x=200, y=120)],
       subattr=0x83),
    ev("dynamic sub-menu", click(55, 7)),
    ev("dynamic sub-menu returning 0", click(55, 7), dyn=DYN_NONE),
    ev("click right of the last item", click(120, 7)),
    ev("release only", [dict(x=36, y=7, button="release")]),
    ev("press outside the menu", click(200, 100)),
]

VERT_ACTIONS = menu(17, 59, 30, 101, 0x83, [("open", 0x00, ROUTINE_AT), ("close", 0x00, ROUTINE_AT),
                                              ("quit", 0x00, ROUTINE_AT)])
for y in (47, 57):
    case = ev("vertical menu, third item at y %d" % y, click(40, y))
    case["mem"].update(VERT_ACTIONS)
    CASES.append(case)
