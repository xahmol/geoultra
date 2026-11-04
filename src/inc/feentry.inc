; File engine: a new file's directory entry on a GEOS drive, for the
; copies (modules 31, 44). Assembled into each module that needs it, after
; fename.inc.

; Entry: the entry (cEntry, named feTmp) into a free slot of the target
; folder, then the BAM. X = 0 or an error.
Entry:  lda #0
        sta r10L
        jsr GetFreeDirBlk       ; (diskBlkBuf, r1; Y the slot)
        txa
        bne @end
        ldx #0
@copy:  lda cEntry,x
        sta diskBlkBuf,y
        iny
        inx
        cpx #30
        bne @copy
        tya                     ; the name, feTmp
        sec
        sbc #30 - 3
        tay
        jsr PutName
        jsr WriteBuff
        txa
        bne @end
        jmp PutDirHead
@end:   rts
