; GeoUltra Settings: the Desktop page (overlay 1, ovl.s; docs/SETTINGS.md,
; "Pages"): which desktop starts, and the desktop's view, toolbar, clock
; panes, the sort order, what an existing file at a copy's target gets
; and whether deleting asks first (the user, 2026-11-12, after
; GeoDesk64), as
; choice rows (choice.s) over SETTINGS.INI's keys, written
; with the values the kernal and the desktop read ([system] desktop=;
; [desktop] view=, toolbar=, clock=, panes=, sort=, copy=, delete=;
; src/desktop/
; inifile.s).
; Own design and code.

        .include "geos.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress
        .export Ov_DeskDraw, Ov_DeskPress

        .segment "OV1"

; Ov_DeskDraw: the page's rows drawn. Ov_DeskPress: a click on them.
Ov_DeskDraw:
        lda #<Rows
        ldx #>Rows
        jmp ChoiceDraw
Ov_DeskPress:
        lda #<Rows
        ldx #>Rows
        jmp ChoicePress

COL1            = 137           ; the options' four columns, the same in
COL2            = 191           ; every row (the user, 2026-11-13: boxes
COL3            = 251           ; aligned), from the system font's widths:
COL4            = 282           ; labels to 134, each column's longest
                                ; option (40, 46, 17 or 32 without a 4th,
                                ; 26) and 11 for its box; "newer" to 318
Y0              = PAGE_TOP + 20 ; the rows' baselines, 18 apart
DY              = 18

Rows:   .byte 8
        .byte Y0                                ; the desktop at the start
        .word LDesk, SSystem, KDesk
        .byte 2, 0
        .word COL1, TUltra, VUltra
        .word COL2, TGeos, VGeos
        .byte Y0 + DY                           ; the view
        .word LView, SDesktop, KView
        .byte 3, 0
        .word COL1, TList, VList
        .word COL2, TIcons, VIcons
        .word COL3, TDetail, VDetail
        .byte Y0 + 2 * DY                       ; the toolbar
        .word LBar, SDesktop, KBar
        .byte 3, 0
        .word COL1, TTwo, V16
        .word COL2, TOne, V8
        .word COL3, TOff, VOff
        .byte Y0 + 3 * DY                       ; the clock
        .word LClock, SDesktop, KClock
        .byte 3, 0
        .word COL1, T24, V24
        .word COL2, T12, V12
        .word COL3, TOff, VOff
        .byte Y0 + 4 * DY                       ; two panes
        .word LPanes, SDesktop, KPanes
        .byte 2, 0
        .word COL1, TOneList, V1
        .word COL2, TTwoPanes, V2
        .byte Y0 + 5 * DY                       ; the sort order
        .word LSort, SDesktop, KSort
        .byte 4, 0
        .word COL1, TName, VName
        .word COL2, TDate, VDate
        .word COL3, TSize, VSize
        .word COL4, TType, VType
        .byte Y0 + 6 * DY                       ; a file at the target
        .word LCopy, SDesktop, KCopy
        .byte 4, 0
        .word COL1, TAsk, VAsk
        .word COL2, TReplace, VReplace
        .word COL3, TSkip, VSkip
        .word COL4, TNewer, VNewer
        .byte Y0 + 7 * DY                       ; deleting
        .word LDel, SDesktop, KDel
        .byte 2, 0
        .word COL1, TAskFirst, VAsk
        .word COL2, TAtOnce, VNow

SSystem:        .byte "system", 0
SDesktop:       .byte "desktop", 0
KDesk:          .byte "desktop", 0
KView:          .byte "view", 0
KBar:           .byte "toolbar", 0
KClock:         .byte "clock", 0
KPanes:         .byte "panes", 0
KSort:          .byte "sort", 0
KCopy:          .byte "copy", 0
KDel:           .byte "delete", 0
LCopy:          .byte "Existing", 0
LDel:           .byte "Delete", 0
TAsk:           .byte "ask", 0
TReplace:       .byte "replace", 0
TSkip:          .byte "skip", 0
TNewer:         .byte "newer", 0
TAskFirst:      .byte "ask first", 0
TAtOnce:        .byte "at once", 0
VAsk:           .byte "ask", 0
VReplace:       .byte "replace", 0
VSkip:          .byte "skip", 0
VNewer:         .byte "newer", 0
VNow:           .byte "now", 0
LSort:          .byte "Sort by", 0
TName:          .byte "name", 0
TDate:          .byte "date", 0
TSize:          .byte "size", 0
TType:          .byte "type", 0
VName:          .byte "name", 0
VDate:          .byte "date", 0
VSize:          .byte "size", 0
VType:          .byte "type", 0
LDesk:          .byte "Start with", 0
LView:          .byte "View", 0
LBar:           .byte "Toolbar", 0
LClock:         .byte "Clock", 0
LPanes:         .byte "Panes", 0
TUltra:         .byte "GeoUltra's", 0
TGeos:          .byte "GEOS 2.0's", 0
TList:          .byte "list", 0
TIcons:         .byte "icons", 0
TDetail:        .byte "detailed", 0
TTwo:           .byte "two lines", 0
TOne:           .byte "one line", 0
TOff:           .byte "off", 0
T24:            .byte "24 hours", 0
T12:            .byte "12 hours", 0
TOneList:       .byte "one list", 0
TTwoPanes:      .byte "two panes", 0
VUltra:         .byte "geoultra", 0
VGeos:          .byte "geos", 0
VList:          .byte "list", 0
VIcons:         .byte "icons", 0
VDetail:        .byte "detailed", 0
V16:            .byte "16", 0
V8:             .byte "8", 0
VOff:           .byte "off", 0
V24:            .byte "24", 0
V12:            .byte "12", 0
V1:             .byte "1", 0
V2:             .byte "2", 0
