; Drive E shown on the current drive's slot for a moment (sysdrive.s):
; Usable, Enter, Leave, HeadDma,
; module 15 (desk accessories and fonts, applications' gate) and module 55
; (FE_RUNSYS, a program from drive E). Assembled into each module that
; needs it; the state (sysType ...) is resident in sysdrive.s.

; Enter: the current slot shows drive E (a read-only 1541 image).
Enter:  ldy #REU_STASH
        jsr HeadDma
        ldx curDrive
        lda driveType-8,x
        sta sysType
        and #$F0                ; (the REU drive bit kept)
        ora #DRV_1541
        sta driveType-8,x
        lda curType
        sta sysCurType
        and #$F0
        ora #DRV_1541
        sta curType
        lda ramBase-8,x
        sta sysBase
        lda #SYSDRV_BANK
        sta ramBase-8,x
        lda drvFlags-8,x
        sta sysFlags
        ora #F_READONLY
        sta drvFlags-8,x
        lda #$80
        sta sysActive
        rts

; Leave: the slot back as it was, curDirHead too. X kept.
Leave:  txa
        pha
        ldy #REU_FETCH
        jsr HeadDma
        ldx curDrive
        lda sysType
        sta driveType-8,x
        lda sysCurType
        sta curType
        lda sysBase
        sta ramBase-8,x
        lda sysFlags
        sta drvFlags-8,x
        lda #0
        sta sysActive
        pla
        tax
        rts

; HeadDma: curDirHead to (Y = REU_STASH) or from (REU_FETCH) HEAD_SAVE in
; REU bank 1; r0-r3 kept (OvFindFile returns r1).
HeadDma:
        ldx #7
@save:  lda r0L,x
        pha
        dex
        bpl @save
        lda #<curDirHead
        sta r0L
        lda #>curDirHead
        sta r0H
        lda #<HEAD_SAVE
        sta r1L
        lda #>HEAD_SAVE
        sta r1H
        lda #0
        sta r2L
        lda #1
        sta r2H
        sta r3L                 ; bank 1
        jsr SysRAMOp
        ldx #0
@back:  pla
        sta r0L,x
        inx
        cpx #8
        bne @back
        rts

; Usable: C clear when drive E can be shown on the current drive (not a
; native one with more than SYSDRV_TRACK tracks, and not shown already).
Usable: sec
        bit sysActive
        bmi @end
        ldx curDrive
        lda driveType-8,x
        and #$0F
        cmp #DRV_NATIVE
        bcc @end
        lda drvTracks-8,x
        cmp #SYSDRV_TRACK + 1
@end:   rts
