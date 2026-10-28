; Text: LoadCharSet, UseSystemFont, GetCharWidth, GetRealSize, PutChar,
; SmallPutChar, PutString, i_PutString, PutDecimal. Written from the
; HG2G2022 descriptions; checked against GEOS 2.0 with the conformance
; harness (tests/conformance/text.py). Styles: bold, underline and
; reverse so far; italic and outline are drawn plain for now.

        .include "geos.inc"

        .export LoadCharSet, UseSystemFont, GetCharWidth, GetRealSize
        .export PutChar, SmallPutChar, PutString, i_PutString, PutDecimal
        .import SystemFont, GetScanLine

        .segment "DATA"

lastWidth:      .byte 0
glyphWidth:     .byte 0
cellWidth:      .byte 0
rowNo:          .byte 0
column:         .byte 0
prevBit:        .byte 0
digits:         .res 5
digitCount:     .byte 0
decFormat:      .byte 0

        .segment "RODATA"

bitMask:
        .byte $80, $40, $20, $10, $08, $04, $02, $01
decLo:  .byte <10000, <1000, <100, <10, <1
decHi:  .byte >10000, >1000, >100, >10, >1

        .segment "CODE"

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
; windowTop..windowBottom and the screen.
DrawChar:
        pha
        jsr GetCharWidth
        sta glyphWidth
        sta cellWidth
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
        lda r1H                 ; top above the screen: nothing is drawn
        cmp baselineOffset
        bcs @top
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
DrawRow:
        ldx r10H
        jsr GetScanLine
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
        lda r11L                ; r12 = x of the current pixel
        sta r12L
        lda r11H
        sta r12H
        lda #0
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
@put:   lda r12H                ; only on screen (x < 320)
        cmp #>SC_PIX_WIDTH
        bcc @write
        bne @skip
        lda r12L
        cmp #<SC_PIX_WIDTH
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
@x:     inc r12L
        bne @cnt
        inc r12H
@cnt:   inc column
        lda column
        cmp cellWidth
        beq @end
        jmp @col
@end:   rts

; Escape codes below 32. Multi-byte codes read their parameters through
; r0 (PutString keeps r0 on the current byte).
Escape:
        cmp #CR
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

        .segment "CODE"

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
