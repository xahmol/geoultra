; Text: LoadCharSet, UseSystemFont, GetCharWidth, GetRealSize, PutChar,
; SmallPutChar, PutString, i_PutString, PutDecimal. Written from the
; HG2G2022 descriptions; checked against GEOS 2.0 with the conformance
; harness (tests/conformance/text.py). Styles: bold, underline and
; reverse so far; italic and outline are drawn plain for now.

        .include "geos.inc"

        .export LoadCharSet, UseSystemFont, GetCharWidth, GetRealSize
        .export PutChar, SmallPutChar, PutString, i_PutString, PutDecimal
        .export StringWidth, DeleteChar
        .import SystemFont, GetScanLine, GraphicsString

        .segment "DATA"

lastWidth:      .byte 0
glyphWidth:     .byte 0
cellWidth:      .byte 0
rowNo:          .byte 0
column:         .byte 0
prevBit:        .byte 0
clipLo:         .byte 0             ; the cell's first column inside the margins
clipEnd:        .byte 0             ; and the column after its last (ClipCols)
digits:         .res 5
digitCount:     .byte 0
decFormat:      .byte 0
swMode:         .byte 0
swIndex:        .byte 0

        .segment "RODATA"

bitMask:
        .byte $80, $40, $20, $10, $08, $04, $02, $01
decLo:  .byte <10000, <1000, <100, <10, <1
decHi:  .byte >10000, >1000, >100, >10, >1

        .segment "CODE"                 ; (not under I/O: GEOS 2.0 allows it with I/O on)

; LoadCharSet: r0 = font header. Destroys A, Y.
LoadCharSet:
        ldy #0
        lda (r0),y
        sta baselineOffset
        iny
        lda (r0),y
        sta curSetWidth
        iny
        lda (r0),y
        sta curSetWidth+1
        iny
        lda (r0),y
        sta curHeight
        iny
        lda (r0),y              ; index table = header + offset
        clc
        adc r0L
        sta curIndexTable
        iny
        lda (r0),y
        adc r0H
        sta curIndexTable+1
        iny
        lda (r0),y              ; bitstream = header + offset
        clc
        adc r0L
        sta cardDataPntr
        iny
        lda (r0),y
        adc r0H
        sta cardDataPntr+1
        rts

; UseSystemFont. Destroys A, X, Y, r0.
UseSystemFont:
        lda #<SystemFont
        sta r0L
        lda #>SystemFont
        sta r0H
        jmp LoadCharSet

; GetCharWidth: A = character. Returns A = plain width (0 below 32).
; Destroys Y.
GetCharWidth:
        cmp #32
        bcs @char
        lda #0
        rts
@char:  sec
        sbc #32
        asl
        tay
        iny
        iny
        lda (curIndexTable),y
        dey
        dey
        sec
        sbc (curIndexTable),y
        rts

; GetRealSize: A = character, X = style mode. Returns Y = width with the
; style, X = height, A = baseline offset.
GetRealSize:
        stx column
        jsr GetCharWidth
        tay
        lda column
        and #SET_BOLD
        beq @outline
        iny
@outline:
        ldx curHeight
        lda column
        and #SET_OUTLINE
        beq @plain
        iny
        iny
        inx
        inx
        lda baselineOffset      ; outline: baseline 2 lower
        clc
        adc #2
        rts
@plain: lda baselineOffset
        rts

; PutChar: A = character or escape code, r11 = x, r1H = baseline y.
; Returns r11 = next x. Destroys A, X, Y, r1L, r2-r10, r12, r13.
PutChar:
        cmp #32
        bcs @print
        jmp Escape
@print: pha
        ldx currentMode
        jsr GetRealSize
        sty lastWidth
        lda r11H                ; left of leftMargin: skip, advance, fault
        cmp leftMargin+1
        bcc @left
        bne @right
        lda r11L
        cmp leftMargin
        bcc @left
@right: lda r11L                ; r13 = right edge = x + width - 1
        clc
        adc lastWidth
        sta r13L
        lda r11H
        adc #0
        sta r13H
        lda r13L
        bne @dec
        dec r13H
@dec:   dec r13L
        lda rightMargin+1
        cmp r13H
        bcc @fault
        bne @draw
        lda rightMargin
        cmp r13L
        bcc @fault
@draw:  pla
        jsr DrawChar
        jmp Advance
@left:  pla
        jsr Advance
        jmp StringFault
@fault: pla
StringFault:
        lda StringFaultVec
        ora StringFaultVec+1
        beq @none
        jmp (StringFaultVec)
@none:  rts

; r11 += lastWidth
Advance:
        lda r11L
        clc
        adc lastWidth
        sta r11L
        bcc @end
        inc r11H
@end:   rts

; SmallPutChar: A = printable character, no escapes, no margin faults.
SmallPutChar:
        pha
        ldx currentMode
        jsr GetRealSize
        sty lastWidth
        pla
        jsr DrawChar
        jmp Advance

; Draw character A (32 or above) at r11/r1H in currentMode, clipped to
; leftMargin..rightMargin, windowTop..windowBottom and the screen.
DrawChar:
        pha
        jsr GetCharWidth
        sta glyphWidth
        sta cellWidth
        jsr ClipCols            ; (destroys A, X, Y; the character is on the stack)
        lda currentMode
        and #SET_BOLD
        beq @nobold
        inc cellWidth
@nobold:
        pla
        sec
        sbc #32
        asl
        tay
        lda (curIndexTable),y   ; r9 = bit offset of the glyph
        sta r9L
        iny
        lda (curIndexTable),y
        sta r9H

; Draw the cell (glyphWidth bits of the glyph at r9, cellWidth columns)
; row by row in currentMode.
DrawCell:
        lda r1H                 ; top above the screen: nothing is drawn (as
        cmp baselineOffset      ; GEOS 2.0, measured: not even the rows
        bcs @top                ; below line 0; tests/conformance/text.py)
        rts
@top:   lda cardDataPntr
        sta r4L
        lda cardDataPntr+1
        sta r4H
        lda #0
        sta rowNo
@row:   lda rowNo
        cmp curHeight
        bcs @done
        lda r1H                 ; r10H = screen line
        sec
        sbc baselineOffset
        clc
        adc rowNo
        sta r10H
        cmp windowTop
        bcc @next
        lda windowBottom
        cmp r10H
        bcc @next
        lda r10H
        cmp #SC_PIX_HEIGHT
        bcs @next
        jsr DrawRow
@next:  clc
        lda r4L
        adc curSetWidth
        sta r4L
        lda r4H
        adc curSetWidth+1
        sta r4H
        inc rowNo
        jmp @row
@done:  rts

; One pixel row of the character: font row at r4, glyph at bit r9.
SC_BYTE_LEN     = 8000          ; a bitmap's bytes (its end: base | $1F40)
        .assert <SCREEN_BASE = 0 && <BACK_SCR_BASE = 0 && (>SCREEN_BASE & $1F) = 0 && (>BACK_SCR_BASE & $1F) = 0, error, "DrawRow: bitmaps on 8 KB boundaries"
DrawRow:
        ldx r10H
        jsr GetScanLine
        lda r5H                 ; r12 = the end of r5's bitmap ($A000 or
        ora #>(SC_BYTE_LEN - 1) ; $6000 + 8000): a pixel past x 319 runs on
        sta r12H                ; into the next card row, as in GEOS 2.0
        lda r11L                ; r5/r6 += x & $FFF8
        and #$F8
        sta r12L
        clc
        adc r5L
        sta r5L
        lda r11H
        adc r5H
        sta r5H
        lda r12L
        clc
        adc r6L
        sta r6L
        lda r11H
        adc r6H
        sta r6H
        lda r11L
        and #7
        tax
        lda bitMask,x
        sta r7L                 ; screen bit
        lda r9L                 ; r2 = r4 + r9 / 8, r3L = font bit
        sta r2L
        lda r9H
        lsr
        ror r2L
        lsr
        ror r2L
        lsr
        ror r2L
        sta r2H
        clc
        lda r2L
        adc r4L
        sta r2L
        lda r2H
        adc r4H
        sta r2H
        lda r9L
        and #7
        tax
        lda bitMask,x
        sta r3L
        lda #<SC_BYTE_LEN
        sta r12L
        lda r10H                ; screen lines 152-159 drawn into the
        sec                     ; background: nothing past their card row
        sbc #152                ; (r12 = the background's base + $1900).
        cmp #8                  ; geoWrite prints a line in two bands, lines
        bcs :+                  ; 144-151 and 152-159 ($7680-$78FF); a
        bit dispBufferOn        ; character of the second past x 319 wrapped
        bvc :+                  ; into the printer driver at $7900 (its jump
        lda r12H                ; table: the user's brochure hung on page 3,
        and #$E0                ; 2026-11-21; tests/print/gwbroch.py)
        ora #>$1900
        sta r12H
        lda #0
        sta r12L
:       lda #0
        sta column
        sta prevBit
@col:   lda #0                  ; font bit of this column
        ldx column
        cpx glyphWidth
        bcs @bit
        ldy #0
        lda (r2),y
        and r3L
        beq @bit
        lda #1
@bit:   tax
        lda currentMode
        and #SET_BOLD
        beq @nobold
        txa
        ora prevBit
        stx prevBit
        tax
@nobold:
        lda currentMode         ; underline row: only the line, over the
        and #SET_UNDERLINE      ; cell minus its last column (the whole
        beq @noul               ; cell when bold), as GEOS 2.0
        lda baselineOffset
        clc
        adc #1
        cmp rowNo
        bne @noul
        ldy column              ; Y = column + 1, + 2 when not bold
        iny
        lda currentMode
        and #SET_BOLD
        bne @bold
        iny
@bold:  ldx #0
        cpy cellWidth
        beq @line
        bcs @noul
@line:  ldx #1
@noul:  lda currentMode
        and #SET_REVERSE
        beq @put
        txa
        eor #1
        tax
@put:   lda column              ; only the columns inside the margins
        cmp clipLo              ; (ClipCols: SmallPutChar clips, HG2G;
        bcc @skip               ; geoPublish narrows the margins to a
        cmp clipEnd             ; column, issue #1)
        bcs @skip
        lda r5H                 ; only within the bitmap (r5 < r12: geoWrite
        cmp r12H                ; prints a 640-dot line as two card rows,
        bcc @write              ; x 320-639 drawn as the next row's 0-319;
        bne @skip               ; the user's PDF lost a character a line at
        lda r5L                 ; x 320 until 2026-11-16, when only x < 320
        cmp r12L                ; was drawn)
        bcs @skip
@write: ldy #0
        txa
        beq @clear
        lda (r5),y
        ora r7L
        sta (r5),y
        lda (r6),y
        ora r7L
        sta (r6),y
        jmp @skip
@clear: lda r7L
        eor #$FF
        sta r13L
        lda (r5),y
        and r13L
        sta (r5),y
        lda (r6),y
        and r13L
        sta (r6),y
@skip:  lsr r7L                 ; next screen pixel
        bcc @font
        lda #$80
        sta r7L
        clc
        lda r5L
        adc #8
        sta r5L
        bcc @b6
        inc r5H
@b6:    clc
        lda r6L
        adc #8
        sta r6L
        bcc @font
        inc r6H
@font:  lsr r3L                 ; next font bit
        bcc @x
        lda #$80
        sta r3L
        inc r2L
        bne @x
        inc r2H
@x:     inc column
        lda column
        cmp cellWidth
        beq @end
        jmp @col
@end:   rts

; ClipCols: clipLo/clipEnd = the cell's columns (from r11) inside
; leftMargin..rightMargin, 0..255: columns clipLo to clipEnd - 1 are drawn.
; Signed 16-bit (r11 may be a little negative). Destroys A, X, Y.
; Own code from HG2G's description of SmallPutChar and GEOS 2.0's
; behaviour measured in the conformance harness (tests/conformance/text.py).
        .segment "KCODE"
ClipCols:
        lda leftMargin          ; leftMargin - x
        sec
        sbc r11L
        tax
        lda leftMargin+1
        sbc r11H
        jsr @clamp
        stx clipLo
        lda rightMargin         ; rightMargin - x + 1
        sec
        sbc r11L
        tax
        lda rightMargin+1
        sbc r11H
        inx
        bne :+
        clc
        adc #1
:       jsr @clamp
        stx clipEnd
        rts
@clamp: tay                     ; A:X signed -> X 0..255
        bpl :+
        ldx #0
        rts
:       beq :+
        ldx #$FF
:       rts
        .segment "CODE"

; Escape codes below 32. Multi-byte codes read their parameters through
; r0 (PutString keeps r0 on the current byte).
Escape:
        cmp #BACKSPACE
        bne @notBs
        jmp EraseLast
@notBs: cmp #CR
        beq @cr
        cmp #LF
        beq @lf
        cmp #UPLINE
        beq @up
        cmp #HOME
        beq @home
        cmp #GOTOX
        beq @gotox
        cmp #GOTOY
        beq @gotoy
        cmp #GOTOXY
        beq @gotoxy
        cmp #ESC_GRAPHICS
        beq @graphics
        ldx #6                  ; style codes
@style: cmp styleCode,x
        beq @setStyle
        dex
        bpl @style
        cmp #PLAINTEXT
        bne @end
        lda #SET_PLAINTEXT
        sta currentMode
@end:   rts
@setStyle:
        lda currentMode
        and styleAnd,x
        ora styleOr,x
        sta currentMode
        rts
@cr:    lda leftMargin
        sta r11L
        lda leftMargin+1
        sta r11H
@lf:    lda r1H
        sec
        adc curHeight
        sta r1H
        rts
@up:    lda r1H                 ; up curHeight lines (LF goes down one more)
        sec
        sbc curHeight
        sta r1H
        rts
@home:  lda #0
        sta r11L
        sta r11H
        sta r1H
        rts
@gotox: jsr NextByte
        sta r11L
        jsr NextByte
        sta r11H
        rts
@gotoy: jsr NextByte
        sta r1H
        rts
@gotoxy:
        jsr @gotox
        jmp @gotoy
@graphics:                      ; a graphics string up to its NULL, which
        inc r0L                 ; also ends this string: leave r0 one before
        bne @gs                 ; the NULL for PutString's increment
        inc r0H
@gs:    jsr GraphicsString
        sec
        lda r0L
        sbc #2
        sta r0L
        bcs @gsEnd
        dec r0H
@gsEnd: rts

; r0 += 1, A = (r0)
NextByte:
        inc r0L
        bne @get
        inc r0H
@get:   ldy #0
        lda (r0),y
        rts

        .segment "RODATA"
styleCode:
        .byte ULINEON, ULINEOFF, REVON, REVOFF, BOLDON, ITALICON, OUTLINEON
styleAnd:
        .byte $FF, <~SET_UNDERLINE, $FF, <~SET_REVERSE, $FF, $FF, $FF
styleOr:
        .byte SET_UNDERLINE, 0, SET_REVERSE, 0, SET_BOLD, SET_ITALIC, SET_OUTLINE

        .segment "CODE"                 ; (not under I/O: GEOS 2.0 allows it with I/O on)

; PutString: r0 = string, r11 = x, r1H = y. Returns r0 at the NULL.
PutString:
@loop:  ldy #0
        lda (r0),y
        beq @end
        jsr PutChar
        inc r0L
        bne @loop
        inc r0H
        bne @loop
@end:   rts

; i_PutString: .word x, .byte y, string, 0 follow the jsr.
i_PutString:
        pla
        sta r0L
        pla
        sta r0H
        jsr NextByte
        sta r11L
        jsr NextByte
        sta r11H
        jsr NextByte
        sta r1H
        inc r0L
        bne @put
        inc r0H
@put:   jsr PutString
        lda r0H                 ; return to the byte after the NULL
        pha
        lda r0L
        pha
        rts

        .segment "BFCODE"       ; $BF40-$BFFF (GEOS 2.0's kernal starts there too)

; PutDecimal: A = format, r0 = number, r11 = x, r1H = y.
PutDecimal:
        sta decFormat
        ldx #0                  ; five digits, most significant first
@digit: ldy #0
@sub:   lda r0L
        sec
        sbc decLo,x
        pha
        lda r0H
        sbc decHi,x
        bcc @less
        sta r0H
        pla
        sta r0L
        iny
        bne @sub
@less:  pla
        tya
        sta digits,x
        inx
        cpx #5
        bne @digit
        ldx #0                  ; first digit to print
        lda decFormat
        and #SET_SUPRESS
        beq @first
@lead:  cpx #4
        beq @first
        lda digits,x
        bne @first
        inx
        bne @lead
@first: stx digitCount
        lda decFormat           ; right justify in the field width
        bmi @print
        lda #0
        sta r0L
@width: lda digits,x
        ora #'0'
        jsr GetCharWidth
        clc
        adc r0L
        sta r0L
        inx
        cpx #5
        bne @width
        lda decFormat
        and #$3F
        sec
        sbc r0L
        bcc @print
        clc
        adc r11L
        sta r11L
        bcc @print
        inc r11H
@print: ldx digitCount
@out:   lda digits,x
        ora #'0'
        stx digitCount
        jsr PutChar
        ldx digitCount
        inx
        cpx #5
        bne @out
        rts

; StringWidth (GeoUltra, no GEOS jump table entry): r0 = string (up to
; 255 bytes). Returns r2 = its width in pixels in the current font,
; following the style codes in it from currentMode (bold is wider);
; position codes are skipped. For centring and laying out text by its
; measured width. Destroys A, X, Y.
        .segment "CODE"

StringWidth:
        lda currentMode
        sta swMode
        lda #0
        sta r2L
        sta r2H
        sta swIndex
@loop:  ldy swIndex
        lda (r0),y
        beq @done
        inc swIndex
        cmp #32
        bcc @code
        ldx swMode
        jsr GetRealSize
        tya
        clc
        adc r2L
        sta r2L
        bcc @loop
        inc r2H
        bne @loop
@code:  ldx #6                  ; style codes as PutChar
@style: cmp styleCode,x
        beq @set
        dex
        bpl @style
        cmp #PLAINTEXT
        bne @pos
        lda #SET_PLAINTEXT
        sta swMode
        jmp @loop
@set:   lda swMode
        and styleAnd,x
        ora styleOr,x
        sta swMode
        jmp @loop
@pos:   ldx #2                  ; skip the parameters of position codes
        cmp #GOTOX
        beq @skip
        dex
        cmp #GOTOY
        beq @skip
        ldx #3
        cmp #GOTOXY
        bne @loop
@skip:  txa
        clc
        adc swIndex
        sta swIndex
        jmp @loop
@done:  rts

; DeleteChar (GeoUltra, for GetString): A = the character before r11 in
; currentMode; moves r11 back by its width and clears its cell.
DeleteChar:
        ldx currentMode
        jsr GetRealSize
        sty lastWidth

; BACKSPACE: move r11 back by the last character's width and clear that
; cell (in the font's height, per dispBufferOn and the window).
EraseLast:
        lda r11L
        sec
        sbc lastWidth
        sta r11L
        bcs @x
        dec r11H
@x:     lda r11L
        pha
        lda r11H
        pha
        lda currentMode
        pha
        lda #SET_PLAINTEXT      ; an empty plain cell of lastWidth columns
        sta currentMode
        sta glyphWidth
        lda lastWidth
        sta cellWidth
        jsr DrawCell
        pla
        sta currentMode
        pla
        sta r11H
        pla
        sta r11L
        rts
