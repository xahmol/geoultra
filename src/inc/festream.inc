; File engine: streams (enginestream.s), for FE_READ and FE_WRITE.
; Assembled into each module that needs it, after fereu.inc.

; Stream: handle feY of type A to feH; sPtr, sLeft from r1, r2, sGot 0;
; its drive selected. Z set when it worked, else X = FE_BAD_HANDLE.
Stream: sta feM
        ldx #FE_BAD_HANDLE
        ldy feY
        cpy #FE_HANDLES_N
        bcs @end
        sty feHandle
        ldy #REU_FETCH
        jsr HandleOp
        ldx #FE_BAD_HANDLE
        lda feH + H_TYPE
        cmp feM
        bne @end
        ldx #3
@args:  lda argR1,x             ; (sPtr, sLeft: r1, r2)
        sta sPtr,x
        dex
        bpl @args
        lda #0
        sta sGot
        sta sGot+1
        lda #$FF                ; (a drive used)
        sta feTouched
        lda feH + H_DRIVE       ; (drive E: shown again in its slot)
        jsr HDrive
        cpx #0                  ; (Z: the caller tests it)
@end:   rts

HDrive: jsr OvlCall             ; (module 81: a handle's drive current; X)
        .byte 81, 18
        .assert sLeft = sPtr + 2, error, "Stream: sPtr, sLeft from r1, r2"

; Count: one byte less to go.
Count:  lda sLeft
        bne :+
        dec sLeft+1
:       dec sLeft
        rts

; ReadCur, WriteCur: the stream's block <-> diskBlkBuf. Z set when it
; worked, else X = the error.
ReadCur:
        jsr CurRegs
        jsr ReadBuff
        txa
        rts
WriteCur:
        jsr CurRegs
        jsr WriteBuff
        txa
        rts
CurRegs:
        lda feH + H_BLKT
        sta r1L
        lda feH + H_BLKS
        sta r1H
        rts

; Keep: the handle back to the REU. X = 0.
Keep:   ldy #REU_STASH
        jsr HandleOp
        ldx #0
        rts
