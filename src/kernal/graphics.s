; Graphics primitives: GetScanLine, SetPattern, HorizontalLine,
; VerticalLine, Rectangle, FrameRectangle. Written from the HG2G2022
; descriptions (parameters, Uses, Destroys); behaviour to be checked
; against GEOS 2.0 with the conformance harness.

        .include "geos.inc"

        .export GetScanLine, SetPattern, HorizontalLine, VerticalLine
        .export Rectangle, FrameRectangle
        .import patterns

        .segment "DATA"

kMask:  .res 1
kInv:   .res 1
kBits:  .res 1
kPat:   .res 1
kY:     .res 1
kSave:  .res 4

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
        ldx r11L
        jsr GetScanLine
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

; Write the pattern byte r11H into the bits of mask A at (r5) and (r6).
PutMasked:
        sta kMask
        eor #$FF
        sta kInv
        lda r11H
        and kMask
        sta kBits
        ldy #0
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
