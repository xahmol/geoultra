; File engine: walking GU.LONGNAMES of the current folder (docs/
; FILE_ENGINE.md, "Long names"), for the long-name modules (enginelong.s).
; Assembled into each module that needs it. The record being looked at is
; at diskBlkBuf + lnOff (block lnBlkT/S).

; LnOpen: GU.LONGNAMES found, its entry's place to lnDir*, its first block
; read, lnOff at the first record. X = 0, FILE_NOT_FOUND (no such file)
; or a disk error. Destroys A, Y, r1, r4-r6, dirEntryBuf.
LnOpen: lda #<LnName
        sta r6L
        lda #>LnName
        sta r6H
        jsr FindFile
        txa
        bne LnEnd
        lda r1L
        sta lnDirT
        lda r1H
        sta lnDirS
        lda r5L
        sta lnDirO
        lda dirEntryBuf + OFF_DE_TR_SC
        sta lnBlkT
        lda dirEntryBuf + OFF_DE_TR_SC + 1
        sta lnBlkS
        lda #2
        sta lnOff
; LnRead: block lnBlkT/S to diskBlkBuf. X = 0 or the error.
LnRead: lda lnBlkT
        sta r1L
        lda lnBlkS
        sta r1H
        jmp ReadBuff
LnEnd:  rts

; LnWrite: diskBlkBuf to block lnBlkT/S. X = 0 or the error.
LnWrite:
        lda lnBlkT
        sta r1L
        lda lnBlkS
        sta r1H
        jmp WriteBuff

; LnNext: the next record (the second of the block, or the first of the
; next block, read). C set when there is none (or the next block does
; not read).
LnNext: lda lnOff
        cmp #2
        bne @block
        lda #2 + LN_REC
        sta lnOff
        clc
        rts
@block: lda diskBlkBuf
        beq @end
        sta lnBlkT
        lda diskBlkBuf+1
        sta lnBlkS
        lda #2
        sta lnOff
        jsr LnRead
        cpx #1                  ; (C clear: read)
        rts
@end:   sec
        rts

; LnKeyIs: Z set when the record at lnOff has the key lnKey*. Destroys A,
; Y.
LnKeyIs:
        ldy lnOff
        lda diskBlkBuf + LN_T,y
        cmp lnKeyT
        bne @end
        lda diskBlkBuf + LN_S,y
        cmp lnKeyS
        bne @end
        lda diskBlkBuf + LN_O,y
        cmp lnKeyO
@end:   rts

LnName: .byte LN_NAME, 0
