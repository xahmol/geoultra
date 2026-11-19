; GU PostScript: fonts (tools/gwps.py Fonts and Font). Each font ID (a
; family and a size) the document uses gets a slot: its 96 widths
; (FONTW), height and baseline, and the name of its file (FONTNAMES),
; found as geoWrite finds fonts: FindFTypes over the FONT files (on
; GeoUltra also drive E's GU fonts and the installed ones), the ID in
; each file's header at $80, the size's record. Slot 0 is GeoUltra's
; system font: for IDs 0 and 128 (BSW, BSW128) and for any font not
; found (as gwps draws it). The glyphs' bits come from a font image in
; FONTBUF (LoadImage), only while the prolog is written. Own code.

        .include "psw.inc"

        .export FontInit, FindFont, SlotAX, UseSlot, LoadImage, Width, Height, Base
        .export GlyphSetup, GlyphBits, glyphW, fHeight, fBase, curSlot
        .import PutHex

FindFTypes      = $C23B
FindFile        = $C20B
GetFHdrInfo     = $C229
dirEntryBuf     = $8400
FONT            = 8             ; GEOS file type
r6L = $0E
r6H = $0F
r9L = $14
r9H = $15
LIST_MAX        = 15            ; font files FindFTypes lists

        .segment "ZEROPAGE"

wp:     .res 2                  ; the slot in use's widths
lp:     .res 2                  ; a name in the font list

        .segment "CODE"

; FontInit: slot 0 = the system font (its widths, height, baseline);
; no other slots yet. Destroys A, X, Y.
FontInit:
        jsr UseSystemFont
        lda curHeight
        sta slotH
        lda baselineOffset
        sta slotB
        lda #$FF                ; (an ID no font has)
        sta slotFid
        sta slotFidH
        lda curIndexTable
        sta op
        lda curIndexTable + 1
        sta op + 1
        php                     ; (the system font lies under the I/O area)
        sei
        lda CPU_PORT
        pha
        lda #$30
        sta CPU_PORT
        ldx #0                  ; widths: offset[c + 1] - offset[c]
        ldy #0
:       iny
        iny
        lda (op),y
        dey
        dey
        sec
        sbc (op),y
        sta FONTW,x
        iny
        iny
        inx
        cpx #96
        bcc :-
        pla
        sta CPU_PORT
        plp
        lda #1
        sta nSlot
        lda #$FF
        sta loaded              ; (no image in FONTBUF)
        lda #0
        jmp UseSlot

; FindFont: a slot for the font ID A/X (lo/hi) unless it has one: its
; file looked for (FindFTypes, the header's ID = the ID's family), its
; size's record read into FONTBUF for the widths, height and baseline.
; Not found (or no slot left): nothing, SlotOf then gives the system
; font. No record file may be open. Destroys all.
FindFont:
        sta fid
        stx fid + 1
        jsr SlotOf
        cmp #0
        bne @end                ; (it has one)
        jsr System
        bcs @end                ; (the system font's IDs)
        lda nSlot
        cmp #FONT_SLOTS
        bcs @end
        jsr Family              ; fam = fid >> 6
        jsr Look                ; its file's name in name
        bcs @end
        jsr Read                ; its size's record into FONTBUF
        bcs @end
        ldx nSlot               ; the slot: ID, metrics, name
        lda fid
        sta slotFid,x
        lda fid + 1
        sta slotFidH,x
        lda FONTBUF + 3
        sta slotH,x
        lda FONTBUF
        sta slotB,x
        txa
        jsr Widths
        ldx nSlot
        jsr NamePtr
        ldy #16
:       lda name,y
        sta (op),y
        dey
        bpl :-
        lda nSlot
        sta loaded
        inc nSlot
@end:   rts

; System: C set when fid is the system font's (family 0 or 128).
System: lda fid + 1
        and #$DF
        bne @no
        lda fid
        and #$C0
        bne @no
        sec
        rts
@no:    clc
        rts

; Family: fam = fid >> 6.
Family: lda fid
        sta fam
        lda fid + 1
        sta fam + 1
        ldy #6
:       lsr fam + 1
        ror fam
        dey
        bne :-
        rts

; Look: name = the FONT file whose header holds fam (at $80), among the
; FONT files FindFTypes lists. C set: none.
Look:   lda #0                  ; the list, cleared
        tay
:       sta FONTLIST,y
        sta FONTLIST + $100,y
        iny
        bne :-
        lda #<FONTLIST
        sta r6L
        lda #>FONTLIST
        sta r6H
        lda #FONT
        sta r7L
        lda #LIST_MAX
        sta r7H
        lda #0
        sta r10L
        sta r10H
        jsr FindFTypes
        txa
        bne @none
        lda #<FONTLIST
        sta lp
        lda #>FONTLIST
        sta lp + 1
        lda #LIST_MAX
        sta left
@each:  ldy #0
        lda (lp),y
        beq @none
        lda lp
        sta r6L
        lda lp + 1
        sta r6H
        jsr FindFile
        txa
        bne @next
        lda #<dirEntryBuf
        sta r9L
        lda #>dirEntryBuf
        sta r9H
        jsr GetFHdrInfo
        txa
        bne @next
        lda fileHeader + $80
        cmp fam
        bne @next
        lda fileHeader + $81
        cmp fam + 1
        bne @next
        ldy #16                 ; found: its name
:       lda (lp),y
        sta name,y
        dey
        bpl :-
        lda #0
        sta name + 16
        clc
        rts
@next:  lda lp
        clc
        adc #17
        sta lp
        bcc :+
        inc lp + 1
:       dec left
        bne @each
@none:  sec
        rts

; Read: record (fid & 63, the size) of the font file `name` into
; FONTBUF. C set: not there.
Read:   lda #<name
        sta r0L
        lda #>name
        sta r0H
        jsr OpenRecordFile
        txa
        bne @no
        lda fid
        and #63
        jsr PointRecord
        txa
        bne @close
        lda #<FONTBUF
        sta r7L
        lda #>FONTBUF
        sta r7H
        lda #<FONT_MAX
        sta r2L
        lda #>FONT_MAX
        sta r2H
        jsr ReadRecord
        txa
        bne @close
        lda r7L                 ; (empty: r7 unchanged)
        cmp #<FONTBUF
        bne :+
        lda r7H
        cmp #>FONTBUF
        beq @close
:       jsr CloseRecordFile
        clc
        rts
@close: jsr CloseRecordFile
@no:    sec
        rts

; Widths: slot A's 96 widths from the image in FONTBUF (its index table:
; offset[c + 1] - offset[c]; a width is under 256).
Widths: jsr WPtr                ; gp = the slot's widths
        lda FONTBUF + 4         ; op = the index table
        clc
        adc #<FONTBUF
        sta op
        lda FONTBUF + 5
        adc #>FONTBUF
        sta op + 1
        ldx #0                  ; X = the character - 32
@w:     txa
        asl a
        tay
        iny
        iny
        lda (op),y
        dey
        dey
        sec
        sbc (op),y
        pha
        txa
        tay
        pla
        sta (gp),y
        inx
        cpx #96
        bcc @w
        rts

; SlotAX: A = the slot of the font ID A/X (lo/hi). SlotOf: of fid (0:
; the system font, or not found). Keep X, Y.
SlotAX: sta fid
        stx fid + 1
SlotOf: stx keep
        ldx nSlot
@find:  dex
        beq @sys
        lda slotFid,x
        cmp fid
        bne @find
        lda slotFidH,x
        cmp fid + 1
        bne @find
        txa
        ldx keep
        rts
@sys:   lda #0
        ldx keep
        rts

; UseSlot: slot A in use: its widths (wp), height and baseline. Keeps X,
; Y.
UseSlot:
        stx keep
        sty keepY
        sta curSlot
        tax
        lda slotH,x
        sta fHeight
        lda slotB,x
        sta fBase
        txa
        jsr WPtr
        lda gp
        sta wp
        lda gp + 1
        sta wp + 1
        ldx keep
        ldy keepY
        rts

; WPtr: gp = slot A's widths (FONTW + A * 96). Keeps X.
WPtr:   sta tmp
        lda #0
        sta tmp + 1
        ldy #5                  ; A * 32
:       asl tmp
        rol tmp + 1
        dey
        bne :-
        lda tmp                 ; * 3
        asl a
        sta gp
        lda tmp + 1
        rol a
        sta gp + 1
        lda gp
        clc
        adc tmp
        sta gp
        lda gp + 1
        adc tmp + 1
        sta gp + 1
        lda gp
        clc
        adc #<FONTW
        sta gp
        lda gp + 1
        adc #>FONTW
        sta gp + 1
        rts

; NamePtr: op = slot X's file name (FONTNAMES + X * 17). Keeps X.
NamePtr:
        lda #<FONTNAMES
        sta op
        lda #>FONTNAMES
        sta op + 1
        txa
        beq @end
        tay
@add:   lda op
        clc
        adc #17
        sta op
        bcc :+
        inc op + 1
:       dey
        bne @add
@end:   rts

; LoadImage: slot A's font image in FONTBUF (slot 0: the system font,
; copied from under the I/O area; others: their file's record), unless
; it is there already. No record file may be open. Destroys A, X, Y.
LoadImage:
        cmp loaded
        beq @end
        sta loaded
        cmp #0
        beq System0
        tax
        jsr NamePtr
        ldy #16
:       lda (op),y
        sta name,y
        dey
        bpl :-
        ldx loaded
        lda slotFid,x
        sta fid
        jsr Read
@end:   rts

; System0: the system font as a font record in FONTBUF: header, index
; table (97 words), bits (height rows of set width bytes).
System0:
        jsr UseSystemFont
        lda baselineOffset
        sta FONTBUF
        lda curSetWidth
        sta FONTBUF + 1
        lda curSetWidth + 1
        sta FONTBUF + 2
        lda curHeight
        sta FONTBUF + 3
        lda #8
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
        lda curIndexTable
        sta op
        lda curIndexTable + 1
        sta op + 1
        ldy #193
:       lda (op),y
        sta FONTBUF + 8,y
        dey
        cpy #$FF
        bne :-
        lda cardDataPntr
        sta op
        lda cardDataPntr + 1
        sta op + 1
        lda #<(FONTBUF + 8 + 194)
        sta gp
        lda #>(FONTBUF + 8 + 194)
        sta gp + 1
        ldx curHeight
@row:   ldy #0
:       lda (op),y
        sta (gp),y
        iny
        cpy curSetWidth         ; (the system font's rows are under 256)
        bne :-
        lda op
        clc
        adc curSetWidth
        sta op
        bcc :+
        inc op + 1
:       lda gp
        clc
        adc curSetWidth
        sta gp
        bcc :+
        inc gp + 1
:       dex
        bne @row
        pla
        sta CPU_PORT
        plp
        rts

; Width: A = the width of character A (32-127) in the slot in use, style
; X (GetRealSize: bold +1, outline +2). Keeps X, Y.
Width:  sty keepY
        sec
        sbc #32
        tay
        lda (wp),y
        ldy keepY
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

; Height, Base: A = the slot's height and baseline offset in style X
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
; reverse) in the image in FONTBUF (the slot in use loaded), as gwps's
; Font.cell: bold makes each column the font's bit or the one before
; (the cell one wider); the underline row (baseline + 1) is the line
; only, over the cell but its last column (all of it when bold); reverse
; inverts the cell; outline adds two blank columns (drawn plain, as
; GeoUltra's kernal). glyphW = the cell's width with them; GlyphBits
; then writes the rows as hex, each padded to whole bytes. Destroy A,
; X, Y, op.
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
:       lda FONTBUF + 4         ; the index table
        clc
        adc #<FONTBUF
        sta op
        lda FONTBUF + 5
        adc #>FONTBUF
        sta op + 1
        lda code                ; the glyph's first bit: offset[code - 32]
        sec
        sbc #32
        asl a
        tay
        lda (op),y
        sta first
        iny
        lda (op),y
        sta first + 1
        lda FONTBUF + 1
        sta setW
        lda FONTBUF + 2
        sta setW + 1
        rts

GlyphBits:
        lda FONTBUF + 6         ; the bits
        clc
        adc #<FONTBUF
        sta op
        lda FONTBUF + 7
        adc #>FONTBUF
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

; Shift: pix into the byte being made; a full byte written as hex.
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

nSlot:  .res 1
curSlot: .res 1
loaded: .res 1                  ; the slot whose image is in FONTBUF
slotFid: .res FONT_SLOTS
slotFidH: .res FONT_SLOTS
slotH:  .res FONT_SLOTS
slotB:  .res FONT_SLOTS
fid:    .res 2
fam:    .res 2
name:   .res 17
left:   .res 1
fHeight: .res 1
fBase:  .res 1
setW:   .res 2
keep:   .res 1
keepY:  .res 1
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
