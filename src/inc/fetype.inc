; File engine: a disk image's type from its name, for modules 65
; (FE_MOUNT) and 71 (FE_MKIMG). Assembled into each module that needs it.

; Type: mType and mBanks from fePath's extension (.d64, .d71, .d81,
; .dnp: a native image's banks later, from its size). C set: X =
; FE_NOT_SUPPORTED for another file.
Type:   ldx #$FF
@end:   inx
        lda fePath,x
        bne @end
        ldy #3                  ; four kinds
@kind:  lda fePath-4,x
        cmp #'.'
        bne @no
        lda fePath-3,x
        ora #$20
        cmp #'d'
        bne @no
        lda fePath-2,x
        ora #$20
        cmp Ext2,y
        bne @next
        lda fePath-1,x
        ora #$20
        cmp Ext3,y
        bne @next
        lda Types,y
        sta mType
        lda Banks,y
        sta mBanks
        clc
        rts
@next:  dey
        bpl @kind
@no:    ldx #FE_NOT_SUPPORTED
        sec
        rts

Ext2:   .byte "678n"
Ext3:   .byte "411p"
Types:  .byte DRV_1541, DRV_1571, DRV_1581, DRV_NATIVE
Banks:  .byte 3, 6, 13, 0       ; (683, 1366, 3200 blocks; native: its size)

