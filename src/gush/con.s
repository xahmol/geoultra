; gush: the console (docs/design/GUSH.md, "Screen"). 53 columns and 25 rows of
; 6x8 cells drawn straight into the hi-res bitmap with gush's own font
; (tools/fonts/gush6.py); row 0 the status line (inverted), rows 1-24
; text that scrolls. A text copy of rows 1-24 (shadow) for redrawing and
; for the tests. Own code.

        .include "geos.inc"
        .include "gush.inc"

        .import sinkOn, sinkPause, SinkPut
        .export ConInit, ConPut, ConPuts, ConNewLine, ConClear, ConCell, ConSet
        .export ConRedraw
        .export ConCursor, ConStatus, conCol, conRow, shadow

MoveData        = $C17E         ; GEOS jump table

        .segment "ZEROPAGE"     ; (first: the code addresses them as such)

glyph:          .res 2          ; ConCell: the glyph, the cell in the bitmap
cell:           .res 2
shPtr:          .res 2          ; a row of the shadow

        .segment "CODE"

; ConInit: colours (screencolors), the screen cleared, the cursor home.
; Destroys A, X, Y, r0-r2.
ConInit:
        ldx #0
        lda screencolors
@col:   sta COLOR_MATRIX,x
        sta COLOR_MATRIX + $100,x
        sta COLOR_MATRIX + $200,x
        sta COLOR_MATRIX + $2E8,x
        inx
        bne @col
; ConClear: rows 1-24 and their shadow cleared, the cursor at row 1,
; column 0.
ConClear:
        lda #<(SCREEN_BASE + 320)
        sta r0L
        lda #>(SCREEN_BASE + 320)
        sta r0H
        ldx #>(ROWS_TEXT * 320) ; whole pages, then the rest
        ldy #0
        tya
@page:  sta (r0),y
        iny
        bne @page
        inc r0H
        dex
        bne @page
@rest:  cpy #<(ROWS_TEXT * 320)
        beq @shadow
        sta (r0),y
        iny
        bne @rest
@shadow:
        lda #<shadow
        sta r0L
        lda #>shadow
        sta r0H
        ldx #>(ROWS_TEXT * COLS)
        lda #' '
        ldy #0
@sp:    sta (r0),y
        iny
        bne @sp
        inc r0H
        dex
        bne @sp
@sr:    cpy #<(ROWS_TEXT * COLS)
        beq @home
        sta (r0),y
        iny
        bne @sr
@home:  lda #0
        sta conCol
        lda #1
        sta conRow
        rts

; ConRedraw: rows 1-24 drawn again from the shadow (after a desk
; accessory used the screen). Destroys A, X, Y.
ConRedraw:
        lda #1
        sta setRow
@row:   ldx setRow
        jsr ShadowAt
        lda #0
        sta setCol
@col:   ldy setCol
        lda (shPtr),y
        ldx setCol
        ldy setRow
        jsr ConCellA
        inc setCol
        lda setCol
        cmp #COLS
        bne @col
        inc setRow
        lda setRow
        cmp #ROWS_LAST + 1
        bne @row
        rts

; ConPuts: the zero-ended text at (r0) (CR: a new line). Destroys A, X,
; Y, r0.
ConPuts:
        ldy #0
        lda (r0),y
        beq @end
        jsr ConPut
        inc r0L
        bne ConPuts
        inc r0H
        bne ConPuts
@end:   rts

; ConPut: character A at the cursor (CR: a new line); the cursor on, a
; new line at the right edge. Destroys A, X, Y.
ConPut: bit sinkOn              ; output to a file (redir.s)?
        bpl @screen
        ldx sinkPause
        bne @screen
        jmp SinkPut             ; (a CR as it is)
@screen:
        cmp #CR
        beq ConNewLine
        pha                     ; into the shadow
        ldx conRow
        jsr ShadowAt
        ldy conCol
        pla
        sta (shPtr),y
        ldx conCol
        ldy conRow
        jsr ConCellA
        inc conCol
        lda conCol
        cmp #COLS
        bcs ConNewLine
        rts
; ConNewLine: the cursor to the next line's start, scrolling at the
; bottom. Destroys A, X, Y.
ConNewLine:
        bit sinkOn              ; output to a file: a CR there (a paused
        bpl @screen             ; line, an error or a question, ends
        lda sinkPause           ; on the screen)
        bne @screen
        lda #CR
        jmp SinkPut
@screen:
        lda #0
        sta sinkPause           ; (the pause ends with its line)
        sta conCol
        lda conRow
        cmp #ROWS_LAST
        bcs Scroll
        inc conRow
@end:   rts

; Scroll: rows 2-24 up one (bitmap and shadow), row 24 cleared.
Scroll: lda r0L                 ; (r0-r2 kept: callers print from r0)
        pha
        lda r0H
        pha
        lda r1L
        pha
        lda r1H
        pha
        lda r2L
        pha
        lda r2H
        pha
        lda #<(SCREEN_BASE + 640)
        sta r0L
        lda #>(SCREEN_BASE + 640)
        sta r0H
        lda #<(SCREEN_BASE + 320)
        sta r1L
        lda #>(SCREEN_BASE + 320)
        sta r1H
        lda #<((ROWS_TEXT - 1) * 320)
        sta r2L
        lda #>((ROWS_TEXT - 1) * 320)
        sta r2H
        jsr MoveData
        lda #<(shadow + COLS)
        sta r0L
        lda #>(shadow + COLS)
        sta r0H
        lda #<shadow
        sta r1L
        lda #>shadow
        sta r1H
        lda #<((ROWS_TEXT - 1) * COLS)
        sta r2L
        lda #>((ROWS_TEXT - 1) * COLS)
        sta r2H
        jsr MoveData
        ldx #0                  ; the last row cleared
        lda #0
@bits:  sta SCREEN_BASE + ROWS_LAST * 320,x
        sta SCREEN_BASE + ROWS_LAST * 320 + 64,x
        inx
        bne @bits
        lda #' '
        ldx #COLS - 1
@chars: sta shadow + (ROWS_TEXT - 1) * COLS,x
        dex
        bpl @chars
        pla
        sta r2H
        pla
        sta r2L
        pla
        sta r1H
        pla
        sta r1L
        pla
        sta r0H
        pla
        sta r0L
        rts
        .assert 256 + 64 = 320, error, "Scroll: a row is 320 bytes"

; ShadowAt: shPtr = the shadow's row X (1-24). Destroys A.
ShadowAt:
        lda shRowLo-1,x
        sta shPtr
        lda shRowHi-1,x
        sta shPtr+1
        rts

; ConSet: character A in column X, row Y (1-24): shadow and screen; the
; cursor stays. Destroys A, X, Y.
ConSet: sta setChar
        stx setCol
        sty setRow
        ldx setRow
        jsr ShadowAt
        ldy setCol
        lda setChar
        sta (shPtr),y
        ldx setCol
        ldy setRow
        lda setChar
        jmp ConCellA

; ConCursor: the cell at the cursor drawn inverted (A nonzero) or plain
; (A = 0), from the shadow. Destroys A, X, Y.
ConCursor:
        beq :+
        lda #$FC
:       sta conInv
        ldx conRow
        jsr ShadowAt
        ldy conCol
        cpy #COLS
        bcs @end
        lda (shPtr),y
        ldx conCol
        ldy conRow
        jsr ConCell
        lda #0
        sta conInv
@end:   rts

; ConCellA: ConCell with conInv 0.
ConCellA:
        pha
        lda #0
        sta conInv
        pla
; ConCell: character A (32-127) in column X, row Y, its pixels XORed
; with conInv ($FC: inverted). Destroys A, X, Y.
ConCell:
        sec                     ; the glyph: Font + (A - 32) * 8
        sbc #32
        bcs :+
        lda #0                  ; (a control character: a space)
:       sta glyph
        lda #0
        asl glyph
        rol a
        asl glyph
        rol a
        asl glyph
        rol a
        sta glyph+1
        lda glyph
        clc
        adc #<Font
        sta glyph
        lda glyph+1
        adc #>Font
        sta glyph+1
        lda rowLo,y             ; the cell's first byte in the bitmap
        clc
        adc colLo,x
        sta cell
        lda rowHi,y
        adc colHi,x
        sta cell+1
        lda colShift,x
        sta shift
        ldy #7
@line:  lda (glyph),y           ; a row: 6 pixels, in two bytes
        eor conInv
        sta bits
        lda #0
        sta bits+1
        lda #$FC
        sta mask
        lda #0
        sta mask+1
        ldx shift
        beq @put
@sh:    lsr bits
        ror bits+1
        lsr mask
        ror mask+1
        dex
        bne @sh
@put:   lda mask
        eor #$FF
        and (cell),y
        ora bits
        sta (cell),y
        lda mask+1
        beq @next
        tya
        clc
        adc #8                  ; (the next byte column: 8 further)
        tay
        lda mask+1
        eor #$FF
        and (cell),y
        ora bits+1
        sta (cell),y
        tya
        sec
        sbc #8
        tay
@next:  dey
        bpl @line
        rts

; ConStatus: row 0 inverted: "gush", the text at (r0) cut from the left to
; fit, the time (hour, minutes), the close "x". Destroys A, X, Y, r0.
ConStatus:
        lda #$FC
        sta conInv
        ldx #COLS - 1           ; all of it blank (inverted) first
@blank: txa
        pha
        lda #' '
        ldy #0
        jsr ConCell
        pla
        tax
        dex
        bpl @blank
        ldx #1
        ldy #0
@gush:  lda Name,y              ; " gush "
        beq @path
        stx statusCol
        sty statusIdx
        ldy #0
        jsr ConCell
        ldx statusCol
        ldy statusIdx
        inx
        iny
        bne @gush
@path:  ldy #$FF                ; the path's length
@len:   iny
        lda (r0),y
        bne @len
        tya                     ; longer than its room: "<" and its end
        sec
        sbc #STATUS_PATH
        bcc @all
        tay
        iny                     ; (one more for the "<")
        sty statusIdx
        lda #'<'
        ldx #STATUS_FROM
        ldy #0
        jsr ConCell
        ldx #STATUS_FROM + 1
        ldy statusIdx
        jmp @chars
@all:   ldx #STATUS_FROM
        ldy #0
@chars: lda (r0),y
        beq @time
        stx statusCol
        sty statusIdx
        ldy #0
        jsr ConCell
        ldx statusCol
        ldy statusIdx
        inx
        iny
        bne @chars
@time:  lda hour
        ldx #COLS - 8
        jsr Two
        lda #':'
        ldx #COLS - 6
        ldy #0
        jsr ConCell
        lda minutes
        ldx #COLS - 5
        jsr Two
        lda #'x'                ; the close button (edit.s EdPress)
        ldx #CLOSE_COL
        ldy #0
        jsr ConCell
        lda #0
        sta conInv
        rts

; Two: A (0-99) as two digits in row 0 from column X.
Two:    ldy #'0' - 1
        sec
@ten:   iny
        sbc #10
        bcs @ten
        adc #10 + '0'
        pha
        tya
        stx statusCol
        ldy #0
        jsr ConCell
        pla
        ldx statusCol
        inx
        ldy #0
        jmp ConCell

Name:   .byte "gush", 0
        .assert STATUS_FROM + STATUS_PATH + 9 = COLS, error, "ConStatus: the columns"

; Tables: each row's first bitmap byte; each column's byte offset and
; pixel shift (column * 6 pixels).
rowLo:
        .repeat ROWS, r
        .byte <(SCREEN_BASE + r * 320)
        .endrepeat
rowHi:
        .repeat ROWS, r
        .byte >(SCREEN_BASE + r * 320)
        .endrepeat
colLo:
        .repeat COLS, c
        .byte <((c * 6 / 8) * 8)
        .endrepeat
colHi:
        .repeat COLS, c
        .byte >((c * 6 / 8) * 8)
        .endrepeat
colShift:
        .repeat COLS, c
        .byte (c * 6) .mod 8
        .endrepeat
shRowLo:
        .repeat ROWS_TEXT, r
        .byte <(shadow + r * COLS)
        .endrepeat
shRowHi:
        .repeat ROWS_TEXT, r
        .byte >(shadow + r * COLS)
        .endrepeat

Font:
        .include "gushfont.inc"

        .segment "DATA"

conCol:         .byte 0
conRow:         .byte 0
conInv:         .byte 0
shift:          .byte 0
bits:           .word 0
mask:           .word 0
statusCol:      .byte 0
setChar:        .byte 0
setCol:         .byte 0
setRow:         .byte 0
statusIdx:      .byte 0

        .segment "BSS"

        .segment "HIGHBSS"
shadow:         .res ROWS_TEXT * COLS
        .segment "BSS"
