; Graphics primitives: GetScanLine, SetPattern, HorizontalLine,
; InvertLine, RecoverLine, VerticalLine, Rectangle, FrameRectangle,
; InvertRectangle, RecoverRectangle, ImprintRectangle, BitmapUp and the
; inline i_ variants. Written from the HG2G2022 descriptions (parameters, Uses,
; Destroys); checked against GEOS 2.0 with the conformance harness.

        .include "geos.inc"

        .export GetScanLine, SetPattern, HorizontalLine, VerticalLine
        .export Rectangle, FrameRectangle
        .export InvertLine, RecoverLine, InvertRectangle, RecoverRectangle
        .export ImprintRectangle, i_Rectangle, i_FrameRectangle
        .export i_RecoverRectangle, i_ImprintRectangle, BitmapUp, i_BitmapUp
        .import patterns

        .segment "DATA"

kMask:  .res 1
kInv:   .res 1
kBits:  .res 1
kPat:   .res 1
kY:     .res 1
kSave:  .res 4
kOp:    .res 1          ; LineOp: OP_PATTERN, OP_INVERT, OP_RECOVER, OP_IMPRINT
kDisp:  .res 1          ; dispBufferOn at the start of a LineOp

OP_PATTERN      = 0
OP_INVERT       = 1
OP_RECOVER      = 2
OP_IMPRINT      = 3

        .segment "RODATA"

rowLo:
        .repeat 25, row
        .byte <(row * 320)
        .endrepeat
rowHi:
        .repeat 25, row
        .byte >(row * 320)
        .endrepeat
leftMask:
        .byte $FF, $7F, $3F, $1F, $0F, $07, $03, $01
rightMask:
        .byte $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF
bitMask:
        .byte $80, $40, $20, $10, $08, $04, $02, $01

        .segment "CODE"

; GetScanLine: X = y. Returns r5/r6 = line addresses in the foreground
; and background screen as selected by dispBufferOn. Destroys A.
GetScanLine:
        tya
        pha
        txa
        lsr
        lsr
        lsr
        tay
        txa
        and #7
        clc
        adc rowLo,y
        sta r5L
        sta r6L
        lda rowHi,y
        adc #0
        pha
        clc
        adc #>BACK_SCR_BASE
        sta r6H
        pla
        clc
        adc #>SCREEN_BASE
        sta r5H
        bit dispBufferOn
        bpl @noFore
        bvs @done               ; both: r5 foreground, r6 background
        lda r5L                 ; foreground only
        sta r6L
        lda r5H
        sta r6H
        jmp @done
@noFore:
        bvc @none
        lda r6L                 ; background only
        sta r5L
        lda r6H
        sta r5H
        jmp @done
@none:  lda #<(SCREEN_BASE + 12 * 320 + 160)
        sta r5L
        sta r6L
        lda #>(SCREEN_BASE + 12 * 320 + 160)
        sta r5H
        sta r6H
@done:  pla
        tay
        rts

; SetPattern: A = system pattern 0-31; curPattern points to its 8 bytes.
SetPattern:
        asl
        asl
        asl
        clc
        adc #<patterns
        sta curPattern
        lda #0
        adc #>patterns
        sta curPattern+1
        rts

; HorizontalLine: A = pattern byte, r3 = x1, r4 = x2, r11L = y.
; Destroys A, X, Y, r5-r8, r11H.
HorizontalLine:
        sta r11H
        lda #OP_PATTERN
        jmp LineOp

; InvertLine: r3 = x1, r4 = x2, r11L = y; inverts per dispBufferOn (with
; both buffers on, the background gets the inverted foreground).
; Destroys A, X, Y, r5-r8.
InvertLine:
        lda #OP_INVERT
        jmp LineOp

; RecoverLine: r3 = x1, r4 = x2, r11L = y; background to foreground.
; Destroys A, X, Y, r5-r8.
RecoverLine:
        lda #OP_RECOVER
        jmp LineOp

; ImprintLine (no jump table entry): foreground to background.
ImprintLine:
        lda #OP_IMPRINT

; One screen line from r3 to r4 at r11L, card by card, with operation A.
LineOp:
        sta kOp
        lda dispBufferOn
        sta kDisp
        lda kOp                 ; all but the pattern line address both
        beq @scan               ; buffers whatever dispBufferOn says
        lda #ST_WR_FORE | ST_WR_BACK
        sta dispBufferOn
@scan:  ldx r11L
        jsr GetScanLine
        lda kDisp
        sta dispBufferOn
        lda r3L
        and #$F8
        sta r7L
        lda r3H
        sta r7H
        jsr AddR7
        lda r4L                 ; r8L = number of cards after the first
        and #$F8
        sec
        sbc r7L
        sta r8L
        lda r4H
        sbc r7H
        sta r8H
        lsr r8H
        ror r8L
        lsr r8H
        ror r8L
        lsr r8H
        ror r8L
        lda r3L
        and #7
        tax
        lda leftMask,x
        sta r7L
        lda r4L
        and #7
        tax
        lda rightMask,x
        sta r7H
        lda r8L
        bne @multi
        lda r7L
        and r7H
        jmp PutMasked
@multi: lda r7L
        jsr PutMasked
@mid:   jsr NextCard
        dec r8L
        beq @last
        lda #$FF
        jsr PutMasked
        jmp @mid
@last:  lda r7H
        jmp PutMasked

; r5 += r7, r6 += r7
AddR7:  clc
        lda r5L
        adc r7L
        sta r5L
        lda r5H
        adc r7H
        sta r5H
        clc
        lda r6L
        adc r7L
        sta r6L
        lda r6H
        adc r7H
        sta r6H
        rts

; r5 += 8, r6 += 8
NextCard:
        clc
        lda r5L
        adc #8
        sta r5L
        bcc @fore
        inc r5H
@fore:  clc
        lda r6L
        adc #8
        sta r6L
        bcc @back
        inc r6H
@back:  rts

; Apply the LineOp operation to the bits of mask A at (r5) and (r6).
PutMasked:
        sta kMask
        eor #$FF
        sta kInv
        ldy #0
        ldx kOp
        beq @pattern
        dex
        beq @invert
        dex
        beq @recover
        lda (r5),y              ; imprint: foreground into background
        and kMask
        sta kBits
        lda (r6),y
        and kInv
        ora kBits
        sta (r6),y
        rts
@recover:
        lda (r6),y              ; background into foreground
        and kMask
        sta kBits
        lda (r5),y
        and kInv
        ora kBits
        sta (r5),y
        rts
@invert:
        bit kDisp
        bpl @backOnly
        lda (r5),y
        eor kMask
        sta (r5),y
        bvc @end                ; foreground only
        sta (r6),y              ; background gets the whole new foreground
@end:   rts                     ; byte, edge bits included (as GEOS 2.0)
@backOnly:
        bvc @end
        lda (r6),y
        eor kMask
        sta (r6),y
        rts
@pattern:
        lda r11H
        and kMask
        sta kBits
        lda (r5),y
        and kInv
        ora kBits
        sta (r5),y
        lda (r6),y
        and kInv
        ora kBits
        sta (r6),y
        rts

; VerticalLine: A = pattern byte (bit 7 for the lines with y & 7 = 0),
; r3L = y1, r3H = y2, r4 = x. Destroys A, X, Y, r5-r7.
VerticalLine:
        sta kPat
        lda r4L
        and #7
        tax
        lda bitMask,x
        sta kMask
        eor #$FF
        sta kInv
        lda r3L
        sta kY
@loop:  ldx kY
        jsr GetScanLine
        lda r4L
        and #$F8
        sta r7L
        lda r4H
        sta r7H
        jsr AddR7
        lda kY
        and #7
        tax
        lda kPat
        and bitMask,x
        beq @set
        lda kMask
@set:   sta kBits
        ldy #0
        lda (r5),y
        and kInv
        ora kBits
        sta (r5),y
        lda (r6),y
        and kInv
        ora kBits
        sta (r6),y
        lda kY
        cmp r3H
        beq @done
        inc kY
        jmp @loop
@done:  rts

; Rectangle: r2L = y1, r2H = y2, r3 = x1, r4 = x2, filled with the
; current pattern. Destroys A, X, Y, r5-r8, r11.
Rectangle:
        lda r2L
        sta r11L
@loop:  lda r11L
        and #7
        tay
        lda (curPattern),y
        jsr HorizontalLine
        lda r11L
        cmp r2H
        beq @done
        inc r11L
        jmp @loop
@done:  rts

; FrameRectangle: A = pattern byte, r2L/r2H = y1/y2, r3/r4 = x1/x2.
; Destroys A, X, Y, r5-r8, r11.
FrameRectangle:
        sta kPat
        lda r2L
        sta r11L
        lda kPat
        jsr HorizontalLine
        lda r2H
        sta r11L
        lda kPat
        jsr HorizontalLine
        ldx #3
@save:  lda r3,x
        sta kSave,x
        dex
        bpl @save
        lda r2L
        sta r3L
        lda r2H
        sta r3H
        lda kSave               ; left edge
        sta r4L
        lda kSave+1
        sta r4H
        lda kPat
        pha
        jsr VerticalLine
        lda kSave+2             ; right edge
        sta r4L
        lda kSave+3
        sta r4H
        pla
        jsr VerticalLine
        ldx #3
@rest:  lda kSave,x
        sta r3,x
        dex
        bpl @rest
        rts

; InvertRectangle, RecoverRectangle, ImprintRectangle: r2L/r2H = y1/y2,
; r3/r4 = x1/x2. Destroy A, X, Y, r5-r8, r11.
InvertRectangle:
        lda #OP_INVERT
        bne RectOp
RecoverRectangle:
        lda #OP_RECOVER
        bne RectOp
ImprintRectangle:
        lda #OP_IMPRINT
RectOp: sta kPat
        lda r2L
        sta r11L
@loop:  lda kPat
        jsr LineOp
        lda r11L
        cmp r2H
        beq @done
        inc r11L
        jmp @loop
@done:  rts

; Inline variants: the parameters follow the jsr (.byte y1, y2,
; .word x1, x2, and for i_FrameRectangle a pattern byte).
i_Rectangle:
        jsr InlineRect
        jsr Rectangle
        jmp InlineReturn
i_RecoverRectangle:
        jsr InlineRect
        jsr RecoverRectangle
        jmp InlineReturn
i_ImprintRectangle:
        jsr InlineRect
        jsr ImprintRectangle
        jmp InlineReturn
i_FrameRectangle:
        jsr InlineRect
        inc inlineLen
        ldy #7
        lda (r5),y              ; r5 = inlinePtr after InlineRect
        jsr FrameRectangle
        jmp InlineReturn

; Read the six rectangle bytes after the caller's jsr into r2-r4.
InlineRect:
        ldx #r2
        bne InlineArgs

; Read the six bytes after the caller's jsr into zero page from X on.
; inlinePtr (and r5) = address of the last byte of that jsr.
InlineArgs:
        pla                     ; our own return address
        sta inlineSelf
        pla
        sta inlineSelf+1
        pla
        sta inlinePtr
        sta r5L
        pla
        sta inlinePtr+1
        sta r5H
        ldy #1
@copy:  lda (r5),y
        sta $00,x
        inx
        iny
        cpy #7
        bne @copy
        lda #6
        sta inlineLen
        lda inlineSelf+1
        pha
        lda inlineSelf
        pha
        rts

; Return to the byte after the inline data (rts to its address - 1,
; which is the last data byte).
InlineReturn:
        lda inlinePtr
        clc
        adc inlineLen
        tax
        lda inlinePtr+1
        adc #0
        pha
        txa
        pha
        rts

        .segment "DATA"
inlineSelf:     .res 2
inlinePtr:      .res 2
inlineLen:      .res 1

; BitmapUp: r0 = compacted bitmap, r1L = x in cards, r1H = y, r2L =
; width in cards, r2H = height in lines; drawn per dispBufferOn.
; Destroys A, X, Y, r0-r9L.
;
; Compaction (HG2G2022, "GEOS Compacted Bitmap Format"): COUNT 1-127
; repeats the next byte COUNT times, 129-219 copies the next COUNT-128
; bytes, 221-255 repeats the next COUNT-220 bytes of packets BIGCOUNT
; times (the byte after COUNT). The data is one stream over all lines.
BitmapUp:
        lda #0
        sta bmCount
        sta bmBig
@line:  ldx r1H
        jsr GetScanLine
        lda r1L                 ; r7/r8 = r5/r6 + x * 8
        sta r7L
        lda #0
        asl r7L
        rol
        asl r7L
        rol
        asl r7L
        rol
        sta r7H
        clc
        lda r5L
        adc r7L
        sta r8L
        lda r5H
        adc r7H
        sta r8H
        clc
        lda r6L
        adc r7L
        sta r7L
        lda r6H
        adc r7H
        sta r7H
        lda r2L
        sta r9L
@byte:  jsr BitmapByte
        ldy #0
        sta (r8),y
        sta (r7),y
        clc
        lda r8L
        adc #8
        sta r8L
        bcc @b
        inc r8H
@b:     clc
        lda r7L
        adc #8
        sta r7L
        bcc @next
        inc r7H
@next:  dec r9L
        bne @byte
        inc r1H
        dec r2H
        bne @line
        rts

; Next byte of the compacted stream at r0.
BitmapByte:
        lda bmCount             ; inside a repeat or unique packet
        beq @packet
        dec bmCount
        lda bmRepeat
        bmi @unique
        lda bmValue
        rts
@unique:
        jmp StreamByte
@packet:
        lda bmBig               ; end of a bigcount group: again or done
        beq @header
        lda r0L
        cmp bmBigEnd
        bne @header
        lda r0H
        cmp bmBigEnd+1
        bne @header
        dec bmBigLeft
        beq @bigDone
        lda bmBigStart
        sta r0L
        lda bmBigStart+1
        sta r0H
        jmp @header
@bigDone:
        lda #0
        sta bmBig
@header:
        jsr StreamByte
        cmp #128
        bcc @repeat
        cmp #220
        bcc @uniq
        sec                     ; bigcount: COUNT-220 bytes, BIGCOUNT times
        sbc #220
        pha
        jsr StreamByte
        sta bmBigLeft
        pla
        clc
        adc r0L
        sta bmBigEnd
        lda r0H
        adc #0
        sta bmBigEnd+1
        lda r0L
        sta bmBigStart
        lda r0H
        sta bmBigStart+1
        lda #1
        sta bmBig
        jmp @packet
@repeat:
        sta bmCount
        jsr StreamByte
        sta bmValue
        lda #0
        sta bmRepeat
        jmp BitmapByte
@uniq:  sec
        sbc #128
        sta bmCount
        lda #$80
        sta bmRepeat
        jmp BitmapByte

; A = (r0), r0 += 1
StreamByte:
        ldy #0
        lda (r0),y
        inc r0L
        bne @end
        inc r0H
@end:   rts

; i_BitmapUp: .word data, .byte x, y, width, height follow the jsr.
i_BitmapUp:
        ldx #r0
        jsr InlineArgs
        jsr BitmapUp
        jmp InlineReturn

        .segment "DATA"
bmCount:        .res 1          ; bytes left in the current packet
bmRepeat:       .res 1          ; 0 repeat, $80 unique
bmValue:        .res 1
bmBig:          .res 1          ; inside a bigcount group
bmBigLeft:      .res 1
bmBigStart:     .res 2
bmBigEnd:       .res 2
