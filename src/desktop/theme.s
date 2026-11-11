; GeoUltra Desktop: themes (docs/DESKTOP.md, "Look and themes", step
; D7a). A theme is a style byte per design element and a colour byte per
; colour (THM_LEN bytes); the six built-in themes are from the approved
; mock-up (2026-11-06). ThemeSet copies one into the record and derives
; the layout the drawing routines use (sidebar width, title bar, row
; height, list top, rows, status line, scroll track). Colours: every
; cell the desktop paints goes to the colour matrix and to a shadow copy
; (Paint); dialogs (Dialog), the desktop's menus (MenuNeutral, from their
; DYN_SUB_MENU routines), desk accessories and programs (Neutral) get
; GEOS's own colours, and Recover (RecoverVector) gives a rectangle back
; its bitmap and its shadow colours. The clock in the menu bar is drawn
; by ClockDraw, kept current by ClockTick (appMain). Own design and code.

        .include "geos.inc"
        .include "desktop.inc"

        .export ThemeSet, ThemeByName, ThemeName, themeNo, ThemePal
        .export tMenu, tSide, tHead, tTitle, tRows, tCols, tIcons, tSel, tCur, tScroll, tStatus
        .export cDesk, cMenu, cSide, cHead, cTitle, cSel, cStatus, cHeadP
        .export cIconP, cSideIconP, cAccentP, cSideAccentP
        .export sideW, listL, ejectCard, pathY, listTop, rowH, rows, bottom
        .export trackTop, trackBot, trackH, iconCard, nameX, sideTx, stY0, stY1
        .export Paint, px0, px1, py0, py1, pcol, PaintAll, PaintSide, PaintList
        .export Neutral, Dialog, MenuNeutral, Recover, ClockDraw, ClockTick
        .export TextWidth, boldOn, clockMode, viewMode, MonthName, Derive
        .import BusyPause, BusyResume

CPU_PORT        = $01
RAM_IO          = $35
VIC_BORDER      = $D020
THM_STYLES      = 11            ; style bytes, then colour bytes
THM_LEN         = 21
STRIP_TOP_PAD   = 9             ; an arrow box's height (8) and a line

        .segment "ZEROPAGE"

cp:             .res 2          ; a colour matrix row (Paint)
shp:            .res 2          ; its shadow row

        .segment "CODE"

; ThemeSet: built-in theme A (0 to THEMES_N - 1) into the record, its
; layout derived, the border set. Destroys A, X, Y.
ThemeSet:
        sta themeNo
        tax                     ; its bytes: A * THM_LEN
        lda #0
@mul:   dex
        bmi @copy
        clc
        adc #THM_LEN
        bne @mul
@copy:  tax
        ldy #0
@b:     lda Themes,x
        sta tMenu,y
        inx
        iny
        cpy #THM_LEN
        bcc @b
        lda #VIEW_LIST          ; the theme's view (its columns style)
        ldx tCols
        beq :+
        lda #VIEW_DETAILED
:       sta viewMode
        jmp Derive

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
        lda #23                 ; the path line's baseline: under the title
        ldx tTitle
        cpx #ST_NONE
        beq :+
        lda #31
:       sta pathY
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
        cpx #1                  ; (solid)
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

; ThemeByName: the built-in theme whose name is at r0 (any case, ended
; by 0, CR or LF) set; C set when there is none.
ThemeByName:
        lda #0
        sta at
@theme: lda at
        cmp #THEMES_N
        bcs @none
        jsr ThemeName           ; r1 = its name
        ldy #0
@ch:    lda (r1),y
        beq @end
        jsr Lower
        sta tmp
        lda (r0),y
        jsr Lower
        cmp tmp
        bne @next
        iny
        bne @ch
@end:   lda (r0),y              ; (the given name must end here too)
        beq @yes
        cmp #CR
        beq @yes
        cmp #10
        beq @yes
@next:  inc at
        bne @theme
@none:  sec
        rts
@yes:   lda at
        jsr ThemeSet
        clc
        rts

; Lower: A in lower case (letters only).
Lower:  cmp #'A'
        bcc @end
        cmp #'Z' + 1
        bcs @end
        ora #$20
@end:   rts

; ThemePal: r1 = built-in theme A's palette (48 bytes), C clear; C set
; when it has none (GeoUltra: the C64's own). Destroys X.
ThemePal:
        tax
        lda PalHi,x
        beq @none
        sta r1H
        lda PalLo,x
        sta r1L
        clc
        rts
@none:  sec
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
        jsr PaintSide
        jmp PaintList

; PaintSide: the sidebar's cells (below the menu bar, to the bottom).
PaintSide:
        lda #0
        sta px0
        lda sideW
        jsr Cells
        sec
        sbc #1
        sta px1
        lda #2
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
        lda #39
        sta px1
        lda #2
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
        lda #2
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

; NeutralCells: cells px0-px1 by py0-py1 in GEOS's colours (the matrix
; only: the shadow keeps the desktop's).
NeutralCells:
        ldx py0
@row:   jsr RowAt
        ldy px0
@cell:  lda screencolors
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

; Dialog: DoDlgBox (r0 = the dialog) with GEOS's colours under it (a
; DEF_DB_POS box and its shadow); the desktop's back afterwards. r0L =
; DoDlgBox's result, as from DoDlgBox.
Dialog: lda #DLG_X0
        sta px0
        lda #DLG_X1
        sta px1
        lda #DLG_Y0
        sta py0
        lda #DLG_Y1
        sta py1
        jsr NeutralCells
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
; gets GEOS's colours under it before GEOS draws it; Recover gives the
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
        jmp NeutralCells

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

; ClockTick (appMain): the clock drawn again when the minute changed.
ClockTick:
        lda minutes
        cmp lastMin
        bne ClockDraw
        rts

; ClockDraw: "Wed 11 Nov 2026  21:42" right in the menu bar (menubar
; style clock; the user's format, 2026-11-11), from GEOS's date and time
; (years 2000-2099). Destroys r0-r15's usual ones.
ClockDraw:
        lda tMenu
        cmp #ST_CLOCK
        beq :+
        rts
:       lda minutes
        sta lastMin
        jsr ClockClear
        lda clockMode
        cmp #CLOCK_OFF
        bne :+
        rts
:       jsr Weekday             ; the text
        tax
        ldy #0
        lda DayLo,x
        sta r1L
        lda DayHi,x
        sta r1H
        jsr Copy3
        lda #' '
        sta clockText,y
        iny
        lda day
        jsr Dec2
        lda #' '
        sta clockText,y
        iny
        ldx month
        dex
        lda MonLo,x
        sta r1L
        lda MonHi,x
        sta r1H
        jsr Copy3
        lda #' '
        sta clockText,y
        iny
        lda #'2'                ; the year: 20yy
        sta clockText,y
        iny
        lda #'0'
        sta clockText,y
        iny
        lda year
        jsr Dec2z
        lda #' '
        sta clockText,y
        iny
        sta clockText,y
        iny
        lda clockMode           ; 12-hour: "9:42 pm", 0 and 12 as 12
        bne @h12
        lda hour
        jsr Dec2z
        jsr Minutes
        jmp @end
@h12:   lda hour
        sec
        sbc #12
        bcs :+
        adc #12                 ; (am: the hour as it is)
:       bne :+
        lda #12
:       jsr Dec2
        jsr Minutes
        ldx #'a'
        lda hour
        cmp #12
        bcc :+
        ldx #'p'
:       lda #' '
        sta clockText,y
        iny
        txa
        sta clockText,y
        iny
        lda #'m'
        sta clockText,y
        iny
@end:   lda #0
        sta clockText,y
        lda #<clockText
        sta r0L
        lda #>clockText
        sta r0H
        jsr TextWidth
        lda #<316               ; right-aligned at x 316
        sec
        sbc r2L
        sta r11L
        lda #>316
        sbc r2H
        sta r11H
        lda #10
        sta r1H
        lda #<clockText
        sta r0L
        lda #>clockText
        sta r0H
        jmp PutString
CLOCK_X0        = 200

; ClockClear: the clock's place in the menu bar cleared (x CLOCK_X0 to
; the edge).
ClockClear:
        lda #0
        jsr SetPattern
        lda #1
        sta r2L
        lda #12
        sta r2H
        lda #CLOCK_X0
        sta r3L
        lda #0
        sta r3H
        lda #<318
        sta r4L
        lda #>318
        sta r4H
        jmp Rectangle

; MonthName: r1 = month A's (1-12) three letters. Destroys X.
MonthName:
        tax
        lda MonLo-1,x
        sta r1L
        lda MonHi-1,x
        sta r1H
        rts

; Minutes: ":" and the minutes (two digits) at clockText + Y.
Minutes:
        lda #':'
        sta clockText,y
        iny
        lda minutes
        jmp Dec2z

; Copy3: three characters from r1 to clockText + Y.
Copy3:  ldx #0
@c:     sty tmp
        txa
        tay
        lda (r1),y
        ldy tmp
        sta clockText,y
        iny
        inx
        cpx #3
        bcc @c
        rts

; Dec2: A (0-99) in decimal at clockText + Y, without a leading zero;
; Dec2z with one.
Dec2:   cmp #10
        bcs Dec2z
        ora #'0'
        sta clockText,y
        iny
        rts
Dec2z:  ldx #'0'
@t:     cmp #10
        bcc :+
        sbc #10
        inx
        bne @t
:       pha
        txa
        sta clockText,y
        iny
        pla
        ora #'0'
        sta clockText,y
        iny
        rts

; Weekday: A = the day of the week of GEOS's date (0 Sunday), for 2000
; to 2099: (y + y / 4 + Month[m] + d) mod 7 with y one less in January
; and February (Sakamoto's method; 2000's own offset folds to 0, 1999's
; to 5 when y would go below 0).
Weekday:
        lda year
        ldx month
        cpx #3
        bcs @y
        sec
        sbc #1
        bcs @y
        lda #5                  ; (January or February 2000: 1999)
        bne @md
@y:     sta tmp
        lsr a
        lsr a
        clc
        adc tmp
@md:    ldx month
        clc
        adc MonthOff-1,x
        clc
        adc day
@mod:   cmp #7
        bcc @end
        sbc #7
        bcs @mod
@end:   rts

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

MonthOff:       .byte 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4
DayNames:       .byte "SunMonTueWedThuFriSat"
MonNames:       .byte "JanFebMarAprMayJunJulAugSepOctNovDec"
DayLo:          .repeat 7, i
                .byte <(DayNames + 3 * i)
                .endrepeat
DayHi:          .repeat 7, i
                .byte >(DayNames + 3 * i)
                .endrepeat
MonLo:          .repeat 12, i
                .byte <(MonNames + 3 * i)
                .endrepeat
MonHi:          .repeat 12, i
                .byte >(MonNames + 3 * i)
                .endrepeat

; The built-in themes (the mock-up, approved 2026-11-06). Styles:
; menubar (plain, clock), sidebar (wide, narrow), headings (inverted,
; band, underlined, plain), titlebar (stripes, solid, line, none), rows
; (9, 8), columns (name, detailed), icons (on, off), selection (invert,
; bar, frame), cursor (dotted, mark, underline), scrollbar (arrows,
; thin), status (on, off). Colours: border, desk, menu, side, heading,
; title (ink << 4 | paper), icon (ink), select (pair), accent (ink),
; status (pair). C64 colours: 0 black, 1 white, 3 cyan, 4 purple, 6
; blue, 7 yellow, 8 orange, 11 dark grey, 12 grey, 14 light blue, 15
; light grey.
Themes:
        ; GeoUltra (the default)
        .byte 1, 0, 0, 0, 9, 0, 0, 0, 0, 0, 0
        .byte 15, $BF, $BF, $BF, $1E, $BF, 6, $14, 6, $1C
        ; GEOS classic
        .byte 0, 0, 2, 0, 9, 0, 1, 0, 0, 0, 1
        .byte 1, $61, $61, $61, $61, $61, 6, $16, 6, $63
        ; Flat
        .byte 1, 0, 1, 1, 8, 0, 0, 1, 1, 1, 0
        .byte 15, $BF, $0F, $BF, $16, $1B, 11, $1E, 8, $1B
        ; Detailed
        .byte 1, 1, 0, 1, 9, 1, 0, 0, 2, 0, 0
        .byte 15, $0F, $0F, $BF, $1B, $1B, 11, $16, 6, $1C
        ; Night
        .byte 1, 0, 1, 2, 8, 0, 0, 1, 1, 1, 0
        .byte 11, $FB, $10, $F0, $03, $3B, 3, $07, 7, $30
        ; Mono
        .byte 0, 0, 3, 2, 9, 0, 1, 2, 2, 1, 1
        .byte 1, $01, $01, $01, $01, $01, 0, $01, 0, $01

; The built-in themes' palettes (user, 2026-11-11: GeoUltra keeps the
; C64's own, the others tuned freely in RGB): 16 RRGGBB triplets in
; the C64 colours' order; each colour keeps its character, as programs
; started from the desktop see the palette too.
PalLo:  .byte 0, <Pal1, <Pal2, <Pal3, <Pal4, <Pal5
PalHi:  .byte 0, >Pal1, >Pal2, >Pal3, >Pal4, >Pal5
Pal1:   ; GEOS classic
        .byte $00, $00, $00, $FF, $FF, $FF, $8D, $2F, $34, $A6, $DC, $E8
        .byte $98, $35, $A4, $4C, $B4, $42, $2A, $3A, $9E, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $4A, $4A, $4A
        .byte $7B, $7B, $7B, $9F, $EF, $93, $7A, $86, $E0, $B2, $B2, $B2
Pal2:   ; Flat
        .byte $1A, $1C, $20, $FF, $FF, $FF, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $2F, $6F, $D6, $EF, $EF, $5D
        .byte $F0, $8A, $24, $5B, $38, $00, $D1, $67, $6D, $3C, $40, $48
        .byte $9A, $A0, $A8, $9F, $EF, $93, $5B, $9B, $F0, $E6, $E8, $EB
Pal3:   ; Detailed
        .byte $20, $22, $26, $FF, $FF, $FF, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $33, $66, $CC, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $50, $55, $5C
        .byte $8A, $90, $98, $9F, $EF, $93, $6F, $95, $E0, $DC, $DF, $E3
Pal4:   ; Night
        .byte $12, $15, $1A, $E8, $EC, $F2, $8D, $2F, $34, $4F, $C7, $C2
        .byte $98, $35, $A4, $4C, $B4, $42, $2C, $29, $B1, $F2, $C9, $4C
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $23, $28, $30
        .byte $6B, $72, $80, $9F, $EF, $93, $6D, $6A, $EF, $C5, $CA, $D3
Pal5:   ; Mono
        .byte $10, $10, $10, $FA, $FA, $F5, $8D, $2F, $34, $6A, $D4, $CD
        .byte $98, $35, $A4, $4C, $B4, $42, $2C, $29, $B1, $EF, $EF, $5D
        .byte $98, $4E, $20, $5B, $38, $00, $D1, $67, $6D, $3A, $3A, $3A
        .byte $8C, $8C, $8C, $9F, $EF, $93, $6D, $6A, $EF, $D0, $D0, $D0

Name0:  .byte "GeoUltra", 0
Name1:  .byte "GEOS classic", 0
Name2:  .byte "Flat", 0
Name3:  .byte "Detailed", 0
Name4:  .byte "Night", 0
Name5:  .byte "Mono", 0
NameLo: .byte <Name0, <Name1, <Name2, <Name3, <Name4, <Name5
NameHi: .byte >Name0, >Name1, >Name2, >Name3, >Name4, >Name5

        .segment "DATA"

; The theme record (THM_LEN bytes, in Themes' order)
tMenu:          .byte 0
tSide:          .byte 0
tHead:          .byte 0
tTitle:         .byte 0
tRows:          .byte 0
tCols:          .byte 0
tIcons:         .byte 0
tSel:           .byte 0
tCur:           .byte 0
tScroll:        .byte 0
tStatus:        .byte 0
cBorder:        .byte 0
cDesk:          .byte 0
cMenu:          .byte 0
cSide:          .byte 0
cHead:          .byte 0
cTitle:         .byte 0
cIcon:          .byte 0
cSel:           .byte 0
cAccent:        .byte 0
cStatus:        .byte 0

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
clockMode:      .byte 0         ; the clock: 0 24-hour, 1 12-hour, 2 off
viewMode:       .byte 0         ; the list: 0 list, 1 icons, 2 detailed
at:             .byte 0
tmp:            .byte 0
px0:            .byte 0
px1:            .byte 0
py0:            .byte 0
py1:            .byte 0
pcol:           .byte 0

        .segment "BSS"

shadow:         .res 1000       ; the desktop's colours (Paint)
clockText:      .res 24
