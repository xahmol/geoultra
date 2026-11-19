; GeoUltra Settings: buttons inside a page (docs/design/SETTINGS.md): a framed
; box with its label centred by its measured width, and the test whether
; a click is on it. A page's overlay holds its buttons' records and
; hands them over (ButtonDraw, OnButton). Own design and code.
;
; A button's record: .word x; .byte top y, width; .addr label (BTN_*).

        .include "geos.inc"
        .include "settings.inc"

        .export ButtonDraw, OnButton, TextWidth

BTN_X           = 0
BTN_Y           = 2
BTN_W           = 3
BTN_LABEL       = 4
BTN_H           = 12            ; its height
BTN_BASE        = 8             ; the label's baseline below its top (its
                                ; cells end above the frame's bottom line)

        .segment "ZEROPAGE"

bp:             .res 2          ; the button's record

        .segment "CODE"

; ButtonDraw: A/X = a button's record: cleared, framed, its label in it.
ButtonDraw:
        jsr Box                 ; r2-r4 = its box
        lda #0
        jsr SetPattern
        jsr Rectangle
        lda #$FF
        jsr FrameRectangle
        ldy #BTN_LABEL          ; the label: x = x + (width - its width) / 2
        lda (bp),y
        sta r0L
        iny
        lda (bp),y
        sta r0H
        jsr TextWidth
        sta tw
        ldy #BTN_W
        lda (bp),y
        sec
        sbc tw
        lsr a
        ldy #BTN_X
        clc
        adc (bp),y
        sta r11L
        iny
        lda (bp),y
        adc #0
        sta r11H
        ldy #BTN_LABEL          ; (TextWidth took r0 along)
        lda (bp),y
        sta r0L
        iny
        lda (bp),y
        sta r0H
        ldy #BTN_Y
        lda (bp),y
        clc
        adc #BTN_BASE
        sta r1H
        jmp PutString

; OnButton: A/X = a button's record: C clear when the pointer is on it.
OnButton:
        jsr Box
        lda mouseYPos
        cmp r2L
        bcc @no
        lda r2H
        cmp mouseYPos
        bcc @no
        lda mouseXPos+1         ; x >= r3
        cmp r3H
        bcc @no
        bne :+
        lda mouseXPos
        cmp r3L
        bcc @no
:       lda r4H                 ; x <= r4
        cmp mouseXPos+1
        bcc @no
        bne @yes
        lda r4L
        cmp mouseXPos
        bcc @no
@yes:   clc
        rts
@no:    sec
        rts

; Box: bp = A/X; r2-r4 = the button's box.
Box:    sta bp
        stx bp+1
        ldy #BTN_Y
        lda (bp),y
        sta r2L
        clc
        adc #BTN_H - 1
        sta r2H
        ldy #BTN_X
        lda (bp),y
        sta r3L
        iny
        lda (bp),y
        sta r3H
        ldy #BTN_W
        lda (bp),y
        sec                     ; r4 = x + width - 1
        sbc #1
        clc
        adc r3L
        sta r4L
        lda r3H
        adc #0
        sta r4H
        rts

; TextWidth: A = the width of the zero-ended text at r0 in the system
; font, plain (at most 255). Destroys X, Y.
TextWidth:
        lda #0
        sta tw
        ldy #0
@ch:    lda (r0),y
        beq @end
        sty ty
        jsr GetCharWidth
        clc
        adc tw
        sta tw
        ldy ty
        iny
        bne @ch
@end:   lda tw
        rts

        .segment "BSS"

tw:             .res 1
ty:             .res 1
