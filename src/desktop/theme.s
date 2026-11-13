; GeoUltra Desktop: themes (docs/DESKTOP.md, "Look and themes", step
; D7a). A theme is a style byte per design element and a colour byte per
; colour (THM_LEN bytes); the six built-in themes are from the approved
; mock-up (2026-11-06). ThemeSet copies one into the record and derives
; the layout the drawing routines use (sidebar width, title bar, row
; height, list top, rows, status line, scroll track). Colours: every
; cell the desktop paints goes to the colour matrix and to a shadow copy
; (Paint); dialogs (Dialog) and the desktop's menus (MenuNeutral, from
; their DYN_SUB_MENU routines) get the menu bar's colours, desk
; accessories and programs (Neutral) GEOS's own, and Recover (RecoverVector) gives a rectangle back
; its bitmap and its shadow colours. The clock in the menu bar is drawn
; by ClockDraw, kept current by ClockTick (appMain). Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .export ThemeName, themeNo, tCols
        .export tMenu, tSide, tHead, tTitle, tRows, tCols, tIcons, tSel, tCur, tScroll, tStatus
        .export cDesk, cMenu, cSide, cHead, cTitle, cSel, cStatus, cHeadP, cToolbar
        .export cProgs
        .export cIconP, cSideIconP, cAccentP, cSideAccentP
        .export sideW, listL, ejectCard, pathY, listTop, rowH, rows, bottom
        .export trackTop, trackBot, trackH, iconCard, nameX, sideTx, stY0, stY1
        .export Paint, px0, px1, py0, py1, pcol, PaintAll, PaintSide, PaintList
        .export Neutral, Dialog, MenuNeutral, Recover, ClockTick
        .export TextWidth, boldOn, clockMode, viewMode, MonthName, Derive
        .export lastMin, clockX, MonLo, MonHi, stripL, listR, paneR
        .import ClockDraw       ; (ovl.s: overlay 5, tooldraw.s)
        .export tbMode, topY, titleEnd
        .import ToolPaint, IconLayout, step, sortPending, SortNow, RightPress
        .import SetGeom, panes
        .import BusyPause, BusyResume

CPU_PORT        = $01
RAM_IO          = $35
VIC_BORDER      = $D020
STRIP_TOP_PAD   = 9             ; an arrow box's height (8) and a line

        .segment "ZEROPAGE"

cp:             .res 2          ; a colour matrix row (Paint)
shp:            .res 2          ; its shadow row

        .segment "CODE"

; Derive: the layout from the record; a colour bar selection forces
; 8-pixel rows (9-pixel rows cross the 8 x 8 cells).
Derive: lda tSel
        cmp #ST_BAR
        bne :+
        lda #8
        sta tRows
:       lda tRows
        sta rowH
        ldx #80                 ; sidebar width
        lda tSide
        beq :+
        ldx #64
:       stx sideW
        stx listL
        txa                     ; the eject icon: two cards from the edge
        lsr a
        lsr a
        lsr a
        sec
        sbc #2
        sta ejectCard
        txa                     ; the icons' card: one in from the list's
        lsr a                   ; edge; names after it, or near the edge
        lsr a
        lsr a
        clc
        adc #1
        sta iconCard
        ldy #5
        lda tIcons
        bne :+
        ldy #18
:       tya
        clc
        adc listL
        sta nameX
        ldy #8                  ; the sidebar's text: after its icon
        lda tIcons
        bne :+
        ldy #19
:       sty sideTx
        jsr SetGeom             ; (panes.s: two panes' edges, or the list's)
        ldx tbMode              ; the content's top: under the toolbar
        lda #MENU_BOTTOM + 2
        clc
        adc BarH,x
        sta topY
        clc
        adc #8
        sta titleEnd            ; (the title bar: topY to titleEnd - 1)
        lda #7                  ; the path line's baseline: under the title
        ldx tTitle
        cpx #ST_NONE
        beq :+
        lda #15
:       clc
        adc topY
        sta pathY
        ldx #199                ; the bottom: above the status line
        lda tStatus
        bne :+
        ldx #191
:       stx bottom
        lda rowH                ; the list's top: 9-pixel rows right under
        cmp #9                  ; the path line, 8-pixel ones on a cell
        bne :+
        lda pathY
        clc
        adc #4
        bne @top
:       lda pathY
        clc
        adc #3 + 7
        and #$F8
@top:   sta listTop
        lda bottom              ; rows: (bottom - 7 - top) / rowH + 1
        sec
        sbc #7
        sec
        sbc listTop
        ldx #0
@rows:  cmp rowH
        bcc :+
        sbc rowH
        inx
        bne @rows
:       inx
        stx rows
        lda #1                  ; scrolling a row at a time; the icon view:
        sta step                ; its grid (iconview.s)
        lda viewMode
        cmp #VIEW_ICONS
        bne :+
        jsr IconLayout
:
        lda listTop             ; the scroll strip and its track
        sta stY0
        sta trackTop
        ldx bottom
        dex
        stx stY1
        stx trackBot
        lda tScroll
        bne :+
        lda trackTop
        clc
        adc #STRIP_TOP_PAD
        sta trackTop
        lda trackBot
        sec
        sbc #STRIP_TOP_PAD
        sta trackBot
:       lda trackBot
        sec
        sbc trackTop
        sta trackH
        lda cHead               ; elements drawn inverted (heading boxes
        ldx tHead               ; and bands, the solid title bar, the
        cpx #ST_UNDERLINED      ; status line): their colours swapped, so
        bcs :+                  ; "white on red" is white text on red
        jsr Swap                ; (the user's reading, 2026-11-11)
:       sta cHeadP
        lda cTitle
        ldx tTitle
        cpx #ST_SOLID
        bne :+
        jsr Swap
:       sta cTitleP
        lda cStatus
        jsr Swap
        sta cStatusP
        lda cDesk               ; the ink-only colours on their papers
        and #$0F
        sta tmp
        lda cIcon
        jsr OnPaper
        sta cIconP
        lda cAccent
        jsr OnPaper
        sta cAccentP
        lda cSide
        and #$0F
        sta tmp
        lda cIcon
        jsr OnPaper
        sta cSideIconP
        lda cAccent
        jsr OnPaper
        sta cSideAccentP
        php                     ; the border
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda VIC_BORDER
        ldx bordSaved
        bne :+
        sta origBorder          ; (GEOS's, for Neutral: kept once)
        inc bordSaved
:       lda cBorder
        sta VIC_BORDER
        pla
        sta CPU_PORT
        plp
        rts

; Swap: A's ink and paper exchanged.
Swap:   asl a                   ; (the nibble swap: twice asl, adc #$80,
        adc #$80                ; rol)
        rol a
        asl a
        adc #$80
        rol a
        rts

; OnPaper: A = ink A on the paper in tmp (a colour byte).
OnPaper:
        asl a
        asl a
        asl a
        asl a
        ora tmp
        rts

; ThemeName: r1 = built-in theme A's name. Destroys X.
ThemeName:
        tax
        lda NameLo,x
        sta r1L
        lda NameHi,x
        sta r1H
        rts

; --- Colours -------------------------------------------------------------

; Paint: cells px0-px1 (columns) by py0-py1 (rows) get colour pcol, in
; the colour matrix and its shadow. Destroys A, X, Y.
Paint:  ldx py0
@row:   jsr RowAt
        ldy px0
@cell:  lda pcol
        sta (cp),y
        sta (shp),y
        cpy px1
        iny
        bcc @cell
        inx
        cpx py1
        beq @row
        bcc @row
        rts

; RowAt: cp and shp at cell row X (X * 40). Destroys A.
RowAt:  lda #0
        sta cp+1
        txa
        asl a                   ; * 8 (row < 32: fits)
        asl a
        asl a
        sta cp
        asl a                   ; * 32
        rol cp+1
        asl a
        rol cp+1
        clc
        adc cp                  ; * 40
        sta cp
        bcc :+
        inc cp+1
:       lda cp
        clc
        adc #<shadow
        sta shp
        lda cp+1
        adc #>shadow
        sta shp+1
        lda cp
        clc
        adc #<COLOR_MATRIX
        sta cp
        lda cp+1
        adc #>COLOR_MATRIX
        sta cp+1
        rts

; PaintAll: the whole screen in the desk's colours, the menu bar's rows
; in the menu's, the sidebar and the list area as theirs.
PaintAll:
        lda #0
        sta px0
        sta py0
        lda #39
        sta px1
        lda #24
        sta py1
        lda cDesk
        sta pcol
        jsr Paint
        lda #1
        sta py1
        lda cMenu
        sta pcol
        jsr Paint
        jsr ToolPaint           ; (toolbar.s: its rows, when it is on)
        lda panes               ; (two panes: no sidebar)
        bne :+
        jsr PaintSide
:       jmp PaintList

; PaintSide: the sidebar's cells (below the menu bar, to the bottom).
PaintSide:
        lda #0
        sta px0
        lda sideW
        jsr Cells
        sec
        sbc #1
        sta px1
        lda topY
        jsr Cells
        sta py0
        lda bottom
        jsr Cells
        sta py1
        lda cSide
        sta pcol
        jmp Paint

; PaintList: the list area's cells (desk; the title bar's row, the icon
; column), and the status line's row.
PaintList:
        lda listL
        jsr Cells
        sta px0
        lda paneR+1             ; to the pane's right edge (a card)
        lsr a
        lda paneR
        ror a
        lsr a
        lsr a
        sta px1
        lda topY
        jsr Cells
        sta py0
        lda bottom
        jsr Cells
        sta py1
        lda cDesk
        sta pcol
        jsr Paint
        lda tTitle
        cmp #ST_NONE
        beq @icons
        lda topY
        jsr Cells
        sta py0
        sta py1
        lda cTitleP
        sta pcol
        jsr Paint
@icons: lda tIcons
        bne @status
        lda iconCard
        sta px0
        sta px1
        lda listTop
        jsr Cells
        sta py0
        lda bottom
        jsr Cells
        sta py1
        lda cIconP
        sta pcol
        jsr Paint
@status:
        lda tStatus
        bne @end
        lda #0
        sta px0
        lda #39
        sta px1
        lda #24
        sta py0
        sta py1
        lda cStatusP
        sta pcol
        jmp Paint
@end:   rts

; Cells: A = pixel A's cell (A / 8).
Cells:  lsr a
        lsr a
        lsr a
        rts

; Neutral: the whole colour matrix in GEOS's colours (screencolors) and
; GEOS's border, for a desk accessory or a program (the shadow keeps the
; desktop's for its return).
Neutral:
        ldx #0
        lda screencolors
@c:     sta COLOR_MATRIX,x
        sta COLOR_MATRIX + $100,x
        sta COLOR_MATRIX + $200,x
        sta COLOR_MATRIX + $2E8,x
        inx
        bne @c
        php
        sei
        lda CPU_PORT
        pha
        lda #RAM_IO
        sta CPU_PORT
        lda origBorder
        sta VIC_BORDER
        pla
        sta CPU_PORT
        plp
        rts

; MenuCells: cells px0-px1 by py0-py1 in the menu bar's colours (the
; matrix only: the shadow keeps the desktop's), under a menu or one of
; the desktop's dialogs (the user, 2026-11-11: themed, with any palette;
; desk accessories and programs keep GEOS's, Neutral).
MenuCells:
        ldx py0
@row:   jsr RowAt
        ldy px0
@cell:  lda cMenu
        sta (cp),y
        cpy px1
        iny
        bcc @cell
        inx
        cpx py1
        beq @row
        bcc @row
        rts

; ShadowCells: cells px0-px1 by py0-py1 back from the shadow.
ShadowCells:
        ldx py0
@row:   jsr RowAt
        ldy px0
@cell:  lda (shp),y
        sta (cp),y
        cpy px1
        iny
        bcc @cell
        inx
        cpx py1
        beq @row
        bcc @row
        rts

; Dialog: DoDlgBox (r0 = the dialog) with the menu bar's colours under
; it (a DEF_DB_POS box and its shadow); the desktop's back afterwards. r0L =
; DoDlgBox's result, as from DoDlgBox.
Dialog: lda #DLG_X0
        sta px0
        lda #DLG_X1
        sta px1
        lda #DLG_Y0
        sta py0
        lda #DLG_Y1
        sta py1
        jsr MenuCells
        jsr BusyPause           ; (icons.s: the arrow while it is open)
        jsr DoDlgBox
        jsr BusyResume
        lda #DLG_X0
        sta px0
        lda #DLG_X1
        sta px1
        lda #DLG_Y0
        sta py0
        lda #DLG_Y1
        sta py1
        jmp ShadowCells
DLG_X0          = 64 / 8        ; DEF_DB_POS: x 64-255, y 32-127, and the
DLG_X1          = (255 + 8) / 8 ; shadow 8 pixels right and below
DLG_Y0          = 32 / 8
DLG_Y1          = (127 + 8) / 8

; MenuNeutral: the menu table at r0 (a DYN_SUB_MENU routine's result)
; gets the menu bar's colours under it before GEOS draws it; Recover gives the
; desktop's back when it closes. r0 kept.
MenuNeutral:
        ldy #0                  ; top, bottom, left (word), right (word)
        lda (r0),y
        jsr Cells
        sta py0
        iny
        lda (r0),y
        jsr Cells
        sta py1
        iny
        lda (r0),y              ; (x < 256 for the desktop's menus)
        jsr Cells
        sta px0
        ldy #4
        lda (r0),y
        sta tmp
        iny
        lda (r0),y
        lsr a
        lda tmp
        ror a
        lsr a
        lsr a
        sta px1
        jmp MenuCells

; Recover (RecoverVector): RecoverRectangle, then the rectangle's cells
; back from the shadow (menus and dialogs closing). r2-r4 as GEOS
; passes them: y r2L-r2H, x r3-r4.
Recover:
        lda r2L
        jsr Cells
        sta py0
        lda r2H
        jsr Cells
        sta py1
        lda r3H
        lsr a
        lda r3L
        ror a
        lsr a
        lsr a
        sta px0
        lda r4H
        lsr a
        lda r4L
        ror a
        lsr a
        lsr a
        sta px1
        jsr RecoverRectangle
        jmp ShadowCells

; --- The clock ------------------------------------------------------------

; ClockTick (appMain): a list waiting to be sorted sorted (list.s,
; SortNow); the clock drawn again when the minute changed.
ClockTick:
        lda sortPending         ; (list.s: a folder read, to be sorted;
        beq :+                  ; here, in MainLoop, an overlay may run:
                                ; never in a dialog, as DoDlgBox clears
                                ; appMain while it runs, dialog.s)
        jsr SortNow
:       lda guMouse2            ; the right button pressed (the 1351
        and #$40                ; driver sets bit 6, the reader clears it):
        beq :+                  ; the context menu (list.s)
        php
        sei
        lda guMouse2
        and #$FF - $40
        sta guMouse2
        plp
        jmp RightPress
:       lda minutes
        cmp lastMin
        beq :+
        jmp ClockDraw           ; (overlay 5, tooldraw.s)
:       rts

; MonthName: r1 = month A's (1-12) three letters. Destroys X.
MonthName:
        tax
        lda MonLo-1,x
        sta r1L
        lda MonHi-1,x
        sta r1H
        rts

; TextWidth: r2 = the width of the text at r0 in the current font
; (boldOn: a pixel more per character; control codes below 32 not
; counted). Destroys A, X, Y.
TextWidth:
        lda #0
        sta r2L
        sta r2H
        ldy #0
@ch:    lda (r0),y
        beq @end
        cmp #32
        bcc @next
        sty tmp
        jsr GetCharWidth
        clc
        adc boldOn
        adc r2L
        sta r2L
        bcc :+
        inc r2H
:       ldy tmp
@next:  iny
        bne @ch
@end:   rts

BarH:           .byte 16, 8, 0  ; the toolbar's height by tbMode
MonNames:       .byte "JanFebMarAprMayJunJulAugSepOctNovDec"
MonLo:          .repeat 12, i
                .byte <(MonNames + 3 * i)
                .endrepeat
MonHi:          .repeat 12, i
                .byte >(MonNames + 3 * i)
                .endrepeat

Name0:  .byte "GeoUltra", 0
Name1:  .byte "GEOS classic", 0
Name2:  .byte "Flat", 0
Name3:  .byte "Detailed", 0
Name4:  .byte "Night", 0
Name5:  .byte "Mono", 0
NameLo: .byte <Name0, <Name1, <Name2, <Name3, <Name4, <Name5
NameHi: .byte >Name0, >Name1, >Name2, >Name3, >Name4, >Name5

        .segment "DATA"

; The theme record (THM_LEN bytes, in Themes' order; themefile.s): at
; the start GeoUltra's, the built-in default
tMenu:          .byte 1
tSide:          .byte 0
tHead:          .byte 0
tTitle:         .byte 0
tRows:          .byte 9
tCols:          .byte 0
tIcons:         .byte 0
tSel:           .byte 0
tCur:           .byte 0
tScroll:        .byte 0
tStatus:        .byte 0
cBorder:        .byte 15
cDesk:          .byte $BF
cMenu:          .byte $BF
cSide:          .byte $BF
cHead:          .byte $1E
cTitle:         .byte $BF
cIcon:          .byte 6
cSel:           .byte $14
cAccent:        .byte 6
cStatus:        .byte $1C
cToolbar:       .byte $BF         ; (the toolbar's row: ink << 4 | paper)
cProgs:         .byte $BF         ; programs' colours (themefile.s: to the
                                  ; kernal's progColours and screencolors)

; Derived (Derive)
themeNo:        .byte 0
cIconP:         .byte 0         ; icon ink on the desk's paper
cSideIconP:     .byte 0         ; and on the sidebar's
cAccentP:       .byte 0
cSideAccentP:   .byte 0
cHeadP:         .byte 0         ; the colours painted for headings, the
cTitleP:        .byte 0         ; title bar and the status line (swapped
cStatusP:       .byte 0         ; where drawn inverted)
sideW:          .byte 80        ; the sidebar's width (its line at sideW - 1)
listL:          .byte 80        ; the list area's left edge
ejectCard:      .byte 8         ; the eject icon's card in the sidebar
iconCard:       .byte 11        ; the list's icon column (a card)
nameX:          .byte 98        ; the list's names
sideTx:         .byte 19        ; the sidebar's text
pathY:          .byte 31        ; the path line's baseline
listTop:        .byte 35        ; the first row's top
rowH:           .byte 9
rows:           .byte 17        ; whole rows that fit
bottom:         .byte 191       ; the last pixel row above the status line
stY0:           .byte 35        ; the scroll strip
stY1:           .byte 190
trackTop:       .byte 44        ; its thumb's track
trackBot:       .byte 181
trackH:         .byte 137
boldOn:         .byte 0         ; TextWidth: 1 with SET_BOLD
origBorder:     .byte 0
bordSaved:      .byte 0
lastMin:        .byte $FF
clockX:         .word 200       ; the clock text's left edge (tooldraw.s,
                                ; ClockDraw; 200 before a first text)
clockMode:      .byte 0         ; the clock: 0 24-hour, 1 12-hour, 2 off
viewMode:       .byte 0         ; the list: 0 list, 1 icons, 2 detailed
tbMode:         .byte TB_TWO    ; the toolbar (TB_*; a view option)
topY:           .byte 32        ; the content's top (under the toolbar)
titleEnd:       .byte 40        ; the title bar's end (topY + 8)
stripL:         .word STRIP_LEFT ; the list's scroll strip (its left edge),
listR:          .word STRIP_LEFT - 3 ; the list's right edge,
paneR:          .word SCREEN_RIGHT ; the list area's (with the strip) right
                                ; edge: the whole list now; a pane's with
                                ; two panes (DESKTOP.md, P4)
at:             .byte 0
tmp:            .byte 0
px0:            .byte 0
px1:            .byte 0
py0:            .byte 0
py1:            .byte 0
pcol:           .byte 0

        .segment "BSS"

shadow:         .res 1000       ; the desktop's colours (Paint)
