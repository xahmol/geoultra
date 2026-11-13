; The theme files' format (docs/DESKTOP.md, "Look and themes"; the
; desktop's themefile.s reads and writes them, GeoUltra Settings' theme
; editor edits them): the lines after name= in the file's order (their
; keys), each line's style words (W_NONE: no style), the kind of its
; colours, the colour names, the palette's key. Shared tables, own
; design (moved here from themefile.s, 2026-11-13). The includer puts it
; in a data segment.

LINES_N         = 14            ; the file's lines after name=
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
KeyLo:  .byte <K_BORDER, <K_DESK, <K_MENUBAR, <K_SIDEBAR, <K_HEADINGS
        .byte <K_TITLEBAR, <K_ROWS, <K_COLUMNS, <K_ICONS, <K_SELECTION
        .byte <K_CURSOR, <K_SCROLLBAR, <K_STATUS, <K_TOOLBAR, <PalKey
KeyHi:  .byte >K_BORDER, >K_DESK, >K_MENUBAR, >K_SIDEBAR, >K_HEADINGS
        .byte >K_TITLEBAR, >K_ROWS, >K_COLUMNS, >K_ICONS, >K_SELECTION
        .byte >K_CURSOR, >K_SCROLLBAR, >K_STATUS, >K_TOOLBAR, >PalKey
LColKind:
        .byte CK_PAPER, CK_PAIR, CK_PAIR, CK_PAIR, CK_PAIR, CK_PAIR
        .byte CK_NONE, CK_NONE, CK_INK, CK_PAIR, CK_INK, CK_NONE, CK_PAIR, CK_PAIR
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
                .byte <W_CURSOR, <W_SCROLLBAR, <W_ONOFF, <W_NONE
WordsHi:        .byte >W_NONE, >W_NONE, >W_MENUBAR, >W_SIDEBAR, >W_HEADINGS
                .byte >W_TITLEBAR, >W_ROWS, >W_COLUMNS, >W_ONOFF, >W_SELECTION
                .byte >W_CURSOR, >W_SCROLLBAR, >W_ONOFF, >W_NONE
        .assert * - WordsHi = LINES_N, error, "WordsLo: a list per line"
ColourNames:    .byte "black", 0, "white", 0, "red", 0, "cyan", 0, "purple", 0
                .byte "green", 0, "blue", 0, "yellow", 0, "orange", 0, "brown", 0
                .byte "light red", 0, "dark grey", 0, "grey", 0
                .byte "light green", 0, "light blue", 0, "light grey", 0, 0
PalKey:         .byte "palette", 0
