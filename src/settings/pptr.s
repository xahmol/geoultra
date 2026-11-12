; GeoUltra Settings: the Pointer page (overlay 2, ovl.s; docs/SETTINGS.md,
; "Pages"): the mouse pointer's four designs (tools/mkpointers.py, the
; kernal's module 86) as one choice row over SETTINGS.INI's [system]
; pointer= (read at every start), each with its picture under it. A
; choice is also applied at once (FE_POINTER). Own design and code.

        .include "geos.inc"
        .include "engine.inc"
        .include "settings.inc"

        .import ChoiceDraw, ChoicePress, FileEngine, sel
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
        beq @end
        sta r2L                 ; (the option's index is the design)
        lda #FE_POINTER
        jmp FileEngine
@end:   rts

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
NOTE_Y          = PIC_Y + 21 + 22

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

        .include "pointers.inc"

; Scratch (overlay data: fetched anew with the overlay)
at:             .byte 0
before:         .byte 0
Pic:            .res 64
