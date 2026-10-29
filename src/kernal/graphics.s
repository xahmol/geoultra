; Graphics primitives: GetScanLine, SetPattern, HorizontalLine,
; InvertLine, RecoverLine, VerticalLine, Rectangle, FrameRectangle,
; InvertRectangle, RecoverRectangle, ImprintRectangle, BitmapUp,
; DrawPoint, TestPoint, DrawLine and the inline i_ variants. Written from the HG2G2022 descriptions (parameters, Uses,
; Destroys); checked against GEOS 2.0 with the conformance harness.

        .include "geos.inc"

        .export GetScanLine, SetPattern, HorizontalLine, VerticalLine
        .export Rectangle, FrameRectangle
        .export InvertLine, RecoverLine, InvertRectangle, RecoverRectangle
        .export ImprintRectangle, i_Rectangle, i_FrameRectangle
        .export i_RecoverRectangle, i_ImprintRectangle, BitmapUp, i_BitmapUp
        .export BitmapClip, BitOtherClip
        .export DrawPoint, TestPoint, DrawLine, InlineArgs, InlineReturn
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
        lda r4L                 ; r8L = number of cards after the first
        and #$F8                ; (the low byte of the 16-bit card
        sec                     ; difference, as GEOS 2.0)
        sbc r7L
        sta r8L
        lda r4H
        sbc r3H
        sta r8H
        lda r3H                 ; the first card: any high byte other than
        beq @page               ; 0 counts as one page, as on GEOS 2.0
        lda #1                  ; (GEOS 128's DOUBLE_W/ADD1_W flags then
@page:  sta r7H                 ; stay on the screen and out of the kernal)
        jsr AddR7
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
@pattern:                       ; as GEOS 2.0: the background (or the only
        lda r11H                ; buffer) is the source, the result goes
        and kMask               ; to both
        sta kBits
        lda (r6),y
        and kInv
        ora kBits
        sta (r6),y
        sta (r5),y
        rts

; VerticalLine: A = pattern byte (bit 7 for the lines with y & 7 = 0),
; r3L = y1, r3H = y2, r4 = x. Destroys A, X, Y, r5-r7.
VerticalLine:
        ldx r4H                 ; x from 512 (GEOS 128's DOUBLE_W flag): off
        cpx #2                  ; the screen; GEOS 2.0 adds the whole x and
        bcs @off                ; writes into memory there (also its own
        sta kPat                ; kernal through the back buffer), the screen
        lda r4L                 ; stays the same; nothing is written here
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
        lda (r6),y              ; background as source (see PutMasked)
        and kInv
        ora kBits
        sta (r6),y
        sta (r5),y
        lda kY
        cmp r3H
        beq @done
        inc kY
        jmp @loop
@done:
@off:   rts

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

        .segment "CODE"

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
        sta bmOther
        sta bmCount
        sta bmBig
@line:  jsr BitmapLine
        inc r1H
        dec r2H
        bne @line
        rts

; BitmapClip: as BitmapUp, but only a window of a larger bitmap: r2L / r2H
; = the window's width and height, r11L / r11H = cards left / right of
; it, r12 = lines above it. BitOtherClip: the same with the data from the
; application: r13 = routine that puts the next stream byte at (r0), r14
; = routine called before each new packet (resets r0 to its buffer).
; Destroys A, X, Y, r0-r12.
BitmapClip:
        lda #0
        .byte $2C               ; bit abs: skips the next lda
BitOtherClip:
        lda #$FF
        sta bmOther
        lda #0
        sta bmCount
        sta bmBig
@above: lda r12L                ; skip the lines above the window
        ora r12H
        beq @line
        lda r11L
        jsr Skip
        lda r2L
        jsr Skip
        lda r11H
        jsr Skip
        lda r12L
        bne @dec
        dec r12H
@dec:   dec r12L
        jmp @above
@line:  lda r11L
        jsr Skip
        jsr BitmapLine
        lda r11H
        jsr Skip
        inc r1H
        dec r2H
        bne @line
        rts

; Skip: A bytes of the stream.
Skip:   tax
        beq @end
@byte:  txa
        pha
        jsr BitmapByte
        pla
        tax
        dex
        bne @byte
@end:   rts

; BitmapLine: r2L bytes of the stream to line r1H from card r1L.
BitmapLine:
        ldx r1H
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
        bit bmOther             ; BitOtherClip: SYNC before a new packet
        bpl @read               ; (not inside a bigcount group)
        lda bmBig
        bne @read
        jsr CallSync
@read:  jsr StreamByte
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
        bit bmOther             ; BitOtherClip: APPINPUT fills (r0) first
        bpl @get
        jsr CallInput
@get:   ldy #0
        lda (r0),y
        inc r0L
        bne @end
        inc r0H
@end:   rts

CallInput:
        jmp (r13)
CallSync:
        jmp (r14)

; i_BitmapUp: .word data, .byte x, y, width, height follow the jsr.
i_BitmapUp:
        ldx #r0
        jsr InlineArgs
        jsr BitmapUp
        jmp InlineReturn

        .segment "DATA"
bmOther:        .res 1          ; $FF: BitOtherClip (data from r13)
bmCount:        .res 1          ; bytes left in the current packet
bmRepeat:       .res 1          ; 0 repeat, $80 unique
bmValue:        .res 1
bmBig:          .res 1          ; inside a bigcount group
bmBigLeft:      .res 1
bmBigStart:     .res 2
bmBigEnd:       .res 2

        .segment "KCODE"                ; points and lines: low kernal area

; Pixel address in r5/r6 (per dispBufferOn, or both buffers when kOp is
; OP_RECOVER) and bit mask in ptMask for r3/r11L.
PointAddr:
        lda dispBufferOn
        pha
        lda kOp
        cmp #OP_RECOVER
        bne @scan
        lda #ST_WR_FORE | ST_WR_BACK
        sta dispBufferOn
@scan:  ldx r11L
        jsr GetScanLine
        pla
        sta dispBufferOn
        lda r3H                 ; any high byte other than 0 counts as
        beq @page               ; one page, as on GEOS 2.0 (see LineOp)
        lda #1
@page:  sta ptMask
        lda r3L
        and #$F8
        clc
        adc r5L
        sta r5L
        lda ptMask
        adc r5H
        sta r5H
        lda r3L
        and #$F8
        clc
        adc r6L
        sta r6L
        lda ptMask
        adc r6H
        sta r6H
        lda r3L
        and #7
        tax
        lda bitMask,x
        sta ptMask
        rts

; DrawPoint: r3 = x, r11L = y. N set: recover from the background; else
; carry set: set, carry clear: clear (per dispBufferOn).
; Destroys A, X, Y, r5, r6.
DrawPoint:
        php
        bpl @draw
        lda #OP_RECOVER
        sta kOp
        jsr PointAddr
        ldy #0
        lda (r6),y
        and ptMask
        sta kBits
        lda ptMask
        eor #$FF
        and (r5),y
        ora kBits
        sta (r5),y
        plp
        rts
@draw:  lda #OP_PATTERN
        sta kOp
        jsr PointAddr
        ldy #0
        plp                     ; as GEOS 2.0: the background (or the only
        bcc @clear              ; buffer) is the source, the result goes
        lda (r6),y              ; to both
        ora ptMask
        sta (r6),y
        sta (r5),y
        rts
@clear: lda ptMask
        eor #$FF
        and (r6),y
        sta (r6),y
        sta (r5),y
        rts

; TestPoint: r3 = x, r11L = y. Carry set when the pixel is set (the
; background is tested when both buffers are on). Destroys A, X, Y, r5,
; r6.
TestPoint:
        lda #OP_PATTERN
        sta kOp
        jsr PointAddr
        ldy #0
        lda (r6),y
        and ptMask
        cmp #1                  ; carry set when not zero
        rts

; DrawLine: r3/r11L to r4/r11H, Bresenham. N set: recover; else carry
; set: set, clear: clear. A horizontal line that is not recovered is a
; HorizontalLine in pattern $FF or $00. Destroys A, X, Y, r3-r13.
;
; Steps (as GEOS 2.0): the shallow case walks x from the endpoint with
; the smaller x, the steep case y from the one with the smaller y; error
; 2 * minor - major, a negative error adds 2 * minor, otherwise the minor
; coordinate steps towards the other end and 2 * (minor - major) is added.
DrawLine:
        php
        bmi @line
        lda r11L
        cmp r11H
        bne @line
        lda #$FF
        plp
        bcs @hl
        lda #0
@hl:    jmp HorizontalLine
@line:  lda r11H                ; r7 = |dy|
        sec
        sbc r11L
        bcs @dy
        eor #$FF
        adc #1
@dy:    sta r7L
        lda #0
        sta r7H
        sec                     ; r12 = |dx|
        lda r4L
        sbc r3L
        sta r12L
        lda r4H
        sbc r3H
        sta r12H
        bpl @dx
        sec
        lda #0
        sbc r12L
        sta r12L
        lda #0
        sbc r12H
        sta r12H
@dx:    lda r12H                ; shallow when dx >= dy
        cmp r7H
        bne @cmp
        lda r12L
        cmp r7L
@cmp:   bcs @shallow
        jmp Steep

@shallow:
        lda r7L                 ; r9 = 2 * dy
        asl
        sta r9L
        lda r7H
        rol
        sta r9H
        sec                     ; r8 = 2 * dy - dx
        lda r9L
        sbc r12L
        sta r8L
        lda r9H
        sbc r12H
        sta r8H
        sec                     ; r10 = 2 * (dy - dx)
        lda r7L
        sbc r12L
        sta r10L
        lda r7H
        sbc r12H
        sta r10H
        asl r10L
        rol r10H
        jsr XOrder              ; start at the smaller x
        bcc @keep
        jsr SwapEnds
@keep:  lda #1                  ; y step towards the other end
        ldx r11H
        cpx r11L
        bcs @step
        lda #$FF
@step:  sta r13L
@hloop: plp
        php
        jsr DrawPoint
        lda r3H
        cmp r4H
        bne @hnext
        lda r3L
        cmp r4L
        beq @done
@hnext: inc r3L
        bne @herr
        inc r3H
@herr:  bit r8H
        bpl @hstep
        clc
        lda r8L
        adc r9L
        sta r8L
        lda r8H
        adc r9H
        sta r8H
        jmp @hloop
@hstep: clc
        lda r11L
        adc r13L
        sta r11L
        clc
        lda r8L
        adc r10L
        sta r8L
        lda r8H
        adc r10H
        sta r8H
        jmp @hloop
@done:  plp
        rts

Steep:  lda r12L                ; r9 = 2 * dx
        asl
        sta r9L
        lda r12H
        rol
        sta r9H
        sec                     ; r8 = 2 * dx - dy
        lda r9L
        sbc r7L
        sta r8L
        lda r9H
        sbc r7H
        sta r8H
        sec                     ; r10 = 2 * (dx - dy)
        lda r12L
        sbc r7L
        sta r10L
        lda r12H
        sbc r7H
        sta r10H
        asl r10L
        rol r10H
        lda r11H                ; start at the smaller y
        cmp r11L
        bcs @keep
        jsr SwapEnds
@keep:  lda #1                  ; x step towards the other end
        sta r13L
        lda #0
        sta r13H
        jsr XOrder
        bcc @vloop
        lda #$FF
        sta r13L
        sta r13H
@vloop: plp
        php
        jsr DrawPoint
        lda r11L
        cmp r11H
        beq @done
        inc r11L
        bit r8H
        bpl @vstep
        clc
        lda r8L
        adc r9L
        sta r8L
        lda r8H
        adc r9H
        sta r8H
        jmp @vloop
@vstep: clc
        lda r3L
        adc r13L
        sta r3L
        lda r3H
        adc r13H
        sta r3H
        clc
        lda r8L
        adc r10L
        sta r8L
        lda r8H
        adc r10H
        sta r8H
        jmp @vloop
@done:  plp
        rts

; Carry set when r3 >= r4 (from the other point of view: r4 is not right
; of r3).
XOrder: lda r3H
        cmp r4H
        bne @end
        lda r3L
        cmp r4L
@end:   rts

; Swap the endpoints r3/r11L and r4/r11H.
SwapEnds:
        ldx #1
@swap:  lda r3,x
        ldy r4,x
        sta r4,x
        sty r3,x
        dex
        bpl @swap
        lda r11L
        ldy r11H
        sta r11H
        sty r11L
        rts

        .segment "DATA"
ptMask:         .res 1
