; File engine: a CVT from the open Ultimate file, for modules 57, 59 and
; 60 (enginecvt.s): its next block read. Assembled into each module that
; needs it, after feult.inc.

; Read: the next min(254, cLeft) bytes of the open file to page X from
; its byte 2 (diskBlkBuf, fileHeader); their number to cCount, cLeft
; less by it. Z set when it worked (all of them came), else X = the
; error.
Read:   ldy #254
        lda cLeft+1
        ora cLeft+2
        bne @full
        lda cLeft
        cmp #254
        bcs @full
        tay
@full:  sty cCount
        tya
        beq @ok
        txa
        pha
        lda #U_READ
        jsr UBegin
        lda cCount
        jsr UPut
        lda #0
        jsr UPut
        pla
        sta r0H
        sta uEnd+1
        inc uEnd+1
        lda #2
        sta r0L
        lda #0
        sta uEnd
        jsr UExec
        txa
        bne @end
        ldx #FE_ULTIMATE
        lda r0L
        sec
        sbc #2
        cmp cCount
        bne @end
        lda cLeft
        sec
        sbc cCount
        sta cLeft
        bcs @ok
        lda cLeft+1
        bne :+
        dec cLeft+2
:       dec cLeft+1
@ok:    ldx #0
@end:   rts
        .assert <diskBlkBuf = 0 && <fileHeader = 0, error, "Read: buffers on a page"

