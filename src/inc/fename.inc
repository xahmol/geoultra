; File engine: a name into a directory entry, for the functions that make
; one (FE_COPY, FE_OPEN). Assembled into each module that needs it.

; PutName: feTmp (zero-ended) to diskBlkBuf+Y, $A0-padded to FE_NAME_MAX.
; Destroys A, X, Y.
PutName:
        ldx #0
@name:  lda feTmp,x
        beq @pad
        sta diskBlkBuf,y
        iny
        inx
        cpx #FE_NAME_MAX
        bne @name
        rts
@pad:   lda #$A0
@fill:  sta diskBlkBuf,y
        iny
        inx
        cpx #FE_NAME_MAX
        bne @fill
        rts
