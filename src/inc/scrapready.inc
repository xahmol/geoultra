; The scrap store's Ready (scrap.s): uses scrapblk.inc.

; Ready: the block map in mapBuf; a store without its mark (the REU
; after power-on) made empty first: no files, blocks 0 and 1 used.
Ready:  lda #MAP_BLOCK
        jsr MapRegs
        ldy #REU_FETCH
        jsr SysRAMOp
        ldx #3
@m:     lda mapBuf,x
        cmp Mark,x
        bne @new
        dex
        bpl @m
        rts
@new:   ldx #0
        txa
@z:     sta diskBlkBuf,x        ; an empty directory block
        cpx #MAP_LEN + 4
        bcs :+
        sta mapBuf,x
:       inx
        bne @z
        dex
        stx diskBlkBuf+1        ; (link 0, $FF)
        ldx #3
@k:     lda Mark,x
        sta mapBuf,x
        dex
        bpl @k
        lda #$C0                ; blocks 0 and 1
        sta mapBuf+4
        jsr DirSave
        jmp MapSave
Mark:   .byte "GUSC"

