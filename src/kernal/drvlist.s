; File boxes: the drive letters (overlay module 87; docs/design/DESIGN.md, the
; user's decisions 2026-11-13): in a DBGETFILES box that asks for
; MegaPatch 3's drive button (DBSETDRVICON, bit 6 of the command; GEOS
; 2.0's applications keep their own document drive and set it again
; after the box, so a switch made in it is lost: geoWrite 2.1's
; openDocument, mist64/geowrite; found by the user's test), the letters A-D
; of the drives that have an image as small framed buttons in the box's
; bottom strip, left of the scroll arrows, the current drive inverted. A
; click ends the dialog with $88 + the drive's index (MegaPatch 3's
; answer for its drive icons), and the application switches its own
; document drive and opens the box again. Own design and code.

        .include "geos.inc"

        .import PutChar, FrameRectangle, InvertRectangle, Rectangle
        .import SetPattern, IsMseInRegion
        .import gfLeft, gfTop, dbIndex, gfDrvOn
        .import gfDrvPick

LET_W           = 11            ; a letter's button
LET_H           = 11
LET_PITCH       = 13
LET_X0          = 3             ; the first one's left edge in the box
LET_Y0          = 88 - 14       ; its top in the box (the strip below the
                                ; list's line, beside the arrows)
DRIVES          = 4

        .segment "OVL87"

        jmp OvLetters           ; entry 0: draw them (DbGetFiles)
        jmp OvLetterPress       ; entry 3: a press in the strip (GfPress)

; OvLetters: the letters of the drives with an image, the current one
; inverted. Destroys A, X, Y, r0-r4, r11.
OvLetters:
        lda #0                  ; the box's command byte (3 back: the
        sta gfDrvOn             ; command, x, y): bit 6, the drive button
        lda dbIndex
        sec
        sbc #3
        tay
        lda (DBoxDesc),y
        and #$40
        bne :+
        rts                     ; (GEOS 2.0's box: none)
:       sta gfDrvOn
        ; (falls into Draw)
Draw:   ldx #0
@one:   stx at
        jsr Box                 ; r2-r4 = its button
        lda #0
        jsr SetPattern
        jsr Rectangle           ; (cleared: a drive gone shows none)
        ldx at
        lda driveType,x
        beq @next
        jsr Box
        lda #$FF
        jsr FrameRectangle
        lda r3L                 ; the letter: 2 pixels in, its baseline
        clc                     ; 8 below the top
        adc #3
        sta r11L
        lda r3H
        adc #0
        sta r11H
        lda r2L
        clc
        adc #8
        sta r1H
        lda at
        clc
        adc #'A'
        jsr PutChar
        ldx at
        txa
        clc
        adc #8
        cmp curDrive
        bne @next
        jsr Box
        jsr InvertRectangle
@next:  ldx at
        inx
        cpx #DRIVES
        bcc @one
        rts

; OvLetterPress: a press at the pointer: on the letter of another drive
; with an image, gfDrvPick = $88 + its index (the drive's number with bit
; 7: MegaPatch's answer for its drive icons, DB_Icon_DrvA-D in its
; -_G3_NewDlgBox, read as behaviour reference); the resident GfStrip then
; ends the dialog with it and the application switches its own document
; drive (as MegaPatch's patched geoWrite does). Else gfDrvPick = 0.
OvLetterPress:
        lda #0
        sta gfDrvPick
        lda gfDrvOn             ; (only in a box with the letters)
        beq @end
        ldx #0
@try:   stx at
        jsr Box
        jsr IsMseInRegion
        bne @hit
        ldx at
        inx
        cpx #DRIVES
        bcc @try
        rts
@hit:   ldx at
        lda driveType,x
        beq @end
        txa
        clc
        adc #8
        cmp curDrive
        beq @end
        ora #$80
        sta gfDrvPick
@end:   rts

; Box: r2-r4 = letter at's button.
Box:    lda gfTop
        clc
        adc #LET_Y0
        sta r2L
        clc
        adc #LET_H - 1
        sta r2H
        lda at                  ; x = left + LET_X0 + at * LET_PITCH
        ldx #0
        stx r3H
        tax
        lda #LET_X0
@mul:   dex
        bmi @x
        clc
        adc #LET_PITCH
        bne @mul
@x:     clc
        adc gfLeft
        sta r3L
        lda gfLeft+1
        adc #0
        sta r3H
        lda r3L
        clc
        adc #LET_W - 1
        sta r4L
        lda r3H
        adc #0
        sta r4H
        rts

at:     .byte 0
