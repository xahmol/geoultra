; GeoUltra Desktop: overlays (docs/DESKTOP.md, "Structure"). The
; desktop is a VLIR file: record 0 the core at $0400-$4FFF, records 1
; and 2 overlays at TRANS ($5000-$5FFF): 1 the theme files
; (themefile.s), 2 the actions and the mounting (actions.s, mount.s:
; mount calls the actions' Error and Append, so they share one). The
; loader and OvlGo are ovlcore.inc (shared with gush); this file names
; the bank and the stubs. Own code.

        .include "geos.inc"
        .include "desktop.inc"

TRANS           = $5000
TRANS_SIZE      = $1000
OVL_BANK        = 6             ; (1-4: the entry table, 5: the clipboard)
OVL_N           = 2

        .segment "CODE"

        .include "ovlcore.inc"  ; (the loader, OvlGo, the Stub macro)

; OvlFail: a stub without the overlays (their records could not be read
; at the start): nothing happens.
OvlFail:
        rts

        Stub ThemeFiles, 1      ; overlay 1: themefile.s
        Stub ThemeUse, 1
        Stub PalReset, 1
        Stub Copy, 2            ; overlay 2: actions.s, mount.s
        Stub Cut, 2
        Stub Paste, 2
        Stub Delete, 2
        Stub Rename, 2
        Stub NewFolder, 2
        Stub Ask, 2
        Stub Mount, 2
        Stub Eject, 2
