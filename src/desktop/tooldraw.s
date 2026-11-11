; GeoUltra Desktop: the toolbar's drawing (overlay 5, ovl.s; split
; from toolbar.s on 2026-11-11 to give the core room). A button's
; bitmap is made when drawn: the frame template with the icon shifted
; into its middle (two lines), or the icon alone (one line). Called only
; from the core's Draw (an overlay calls no other overlay). Own design
; and drawings (the approved mock-up's icons).

        .include "geos.inc"
        .include "desktop.inc"

        .import tbMode, topY, Cards
        .export Ov_ToolDraw
Ov_ToolDraw = ToolDraw

FRAME_ROWS      = 14
FLAT_ROWS       = 8
ICON_ROW        = 3             ; the icon's first row in a frame
DOT_ROWS        = 4             ; a flat group line: 4 dots, 2 px apart

        .segment "OV5"

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

GROUPS_N = 4
GroupLine:      .byte 11, 16, 21        ; the gaps' cards (flat: dots)

; The frame (16 x 14: rounded corners, a shadow right and below).
Frame:  .byte $00, $00, $7F, $F8, $80, $06, $80, $06, $80, $06, $80, $06
        .byte $80, $06, $80, $06, $80, $06, $80, $06, $80, $06, $80, $06
        .byte $7F, $FA, $7F, $FE

; The icons, 8 x 8, rows top to bottom (the approved mock-up).
Icons:  .byte $00, $20, $60, $FE, $60, $20, $00, $00    ; back
        .byte $00, $08, $0C, $FE, $0C, $08, $00, $00    ; forward
        .byte $10, $38, $7C, $FE, $38, $38, $38, $00    ; up
        .byte $06, $0C, $0C, $18, $30, $30, $60, $00    ; root "/"
        .byte $10, $38, $7C, $FE, $44, $54, $7C, $00    ; home
        .byte $FE, $00, $10, $38, $7C, $10, $10, $00    ; top
        .byte $10, $10, $7C, $38, $10, $00, $FE, $00    ; end
        .byte $EE, $EE, $EE, $00, $EE, $EE, $EE, $00    ; view
        .byte $3A, $46, $8E, $80, $82, $44, $38, $00    ; refresh
        .byte $70, $8F, $81, $91, $B9, $91, $FF, $00    ; new folder
        .byte $38, $54, $82, $92, $92, $54, $38, $00    ; info
        .byte $AA, $01, $80, $01, $80, $01, $55, $00    ; select all
        .byte $F0, $9E, $92, $92, $F2, $12, $1E, $00    ; copy
        .byte $38, $EE, $82, $BA, $82, $BA, $FE, $00    ; paste
        .byte $38, $FE, $44, $54, $54, $54, $38, $00    ; delete
        .assert * - Icons = 8 * TB_BUTTONS, error, "an icon per button"


; Scratch while drawing (overlay data: fetched anew with the overlay).
bits:           .res 1 + 2 * FRAME_ROWS ; a button's compacted bitmap
shift:          .res 2
at:             .res 1
