; GU PostScript: a picture (geoWrite's graphics escape, its photo scrap
; in records 64-126) as an image mask, as tools/gwps.py writes it:
; "<hex> x y w h PIC", centred between the ruler's margins on a card,
; 2 rows up into the line above (geoWrite's printout); the bits
; decompacted as GEOS compacts bitmaps (HG2G, BitmapUp; gwdocx.py
; decompact). Own code.

        .include "psw.inc"

        .export Picture
        .import Down, top, dry, PutC, PutI, PutDec, PutSp, PutHex

        .segment "CODE"

; Picture: the graphics escape at tp (width in cards, height, record):
; written unless dry, then a line of the escape's height (Down). tp
; unchanged.
Picture:
        ldy #1
        lda (tp),y
        sta cards
        iny
        lda (tp),y
        sta height
        iny
        lda (tp),y
        sta height + 1
        iny
        lda (tp),y
        sta rec
        jsr Place
        bit dry
        bmi :+
        jsr Write
:       lda height
        ldx height + 1
        jmp Down

; Place: picX = ((left + right - 8 * cards) / 2) rounded down to a card
; (the ruler's margins; none: 0 and 480).
Place:  lda #0
        sta sum
        sta sum + 1
        lda #<480
        sta right
        lda #>480
        sta right + 1
        lda rp + 1
        beq :+
        ldy #R_LEFT
        lda (rp),y
        sta sum
        iny
        lda (rp),y
        sta sum + 1
        ldy #R_RIGHT
        lda (rp),y
        sta right
        iny
        lda (rp),y
        sta right + 1
:       lda sum                 ; left + right
        clc
        adc right
        sta sum
        lda sum + 1
        adc right + 1
        sta sum + 1
        lda cards               ; - 8 * cards
        jsr Times8
        lda sum
        sec
        sbc tmp
        sta picX
        lda sum + 1
        sbc tmp + 1
        cmp #$80                ; / 2, rounded down (signed)
        ror a
        sta picX + 1
        lda picX
        ror a
        and #$F8                ; down to a card
        sta picX
        rts

; Times8: tmp = A * 8.
Times8: sta tmp
        lda #0
        sta tmp + 1
        ldx #3
:       asl tmp
        rol tmp + 1
        dex
        bne :-
        rts

; Write: the picture's record read; "<hex> x y-2 w h PIC" with w and h
; from the record's first three bytes (an empty or unreadable record:
; nothing). tp kept.
Write:  lda tp
        pha
        lda tp + 1
        pha
        jsr Load
        bcc :+
        jmp @end
:       lda #'<'
        jsr PutC
        lda PICBUF
        sta wc
        lda PICBUF + 1
        sta hh
        lda PICBUF + 2
        sta hh + 1
        jsr Decompact
        jsr PutI
        .byte "> ", 0
        lda picX
        ldx picX + 1
        jsr PutDec
        jsr PutSp
        lda top                 ; y - 2: up into the line above
        sec
        sbc #PIC_DOWN
        pha
        lda top + 1
        sbc #0
        tax
        pla
        jsr PutDec
        jsr PutSp
        lda wc
        jsr Times8
        lda tmp
        ldx tmp + 1
        jsr PutDec
        jsr PutSp
        lda hh
        ldx hh + 1
        jsr PutDec
        jsr PutI
        .byte " PIC", 10, 0
@end:   pla
        sta tp + 1
        pla
        sta tp
        rts

; Load: the picture's record into PICBUF, dataEnd its end. C set when
; it cannot be read or holds less than its size (nothing to draw).
Load:   lda rec
        jsr PointRecord
        txa
        bne @no
        lda #<PICBUF
        sta r7L
        lda #>PICBUF
        sta r7H
        lda #<PIC_MAX
        sta r2L
        lda #>PIC_MAX
        sta r2H
        jsr ReadRecord
        txa
        bne @no
        lda r7L
        sta dataEnd
        lda r7H
        sta dataEnd + 1
        lda dataEnd             ; dataEnd - (PICBUF + 3) >= 0: C clear
        cmp #<(PICBUF + 3)
        lda dataEnd + 1
        sbc #>(PICBUF + 3)
        bcc @no
        clc
        rts
@no:    sec
        rts

; Decompact: wc * hh bytes from the compacted data at PICBUF + 3, as
; hex; it stops at the data's end too (then fewer, as gwdocx).
Decompact:
        lda #<(PICBUF + 3)
        sta gp
        lda #>(PICBUF + 3)
        sta gp + 1
        lda #0                  ; left = wc * hh
        sta left
        sta left + 1
        lda hh
        sta cnt16
        lda hh + 1
        sta cnt16 + 1
@mul:   lda cnt16
        ora cnt16 + 1
        beq @go
        lda left
        clc
        adc wc
        sta left
        bcc :+
        inc left + 1
:       lda cnt16
        bne :+
        dec cnt16 + 1
:       dec cnt16
        jmp @mul
@go:    lda left
        ora left + 1
        beq @end
        jsr AtEnd
        bcs @end
        jsr Packet
        jmp @go
@end:   rts

; AtEnd: C set when gp has reached the data's end.
AtEnd:  lda gp
        cmp dataEnd
        lda gp + 1
        sbc dataEnd + 1
        rts

; Packet: one packet at gp (HG2G: 0-127 the next byte that many times;
; 128-219 that less 128 bytes copied; 220-255 the packets in the next
; (that less 220) bytes, repeated as often as the byte after the count
; says). Bytes beyond `left` are not written.
Packet: jsr Byte
        cmp #128
        bcs @copy
        sta cnt                 ; a repeat
        jsr Byte
        sta val
@rep:   lda cnt
        beq @end
        lda val
        jsr Out1
        dec cnt
        jmp @rep
@copy:  cmp #220
        bcs @big
        sec
        sbc #128
        sta cnt
@cp:    lda cnt
        beq @end
        jsr Byte
        jsr Out1
        dec cnt
        jmp @cp
@end:   rts
@big:   sec
        sbc #220
        sta bigN                ; the packets' bytes
        jsr Byte
        sta bigR                ; how often
        lda gp
        sta bigAt
        lda gp + 1
        sta bigAt + 1
@again: lda bigR
        beq @past
        lda bigAt
        sta gp
        lda bigAt + 1
        sta gp + 1
@in:    lda gp                  ; packets while within bigN bytes
        sec
        sbc bigAt
        cmp bigN
        bcs :+
        jsr AtEnd
        bcs :+
        jsr Small
        jmp @in
:       dec bigR
        jmp @again
@past:  lda bigAt               ; after them (gwdocx: start + n)
        clc
        adc bigN
        sta gp
        lda bigAt + 1
        adc #0
        sta gp + 1
        rts

; Small: a repeat or copy packet inside a BIGCOUNT one (no BIGCOUNT
; inside another: HG2G).
Small:  jsr Byte
        cmp #128
        bcs @copy
        sta cnt
        jsr Byte
        sta val
@rep:   lda cnt
        beq @end
        lda val
        jsr Out1
        dec cnt
        jmp @rep
@copy:  cmp #220                ; (a BIGCOUNT inside one: skipped)
        bcs @end
        sec
        sbc #128
        sta cnt
@cp:    lda cnt
        beq @end
        jsr Byte
        jsr Out1
        dec cnt
        jmp @cp
@end:   rts

; Byte: A = the byte at gp, gp + 1. Keeps X, Y.
Byte:   sty keepY
        ldy #0
        lda (gp),y
        inc gp
        bne :+
        inc gp + 1
:       ldy keepY
        rts

; Out1: A as hex while bytes are left (left - 1). Keeps X, Y.
Out1:   pha
        lda left
        ora left + 1
        beq @no
        pla
        jsr PutHex
        lda left
        bne :+
        dec left + 1
:       dec left
        rts
@no:    pla
        rts

        .segment "BSS"

cards:  .res 1
height: .res 2
rec:    .res 1
sum:    .res 2
right:  .res 2
picX:   .res 2
dataEnd: .res 2
wc:     .res 1
hh:     .res 2
left:   .res 2
cnt16:  .res 2
cnt:    .res 1
val:    .res 1
bigN:   .res 1
bigR:   .res 1
bigAt:  .res 2
keepY:  .res 1
