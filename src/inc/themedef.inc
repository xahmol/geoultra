; The theme files' format (docs/design/DESKTOP.md, "Look and themes"; the
; desktop's themefile.s reads and writes them, GeoUltra Settings' theme
; editor edits them): the lines after name= in the file's order (their
; keys), each line's style words (W_NONE: no style), the kind of its
; colours, the colour names, the palette's key. Shared tables, own
; design (moved here from themefile.s, 2026-11-13). The includer puts it
; in a data segment.

LINES_N         = 22            ; the file's lines after name=
LINE_BYTYPE     = 15            ; icons-bytype=on|off: the icon colours by
                                ; type used (the user, 2026-11-14: optional)
LINE_ITYPES     = 16            ; the first of the icon colours by type
        .ifndef ITYPES_N        ; (desktop.inc has it too)
ITYPES_N        = 6             ; (the user, 2026-11-14: apps, documents,
        .endif                  ; desk accessories, system files, folders
                                ; and drives, Ultimate files; ink only, on
                                ; the desk's paper; icon view only)
KIND_PALETTE    = LINES_N       ; (KeyLo/KeyHi: the palette's key after them)
CK_NONE         = 0             ; a line's colours: none,
CK_PAIR         = 1             ; ink on paper,
CK_INK          = 2             ; ink (on the area's paper),
CK_PAPER        = 3             ; paper only (the border)

K_BORDER:       .byte "border", 0
K_DESK:         .byte "desk", 0
K_MENUBAR:      .byte "menubar", 0
K_SIDEBAR:      .byte "sidebar", 0
K_HEADINGS:     .byte "headings", 0
K_TITLEBAR:     .byte "titlebar", 0
K_ROWS:         .byte "rows", 0
K_COLUMNS:      .byte "columns", 0
K_ICONS:        .byte "icons", 0
K_SELECTION:    .byte "selection", 0
K_CURSOR:       .byte "cursor", 0
K_SCROLLBAR:    .byte "scrollbar", 0
K_STATUS:       .byte "status", 0
K_TOOLBAR:      .byte "toolbar", 0
K_PROGRAMS:     .byte "programs", 0      ; (programs' colours: 2026-11-13)
K_IBYTYPE:      .byte "icons-bytype", 0
K_IAPPS:        .byte "icons-apps", 0
K_IDOCS:        .byte "icons-documents", 0
K_IDAS:         .byte "icons-accessories", 0
K_ISYS:         .byte "icons-system", 0
K_IFOLDERS:     .byte "icons-folders", 0
K_IULT:         .byte "icons-ultimate", 0
KeyLo:  .byte <K_BORDER, <K_DESK, <K_MENUBAR, <K_SIDEBAR, <K_HEADINGS
        .byte <K_TITLEBAR, <K_ROWS, <K_COLUMNS, <K_ICONS, <K_SELECTION
        .byte <K_CURSOR, <K_SCROLLBAR, <K_STATUS, <K_TOOLBAR, <K_PROGRAMS
        .byte <K_IBYTYPE, <K_IAPPS, <K_IDOCS, <K_IDAS, <K_ISYS, <K_IFOLDERS, <K_IULT, <PalKey
KeyHi:  .byte >K_BORDER, >K_DESK, >K_MENUBAR, >K_SIDEBAR, >K_HEADINGS
        .byte >K_TITLEBAR, >K_ROWS, >K_COLUMNS, >K_ICONS, >K_SELECTION
        .byte >K_CURSOR, >K_SCROLLBAR, >K_STATUS, >K_TOOLBAR, >K_PROGRAMS
        .byte >K_IBYTYPE, >K_IAPPS, >K_IDOCS, >K_IDAS, >K_ISYS, >K_IFOLDERS, >K_IULT, >PalKey
LColKind:
        .byte CK_PAPER, CK_PAIR, CK_PAIR, CK_PAIR, CK_PAIR, CK_PAIR
        .byte CK_NONE, CK_NONE, CK_INK, CK_PAIR, CK_INK, CK_NONE, CK_PAIR, CK_PAIR
        .byte CK_PAIR           ; programs
        .byte CK_NONE           ; icons-bytype (on, off)
        .byte CK_INK, CK_INK, CK_INK, CK_INK, CK_INK, CK_INK ; icons by type
        .assert * - LColKind = LINES_N, error, "LColKind: a kind per line"
W_NONE:         .byte 0
W_MENUBAR:      .byte "plain", 0, "clock", 0, 0
W_SIDEBAR:      .byte "wide", 0, "narrow", 0, 0
W_HEADINGS:     .byte "inverted", 0, "band", 0, "underlined", 0, "plain", 0, 0
W_TITLEBAR:     .byte "stripes", 0, "solid", 0, "line", 0, "none", 0, 0
W_ROWS:         .byte "9", 0, "8", 0, 0
W_COLUMNS:      .byte "name", 0, "detailed", 0, 0
W_ONOFF:        .byte "on", 0, "off", 0, 0
W_SELECTION:    .byte "invert", 0, "bar", 0, "frame", 0, 0
W_CURSOR:       .byte "dotted", 0, "mark", 0, "underline", 0, 0
W_SCROLLBAR:    .byte "arrows", 0, "thin", 0, 0
WordsLo:        .byte <W_NONE, <W_NONE, <W_MENUBAR, <W_SIDEBAR, <W_HEADINGS
                .byte <W_TITLEBAR, <W_ROWS, <W_COLUMNS, <W_ONOFF, <W_SELECTION
                .byte <W_CURSOR, <W_SCROLLBAR, <W_ONOFF, <W_NONE, <W_NONE
                .byte <W_ONOFF, <W_NONE, <W_NONE, <W_NONE, <W_NONE, <W_NONE, <W_NONE
WordsHi:        .byte >W_NONE, >W_NONE, >W_MENUBAR, >W_SIDEBAR, >W_HEADINGS
                .byte >W_TITLEBAR, >W_ROWS, >W_COLUMNS, >W_ONOFF, >W_SELECTION
                .byte >W_CURSOR, >W_SCROLLBAR, >W_ONOFF, >W_NONE, >W_NONE
                .byte >W_ONOFF, >W_NONE, >W_NONE, >W_NONE, >W_NONE, >W_NONE, >W_NONE
        .assert * - WordsHi = LINES_N, error, "WordsLo: a list per line"
ColourNames:    .byte "black", 0, "white", 0, "red", 0, "cyan", 0, "purple", 0
                .byte "green", 0, "blue", 0, "yellow", 0, "orange", 0, "brown", 0
                .byte "light red", 0, "dark grey", 0, "grey", 0
                .byte "light green", 0, "light blue", 0, "light grey", 0, 0
PalKey:         .byte "palette", 0
