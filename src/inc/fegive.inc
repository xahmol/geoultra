; File engine: one listing entry to the caller, for FE_READDIR on the
; Ultimate and on "/" (modules 39, 40; module 28 has its own for GEOS
; names in feTmp). Assembled into each module that needs it, after
; fereu.inc and feinfo.inc.

; Give: the handle kept, feInfo and the name at fileHeader + 1 to the
; caller (r1, r2; a name longer than FE_LONG_MAX cut, with FF_CUT).
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
        beq @put
        cpy #FE_LONG_MAX - 1
        bne @name
        iny                     ; longer: cut, FF_CUT
        lda fileHeader+1,y
        beq @put
        lda #0
        sta (r0),y
        lda feInfo + FI_FLAGS
        ora #FF_CUT
        sta feInfo + FI_FLAGS
@put:   jmp PutInfo
Eod:    ldx #FE_END_OF_DIR
        rts
