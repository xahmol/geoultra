; GeoUltra Desktop: the toolbar's drawing and the clock (overlay 5,
; ovl.s; the clock moved here from theme.s on 2026-11-12 for room; split
; from toolbar.s on 2026-11-11 to give the core room). A button's
; bitmap is made when drawn: the frame template with the icon shifted
; into its middle (two lines), or the icon alone (one line). Called only
; from the core's Draw (an overlay calls no other overlay). Own design
; and drawings (the approved mock-up's icons).

        .include "geos.inc"
        .include "desktop.inc"

        .import tbMode, topY, Cards
        .import bigOk, tMenu, clockMode, lastMin, clockX, MonLo, MonHi, TextWidth
        .import spShown, spX, QPut, QDraw0      ; (spool.s: the print queue)
        .export Ov_ToolDraw, Ov_BigInit, Ov_ClockDraw
Ov_ToolDraw = ToolDraw
Ov_BigInit = BigInit
Ov_ClockDraw = ClockDraw

FRAME_ROWS      = 14
FLAT_ROWS       = 8
ICON_ROW        = 3             ; the icon's first row in a frame
DOT_ROWS        = 4             ; a flat group line: 4 dots, 2 px apart

        .segment "OV5"

; BigInit (desktop.s, at the start): the icon view's generic 24 x 21
; icons (build/gen/bigicons.inc, tools/mkbigicons.py) into the REU,
; where iconview.s fetches them (bank 6 from $7000: between the overlays
; and the history); bigOk set. Here, not in the core: they cost it
; nothing.
BigInit:
        lda #<BigIcons
        sta r0L
        lda #>BigIcons
        sta r0H
        lda #0
        sta r1L
        sta r2L
        lda #BIG_PAGE
        sta r1H
        lda #>(BIG_N * 64)
        sta r2H
        lda #<(BIG_N * 64)
        sta r2L
        lda #BIG_BANK
        sta r3L
        jsr StashRAM
        lda #1
        sta bigOk
        rts

; ToolDraw: the toolbar drawn (nothing when it is off): its area
; cleared, each button, the line under two-line buttons or the dotted
; lines between the groups of flat ones. Destroys A, X, Y, r0-r4, r11.
ToolDraw:
        lda tbMode
        cmp #TB_OFF
        bne :+
        rts
:       lda #0
        jsr SetPattern
        lda #TB_Y
        sta r2L
        ldx topY
        dex
        stx r2H
        jsr Across
        jsr Rectangle
        lda #0
        sta at
@button:
        jsr Make
        ldx at
        lda Cards,x
        sta r1L
        lda #TB_Y
        sta r1H
        lda #<bits
        sta r0L
        lda #>bits
        sta r0H
        lda #2
        sta r2L
        lda #FRAME_ROWS
        ldx tbMode
        beq :+
        lda #FLAT_ROWS
:       sta r2H
        jsr BitmapUp
        inc at
        lda at
        cmp #TB_BUTTONS
        bcc @button
        lda tbMode              ; two lines: a line under the buttons
        bne @dots
        ldx topY
        dex
        stx r11L
        jsr Across
        lda #$FF
        jmp HorizontalLine
@dots:  ldx #GROUPS_N - 2       ; one line: dots between the groups
@group: stx at
        lda GroupLine,x         ; (x: a card's start + 4, in the gap)
        asl a
        asl a
        asl a
        clc
        adc #4
        sta r3L
        lda #0
        sta r3H
        lda #TB_Y
        sta r11L
@dot:   jsr DrawPoint1
        lda r11L
        clc
        adc #2
        sta r11L
        cmp #TB_Y + 2 * DOT_ROWS
        bcc @dot
        ldx at
        dex
        bpl @group
        rts

; DrawPoint1: a black point at r3 (x), r11L (y). Keeps r3, r11L.
DrawPoint1:
        sec                     ; (C set: drawn; N clear: in black)
        lda #0
        jmp DrawPoint

; Make: bits = button `at`'s compacted bitmap: two lines, the frame
; template and the icon 3 pixels in (rows 3-10); one line, the icon
; alone, 4 pixels in. Destroys A, X, Y, r4.
Make:   lda #$80 + 2 * FRAME_ROWS  ; (a unique packet: its length)
        ldx tbMode
        beq :+
        lda #$80 + 2 * FLAT_ROWS
:       sta bits
        ldx #2 * FRAME_ROWS - 1 ; the template (or zeros)
@t:     lda Frame,x
        ldy tbMode
        beq :+
        lda #0
:       sta bits + 1,x
        dex
        bpl @t
        lda at                  ; r4 = the icon: Icons + at * 8
        asl a
        asl a
        asl a
        clc
        adc #<Icons
        sta r4L
        lda #>Icons
        adc #0
        sta r4H
        ldy #0
        ldx #2 * ICON_ROW       ; its first row's left byte in the frame
        lda tbMode
        beq @row
        ldx #0
@row:   lda (r4),y
        sta shift
        lda #0
        sta shift + 1
        lda tbMode              ; framed: 3 pixels right, flat: 4
        beq :+
        lsr shift
        ror shift + 1
:       lsr shift
        ror shift + 1
        lsr shift
        ror shift + 1
        lsr shift
        ror shift + 1
        lda shift
        ora bits + 1,x
        sta bits + 1,x
        lda shift + 1
        ora bits + 2,x
        sta bits + 2,x
        inx
        inx
        iny
        cpy #8
        bcc @row
        rts

; Across: r3-r4 = x 0 to 319.
Across: lda #0
        sta r3L
        sta r3H
        lda #<SCREEN_RIGHT
        sta r4L
        lda #>SCREEN_RIGHT
        sta r4H
        rts

GROUPS_N = 5
GroupLine:      .byte 9, 14, 21, 34     ; the gaps' cards (flat: dots)

; The frame (16 x 14: rounded corners, a shadow right and below).
Frame:  .byte $00, $00, $7F, $F8, $80, $06, $80, $06, $80, $06, $80, $06
        .byte $80, $06, $80, $06, $80, $06, $80, $06, $80, $06, $80, $06
        .byte $7F, $FA, $7F, $FE

; The icons, 8 x 8, rows top to bottom (the approved mock-up).
Icons:  .byte $00, $20, $60, $FE, $60, $20, $00, $00    ; back
        .byte $00, $08, $0C, $FE, $0C, $08, $00, $00    ; forward
        .byte $10, $38, $7C, $FE, $38, $38, $38, $00    ; up
        .byte $06, $0C, $0C, $18, $30, $30, $60, $00    ; root "/"
        .byte $FE, $00, $10, $38, $7C, $10, $10, $00    ; top
        .byte $10, $10, $7C, $38, $10, $00, $FE, $00    ; end
        .byte $EE, $EE, $EE, $00, $EE, $EE, $EE, $00    ; view
        .byte $FF, $99, $99, $99, $99, $99, $FF, $00    ; two panes
        .byte $3A, $46, $8E, $80, $82, $44, $38, $00    ; refresh
        .byte $70, $8F, $81, $91, $B9, $91, $FF, $00    ; new folder
        .byte $38, $54, $82, $92, $92, $54, $38, $00    ; info
        .byte $AA, $01, $80, $01, $80, $01, $55, $00    ; select all
        .byte $F0, $9E, $92, $92, $F2, $12, $1E, $00    ; copy
        .byte $38, $EE, $82, $BA, $82, $BA, $FE, $00    ; paste
        .byte $38, $FE, $44, $54, $54, $54, $38, $00    ; delete
        .byte $60, $FE, $60, $00, $0C, $FE, $0C, $00    ; settings: two sliders
        .byte $00, $40, $20, $10, $20, $4E, $00, $00    ; gush: a ">_" prompt
        .assert * - Icons = 8 * TB_BUTTONS, error, "an icon per button"


; --- The clock (moved from theme.s; called from ClockTick, Draw and the
; clock menu, all in MainLoop) ----------------------------------------

; ClockDraw: "Wed 11 Nov 2026  21:42" right in the menu bar (menubar
; style clock; the user's format, 2026-11-11), from GEOS's date and time
; (years 2000-2099). Destroys r0-r15's usual ones.
ClockDraw:
        lda tMenu
        cmp #ST_CLOCK
        beq :+
        jmp QDraw0              ; (no clock: the print queue's indicator)
:       lda minutes
        sta lastMin
        jsr ClockClear
        lda clockMode
        cmp #CLOCK_OFF
        bne :+
        jmp QPut
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
        sta clockX              ; (ClockClear's left edge next time)
        lda #>316
        sbc r2H
        sta r11H
        sta clockX+1
        lda #10
        sta r1H
        lda #<clockText
        sta r0L
        lda #>clockText
        sta r0H
        jsr PutString
        jmp QPut                ; (the indicator left of it: its place was
                                ; cleared with the clock's)
CLOCK_X0        = 200           ; the clear's left edge before a first text
CLOCK_TEXT_LEN  = 26            ; "Wed 11 Nov 2026  12:42 pm" and its zero

; ClockClear: the clock's place in the menu bar cleared, from the last
; text's left edge (clockX: a wider text starts left of CLOCK_X0) to the
; edge.
ClockClear:
        lda #0
        jsr SetPattern
        lda #1
        sta r2L
        lda #12
        sta r2H
        lda clockX
        sta r3L
        lda clockX+1
        sta r3H
        lda spShown             ; the print queue's indicator too (left of
        beq :+                  ; the clock, spool.s)
        lda spX
        sta r3L
        lda spX+1
        sta r3H
:
        lda #<318
        sta r4L
        lda #>318
        sta r4H
        jmp Rectangle

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

MonthOff:       .byte 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4
DayNames:       .byte "SunMonTueWedThuFriSat"
DayLo:          .repeat 7, i
                .byte <(DayNames + 3 * i)
                .endrepeat
DayHi:          .repeat 7, i
                .byte >(DayNames + 3 * i)
                .endrepeat

.include "bigicons.inc"

; Scratch while drawing (overlay data: fetched anew with the overlay).
bits:           .res 1 + 2 * FRAME_ROWS ; a button's compacted bitmap
shift:          .res 2
at:             .res 1
tmp:            .res 1
clockText:      .res CLOCK_TEXT_LEN
