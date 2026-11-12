; GeoUltra Desktop: overlays (docs/DESKTOP.md, "Structure"). The
; desktop is a VLIR file: record 0 the core at $0400-$4FFF, records 1
; to 6 overlays at TRANS ($5000-$5FFF): 1 the theme files
; (themefile.s), 2 the actions with the recursion into folders
; (actions.s, tree.s), 3 mounting (mount.s), 4 the INI files
; (inifile.s), 5 the toolbar's drawing and the clock (tooldraw.s), 6
; sorting the list
; (sort.s). The loader and OvlGo are ovlcore.inc (shared with gush);
; this file names the bank and the stubs. Own code.

        .include "geos.inc"
        .include "desktop.inc"

TRANS           = $5000
TRANS_SIZE      = $1000
OVL_BANK        = 6             ; (1-4: the entry table, 5: the clipboard;
                                ; bank 6: the overlays $0000-$5FFF, the
                                ; big icons $7000 (tooldraw.s), the history
                                ; $8000 (history.s), icons $9000 (iconview.s))
OVL_N           = 6

        .segment "CODE"

        .include "ovlcore.inc"  ; (the loader, OvlGo, the Stub macro)

; OvlFail: a stub without the overlays (their records could not be read
; at the start): nothing happens.
OvlFail:
        rts

        Stub ThemeFiles, 1      ; overlay 1: themefile.s
        Stub ThemeUse, 1
        Stub PalReset, 1
        Stub Copy, 2            ; overlay 2: actions.s, tree.s
        Stub Cut, 2
        Stub Paste, 2
        Stub Delete, 2
        Stub Rename, 2
        Stub NewFolder, 2
        Stub Ask, 2
        Stub Mount, 3           ; overlay 3: mount.s
        Stub Eject, 3
        Stub LoadAll, 4         ; overlay 4: inifile.s
        Stub Save, 4
        Stub ThemeSave, 4
        Stub ViewSave, 4
        Stub ClockSave, 4
        Stub ToolbarSave, 4
        Stub ToolDraw, 5        ; overlay 5: tooldraw.s
        Stub BigInit, 5
        Stub ClockDraw, 5
        Stub SortList, 6        ; overlay 6: sort.s
