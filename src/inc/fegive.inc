; File engine: one listing entry to the caller, for FE_READDIR on the
; Ultimate and on "/" (modules 39, 40; module 28 has its own for GEOS
; names in feTmp). Assembled into each module that needs it, after
; fereu.inc and feinfo.inc.

; Give: the handle kept, feInfo and the name at fileHeader + 1 to the
; caller (r1, r2).
Give:   ldy #REU_STASH
        jsr HandleOp
        lda argR2
        sta r0L
        lda argR2+1
        sta r0H
        ldy #$FF
@name:  iny
        lda fileHeader+1,y
        sta (r0),y
        bne @name
        jmp PutInfo
Eod:    ldx #FE_END_OF_DIR
        rts
