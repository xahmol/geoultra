; File engine: a CVT from the open Ultimate file onto a GEOS drive, for
; modules 57 and 59 (enginecvt.s): a block written. Assembled into each
; module that needs it, after feblock.inc and feprog.inc.

; Write: diskBlkBuf to the target block cCurT/S; one more block done.
; Z set when it worked, else X = the error (FE_CANCELLED).
Write:  jsr Dest
        lda cCurT
        sta r1L
        lda cCurS
        sta r1H
        jsr WriteBuff
        txa
        bne @end
        jsr Progress
        ldx #FE_CANCELLED
        bcs @end
        ldx #0
@end:   rts

