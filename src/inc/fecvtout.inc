; File engine: a GEOS file onto the open Ultimate file as CVT, for
; modules 56 and 58 (enginecvt.s): the source's blocks read, data sent.
; Assembled into each module that needs it, after feult.inc.

; Source: the source's drive selected.
Source: lda cSrcDrv
        jmp SetDevice

; ReadSrc: the source block cNextT/S to diskBlkBuf. Z set when it worked,
; else X = the error.
ReadSrc:
        jsr Source
        lda cNextT
        sta r1L
        lda cNextS
        sta r1H
        jsr ReadBuff
        txa
        rts

; SendFull: diskBlkBuf's 254 data bytes to the open file. Send: from X
; to cCurT (at most 255), in pieces of U_PIECE. Z set when it worked,
; else X = the error. Destroys cCurS.
SendFull:
        ldx #255
        stx cCurT
        ldx #2
Send:   stx cCurS
        jsr Begin
        ldx cCurS
@byte:  lda diskBlkBuf,x
        jsr UPut
        cpx cCurT
        beq Exec
        inx
        lda uLen
        cmp #4 + U_PIECE
        bne @byte
        stx cCurS
        jsr Exec
        bne @end
        ldx cCurS
        jmp Send
@end:   rts

; Begin: uCmd = WRITE_DATA (its two zero bytes); the data follows.
Begin:  lda #U_WRITE
        jsr UBegin
        lda #0
        jsr UPut
        jmp UPut

; Exec: uCmd to the Ultimate, no data back. Z set when it worked, else X
; = the error.
Exec:   jsr UNoData
        jsr UExec
        txa
        rts

