; GeoUltra Settings: the Pointer page (overlay 2, ovl.s; docs/SETTINGS.md,
; "Pages"): the mouse pointer's four designs (tools/mkpointers.py, the
; kernal's module 86) as one choice row over SETTINGS.INI's [system]
; pointer= (read at every start), each with its picture under it, and
; its colour (pointercolour=, 0-15, with - and +; the user, 2026-11-12,
; after GeoDesk64). Both are also applied at once (FE_POINTER). Own
; design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress, FileEngine, sel, ButtonDraw, OnButton
        .import IniFind, IniSet, dirty, NoRoom
        .import ColourNames     ; (tdef.s: the theme files' names)
        .export Ov_PtrDraw, Ov_PtrPress

        .segment "OV2"

; Ov_PtrDraw: the row, the four pictures, the note.
Ov_PtrDraw:
        lda #<Rows
        ldx #>Rows
        jsr ChoiceDraw
        lda #0
        sta at
@pic:   ldx at                  ; picture n: a compacted bitmap made from
        jsr Picture             ; its 63 bytes (Pic)
        lda #<Pic
        sta r0L
        lda #>Pic
        sta r0H
        ldx at
        lda Card,x
        sta r1L
        lda #PIC_Y
        sta r1H
        lda #3
        sta r2L
        lda #21
        sta r2H
        jsr BitmapUp
        inc at
        lda at
        cmp #POINTERS_N
        bcc @pic
        jsr ReadColour          ; the colour row: label, buttons, name
        lda #<LColour
        sta r0L
        lda #>LColour
        sta r0H
        lda #<X0
        sta r11L
        lda #>X0
        sta r11H
        lda #COL_Y
        sta r1H
        jsr PutString
        lda #<Minus
        ldx #>Minus
        jsr ButtonDraw
        lda #<Plus
        ldx #>Plus
        jsr ButtonDraw
        jsr ColourDraw
        lda #<Note
        sta r0L
        lda #>Note
        sta r0H
        lda #<X0
        sta r11L
        lda #>X0
        sta r11H
        lda #NOTE_Y
        sta r1H
        jmp PutString

; Ov_PtrPress: a click on the row; a new design applied at once.
Ov_PtrPress:
        lda sel
        sta before
        lda #<Rows
        ldx #>Rows
        jsr ChoicePress
        lda sel
        cmp before
        beq @col
        sta r2L                 ; (the option's index is the design)
        lda #$FF                ; (its colour as it is)
        sta r2H
        lda #FE_POINTER
        jmp FileEngine
@col:   lda #<Minus             ; the colour's - and +
        ldx #>Minus
        jsr OnButton
        bcs :+
        lda colour
        sec
        sbc #1
        jmp NewColour
:       lda #<Plus
        ldx #>Plus
        jsr OnButton
        bcc :+
        rts
:       lda colour
        clc
        adc #1
; NewColour: colour A (0-15, wrapping) for the pointer: pointercolour=
; in the text, its name drawn, applied at once (FE_POINTER).
NewColour:
        and #$0F
        sta colour
        jsr ColourKey
        ldx #0                  ; its digits as the value
        lda colour
        cmp #10
        bcc :+
        lda #'1'
        sta buf
        inx
        lda colour
        sec
        sbc #10
:       ora #'0'
        sta buf,x
        lda #0
        sta buf + 1,x
        lda #<buf
        sta r2L
        lda #>buf
        sta r2H
        jsr IniSet
        bcc :+
        jmp NoRoom
:       lda #1
        sta dirty
        jsr ColourDraw
        lda #$FF                ; (the design as it is)
        sta r2L
        lda colour
        sta r2H
        lda #FE_POINTER
        jmp FileEngine

; ReadColour: colour = pointercolour= (one or two digits; none or
; another: 6, blue, the kernal's).
ReadColour:
        lda #DEFAULT_COLOUR
        sta colour
        jsr ColourKey
        jsr IniFind             ; (r2 the value, A its length)
        bcs @end
        tax
        ldy #0
        lda (r2),y
        sec
        sbc #'0'
        cmp #10
        bcs @end
        cpx #2
        bcc @one
        pha                     ; two digits: 10 + the second (10-15)
        iny
        lda (r2),y
        sec
        sbc #'0'
        cmp #6
        pla
        bcs @end
        lda (r2),y
        sec
        sbc #'0' - 10
@one:   sta colour
@end:   rts

; ColourDraw: the colour's name between its buttons.
ColourDraw:
        lda #0
        jsr SetPattern
        lda #COL_Y - 9
        sta r2L
        lda #COL_Y + 2
        sta r2H
        lda #<COLNAME_X
        sta r3L
        lda #>COLNAME_X
        sta r3H
        lda #<(PLUS_X - 2)
        sta r4L
        lda #>(PLUS_X - 2)
        sta r4H
        jsr Rectangle
        lda #<ColourNames       ; its name: the colour-th of the names
        sta r0L
        lda #>ColourNames
        sta r0H
        ldx colour
@skip:  dex
        bmi @draw
        ldy #0
@ch:    lda (r0),y
        iny
        cmp #0
        bne @ch
        tya
        clc
        adc r0L
        sta r0L
        bcc @skip
        inc r0H
        bne @skip
@draw:  lda #<COLNAME_X
        sta r11L
        lda #>COLNAME_X
        sta r11H
        lda #COL_Y
        sta r1H
        jmp PutString

; ColourKey: r0 = "system", r1 = "pointercolour".
ColourKey:
        lda #<SSystem
        sta r0L
        lda #>SSystem
        sta r0H
        lda #<KColour
        sta r1L
        lda #>KColour
        sta r1H
        rts

; Picture: Pic = design X's 63 bytes as a compacted bitmap (one run of
; 63 bytes as they are).
Picture:
        lda #<Pointers          ; r0 = Pointers + X * 63
        sta r0L
        lda #>Pointers
        sta r0H
@add:   dex
        bmi @copy
        lda r0L
        clc
        adc #63
        sta r0L
        bcc @add
        inc r0H
        bne @add
@copy:  lda #$80 + 63
        sta Pic
        ldy #62
@b:     lda (r0),y
        sta Pic + 1,y
        dey
        bpl @b
        rts

X0              = PAGE_LEFT + 10 ; the four options' columns, 56 apart
STEP            = 56
Y0              = PAGE_TOP + 20 ; the row's baseline
PIC_Y           = Y0 + 10       ; the pictures' top
COL_Y           = PIC_Y + 21 + 20 ; the colour row's baseline
MINUS_X         = X0 + 50
COLNAME_X       = MINUS_X + 18
PLUS_X          = MINUS_X + 92
NOTE_Y          = COL_Y + 22
DEFAULT_COLOUR  = 6             ; blue (load.s)

Card:   .byte X0 / 8 + 1, (X0 + STEP) / 8 + 1, (X0 + 2 * STEP) / 8 + 1
        .byte (X0 + 3 * STEP) / 8 + 1

Rows:   .byte 1
        .byte Y0
        .word 0, SSystem, KPointer      ; (no label: the options say it)
        .byte POINTERS_N, 0
        .word X0, T0, V0
        .word X0 + STEP, T1, V1
        .word X0 + 2 * STEP, T2, V2
        .word X0 + 3 * STEP, T3, V3

SSystem:        .byte "system", 0
KPointer:       .byte "pointer", 0
T0:             .byte "classic", 0
T1:             .byte "large", 0
T2:             .byte "hand", 0
T3:             .byte "cross", 0
V0:             .byte "0", 0
V1:             .byte "1", 0
V2:             .byte "2", 0
V3:             .byte "3", 0
Note:           .byte "In use at once, and at every start.", 0
LColour:        .byte "Colour", 0
KColour:        .byte "pointercolour", 0
TMinus:         .byte "-", 0
TPlus:          .byte "+", 0
Minus:  .word MINUS_X
        .byte COL_Y - 9, 14
        .word TMinus
Plus:   .word PLUS_X
        .byte COL_Y - 9, 14
        .word TPlus


        .include "pointers.inc"

; Scratch (overlay data: fetched anew with the overlay)
at:             .byte 0
before:         .byte 0
colour:         .byte 0         ; the pointer's colour (0-15)
buf:            .res 4          ; its value's digits
Pic:            .res 64
