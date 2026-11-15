; The scrap store's routines (scrap.s); each module assembles the parts
; it uses (an overlay module cannot call another's code). Shared state in
; the overlay scratch at $9F70 (scrap.s).

; Blocks of the store: track SCRAP_TRACK+1+n, sector s is block 256 * n
; + s, at REU bank SCRAP_BANK + n, page s.

; MapRegs: r0-r3 for mapBuf <-> the map block.
MapRegs:
        lda #<mapBuf
        sta r0L
        lda #>mapBuf
        sta r0H
        lda #SCRAP_TRACK + 1
        ldx #MAP_BLOCK
        jsr BlkRegs
        lda #MAP_LEN + 4
        sta r2L
        rts

; MapSave: mapBuf to the map block.
MapSave:
        jsr MapRegs
        ldy #REU_STASH
        jmp SysRAMOp

; BlkRegs: A = track, X = sector: r1 and r3L its REU address, r2 = 256.
BlkRegs:
        sec
        sbc #SCRAP_TRACK + 1
        clc
        adc #SCRAP_BANK
        sta r3L
        stx r1H
        lda #0
        sta r1L
        sta r2L
        lda #1
        sta r2H
        rts

; DirLoad / DirSave: the directory block <-> diskBlkBuf.
DirLoad:
        ldy #REU_FETCH
        .byte $2C
DirSave:
        ldy #REU_STASH
        sty dirCmd
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        lda #SCRAP_TRACK + 1
        ldx #DIR_BLOCK
        jsr BlkRegs
        ldy dirCmd
        jmp SysRAMOp

; PutBlk: A = track, X = sector: 256 bytes from r0 to that block.
PutBlk: jsr BlkRegs
        ldy #REU_STASH
        jmp SysRAMOp

