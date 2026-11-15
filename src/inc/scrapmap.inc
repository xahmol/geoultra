; The scrap store's routines (scrap.s); each module assembles the parts
; it uses (an overlay module cannot call another's code). Shared state in
; the overlay scratch at $9F70 (scrap.s).

; Alloc: a free block taken in mapBuf: X = its track, Y = its sector, C
; clear; C set: the store is full.
Alloc:  ldx #0
@byte:  lda mapBuf+4,x
        cmp #$FF
        bne @bit
        inx
        cpx #MAP_LEN
        bne @byte
        sec
        rts
@bit:   ldy #0
        lda #$80
        sta tmpT
@b:     lda mapBuf+4,x
        and tmpT
        beq @got
        lsr tmpT
        iny
        bne @b
@got:   lda mapBuf+4,x
        ora tmpT
        sta mapBuf+4,x
        txa                     ; block = 8 * byte + bit
        asl a
        asl a
        asl a
        sta tmpS
        tya
        ora tmpS
        tay                     ; (the sector: the block's low byte)
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a                   ; (byte / 32: the track's offset)
        clc
        adc #SCRAP_TRACK + 1
        tax
        clc
        rts

; FreeTS: A = track, X = sector: that block free in mapBuf.
FreeTS: sec
        sbc #SCRAP_TRACK + 1
        asl a                   ; byte = 32 * track offset + sector / 8
        asl a
        asl a
        asl a
        asl a
        sta tmpT
        txa
        lsr a
        lsr a
        lsr a
        ora tmpT
        tay
        txa
        and #7
        tax
        lda #$80
@s:     dex
        bmi @clr
        lsr a
        bne @s
@clr:   eor #$FF
        and mapBuf+4,y
        sta mapBuf+4,y
        rts

