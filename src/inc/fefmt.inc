; File engine: an empty image's blocks (enginemkimg.s), for modules 72
; and 73. Assembled into each module that needs it.

; Wipe: diskBlkBuf zeros. Dir: an empty directory block (link 0, $FF).
; Destroy A, X.
Dir:    jsr Wipe
        lda #$FF
        sta diskBlkBuf+1
        rts
Wipe:   lda #0
        tax
@zero:  sta diskBlkBuf,x
        inx
        bne @zero
        rts

; Name: the caller's disk name (r1, zero-ended; none when r1 is 0) to
; diskBlkBuf + Y, 16 characters padded with $A0. Destroys A, X, Y, r5.
Name:   tya
        tax
        ldy #0
        lda argR1+1
        beq @pad
        sta r5H
        lda argR1
        sta r5L
@ch:    lda (r5),y
        beq @pad
        sta diskBlkBuf,x
        inx
        iny
        cpy #16
        bne @ch
        rts
@pad:   lda #$A0
@fill:  sta diskBlkBuf,x
        inx
        iny
        cpy #16
        bne @fill
        rts

; Put: diskBlkBuf to the image's block A + 256 * X (in the banks from
; mBank). Destroys A, X, Y, r0-r3L.
Put:    sta r1H
        txa
        clc
        adc mBank
        sta r3L
        lda #0
        sta r1L
        sta r2L
        lda #1
        sta r2H
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        ldy #REU_STASH
        jmp SysRAMOp
