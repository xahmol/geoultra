; File engine: mounting (enginemount.s), for modules 65 and 66.
; Assembled into each module that needs it.

; ParseDrive: the caller's r0 ("/a" to "/d", a "/" after it allowed) as
; a drive 0-3 in X, C clear; else C set, X = FE_BAD_PATH. Destroys A, Y.
ParseDrive:
        lda argR0
        sta r0L
        lda argR0+1
        sta r0H
        ldy #0
        lda (r0),y
        cmp #'/'
        bne @bad
        iny
        lda (r0),y
        ora #$20
        sec
        sbc #'a'
        cmp #4
        bcs @bad
        tax
        iny
        lda (r0),y
        beq @ok
        cmp #'/'
        bne @bad
        iny
        lda (r0),y
        bne @bad
@ok:    clc
        rts
@bad:   ldx #FE_BAD_PATH
        sec
        rts

        .include "banksof.inc"
