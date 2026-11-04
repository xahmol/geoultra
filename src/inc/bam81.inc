; Shared by the 1581 partition modules 19 and 21 (src/kernal/folders.s),
; assembled into each, as an overlay module cannot call another's code.

dir3Head        = $9C80         ; the 1581's second BAM block (reudrv.s)

; Bam: A = track (1-80) -> r5 = its 6-byte entry in dir2Head (tracks
; 1-40) or dir3Head (41-80). Destroys A, X, Y, r6L.
Bam:    sec
        sbc #1
        cmp #40
        bcc @low
        sbc #40
        ldy #>(dir3Head + $10)
        ldx #<(dir3Head + $10)
        bne @mul
@low:   ldy #>(dir2Head + $10)
        ldx #<(dir2Head + $10)
@mul:   stx r5L
        sty r5H
        sta r6L                 ; r5 += 6 * (track - 1 within the block)
        asl
        clc
        adc r6L
        asl
        clc
        adc r5L
        sta r5L
        bcc @end
        inc r5H
@end:   rts
