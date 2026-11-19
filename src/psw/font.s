; GU PostScript: font metrics and glyph cells (tools/gwps.py Font). The
; font image (HG2G "Fonts": baseline offset, set width, height, the
; index table of characters 32-127 and its end, the bit rows) is kept
; in FONTBUF; step P1 has GeoUltra's system font there for every font ID
; (as gwps draws a font it does not find), step P2 loads the others.
; Own code.

        .include "psw.inc"

        .export FontInit, Width, Height, Base, GlyphSetup, GlyphBits, glyphW, widths, fHeight, fBase
        .import PutHex

        .segment "CODE"

; FontInit: the system font copied to FONTBUF (it lies in the RAM under
; the I/O area: read with all RAM in view, interrupts off) and its
; widths, height and baseline taken. Destroys A, X, Y, op, gp.
FontInit:
        jsr UseSystemFont
        lda baselineOffset      ; the image's header (8 bytes)
        sta FONTBUF
        sta fBase
        lda curSetWidth
        sta FONTBUF + 1
        sta setW
        lda curSetWidth + 1
        sta FONTBUF + 2
        sta setW + 1
        lda curHeight
        sta FONTBUF + 3
        sta fHeight
        lda #8                  ; the index table at 8, the bits at 8 + 194
        sta FONTBUF + 4
        lda #0
        sta FONTBUF + 5
        sta FONTBUF + 7
        lda #8 + 194
        sta FONTBUF + 6
        php
        sei
        lda CPU_PORT
        pha
        lda #$30
        sta CPU_PORT
        lda curIndexTable       ; the index table: 97 words
        sta op
        lda curIndexTable + 1
        sta op + 1
        ldy #193
:       lda (op),y
        sta FONTBUF + 8,y
        dey
        cpy #$FF
        bne :-
        lda cardDataPntr        ; the bits: height x set width bytes
        sta op
        lda cardDataPntr + 1
        sta op + 1
        lda #<(FONTBUF + 8 + 194)
        sta gp
        lda #>(FONTBUF + 8 + 194)
        sta gp + 1
        ldx fHeight
@row:   ldy #0
:       lda (op),y
        sta (gp),y
        iny
        cpy setW                ; (the system font's rows are under 256)
        bne :-
        lda op
        clc
        adc setW
        sta op
        bcc :+
        inc op + 1
:       lda gp
        clc
        adc setW
        sta gp
        bcc :+
        inc gp + 1
:       dex
        bne @row
        pla
        sta CPU_PORT
        plp
        ldx #0                  ; the widths: offset[c + 1] - offset[c]
:       txa
        asl a
        tay
        lda FONTBUF + 8 + 2,y
        sec
        sbc FONTBUF + 8,y
        sta widths,x
        inx
        cpx #96
        bcc :-
        rts

; Width: A = the width of character A (32-127) in style X (GetRealSize:
; bold +1, outline +2). Keeps X, Y.
Width:  stx keep
        sec
        sbc #32
        tax
        lda widths,x
        ldx keep
        pha
        txa
        and #BOLD
        beq :+
        pla
        clc
        adc #1
        pha
:       txa
        and #OUTLINE
        beq :+
        pla
        clc
        adc #2
        pha
:       pla
        rts

; Height, Base: A = the font's height and baseline offset in style X
; (outline 2 more). Keep X, Y.
Height: lda fHeight
        jmp Plus2
Base:   lda fBase
Plus2:  pha
        txa
        and #OUTLINE
        beq :+
        pla
        clc
        adc #2
        rts
:       pla
        rts

; GlyphSetup: character A's cell in style X (CELL_STYLES; a space without
; reverse) as hex digits, row by row, each row padded to whole bytes, as
; gwps's Font.cell and type3_def: bold makes each column the font's bit
; or the one before (the cell one wider); the underline row (baseline +
; 1) is the line only, over the cell but its last column (all of it when
; bold); reverse inverts the cell; outline adds two blank columns (drawn
; plain, as GeoUltra's kernal). GlyphSetup: glyphW = the cell's width
; with them; GlyphBits then writes the rows. Destroy A, X, Y, op.
GlyphSetup:
        sta code
        cmp #' '
        bne :+
        txa
        and #CELL_STYLES & ~REVERSE
        tax
:       stx style
        lda code
        ldx #0
        jsr Width               ; the font's own width (no style)
        sta glyphW0
        sta cellW
        lda style
        and #BOLD
        beq :+
        inc cellW
:       lda cellW
        sta glyphW
        lda style
        and #OUTLINE
        beq :+
        inc glyphW
        inc glyphW
:       lda code                ; the glyph's first bit: offset[code - 32]
        sec
        sbc #32
        asl a
        tay
        lda FONTBUF + 8,y
        sta first
        lda FONTBUF + 8 + 1,y
        sta first + 1
        rts

GlyphBits:
        lda #<(FONTBUF + 8 + 194)
        sta op
        lda #>(FONTBUF + 8 + 194)
        sta op + 1
        lda #0
        sta row
@row:   lda #0
        sta prev
        sta col
        sta acc
        sta bits
@col:   lda #0                  ; the font's bit (columns below its width)
        ldx col
        cpx glyphW0
        bcs :+
        jsr FontBit
:       sta pix
        lda style
        and #BOLD
        beq :+
        lda pix
        ldx prev
        sta prev
        txa
        ora prev
        sta pix
:       lda style               ; the underline row: the line only
        and #UNDERLINE
        beq @rev
        lda fBase
        clc
        adc #1
        cmp row
        bne @rev
        ldx #2                  ; col + (1 bold, 2 plain) <= cellW
        lda style
        and #BOLD
        beq :+
        dex
:       txa
        clc
        adc col
        cmp cellW
        beq :+
        bcs @off
:       lda #1
        bne @set
@off:   lda #0
@set:   sta pix
@rev:   lda style
        and #REVERSE
        beq :+
        lda pix
        eor #1
        sta pix
:       jsr Shift               ; the cell's columns
        inc col
        lda col
        cmp cellW
        bcc @col
@pad:   lda col                 ; outline's two blank columns, then the row
        cmp glyphW              ; to a whole byte
        bcs @end
        lda #0
        sta pix
        jsr Shift
        inc col
        bne @pad
@end:   lda bits
        beq :+
@fill:  lda #0
        sta pix
        jsr Shift
        lda bits
        bne @fill
:       lda op                  ; the next row of the font
        clc
        adc setW
        sta op
        lda op + 1
        adc setW + 1
        sta op + 1
        inc row
        lda row
        cmp fHeight
        bcs :+
        jmp @row
:       rts

; Shift: bit into the byte being made; a full byte written as hex.
Shift:  lda pix
        lsr a
        rol acc
        inc bits
        lda bits
        cmp #8
        bne :+
        lda acc
        jsr PutHex
        lda #0
        sta bits
        sta acc
:       rts

; FontBit: A = the font's bit at column X of the glyph (first + X) in
; the row at op. Keeps Y.
FontBit:
        tya
        pha
        txa
        clc
        adc first
        sta pos
        lda first + 1
        adc #0
        sta pos + 1
        lda pos                 ; the byte: pos / 8
        and #7
        tax
        lsr pos + 1
        ror pos
        lsr pos + 1
        ror pos
        lsr pos + 1
        ror pos
        lda op
        clc
        adc pos
        sta gp
        lda op + 1
        adc pos + 1
        sta gp + 1
        ldy #0
        lda (gp),y
        and Mask,x
        beq :+
        lda #1
:       sta keep
        pla
        tay
        lda keep
        rts

Mask:   .byte $80, $40, $20, $10, $08, $04, $02, $01

        .segment "BSS"

widths: .res 96
fHeight: .res 1
fBase:  .res 1
setW:   .res 2
keep:   .res 1
code:   .res 1
style:  .res 1
glyphW0: .res 1
cellW:  .res 1
glyphW: .res 1
first:  .res 2
row:    .res 1
col:    .res 1
prev:   .res 1
pix:    .res 1
acc:    .res 1
bits:   .res 1
pos:    .res 2
