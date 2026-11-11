; File engine: helpers for the Ultimate-to-Ultimate modules 83 and 84
; (engineuu.s), assembled into each (feult.inc and fecd.inc first). The
; source's path is kept in diskBlkBuf (cSrcFT: the "/" before its last
; part), the target's in fePath (fePos: the "/" before its last part).
; (Volume: module 83's own.) Own code.

; SaveSrc: fePath (the source, resolved) to diskBlkBuf; cSrcFT = fePos.
SaveSrc:
        ldx #0
@ch:    lda fePath,x
        sta diskBlkBuf,x
        beq @end
        inx
        bne @ch
@end:   lda fePos
        sta cSrcFT
        rts

; IntoFolder: when the target names an existing folder, the source's
; last part added to it (fePos at the new "/"). C set: too long.
IntoFolder:
        jsr UCdAll              ; (a folder: entered)
        txa
        bne @end                ; (not a folder: the target named; C clear)
        jsr EndOf
        sty fePos
        lda #'/'
        sta fePath,y
        ldx cSrcFT
@add:   inx
        iny
        beq @long
        lda diskBlkBuf,x
        sta fePath,y
        bne @add
@end:   clc
        rts
@long:  sec
        rts

; Same: Z set when the target's path is the source's.
Same:   ldx #$FF
@ch:    inx
        lda fePath,x
        cmp diskBlkBuf,x
        bne @end
        cmp #0
        bne @ch
@end:   rts

; PutChk: A to uCmd (UPut) when there is room; C set when not. Keeps A,
; X.
PutChk: ldy uLen
        cpy #U_CMD_MAX
        bcs @end
        sta uCmd,y
        inc uLen
        clc
@end:   rts

; EndOf: Y = fePath's length.
EndOf:  ldy #$FF
@ch:    iny
        lda fePath,y
        bne @ch
        rts
