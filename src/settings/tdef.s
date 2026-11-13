; GeoUltra Settings: the theme files' format (src/inc/themedef.inc,
; shared with the desktop's themefile.s): its tables once in the core,
; for the Theme and Pointer pages. Own design.

        .segment "DATA"

        .include "themedef.inc"

        .export KeyLo, KeyHi, LColKind, WordsLo, WordsHi, ColourNames, PalKey
        .exportzp LINES_N, KIND_PALETTE, CK_NONE, CK_PAIR, CK_INK, CK_PAPER
