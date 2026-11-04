; Shared by the folder modules (src/kernal/folders.s), assembled into
; each that writes a name: an overlay module cannot call another's code.

; Name: the name at nameLo/Hi, padded with $A0 to 16 bytes, to (r4)+Y.
Name:   lda nameLo
        sta r6L
        lda nameHi
        sta r6H
        ldx #0
@char:  txa
        pha
        tya
        pha
        txa
        tay
        lda (r6),y
        sta r7L
        pla
        tay
        pla
        tax
        lda r7L
        beq @pad
        sta (r4),y
        iny
        inx
        cpx #16
        bne @char
        rts
@pad:   lda #$A0
@fill:  sta (r4),y
        iny
        inx
        cpx #16
        bne @fill
        rts

