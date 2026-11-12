; GeoUltra Settings: the Desktop page (overlay 1, ovl.s; docs/SETTINGS.md,
; "Pages"): which desktop starts, and the desktop's view, toolbar, clock
; and panes, as choice rows (choice.s) over SETTINGS.INI's keys, written
; with the values the kernal and the desktop read ([system] desktop=;
; [desktop] view=, toolbar=, clock=, panes=; src/desktop/inifile.s).
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

X1              = 150           ; the options' columns
X2              = 212
X3              = 266
Y0              = PAGE_TOP + 20 ; the rows' baselines, 18 apart
DY              = 18

Rows:   .byte 5
        .byte Y0                                ; the desktop at the start
        .word LDesk, SSystem, KDesk
        .byte 2, 0
        .word X1, TUltra, VUltra
        .word X2 + 14, TGeos, VGeos
        .byte Y0 + DY                           ; the view
        .word LView, SDesktop, KView
        .byte 3, 0
        .word X1, TList, VList
        .word X2, TIcons, VIcons
        .word X3, TDetail, VDetail
        .byte Y0 + 2 * DY                       ; the toolbar
        .word LBar, SDesktop, KBar
        .byte 3, 0
        .word X1, TTwo, V16
        .word X2, TOne, V8
        .word X3, TOff, VOff
        .byte Y0 + 3 * DY                       ; the clock
        .word LClock, SDesktop, KClock
        .byte 3, 0
        .word X1, T24, V24
        .word X2, T12, V12
        .word X3, TOff, VOff
        .byte Y0 + 4 * DY                       ; two panes
        .word LPanes, SDesktop, KPanes
        .byte 2, 0
        .word X1, TOneList, V1
        .word X2 + 14, TTwoPanes, V2

SSystem:        .byte "system", 0
SDesktop:       .byte "desktop", 0
KDesk:          .byte "desktop", 0
KView:          .byte "view", 0
KBar:           .byte "toolbar", 0
KClock:         .byte "clock", 0
KPanes:         .byte "panes", 0
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
