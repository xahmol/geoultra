; The scrap store's routines (scrap.s); each module assembles the parts
; it uses (an overlay module cannot call another's code). Shared state in
; the overlay scratch at $9F70 (scrap.s).

; Seek: the entry named r6 in the directory block (DirLoad): C clear and
; r5 = the entry in diskBlkBuf (its type byte); C set: none.
Seek:   jsr DirLoad
        lda #2
@entry: sta tmpT
        clc
        adc #<diskBlkBuf
        sta r5L
        lda #>diskBlkBuf
        sta r5H
        ldy #0
        lda (r5),y
        beq @next               ; (a free entry)
        ldy #0
@cmp:   lda (r6),y              ; the name: up to 16, then $A0-padded
        beq @end
        sty tmpS
        pha
        tya
        clc
        adc #OFF_FNAME
        tay
        pla
        cmp (r5),y
        bne @next
        ldy tmpS
        iny
        cpy #16
        bne @cmp
        clc
        rts
@end:   tya                     ; the name ended: the entry's rest $A0
        clc
        adc #OFF_FNAME
        tay
        cpy #OFF_FNAME + 16
        beq @hit
        lda (r5),y
        cmp #$A0
        beq @hit
@next:  lda tmpT
        clc
        adc #32
        bcc @entry
        sec
        rts
@hit:   clc
        rts

