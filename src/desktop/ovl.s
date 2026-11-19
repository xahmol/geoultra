; GeoUltra Desktop: overlays (docs/DESKTOP.md, "Structure"). The
; desktop is a VLIR file: record 0 the core at $0400-$4FFF, records 1
; to 8 overlays at TRANS ($5000-$5FFF): 1 the theme files
; (themefile.s), 2 the actions with the recursion into folders
; (actions.s, tree.s), 3 mounting (mount.s) and the clipboard (clip.s), 4 the INI files
; (inifile.s), 5 the toolbar's drawing and the clock (tooldraw.s), 6
; sorting the list (sort.s), 7 the context menu and Info (ctxmenu.s), 8
; the list's mouse and key handling (listin.s)
; (sort.s). The loader and OvlGo are ovlcore.inc (shared with gush);
; this file names the bank and the stubs. Own code.

        .include "geos.inc"
        .include "desktop.inc"

TRANS           = $5000
TRANS_SIZE      = $1000
OVL_BANK        = 6             ; (1-4: the entry table, 5: the clipboard;
                                ; bank 6: the overlays $0000-$7FFF, the
                                ; history $8000 (history.s), icons $9000-
                                ; $FDFF (iconview.s), the big icons $FE00
                                ; (tooldraw.s))
OVL_N           = 8
        .assert OVL_N * TRANS_SIZE <= $8000, error, "overlays: into the history (history.s, $8000)"

        .segment "CODE"

        .include "ovlcore.inc"  ; (the loader, OvlGo, the Stub macro)

; OvlFail: a stub without the overlays (their records could not be read
; at the start): nothing happens.
OvlFail:
        rts

        Stub ThemeFiles, 1      ; overlay 1: themefile.s
        Stub ThemeUse, 1
        Stub PalReset, 1
        Stub Derive, 1          ; (theme.s: the layout from the theme)
        Stub Copy, 2            ; overlay 2: actions.s, tree.s
        Stub Cut, 2
        Stub Paste, 2
        Stub Delete, 2
        Stub Rename, 2
        Stub NewFolder, 2
        Stub Ask, 2
        Stub OpenTask, 2        ; (actions.s: task.s's FE_TASK)
        Stub TaskTake, 2
        Stub Mount, 3           ; overlay 3: mount.s
        Stub Eject, 3
        Stub ClipShow, 3        ; (clip.s: the clipboard menu)
        Stub ClipSave, 3
        Stub ClipClear, 3
        Stub LoadAll, 4         ; overlay 4: inifile.s
        Stub Save, 4
        Stub ThemeSave, 4
        Stub ViewSave, 4
        Stub ClockSave, 4
        Stub ToolbarSave, 4
        Stub PanesSave, 4
        Stub PanesKeep, 4
        Stub SortSave, 4
        Stub UsePrinter, 4      ; (a printer driver opened: the printer)
        Stub ToolDraw, 5        ; overlay 5: tooldraw.s
        Stub BigInit, 5
        Stub ClockDraw, 5
        Stub SpoolDraw, 5       ; (spool.s: the print queue)
        Stub QueueWin, 5
        Stub SortList, 6        ; overlay 6: sort.s
        Stub PrnUlt, 6          ; (prnult.s: the Ultimate's printer set up)
        Stub AppFind, 6         ; (appfind.s: a document's application)
        Stub AppGo, 6
        Stub ImgPath, 6         ; (imgpath.s: paths through disk images)
        Stub ImgLocal, 6
        Stub NameImg, 6
        Stub AfterMount, 6
        Stub Popup, 7           ; overlay 7: ctxmenu.s
        Stub Info, 7
        Stub About, 7           ; (geos > GeoUltra info)
        Stub FontAct, 7         ; (fontact.s: a system font in or out)
        Stub FontImport, 7      ; (fontact.s: GEOULTRA/fonts' CVT files)
        Stub ListPress, 8       ; overlay 8: listin.s
        Stub PaneLetters, 8     ; (two panes: the drive letters)
        Stub ListKey, 8
        Stub ListEnd, 8
        Stub SelAll, 8
