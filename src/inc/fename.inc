; File engine: a name into a directory entry, for the functions that make
; one (the new entry of a copy, module 52; FE_OPEN's new file, module 33).
; Assembled into each module that needs it.

; PutName: feShort (zero-ended) to diskBlkBuf+Y, $A0-padded to
; FE_NAME_MAX.
; Destroys A, X, Y.
PutName:
        ldx #0
@name:  lda feShort,x
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
