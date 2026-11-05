; File engine: a drive's state when mounted or emptied (enginemount.s),
; for modules 66 and 69. Assembled into each module that needs it, after
; fereu.inc.

; TableOp: drive mSlot's mount table entry from the driver's state
; (type without DRV_RAM, first bank, tracks, flags).
TableOp:
        ldx mSlot
        lda driveType,x
        and #$0F
        sta diskBlkBuf
        lda ramBase,x
        sta diskBlkBuf+1
        lda drvTracks,x
        sta diskBlkBuf+2
        lda drvFlags,x
        sta diskBlkBuf+3
        lda #<diskBlkBuf
        sta r0L
        lda #>diskBlkBuf
        sta r0H
        txa                     ; MOUNT_ENTRY + 32 * drive
        asl
        asl
        asl
        asl
        asl
        clc
        adc #<MOUNT_ENTRY
        sta r1L
        lda #>MOUNT_ENTRY
        sta r1H
        lda #4
        sta r2L
        lda #0
        sta r2H
SysOp:  lda #SYS_BANK
        sta r3L
        ldy #REU_STASH
        jmp SysRAMOp

; Common: for drive mSlot, mounted or emptied: NUMDRV counted again, its
; folder the root (also the caller's saved one: the dispatcher puts the
; saved folders back), the native BAM copy dropped if it was its.
Common: ldx mSlot
        lda #1
        sta folderT,x
        sta folderS,x
        sta saveFT,x
        sta saveFS,x
        txa
        clc
        adc #8
        cmp natLoaded
        bne :+
        lda #0
        sta natLoaded
:       ldx #3
        ldy #0
@count: lda driveType,x
        and #$0F
        beq :+
        iny
:       dex
        bpl @count
        sty NUMDRV
        rts

